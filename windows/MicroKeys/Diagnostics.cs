using HidSharp;
using MicroKeys.Core;

namespace MicroKeys;

/// <summary><c>--detect</c>: list HID devices that could be a Work Louder pad and what MicroKeys would do with each.</summary>
internal static class DeviceDetector
{
    public static int Run()
    {
        var all = DeviceList.Local.GetHidDevices().ToList();
        var candidates = all.Where(d =>
            d.VendorID == PadMonitor.VendorId
            || PadMonitor.SafeManufacturer(d).Contains(PadMonitor.Manufacturer, StringComparison.OrdinalIgnoreCase)
            || PadMonitor.SafeProduct(d).Contains("micro", StringComparison.OrdinalIgnoreCase)).ToList();
        if (candidates.Count == 0)
        {
            Console.WriteLine(L10n.Pick("没有找到 Work Louder / 乐鑫（VID 0x303A）的 HID 设备。请确认键盘已开机并通过 USB 或蓝牙连接。",
                "No Work Louder / Espressif (VID 0x303A) HID device found. Make sure the pad is on and connected over USB or Bluetooth."));
            return 1;
        }
        foreach (var d in candidates)
        {
            var supported = PadMonitor.IsSupported(d, out var vendorPage);
            int inLen = 0; try { inLen = d.GetMaxInputReportLength(); } catch (Exception) { }
            Console.WriteLine($"VID 0x{d.VendorID:X4}  PID 0x{d.ProductID:X4}  {PadMonitor.SafeManufacturer(d)} / {PadMonitor.SafeProduct(d)}  [{Transport.Label(d.DevicePath)}]");
            Console.WriteLine("  " + d.DevicePath);
            Console.WriteLine("  " + L10n.Pick($"最大输入报告 {inLen} 字节，厂商通道 (0xFF00)：{(vendorPage ? "有" : "无")}",
                $"max input report {inLen} bytes, vendor page 0xFF00: {(vendorPage ? "present" : "absent")}"));
            Console.WriteLine("  " + (supported
                ? L10n.Pick("MicroKeys 会接管这个设备。", "MicroKeys will use this device.")
                : L10n.Pick("MicroKeys 不会接管（不是厂商通道，或 PID/厂商名不匹配）。", "MicroKeys will ignore it (not the vendor collection, or PID/manufacturer do not match).")));
        }
        return 0;
    }
}

/// <summary><c>--dump-events</c>: print every keyboard event the system delivers, flagging injected ones.</summary>
internal static class EventDumper
{
    private static Native.LowLevelKeyboardProc? _proc;   // keep the delegate alive while hooked

    public static int Run(int seconds)
    {
        var hook = nint.Zero;
        _proc = (nCode, wParam, lParam) =>
        {
            if (nCode >= 0)
            {
                var k = System.Runtime.InteropServices.Marshal.PtrToStructure<Native.KBDLLHOOKSTRUCT>(lParam);
                var kind = (int)wParam switch { Native.WM_KEYDOWN or Native.WM_SYSKEYDOWN => "keyDown", Native.WM_KEYUP or Native.WM_SYSKEYUP => "keyUp  ", _ => $"msg={wParam}" };
                var injected = (k.flags & Native.LLKHF_INJECTED) != 0;
                var ext = (k.flags & Native.LLKHF_EXTENDED) != 0;
                Console.WriteLine($"{kind} vk=0x{k.vkCode:X2} scan=0x{k.scanCode:X2} flags=0x{k.flags:X2} extended={(ext ? "yes" : "no")} injected={(injected ? "yes" : "no")}");
            }
            return Native.CallNextHookEx(hook, nCode, wParam, lParam);
        };
        hook = Native.SetWindowsHookEx(Native.WH_KEYBOARD_LL, _proc, Native.GetModuleHandle(null), 0);
        if (hook == nint.Zero)
        {
            Console.Error.WriteLine(L10n.Pick("无法安装键盘钩子。", "Could not install the keyboard hook."));
            return 1;
        }
        Console.WriteLine(L10n.Pick($"监听 {seconds} 秒。先在真实键盘上按一次快捷键，再按一次 Codex Micro 上映射的键，对比两组输出。",
            $"Listening for {seconds} s. Press the shortcut on a real keyboard, then the mapped Codex Micro key, and compare."));
        Console.WriteLine(L10n.Pick("真实按键 injected=no；MicroKeys 合成的按键 injected=yes。有的软件会忽略 injected 事件。",
            "Hardware keys show injected=no; keys MicroKeys synthesizes show injected=yes. Some apps ignore injected input."));
        var timer = new System.Windows.Forms.Timer { Interval = seconds * 1000 };
        timer.Tick += (_, _) => Application.ExitThread();
        timer.Start();
        Application.Run();
        Native.UnhookWindowsHookEx(hook);
        return 0;
    }
}

/// <summary><c>--test-shortcut</c>: press a chord, hold, release, without the pad.</summary>
internal static class ShortcutTester
{
    public static int Run(string text, int holdMs)
    {
        KeyChord chord;
        try { chord = KeyChord.Parse(text); }
        catch (KeyChord.ParseException e)
        {
            Console.Error.WriteLine(L10n.Pick($"快捷键有误：{e.Message}", $"Invalid shortcut: {e.Message}"));
            return 1;
        }
        Console.WriteLine(L10n.Pick($"3 秒后按下 {chord}，按住 {holdMs} ms 后松开。请切到目标应用…",
            $"Pressing {chord} in 3 s, holding {holdMs} ms. Switch to the target app…"));
        Thread.Sleep(3000);
        var synth = new SendInputSynthesizer { IntervalMs = 30 };
        synth.Press(chord);
        Thread.Sleep(holdMs);
        synth.Release(chord);
        Console.WriteLine(L10n.Pick("完成", "done"));
        return 0;
    }
}
