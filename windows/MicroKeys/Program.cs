using System.Reflection;
using System.Text;
using MicroKeys.Core;

namespace MicroKeys;

internal static class Program
{
    private static string Version =>
        Assembly.GetExecutingAssembly().GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion.Split('+')[0]
        ?? Assembly.GetExecutingAssembly().GetName().Version?.ToString(3) ?? "0.0.0";

    [STAThread]
    private static int Main(string[] args)
    {
        Preferences.Apply();
        if (args.Length > 0)
        {
            // A WinExe has no console; borrow the parent's so CLI modes print where they were typed.
            if (Native.AttachConsole(Native.ATTACH_PARENT_PROCESS) || Native.AllocConsole())
            {
                Console.OutputEncoding = Encoding.UTF8;
                Console.SetOut(new StreamWriter(Console.OpenStandardOutput()) { AutoFlush = true });
                Console.SetError(new StreamWriter(Console.OpenStandardError()) { AutoFlush = true });
                Console.WriteLine();
            }
            return RunCli(args);
        }

        using var mutex = new Mutex(true, "Local\\MicroKeys.SingleInstance", out var first);
        if (!first)
        {
            MessageBox.Show(L10n.Pick("MicroKeys 已经在运行，看系统托盘。", "MicroKeys is already running; see the system tray."), "MicroKeys");
            return 0;
        }
        ApplicationConfiguration.Initialize();
        Application.Run(new TrayApp());
        return 0;
    }

    private static int RunCli(string[] args)
    {
        switch (args[0])
        {
            case "--version":
            case "-v":
                Console.WriteLine($"MicroKeys {Version}");
                return 0;

            case "--check-config":
            {
                var path = args.Length > 1 ? Path.GetFullPath(args[1]) : ConfigStore.DefaultPath;
                try
                {
                    var config = Config.Load(path);
                    Console.WriteLine(L10n.Pick($"配置正常：{path}", $"Config OK: {path}"));
                    foreach (var b in config.Bindings.Values.OrderBy(b => b.KeyId, StringComparer.Ordinal))
                        Console.WriteLine($"  {b.KeyId} → {b.Chord}  [{b.Mode.ToString().ToLowerInvariant()}]");
                    return 0;
                }
                catch (Exception e) when (e is ConfigException or IOException)
                {
                    Console.Error.WriteLine(L10n.Pick($"配置错误：{e.Message}", $"Config error: {e.Message}"));
                    return 1;
                }
            }

            case "--detect":
                return DeviceDetector.Run();

            case "--dump-events":
                return EventDumper.Run(args.Length > 1 && int.TryParse(args[1], out var s) ? s : 20);

            case "--test-shortcut":
                if (args.Length < 2)
                {
                    Console.Error.WriteLine(L10n.Pick("用法：MicroKeys --test-shortcut \"rctrl+rshift\" [按住毫秒数，默认 800]",
                        "usage: MicroKeys --test-shortcut \"rctrl+rshift\" [hold ms, default 800]"));
                    return 2;
                }
                return ShortcutTester.Run(args[1], args.Length > 2 && int.TryParse(args[2], out var ms) ? ms : 800);

            case "--uninstall":
                return Uninstaller.Run(args.Contains("--yes") || args.Contains("-y"));

            case "--help":
            case "-h":
            case "/?":
                Console.WriteLine(L10n.Pick($"""
                    MicroKeys {Version} - 把 Codex Micro 的按键映射成系统快捷键

                    不带参数：以托盘应用运行。
                      --check-config [路径]           校验配置文件并列出绑定
                      --test-shortcut <快捷键> [毫秒]  合成一次快捷键，用来验证目标应用是否响应
                      --dump-events [秒数]            打印这段时间内系统收到的所有键盘事件（诊断用）
                      --detect                        列出接在这台电脑上的 Work Louder / 乐鑫 HID 设备
                      --uninstall [--yes]             删除配置、日志、偏好和开机自启，并列出需手动处理的项
                      --version
                    环境变量 MICROKEYS_CONFIG 可指定配置文件路径（默认 %APPDATA%\MicroKeys\config.json）。
                    """, $"""
                    MicroKeys {Version} - map Codex Micro keys to system shortcuts

                    No arguments: run as the tray app.
                      --check-config [path]            validate the config and list bindings
                      --test-shortcut <chord> [ms]     synthesize one shortcut to see if the target app reacts
                      --dump-events [seconds]          print every keyboard event the system delivers (diagnostic)
                      --detect                         list Work Louder / Espressif HID devices attached to this PC
                      --uninstall [--yes]              remove config, log, preferences and the login entry; list what is left for you
                      --version
                    MICROKEYS_CONFIG overrides the config path (default %APPDATA%\MicroKeys\config.json).
                    """));
                return 0;

            default:
                Console.Error.WriteLine(L10n.Pick($"不认识的参数 {args[0]}，用 --help 查看用法。", $"Unknown argument {args[0]}; see --help."));
                return 2;
        }
    }
}
