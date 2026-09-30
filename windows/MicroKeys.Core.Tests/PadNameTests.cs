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
}
