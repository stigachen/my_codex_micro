using MicroKeys.Core;

namespace MicroKeys;

/// <summary>
/// Posts keyboard input through SendInput. Each event carries both the
/// virtual key and its scan code, and right-hand modifiers / navigation keys
/// set the extended flag, so apps that look at either see a normal keyboard.
/// No permission is needed on Windows; the only limit is that a normal
/// process cannot inject into windows running as administrator.
/// </summary>
internal sealed class SendInputSynthesizer : IKeySynthesizer
{
    /// <summary>Pause between individual events, in milliseconds.</summary>
    public int IntervalMs { get; set; }

    public void Press(KeyChord chord)
    {
        foreach (var m in chord.Modifiers) Post(m, down: true);
        if (chord.Key is { } k) Post(k, down: true);
    }

    public void Release(KeyChord chord)
    {
        if (chord.Key is { } k) Post(k, down: false);
        for (int i = chord.Modifiers.Count - 1; i >= 0; i--) Post(chord.Modifiers[i], down: false);
    }

    private void Post(KeyChord.Element e, bool down)
    {
        var scan = (ushort)Native.MapVirtualKey(e.VirtualKey, 0);
        var flags = (e.Extended ? Native.KEYEVENTF_EXTENDEDKEY : 0u) | (down ? 0u : Native.KEYEVENTF_KEYUP);
        var input = new Native.INPUT
        {
            type = Native.INPUT_KEYBOARD,
            u = new Native.INPUTUNION { ki = new Native.KEYBDINPUT { wVk = e.VirtualKey, wScan = scan, dwFlags = flags } },
        };
        var sent = Native.SendInput(1, new[] { input }, System.Runtime.InteropServices.Marshal.SizeOf<Native.INPUT>());
        if (sent != 1) Log.Error($"SendInput failed for {e.Name}: error {System.Runtime.InteropServices.Marshal.GetLastWin32Error()}");
        if (IntervalMs > 0) Thread.Sleep(IntervalMs);
    }
}
