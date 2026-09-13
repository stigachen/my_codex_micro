using MicroKeys.Core;

namespace MicroKeys;

/// <summary>Where the config lives, first-run seeding, and reload-on-save (1 s stat polling).</summary>
internal sealed class ConfigStore
{
    public static string DefaultPath
    {
        get
        {
            var env = Environment.GetEnvironmentVariable("MICROKEYS_CONFIG");
            if (!string.IsNullOrWhiteSpace(env)) return Path.GetFullPath(env);
            return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "MicroKeys", "config.json");
        }
    }

    public string FilePath { get; }
    public Config Config { get; private set; } = new();
    public string? LastError { get; private set; }
    public event Action<Config?, string?>? Changed;

    private string? _lastData;
    private string? _lastStamp;
    private System.Windows.Forms.Timer? _timer;

    public ConfigStore(string? path = null) => FilePath = path ?? DefaultPath;

    public void SeedIfMissing()
    {
        if (File.Exists(FilePath)) return;
        try
        {
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(FilePath)!);
            File.WriteAllText(FilePath, Config.ExampleJson);
            Log.Info(S.LogSeeded(FilePath));
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { Log.Error(S.LogSeedFailed(e.Message)); }
    }

    public bool Load()
    {
        try
        {
            var data = File.ReadAllText(FilePath);
            _lastData = data;
            Config = Config.Parse(data);
            LastError = null;
            Log.Info(S.LogLoaded(Config.Bindings.Count, Describe(Config)));
            Changed?.Invoke(Config, null);
            return true;
        }
        catch (Exception e) when (e is ConfigException or IOException or UnauthorizedAccessException)
        {
            LastError = e.Message;
            Log.Error(S.LogConfigError(e.Message));
            Changed?.Invoke(null, e.Message);
            return false;
        }
    }

    public void StartWatching()
    {
        _lastStamp = Stamp();
        _timer = new System.Windows.Forms.Timer { Interval = 1000 };
        _timer.Tick += (_, _) => CheckForChange();
        _timer.Start();
    }

    private string? Stamp()
    {
        try { var fi = new FileInfo(FilePath); return fi.Exists ? $"{fi.LastWriteTimeUtc.Ticks}-{fi.Length}" : null; }
        catch (IOException) { return null; }
    }

    private void CheckForChange()
    {
        var current = Stamp();
        if (current == _lastStamp) return;
        _lastStamp = current;
        string? data = null;
        try { data = File.ReadAllText(FilePath); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        if (data == _lastData && LastError is null) return;
        Load();
    }

    private static string Describe(Config c) => string.Join(", ",
        c.Bindings.Values.OrderBy(b => b.KeyId, StringComparer.Ordinal).Select(b => $"{b.KeyId}→{b.Chord} ({b.Mode.ToString().ToLowerInvariant()})"));
}
