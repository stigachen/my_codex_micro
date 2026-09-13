using System.Diagnostics;
using MicroKeys.Core;
using Microsoft.Win32;

namespace MicroKeys;

/// <summary><c>--uninstall</c>: remove everything MicroKeys created for this user, then say what is left (the exe itself).</summary>
internal static class Uninstaller
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string AppKey = @"Software\MicroKeys";

    public static int Run(bool assumeYes)
    {
        var dirs = new[]
        {
            (Path.GetDirectoryName(ConfigStore.DefaultPath)!, L10n.Pick("配置目录", "config directory")),
            (Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "MicroKeys"), L10n.Pick("日志目录", "log directory")),
            (Path.Combine(Path.GetTempPath(), ".net", "MicroKeys"), L10n.Pick("运行时解压缓存", "runtime extraction cache")),
        };
        bool HasRun() { using var k = Registry.CurrentUser.OpenSubKey(RunKey); return k?.GetValue("MicroKeys") is not null; }
        bool HasAppKey() { using var k = Registry.CurrentUser.OpenSubKey(AppKey); return k is not null; }
        var others = Process.GetProcessesByName("MicroKeys").Where(p => p.Id != Environment.ProcessId).ToList();

        Console.WriteLine(L10n.Pick("将要删除：", "About to remove:"));
        foreach (var (dir, what) in dirs) if (Directory.Exists(dir)) Console.WriteLine($"  {what}: {dir}");
        if (HasRun()) Console.WriteLine("  " + L10n.Pick("开机自动启动（注册表 Run 项）", "the launch-at-login entry (registry Run key)"));
        if (HasAppKey()) Console.WriteLine($"  {L10n.Pick("语言等偏好设置", "preferences (language)")}: HKCU\\{AppKey}");
        if (others.Count > 0) Console.WriteLine("  " + L10n.Pick("正在运行的 MicroKeys（先退出）", "the running MicroKeys instance (quit first)"));

        if (!assumeYes)
        {
            Console.Write(L10n.Pick("继续？[y/N] ", "Continue? [y/N] "));
            var answer = Console.ReadLine()?.Trim().ToLowerInvariant();
            if (answer is not ("y" or "yes")) { Console.WriteLine(L10n.Pick("已取消，什么都没改。", "Cancelled; nothing was changed.")); return 1; }
        }

        var failed = false;
        foreach (var p in others) { try { p.Kill(); p.WaitForExit(3000); } catch (Exception e) { Console.WriteLine($"✗ {e.Message}"); failed = true; } }
        try
        {
            using (var k = Registry.CurrentUser.OpenSubKey(RunKey, writable: true)) k?.DeleteValue("MicroKeys", throwOnMissingValue: false);
            Registry.CurrentUser.DeleteSubKeyTree(AppKey, throwOnMissingSubKey: false);
            Console.WriteLine("✓ " + L10n.Pick("注册表项已清除", "registry entries removed"));
        }
        catch (Exception e) { Console.WriteLine("✗ " + L10n.Pick($"注册表清理失败：{e.Message}", $"registry cleanup failed: {e.Message}")); failed = true; }
        foreach (var (dir, what) in dirs)
        {
            if (!Directory.Exists(dir)) continue;
            try { Directory.Delete(dir, recursive: true); Console.WriteLine($"✓ {what}"); }
            catch (Exception e) { Console.WriteLine($"✗ {what}: {e.Message}"); failed = true; }
        }

        Console.WriteLine();
        Console.WriteLine(L10n.Pick("剩下一件事只能手动做：删除程序本身：", "One thing only you can do: delete the program itself:"));
        Console.WriteLine($"  {Environment.ProcessPath}");
        Console.WriteLine(L10n.Pick("没有其他残留：不写 Program Files，不装服务、驱动或计划任务。",
            "Nothing else is left behind: no Program Files entry, no service, driver or scheduled task."));
        return failed ? 1 : 0;
    }
}
