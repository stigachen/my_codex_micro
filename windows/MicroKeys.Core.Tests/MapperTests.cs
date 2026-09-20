using MicroKeys.Core;
using Xunit;

namespace MicroKeys.Core.Tests;

public class MapperTests
{
    private static (Mapper, Recorder) Make(string json)
    {
        var rec = new Recorder();
        return (new Mapper(Config.Parse(json), rec), rec);
    }

    [Fact]
    public void HoldFollowsPressAndRelease()
    {
        var (m, rec) = Make("""{"bindings": {"MIC": {"mode": "hold", "keys": "rctrl+rshift"}}}""");
        m.Handle(new PadEvent.Key("ACT10", 1));
        m.Handle(new PadEvent.Key("ACT10", 1));   // repeat while held: ignored
        Assert.Equal(new[] { "down rctrl+rshift" }, rec.Log);
        Assert.Equal(new[] { "ACT10" }, m.HeldKeys);
        m.Handle(new PadEvent.Key("ACT10", 0));
        m.Handle(new PadEvent.Key("ACT10", 0));
        Assert.Equal(new[] { "down rctrl+rshift", "up rctrl+rshift" }, rec.Log);
        Assert.Empty(m.HeldKeys);
    }

    [Fact]
    public void OtherHalfOfMicCapCountsAsAct10ByDefault()
    {
        var (m, rec) = Make("""{"bindings": {"MIC": {"mode": "hold", "keys": "rctrl+rshift"}}}""");
        var seen = new List<string>();
        m.KeyObserved += (id, act) => seen.Add($"{id} {act}");
        m.Handle(new PadEvent.Key("ACT11", 1));
        Assert.Equal(new[] { "ACT10" }, m.HeldKeys);
        m.Handle(new PadEvent.Key("ACT11", 0));
        Assert.Equal(new[] { "down rctrl+rshift", "up rctrl+rshift" }, rec.Log);
        Assert.Equal(new[] { "ACT10 1", "ACT10 0" }, seen);
    }

    [Fact]
    public void SplitMicKeyRoutesEachHalfSeparately()
    {
        var (m, rec) = Make("""{"options": {"split_mic_key": true}, "bindings": {"ACT10": {"mode": "hold", "keys": "rctrl+rshift"}, "ACT11": "f13"}}""");
        var seen = new List<string>();
        m.KeyObserved += (id, act) => seen.Add($"{id} {act}");
        m.Handle(new PadEvent.Key("ACT11", 1));
        m.Handle(new PadEvent.Key("ACT11", 0));
        Assert.Equal(new[] { "down f13", "up f13" }, rec.Log);
        Assert.Empty(m.HeldKeys);
        m.Handle(new PadEvent.Key("ACT10", 1));
        Assert.Equal(new[] { "ACT10" }, m.HeldKeys);
        m.Handle(new PadEvent.Key("ACT10", 0));
        Assert.Equal(new[] { "down f13", "up f13", "down rctrl+rshift", "up rctrl+rshift" }, rec.Log);
        Assert.Equal(new[] { "ACT11 1", "ACT11 0", "ACT10 1", "ACT10 0" }, seen);
    }

    [Fact]
    public void TapFiresOnDownOnly()
    {
        var (m, rec) = Make("""{"bindings": {"ACT06": "ctrl+shift+4"}}""");
        m.Handle(new PadEvent.Key("ACT06", 1));
        m.Handle(new PadEvent.Key("ACT06", 0));
        Assert.Equal(new[] { "down ctrl+shift+4", "up ctrl+shift+4" }, rec.Log);
    }

    [Fact]
    public void RotationFiresOnAnyAct()
    {
        var (m, rec) = Make("""{"bindings": {"ENC_CW": "up", "ENC_CC": "down"}}""");
        m.Handle(new PadEvent.Key("ENC_CW", 2));
        m.Handle(new PadEvent.Key("ENC_CC", 0));
        Assert.Equal(new[] { "down up", "up up", "down down", "up down" }, rec.Log);
    }

    [Fact]
    public void UnboundKeysDoNothing()
    {
        var (m, rec) = Make("""{"bindings": {"ACT06": "a"}}""");
        m.Handle(new PadEvent.Key("AG00", 1));
        m.Handle(new PadEvent.Joystick(0.1, 0.9));
        Assert.Empty(rec.Log);
    }

    [Fact]
    public void ConfigChangeAndReleaseAllLetGoOfHeldKeys()
    {
        var (m, rec) = Make("""{"bindings": {"MIC": {"mode": "hold", "keys": "ralt"}}}""");
        m.Handle(new PadEvent.Key("ACT10", 1));
        m.Config = new Config();
        Assert.Equal(new[] { "down ralt", "up ralt" }, rec.Log);
        m.Handle(new PadEvent.Key("ACT10", 0));   // stale release: nothing held any more
        Assert.Equal(2, rec.Log.Count);
    }
}
