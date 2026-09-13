using System.Text;

namespace MicroKeys.Core;

/// <summary>
/// Reassembles JSON-RPC messages from a stream of vendor HID input reports.
/// Each report is <c>[0x02][len][utf-8 json…]</c>; Windows prefixes the buffer
/// with the report id (0x06), other paths may not, and both layouts are accepted.
/// Messages are CRLF-terminated, may span several reports, and several may
/// share one report.
/// </summary>
public sealed class FrameDecoder
{
    public const byte ReportId = 6;
    public const byte OpcodeData = 0x02;

    private readonly List<byte> _buffer = new();

    /// <summary>Consume one raw report; return every event it completed.</summary>
    public List<PadEvent> Feed(ReadOnlySpan<byte> raw)
    {
        var events = new List<PadEvent>();
        int start;
        if (raw.Length >= 3 && raw[0] == ReportId && raw[1] == OpcodeData) start = 1;
        else if (raw.Length >= 2 && raw[0] == OpcodeData) start = 0;
        else return events;

        int length = raw[start + 1];
        int bodyStart = start + 2;
        int bodyEnd = Math.Min(raw.Length, bodyStart + length);
        if (bodyEnd <= bodyStart) return events;
        _buffer.AddRange(raw[bodyStart..bodyEnd].ToArray());

        int crlf;
        while ((crlf = IndexOfCrlf()) >= 0)
        {
            var line = _buffer.GetRange(0, crlf).ToArray();
            _buffer.RemoveRange(0, crlf + 2);
            string text;
            try { text = Encoding.UTF8.GetString(line).Trim(); }
            catch (ArgumentException) { continue; }
            if (text.Length == 0) continue;
            var e = PadEvent.Parse(text);
            if (e is not null) events.Add(e);
        }
        // A runaway buffer means we lost framing; drop it rather than grow forever.
        if (_buffer.Count > 8192) _buffer.Clear();
        return events;
    }

    public void Reset() => _buffer.Clear();

    private int IndexOfCrlf()
    {
        for (int i = 0; i + 1 < _buffer.Count; i++)
            if (_buffer[i] == 0x0D && _buffer[i + 1] == 0x0A) return i;
        return -1;
    }
}
