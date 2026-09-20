using System.Diagnostics;
using System.Reflection;
using MicroKeys.Core;
using Microsoft.Win32;

namespace MicroKeys;

/// <summary>The resident tray application: icon, menu, and the wiring between HID, mapper and synthesizer.</summary>
internal sealed class TrayApp : ApplicationContext
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

    private readonly NotifyIcon _tray;
    private readonly ContextMenuStrip _menu = new();
    private readonly SendInputSynthesizer _synth = new();
    private readonly ConfigStore _store = new();
    private readonly Mapper _mapper;
    private readonly PadMonitor _pad;

    private PadState _padState = PadState.Disconnected;
    private string _padDetail = "";
    private string? _lastKey, _lastFire;

    public TrayApp()
    {
        Preferences.Apply();
        Log.Info(S.LogStarted(_store.FilePath));
        _mapper = new Mapper(new Config(), _synth);

        _tray = new NotifyIcon { Icon = LoadIcon(), Visible = true, ContextMenuStrip = _menu };
        _tray.DoubleClick += (_, _) => OpenConfig();
        _menu.Opening += (_, _) => BuildMenu();

        _store.Changed += (config, _) =>
        {
            if (config is not null) { _mapper.Config = config; _synth.IntervalMs = config.Options.KeyIntervalMs; }
            RefreshTooltip();
        };
        _store.SeedIfMissing();
        _store.Load();
        _store.StartWatching();

        _mapper.KeyObserved += (id, act) => _lastKey = $"{id} {(act == 1 ? S.Pressed : act == 0 ? S.Released : S.Turned)}";
        _mapper.Fired += (b, down) => _lastFire = $"{b.KeyId} → {b.Target}{(b.Mode == BindingMode.Hold ? (down ? S.Holding : S.LetGo) : "")}";

        _pad = new PadMonitor(SynchronizationContext.Current ?? new WindowsFormsSynchronizationContext());
        _pad.EventReceived += e => _mapper.Handle(e);
        _pad.StatusChanged += (state, detail) =>
        {
            _padState = state; _padDetail = detail;
            if (state != PadState.Connected) _mapper.ReleaseAll();
            RefreshTooltip();
        };
        _pad.Start();
        RefreshTooltip();
        Application.ApplicationExit += (_, _) => { _mapper.ReleaseAll(); _pad.Dispose(); _tray.Visible = false; };
    }

    private static Icon LoadIcon()
    {
        using var s = Assembly.GetExecutingAssembly().GetManifestResourceStream("AppIcon.ico");
        return s is null ? SystemIcons.Application : new Icon(s);
    }

    private void RefreshTooltip()
    {
        var problem = _store.LastError is { } e ? S.ProblemConfig(e)
            : _padState == PadState.OpenFailed ? _padDetail
            : _padState != PadState.Connected ? S.ProblemDisconnected : null;
        var text = problem is null ? S.TooltipRunning : S.TooltipProblem(problem);
        _tray.Text = text.Length > 127 ? text[..127] : text;   // NotifyIcon caps the tooltip
    }

    private void BuildMenu()
    {
        _menu.Items.Clear();
        Add(_padState switch
        {
            PadState.Connected => S.PadConnected(_padDetail),
            PadState.OpenFailed => S.PadOpenFailed(_padDetail),
            _ => S.PadDisconnected,
        }, enabled: false);
        _menu.Items.Add(new ToolStripSeparator());

        if (_store.LastError is { } error)
        {
            Add(S.ConfigError(error), OpenConfig);
        }
        else
        {
            var n = _mapper.Config.Bindings.Count;
            Add(n == 0 ? S.ConfigNoBindings : S.ConfigCount(n), enabled: false);
            foreach (var b in _mapper.Config.Bindings.Values.OrderBy(b => b.KeyId, StringComparer.Ordinal))
            {
                var label = b.KeyId == "ACT10" ? "ACT10 (MIC)" : b.KeyId;
                var mode = b.Mode switch { BindingMode.Hold => S.ModeHold, BindingMode.Type => S.ModeType, _ => S.ModeTap };
                Add($"    {label} → {b.Target}  [{mode}]", enabled: false);
            }
        }
        Add(S.LastKey(_lastKey ?? S.NoKeyYet), enabled: false);
        Add(S.LastFire(_lastFire ?? S.NoFireYet), enabled: false);
        _menu.Items.Add(new ToolStripSeparator());

        Add(S.OpenConfig, OpenConfig);
        Add(S.ReloadConfig, () => _store.Load());
        Add(S.OpenDocs, OpenDocs);
        Add(S.OpenLog, () => Open(Log.Path));
        _menu.Items.Add(new ToolStripSeparator());

        var lang = new ToolStripMenuItem(S.Language);
        foreach (var (pref, title) in new[] { (LanguagePreference.System, S.LanguageSystem), (LanguagePreference.ZhHans, S.LanguageZh), (LanguagePreference.En, S.LanguageEn) })
        {
            var item = new ToolStripMenuItem(title) { Checked = Preferences.Language == pref };
            item.Click += (_, _) => { Preferences.Language = pref; if (_store.LastError is not null) _store.Load(); RefreshTooltip(); };
            lang.DropDownItems.Add(item);
        }
        _menu.Items.Add(lang);

        var login = new ToolStripMenuItem(S.LoginItem) { Checked = IsLaunchAtLogin() };
        login.Click += (_, _) => SetLaunchAtLogin(!IsLaunchAtLogin());
        _menu.Items.Add(login);
        Add(S.Quit, () => Application.Exit());
    }

    private void Add(string text, Action? click = null, bool enabled = true)
    {
        var item = new ToolStripMenuItem(text) { Enabled = enabled && click is not null };
        if (click is not null) item.Click += (_, _) => click();
        _menu.Items.Add(item);
    }

    private void OpenConfig() { _store.SeedIfMissing(); Open(_store.FilePath); }

    private void OpenDocs()
    {
        var dir = Path.Combine(AppContext.BaseDirectory, "docs");
        var preferred = Path.Combine(dir, L10n.Language == Core.Language.ZhHans ? "CONFIG.md" : "CONFIG.en.md");
        var fallback = Path.Combine(dir, "CONFIG.md");
        Open(File.Exists(preferred) ? preferred : File.Exists(fallback) ? fallback : "https://github.com/stigachen/my_codex_micro/blob/main/docs/CONFIG.md");
    }

    private static void Open(string target)
    {
        try { Process.Start(new ProcessStartInfo(target) { UseShellExecute = true }); }
        catch (Exception e) { Log.Error($"open failed: {target}: {e.Message}"); }
    }

    private static bool IsLaunchAtLogin()
    {
        using var k = Registry.CurrentUser.OpenSubKey(RunKey);
        return k?.GetValue("MicroKeys") is string;
    }

    private static void SetLaunchAtLogin(bool on)
    {
        using var k = Registry.CurrentUser.CreateSubKey(RunKey);
        if (on) k.SetValue("MicroKeys", $"\"{Environment.ProcessPath}\"");
        else k.DeleteValue("MicroKeys", throwOnMissingValue: false);
    }
}
