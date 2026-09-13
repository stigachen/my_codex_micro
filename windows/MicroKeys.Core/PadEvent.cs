using System.Text.Json;

namespace MicroKeys.Core;

/// <summary>
/// One decoded message from the pad's vendor HID channel (Report ID 6, JSON-RPC).
/// Every key, dial tick and joystick sample on the Codex Micro arrives here; the
/// keys do not emit ordinary keyboard scancodes.
/// </summary>
public abstract record PadEvent
{
    /// <summary><c>v.oai.hid</c>: key id (AG00…AG05, ACT06…ACT12, ENC_CLK, ENC_CW, ENC_CC);
    /// act 1 = down, 0 = up. Dial rotation carries other act values, so rotation fires on any act.</summary>
    public sealed record Key(string Id, int Act) : PadEvent;

    /// <summary><c>v.oai.rad</c>: analogue thumbstick, angle and distance both 0…1.</summary>
    public sealed record Joystick(double Angle, double Distance) : PadEvent;

    /// <summary>Anything else: RPC replies, unknown notifications.</summary>
    public sealed record Other(string Method) : PadEvent;

    /// <summary>Parse one CRLF-delimited JSON line. Accepts the compact form
    /// <c>{"m":…,"p":…}</c> and the standard <c>{"method":…,"params":…}</c>.</summary>
    public static PadEvent? Parse(string text)
    {
        JsonDocument doc;
        try { doc = JsonDocument.Parse(text); }
        catch (JsonException) { return null; }
        using (doc)
        {
            var root = doc.RootElement;
            if (root.ValueKind != JsonValueKind.Object) return null;
            var method = GetString(root, "m") ?? GetString(root, "method") ?? "";
            JsonElement p = default;
            var hasParams = (root.TryGetProperty("p", out p) || root.TryGetProperty("params", out p))
                            && p.ValueKind == JsonValueKind.Object;
            switch (method)
            {
                case "v.oai.hid":
                {
                    if (!hasParams) return null;
                    var k = GetString(p, "k");
                    if (k is null) return null;
                    var act = p.TryGetProperty("act", out var a) && a.ValueKind == JsonValueKind.Number ? a.GetInt32() : -1;
                    return new Key(k, act);
                }
                case "v.oai.rad":
                {
                    if (!hasParams) return null;
                    var angle = p.TryGetProperty("a", out var av) && av.ValueKind == JsonValueKind.Number ? av.GetDouble() : 0;
                    var dist = p.TryGetProperty("d", out var dv) && dv.ValueKind == JsonValueKind.Number ? dv.GetDouble() : 0;
                    return new Joystick(angle, dist);
                }
                default:
                    return new Other(method);
            }
        }
    }

    private static string? GetString(JsonElement e, string name) =>
        e.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;
}
