using MicroKeys.Core;
using Xunit;

namespace MicroKeys.Core.Tests;

public class FrameDecoderTests
{
    [Fact]
    public void KeyDownUsbFraming()
    {
        var d = new FrameDecoder();
        var events = d.Feed(Reports.Make("""{"m":"v.oai.hid","p":{"k":"ACT10","act":1,"ag":0}}"""));
        Assert.Equal(new PadEvent[] { new PadEvent.Key("ACT10", 1) }, events);
    }

    [Fact]
    public void KeyUpWithReportIdPrefix()
    {
        var d = new FrameDecoder();
        var events = d.Feed(Reports.Make("""{"m":"v.oai.hid","p":{"k":"AG03","act":0}}""", prefixed: true, size: 64));
        Assert.Equal(new PadEvent[] { new PadEvent.Key("AG03", 0) }, events);
    }

    [Fact]
    public void MessageSpanningTwoReports()
    {
        var d = new FrameDecoder();
        var json = """{"jsonrpc":"2.0","method":"v.oai.hid","params":{"k":"ENC_CW","act":2,"padding":"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"}}""";
        var body = System.Text.Encoding.UTF8.GetBytes(json + "\r\n");
        var first = body[..60]; var second = body[60..];
        Assert.Empty(d.Feed(new byte[] { 0x02, (byte)first.Length }.Concat(first).ToArray()));
        Assert.Equal(new PadEvent[] { new PadEvent.Key("ENC_CW", 2) },
            d.Feed(new byte[] { 0x02, (byte)second.Length }.Concat(second).ToArray()));
    }

    [Fact]
    public void TwoMessagesInOneReport()
    {
        var d = new FrameDecoder();
        var json = """{"m":"v.oai.hid","p":{"k":"ACT06","act":1}}""" + "\r\n" + """{"m":"v.oai.rad","p":{"a":0.5,"d":0.25}}""";
        var body = System.Text.Encoding.UTF8.GetBytes(json + "\r\n");
        Assert.Equal(new PadEvent[] { new PadEvent.Key("ACT06", 1), new PadEvent.Joystick(0.5, 0.25) },
            d.Feed(new byte[] { 0x02, (byte)body.Length }.Concat(body).ToArray()));
    }

    [Fact]
    public void GarbageIsIgnored()
    {
        var d = new FrameDecoder();
        Assert.Empty(d.Feed(new byte[] { 0x01, 0x00, 0x00 }));
        Assert.Empty(d.Feed(Array.Empty<byte>()));
        Assert.Empty(d.Feed(Reports.Make("not json")));
    }
}
