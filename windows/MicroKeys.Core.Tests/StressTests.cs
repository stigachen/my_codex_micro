using MicroKeys.Core;
using Xunit;

namespace MicroKeys.Core.Tests;

public class StressTests
{
    private sealed class NullSynth : IKeySynthesizer
    {
        public int Presses;
        public void Press(KeyChord chord) => Presses++;
        public void Release(KeyChord chord) { }
    }

    /// <summary>A million events through decoder and mapper; managed heap must stay flat.</summary>
    [Fact]
    public void MillionEventsDoNotGrowMemory()
    {
        var config = Config.Parse("""{"bindings": {"MIC": {"mode": "hold", "keys": "rctrl+rshift"}, "ACT06": "ctrl+shift+4", "ENC_CW": "up"}}""");
        var synth = new NullSynth();
        var mapper = new Mapper(config, synth);
        var decoder = new FrameDecoder();
        var frames = new[]
        {
            Reports.Make("""{"m":"v.oai.hid","p":{"k":"ACT10","act":1,"ag":0}}""", prefixed: true, size: 64),
            Reports.Make("""{"m":"v.oai.hid","p":{"k":"ACT11","act":1,"ag":0}}""", prefixed: true, size: 64),
            Reports.Make("""{"m":"v.oai.hid","p":{"k":"ACT10","act":0,"ag":0}}""", prefixed: true, size: 64),
            Reports.Make("""{"m":"v.oai.hid","p":{"k":"ACT11","act":0,"ag":0}}""", prefixed: true, size: 64),
            Reports.Make("""{"m":"v.oai.hid","p":{"k":"ACT06","act":1,"ag":0}}""", prefixed: true, size: 64),
            Reports.Make("""{"m":"v.oai.hid","p":{"k":"ACT06","act":0,"ag":0}}""", prefixed: true, size: 64),
            Reports.Make("""{"m":"v.oai.hid","p":{"k":"ENC_CW","act":2,"ag":0}}""", prefixed: true, size: 64),
            Reports.Make("""{"m":"v.oai.rad","p":{"a":0.42,"d":0.9}}""", prefixed: true, size: 64),
            Reports.Make("""{"m":"v.oai.hid","p":{"k":"AG03","act":1,"ag":3}}""", prefixed: true, size: 64),
            Reports.Make("""{"result":{"ok":1},"id":null,"method":"v.oai.rgbcfg"}""", prefixed: true, size: 64),
        };

        void Run(int rounds) { for (int r = 0; r < rounds; r++) foreach (var f in frames) foreach (var e in decoder.Feed(f)) mapper.Handle(e); }

        Run(20_000);
        GC.Collect(); GC.WaitForPendingFinalizers(); GC.Collect();
        var before = GC.GetTotalMemory(forceFullCollection: true);
        Run(100_000);
        var after = GC.GetTotalMemory(forceFullCollection: true);

        Assert.True(synth.Presses > 300_000);
        Assert.Empty(mapper.HeldKeys);
        var growth = after - before;
        Assert.True(growth < 2 * 1024 * 1024, $"managed heap grew by {growth / 1024} KB over 1,000,000 events");
    }
}
