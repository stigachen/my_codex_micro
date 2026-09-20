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
        Assert.Equal("rctrl+rshift", c.Bindings["ACT10"].Chord!.Text);
        Assert.Equal(30, c.Options.KeyIntervalMs);
    }

    [Fact]
    public void StringShorthandIsTapAndAliasesResolve()
    {
        var c = Config.Parse("""{"bindings": {"act06": "ctrl+shift+4", "dial_cw": "up", "Mic": {"keys": "f13"}}}""");
        Assert.Equal(BindingMode.Tap, c.Bindings["ACT06"].Mode);
        Assert.Equal(0x26, c.Bindings["ENC_CW"].Chord!.Key!.VirtualKey);
        Assert.Equal(BindingMode.Tap, c.Bindings["ACT10"].Mode);
    }

    [Fact]
    public void OptionsParse()
    {
        Assert.Equal(10, Config.Parse("""{"options": {"key_interval_ms": 10}, "bindings": {}}""").Options.KeyIntervalMs);
        Assert.Throws<ConfigException>(() => Config.Parse("""{"options": {"key_interval_ms": -1}}"""));
        Assert.True(Config.Parse("""{"options": {"split_mic_key": true}}""").Options.SplitMicKey);
        Assert.False(Config.Parse("{}").Options.SplitMicKey);
        Assert.Throws<ConfigException>(() => Config.Parse("""{"options": {"split_mic_key": "yes"}}"""));
    }

    [Fact]
    public void SplitMicKeyMakesAct11ItsOwnKey()
    {
        // Default: ACT11 folds into ACT10, and the error points at the option.
        var folded = Config.Parse("""{"bindings": {"act11": "f13"}}""");
        Assert.Equal("f13", folded.Bindings["ACT10"].Chord!.Text);
        Assert.False(folded.Bindings.ContainsKey("ACT11"));
        Assert.Contains("split_mic_key", Message("""{"bindings": {"ACT10": "a", "ACT11": "b"}}"""));
        Assert.DoesNotContain("split_mic_key", Message("""{"bindings": {"MIC": "a", "ACT10": "b"}}"""));

        // Split: both halves bind separately; MIC still means ACT10.
        var split = Config.Parse("""{"options": {"split_mic_key": true}, "bindings": {"MIC": "a", "ACT11": {"mode": "hold", "keys": "b"}}}""");
        Assert.Equal("a", split.Bindings["ACT10"].Chord!.Text);
        Assert.Equal(BindingMode.Hold, split.Bindings["ACT11"].Mode);
        Assert.Contains("MIC", Message("""{"options": {"split_mic_key": true}, "bindings": {"MIC": "a", "ACT10": "b"}}"""));
    }

    [Fact]
    public void TypeMode()
    {
        var c = Config.Parse("""{"bindings": {"ACT06": {"mode": "type", "text": "abc"}, "DIAL_CW": {"mode": "TYPE", "text": "你好\n"}}}""");
        Assert.Equal(BindingMode.Type, c.Bindings["ACT06"].Mode);
        Assert.Equal("abc", c.Bindings["ACT06"].Text);
        Assert.Null(c.Bindings["ACT06"].Chord);
        Assert.Equal("\"abc\"", c.Bindings["ACT06"].Target);
        Assert.Equal("你好\n", c.Bindings["ENC_CW"].Text);

        Assert.Contains("text", Message("""{"bindings": {"ACT06": {"mode": "type"}}}"""));
        Assert.Contains("text", Message("""{"bindings": {"ACT06": {"mode": "type", "text": ""}}}"""));
        Assert.Contains("keys", Message("""{"bindings": {"ACT06": {"mode": "type", "text": "a", "keys": "b"}}}"""));
        Assert.Contains("text", Message("""{"bindings": {"ACT06": {"mode": "type", "text": 5}}}"""));
        // "text" without mode: the default is still tap, so this is an error that points at "type".
        Assert.Contains("type", Message("""{"bindings": {"ACT06": {"text": "abc"}}}"""));
        Assert.Contains("type", Message("""{"bindings": {"ACT06": {"mode": "hold", "text": "abc"}}}"""));
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
