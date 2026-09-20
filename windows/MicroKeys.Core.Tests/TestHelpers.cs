using MicroKeys.Core;

namespace MicroKeys.Core.Tests;

internal static class Reports
{
    /// <summary>One vendor report carrying <paramref name="json"/> + CRLF, padded to the report size.</summary>
    public static byte[] Make(string json, bool prefixed = false, int size = 63)
    {
        var body = System.Text.Encoding.UTF8.GetBytes(json + "\r\n");
        var list = new List<byte>();
        if (prefixed) list.Add(6);
        list.Add(0x02); list.Add((byte)body.Length); list.AddRange(body);
        while (list.Count < size) list.Add(0);
        return list.ToArray();
    }
}

internal sealed class Recorder : IKeySynthesizer
{
    public List<string> Log { get; } = new();
    public void Press(KeyChord chord) => Log.Add($"down {chord}");
    public void Release(KeyChord chord) => Log.Add($"up {chord}");
    public void Type(string text) => Log.Add($"type {text}");
}
