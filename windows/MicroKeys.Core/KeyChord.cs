namespace MicroKeys.Core;

/// <summary>
/// A system shortcut to synthesize: zero or more modifiers plus at most one
/// ordinary key, e.g. <c>rctrl+rshift</c>, <c>ctrl+shift+s</c>, <c>f13</c>.
/// Modifiers keep the order written: pressed in that order, released in reverse.
/// </summary>
public sealed record KeyChord(IReadOnlyList<KeyChord.Element> Modifiers, KeyChord.Element? Key, string Text)
{
    /// <param name="Name">canonical name</param>
    /// <param name="VirtualKey">Win32 virtual-key code</param>
    /// <param name="IsModifier">true for Shift/Ctrl/Alt/Win</param>
    /// <param name="Extended">key needs KEYEVENTF_EXTENDEDKEY (right-hand modifiers, nav cluster, keypad Enter…)</param>
    public sealed record Element(string Name, ushort VirtualKey, bool IsModifier, bool Extended);

    public override string ToString() => Text;

    public sealed class ParseException : Exception
    {
        public ParseException(string message) : base(message) { }
    }

    /// <summary>Parse <c>"rctrl+rshift"</c>-style text. Case-insensitive; spaces around '+' are ignored.</summary>
    public static KeyChord Parse(string text)
    {
        var trimmed = text.Trim();
        if (trimmed.Length == 0) throw new ParseException(L10n.Pick("快捷键为空", "the shortcut is empty"));
        var modifiers = new List<Element>();
        Element? key = null;
        foreach (var raw in trimmed.Split('+'))
        {
            var token = raw.Trim().ToLowerInvariant();
            if (token.Length == 0)
                throw new ParseException(L10n.Pick("快捷键里有空的片段（多余的 '+'？）", "empty piece in the shortcut (a stray '+'?)"));
            if (KeyTable.Modifier(token) is { } mod)
            {
                if (modifiers.Any(m => m.VirtualKey == mod.VirtualKey))
                    throw new ParseException(L10n.Pick($"修饰键 '{token}' 重复出现", $"modifier '{token}' appears twice"));
                modifiers.Add(mod);
            }
            else if (KeyTable.Key(token) is { } plain)
            {
                if (key is not null)
                    throw new ParseException(L10n.Pick($"一个快捷键只能有一个普通键，这里有 '{key.Name}' 和 '{token}'",
                        $"a shortcut can have only one regular key; found '{key.Name}' and '{token}'"));
                key = plain;
            }
            else if (token is "fn" or "globe")
            {
                throw new ParseException(L10n.Pick("Windows 上没有可合成的 fn 键", "there is no synthesizable fn key on Windows"));
            }
            else
            {
                throw new ParseException(L10n.Pick($"不认识的按键名 '{token}'", $"unknown key name '{token}'"));
            }
        }
        return new KeyChord(modifiers, key, trimmed);
    }
}

/// <summary>Virtual-key codes. Names match the macOS build so one config works on both.</summary>
public static class KeyTable
{
    private static KeyChord.Element Mod(string name, ushort vk, bool ext) => new(name, vk, true, ext);

    private static readonly Dictionary<string, KeyChord.Element> Modifiers = Build(new (string[] names, KeyChord.Element e)[]
    {
        (new[] { "shift", "lshift", "⇧" }, Mod("shift", 0xA0, false)),
        (new[] { "rshift", "rightshift", "right_shift" }, Mod("rshift", 0xA1, false)),
        (new[] { "ctrl", "control", "lctrl", "lcontrol", "⌃" }, Mod("ctrl", 0xA2, false)),
        (new[] { "rctrl", "rcontrol", "rightctrl", "rightcontrol", "right_ctrl", "right_control" }, Mod("rctrl", 0xA3, true)),
        (new[] { "opt", "option", "alt", "lopt", "loption", "lalt", "⌥" }, Mod("alt", 0xA4, false)),
        (new[] { "ropt", "roption", "ralt", "rightoption", "rightalt", "right_option", "right_alt" }, Mod("ralt", 0xA5, true)),
        // cmd on macOS is the Windows key here, so a shared config keeps working.
        (new[] { "cmd", "command", "lcmd", "lcommand", "win", "lwin", "super", "⌘" }, Mod("win", 0x5B, true)),
        (new[] { "rcmd", "rcommand", "rightcmd", "rightcommand", "right_cmd", "right_command", "rwin" }, Mod("rwin", 0x5C, true)),
    });

    private static readonly Dictionary<string, (ushort vk, bool ext)> Keys = BuildKeys();

    private static Dictionary<string, KeyChord.Element> Build((string[] names, KeyChord.Element e)[] rows)
    {
        var d = new Dictionary<string, KeyChord.Element>();
        foreach (var (names, e) in rows) foreach (var n in names) d[n] = e;
        return d;
    }

    private static Dictionary<string, (ushort, bool)> BuildKeys()
    {
        var d = new Dictionary<string, (ushort, bool)>();
        for (char c = 'a'; c <= 'z'; c++) d[c.ToString()] = ((ushort)(0x41 + (c - 'a')), false);
        for (char c = '0'; c <= '9'; c++) d[c.ToString()] = ((ushort)(0x30 + (c - '0')), false);
        for (int i = 1; i <= 24; i++) d[$"f{i}"] = ((ushort)(0x6F + i), false);
        void Add(ushort vk, bool ext, params string[] names) { foreach (var n in names) d[n] = (vk, ext); }
        Add(0x0D, false, "return", "enter");
        Add(0x09, false, "tab");
        Add(0x20, false, "space");
        Add(0x1B, false, "escape", "esc");
        // Same meaning as the macOS build: "delete" is the backspace key, "forwarddelete"/"del" the forward one.
        Add(0x08, false, "delete", "backspace");
        Add(0x2E, true, "forwarddelete", "del");
        Add(0x2D, true, "insert");
        Add(0x25, true, "left"); Add(0x26, true, "up"); Add(0x27, true, "right"); Add(0x28, true, "down");
        Add(0x24, true, "home"); Add(0x23, true, "end"); Add(0x21, true, "pageup"); Add(0x22, true, "pagedown");
        Add(0x14, false, "capslock");
        Add(0x2C, true, "printscreen");
        Add(0x91, false, "scrolllock");
        Add(0x13, false, "pause");
        Add(0x90, true, "numlock");
        Add(0x5D, true, "apps", "menu", "contextmenu");
        Add(0xBD, false, "-", "minus"); Add(0xBB, false, "=", "equal", "equals");
        Add(0xDB, false, "[", "leftbracket"); Add(0xDD, false, "]", "rightbracket");
        Add(0xDC, false, "\\", "backslash"); Add(0xBA, false, ";", "semicolon");
        Add(0xDE, false, "'", "quote"); Add(0xBC, false, ",", "comma");
        Add(0xBE, false, ".", "period"); Add(0xBF, false, "/", "slash");
        Add(0xC0, false, "`", "grave", "backtick");
        for (int i = 0; i <= 9; i++) d[$"keypad{i}"] = ((ushort)(0x60 + i), false);
        Add(0x0D, true, "keypadenter");
        Add(0x6B, false, "keypadplus"); Add(0x6D, false, "keypadminus"); Add(0x6A, false, "keypadmultiply");
        Add(0x6F, true, "keypaddivide"); Add(0x6E, false, "keypaddecimal");
        // Windows can synthesize media keys, so they are allowed here (not on macOS).
        Add(0xAF, true, "volumeup"); Add(0xAE, true, "volumedown"); Add(0xAD, true, "mute");
        Add(0xB3, true, "playpause"); Add(0xB0, true, "nexttrack"); Add(0xB1, true, "prevtrack");
        return d;
    }

    public static KeyChord.Element? Modifier(string name) => Modifiers.TryGetValue(name, out var e) ? e : null;

    public static KeyChord.Element? Key(string name) =>
        Keys.TryGetValue(name, out var k) ? new KeyChord.Element(name, k.vk, false, k.ext) : null;
}
