using MicroKeys.Core;
using Xunit;

namespace MicroKeys.Core.Tests;

public class ConfigTests
{
    private static string Message(string json)
    {
        try { Config.Parse(json); return ""; }
        catch (ConfigException e) { return e.Message; }
    }

    [Fact]
    public void ExampleConfigParses()
    {
        var c = Config.Parse(Config.ExampleJson);
        Assert.Single(c.Bindings);
        Assert.Equal(BindingMode.Hold, c.Bindings["ACT10"].Mode);
        Assert.Equal("rctrl+rshift", c.Bindings["ACT10"].Chord.Text);
        Assert.Equal(30, c.Options.KeyIntervalMs);
    }

    [Fact]
    public void StringShorthandIsTapAndAliasesResolve()
    {
        var c = Config.Parse("""{"bindings": {"act06": "ctrl+shift+4", "dial_cw": "up", "Mic": {"keys": "f13"}}}""");
        Assert.Equal(BindingMode.Tap, c.Bindings["ACT06"].Mode);
        Assert.Equal(0x26, c.Bindings["ENC_CW"].Chord.Key!.VirtualKey);
        Assert.Equal(BindingMode.Tap, c.Bindings["ACT10"].Mode);
    }

    [Fact]
    public void OptionsParse()
    {
        Assert.Equal(10, Config.Parse("""{"options": {"key_interval_ms": 10}, "bindings": {}}""").Options.KeyIntervalMs);
        Assert.Throws<ConfigException>(() => Config.Parse("""{"options": {"key_interval_ms": -1}}"""));
    }

    [Fact]
    public void ErrorsNameTheKey()
    {
        Assert.Contains("ACT99", Message("""{"bindings": {"ACT99": "a"}}"""));
        Assert.Contains("nope", Message("""{"bindings": {"ACT06": {"mode": "hold", "keys": "nope"}}}"""));
        Assert.Contains("toggle", Message("""{"bindings": {"ACT06": {"mode": "toggle", "keys": "a"}}}"""));
        Assert.Contains("hold", Message("""{"bindings": {"ENC_CW": {"mode": "hold", "keys": "a"}}}"""));
        Assert.Contains("MIC", Message("""{"bindings": {"MIC": "a", "ACT10": "b"}}"""));
        Assert.Contains("ACT06", Message("""{"bindings": {"ACT06": 5}}"""));
        Assert.Contains("version", Message("""{"version": 2}"""));
        Assert.Contains("JSON", Message("{ oops"));
    }
}
