using MicroKeys.Core;
using Microsoft.Win32;

namespace MicroKeys;

/// <summary>The saved language preference: follow the system, or one fixed language.</summary>
internal enum LanguagePreference { System, ZhHans, En }

internal static class Preferences
{
    private const string KeyPath = @"Software\MicroKeys";

    public static LanguagePreference Language
    {
        get
        {
            using var k = Registry.CurrentUser.OpenSubKey(KeyPath);
            return (k?.GetValue("language") as string) switch { "zh-Hans" => LanguagePreference.ZhHans, "en" => LanguagePreference.En, _ => LanguagePreference.System };
        }
        set
        {
            using var k = Registry.CurrentUser.CreateSubKey(KeyPath);
            k.SetValue("language", value switch { LanguagePreference.ZhHans => "zh-Hans", LanguagePreference.En => "en", _ => "system" });
            Apply();
        }
    }

    /// <summary>Push the effective language into Core so error messages match.</summary>
    public static void Apply() => L10n.Language = Language switch
    {
        LanguagePreference.ZhHans => Core.Language.ZhHans,
        LanguagePreference.En => Core.Language.En,
        _ => L10n.SystemDefault,
    };
}

/// <summary>Every user-facing string, in both languages.</summary>
internal static class S
{
    private static bool Zh => L10n.Language == Core.Language.ZhHans;
    private static string P(string zh, string en) => Zh ? zh : en;

    public static string PadConnected(string t) => P($"Codex Micro：已连接（{t}）", $"Codex Micro: connected ({t})");
    public static string PadDisconnected => P("Codex Micro：未连接（USB 或蓝牙均可）", "Codex Micro: not connected (USB or Bluetooth)");
    public static string PadOpenFailed(string r) => P($"Codex Micro：打不开，{r}", $"Codex Micro: cannot open, {r}");
    public static string TransportBluetooth => P("蓝牙", "Bluetooth");
    public static string ConfigError(string e) => P($"❌ 配置错误：{e}", $"❌ Config error: {e}");
    public static string ConfigNoBindings => P("配置：没有任何绑定", "Config: no bindings");
    public static string ConfigCount(int n) => P($"配置：{n} 个绑定", $"Config: {n} binding{(n == 1 ? "" : "s")}");
    public static string ModeHold => P("按住", "hold");
    public static string ModeTap => P("单击", "tap");
    public static string ModeType => P("输入文字", "type");
    public static string LastKey(string k) => P($"最近按键：{k}", $"Last key: {k}");
    public static string LastFire(string f) => P($"最近触发：{f}", $"Last fired: {f}");
    public static string NoKeyYet => P("（还没有按过键）", "(nothing yet)");
    public static string NoFireYet => P("（还没有触发过）", "(nothing yet)");
    public static string Pressed => P("按下", "down");
    public static string Released => P("抬起", "up");
    public static string Turned => P("转动", "turn");
    public static string Holding => P("（按住）", " (holding)");
    public static string LetGo => P("（松开）", " (released)");
    public static string OpenConfig => P("打开配置文件…", "Open Config File…");
    public static string ReloadConfig => P("重新加载配置", "Reload Config");
    public static string OpenDocs => P("打开说明文档…", "Open Documentation…");
    public static string OpenLog => P("打开日志…", "Open Log…");
    public static string Language => P("语言 / Language", "Language / 语言");
    public static string LanguageSystem => P("跟随系统", "Follow System");
    public static string LanguageZh => "简体中文";
    public static string LanguageEn => "English";
    public static string LoginItem => P("开机自动启动", "Launch at Login");
    public static string About => P("关于 MicroKeys", "About MicroKeys");
    public static string Quit => P("退出 MicroKeys", "Quit MicroKeys");
    public static string TooltipRunning => P("MicroKeys：运行中", "MicroKeys: running");
    public static string TooltipProblem(string p) => P($"MicroKeys：{p}", $"MicroKeys: {p}");
    public static string ProblemConfig(string e) => P($"配置错误：{e}", $"config error: {e}");
    public static string ProblemDisconnected => P("未连接 Codex Micro", "Codex Micro not connected");
    public static string LogStarted(string p) => P($"MicroKeys 启动，配置文件：{p}", $"MicroKeys started, config: {p}");
    public static string LogSeeded(string p) => P($"已生成示例配置：{p}", $"Wrote example config: {p}");
    public static string LogSeedFailed(string e) => P($"写入示例配置失败：{e}", $"Could not write example config: {e}");
    public static string LogLoaded(int n, string d) => P($"配置已加载：{n} 个绑定 {d}", $"Config loaded: {n} binding(s) {d}");
    public static string LogConfigError(string e) => P($"配置错误：{e}", $"Config error: {e}");
    public static string LogConnected(string t) => P($"Codex Micro 已连接（{t}）", $"Codex Micro connected ({t})");
    public static string LogDisconnected(string t) => P($"Codex Micro 已断开（{t}）", $"Codex Micro disconnected ({t})");
    public static string LogOpenFailed(string r) => P($"打开设备失败：{r}", $"Could not open the device: {r}");
}

internal static class Transport
{
    /// <summary>Bluetooth LE HID devices enumerate through the BTHLE bus; anything else is USB.</summary>
    public static bool IsBluetooth(string devicePath) =>
        devicePath.Contains("bthle", StringComparison.OrdinalIgnoreCase) || devicePath.Contains("bthenum", StringComparison.OrdinalIgnoreCase);

    public static string Label(string devicePath) => IsBluetooth(devicePath) ? S.TransportBluetooth : "USB";
}
