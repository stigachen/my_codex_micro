using MicroKeys.Core;
using Xunit;

namespace MicroKeys.Core.Tests;

public class PadNameTests
{
    [Theory]
    [InlineData("Codex Micro", "Codex Micro")]
    [InlineData("Codex Micro #1", "Codex Micro")]          // over Bluetooth
    [InlineData("Creator Micro 2", "Creator Micro 2")]
    [InlineData("  Creator Micro 2 #12 ", "Creator Micro 2")]
    [InlineData("#1", "#1")]                               // nothing to strip before it
    [InlineData("", null)]
    [InlineData("   ", null)]
    [InlineData(null, null)]
    public void TidiesProductStrings(string? product, string? expected) =>
        Assert.Equal(expected, PadName.Display(product));

    /// <summary>Review #15: a nameless pad stores null, and the generic name is
    /// picked in whatever language is current when it is shown.</summary>
    [Fact]
    public void GenericNameFollowsTheLanguage()
    {
        var stored = PadName.Display("  ");
        Assert.Null(stored);
        Assert.Equal("Work Louder 键盘", PadName.Label(stored, Language.ZhHans));
        Assert.Equal("Work Louder pad", PadName.Label(stored, Language.En));
        Assert.Equal("Creator Micro 2", PadName.Label("Creator Micro 2", Language.En));
    }
}
