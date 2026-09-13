using MicroKeys.Core;
using Xunit;

namespace MicroKeys.Core.Tests;

public class KeyChordTests
{
    [Fact]
    public void RightModifiersOnly()
    {
        var c = KeyChord.Parse("rctrl+rshift");
        Assert.Null(c.Key);
        Assert.Equal(new ushort[] { 0xA3, 0xA1 }, c.Modifiers.Select(m => m.VirtualKey));
        Assert.True(c.Modifiers[0].Extended);   // right Ctrl is an extended key
        Assert.False(c.Modifiers[1].Extended);
    }

    [Fact]
    public void ModifiersPlusKeyCaseAndSpaces()
    {
        var c = KeyChord.Parse(" Ctrl + Shift + 4 ");
        Assert.Equal(new[] { "ctrl", "shift" }, c.Modifiers.Select(m => m.Name));
        Assert.Equal(0x34, c.Key!.VirtualKey);
    }

    [Fact]
    public void MacNamesMapOntoWindowsKeys()
    {
        Assert.Equal(0x5B, KeyChord.Parse("cmd+shift+4").Modifiers[0].VirtualKey);   // cmd -> Win
        Assert.Equal(0x08, KeyChord.Parse("delete").Key!.VirtualKey);               // delete -> Backspace, as on macOS
        Assert.Equal(0x2E, KeyChord.Parse("forwarddelete").Key!.VirtualKey);
        Assert.Equal(0x1B, KeyChord.Parse("⌘+⇧+esc").Key!.VirtualKey);
        Assert.Equal(0x7C, KeyChord.Parse("f13").Key!.VirtualKey);
        Assert.Equal(0xAF, KeyChord.Parse("volumeup").Key!.VirtualKey);
    }

    [Theory]
    [InlineData("", "empty")]
    [InlineData("ctrl++a", "stray")]
    [InlineData("ctrl+bogus", "bogus")]
    [InlineData("ctrl+control+a", "twice")]
    [InlineData("a+b", "only one")]
    [InlineData("fn", "fn")]
    public void Errors(string text, string fragment)
    {
        L10n.Language = Language.En;
        var e = Assert.Throws<KeyChord.ParseException>(() => KeyChord.Parse(text));
        Assert.Contains(fragment, e.Message);
    }
}
