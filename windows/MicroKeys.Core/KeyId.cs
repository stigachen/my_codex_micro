namespace MicroKeys.Core;

/// <summary>The pad's bindable inputs, and how config names map onto wire ids.</summary>
public static class KeyId
{
    public static readonly string[] AgentKeys = { "AG00", "AG01", "AG02", "AG03", "AG04", "AG05" };
    public static readonly string[] ActionKeys = { "ACT06", "ACT07", "ACT08", "ACT09", "ACT10", "ACT12" };
    public const string DialPress = "ENC_CLK";
    public static readonly string[] DialRotation = { "ENC_CW", "ENC_CC" };

    /// <summary>Every id a binding may target, after alias resolution.</summary>
    public static readonly string[] All = AgentKeys.Concat(ActionKeys).Append(DialPress).Concat(DialRotation).ToArray();

    /// <summary>
    /// Friendly names accepted in config. ACT10 and ACT11 are the two switches
    /// under one double-width keycap (the MIC key) and both fire on every press;
    /// the slot is routed through ACT10 and ACT11 is dropped, like the vendor app.
    /// </summary>
    public static readonly IReadOnlyDictionary<string, string> Aliases = new Dictionary<string, string>
    {
        ["MIC"] = "ACT10", ["ACT10_ACT11"] = "ACT10", ["ACT11"] = "ACT10",
        ["DIAL"] = "ENC_CLK", ["DIAL_CLICK"] = "ENC_CLK", ["ENC"] = "ENC_CLK",
        ["DIAL_CW"] = "ENC_CW", ["DIAL_CC"] = "ENC_CC", ["DIAL_CCW"] = "ENC_CC", ["ENC_CCW"] = "ENC_CC",
    };

    /// <summary>Resolve a config key (any case, alias allowed) to a wire id, or null.</summary>
    public static string? Resolve(string name)
    {
        var upper = name.Trim().ToUpperInvariant();
        if (Aliases.TryGetValue(upper, out var alias)) return alias;
        return Array.IndexOf(All, upper) >= 0 ? upper : null;
    }

    /// <summary>Map an incoming wire id to the id bindings are keyed on; ACT11 is dropped.</summary>
    public static string? NormalizeEvent(string wireId) => wireId == "ACT11" ? null : wireId;

    public static bool IsRotation(string id) => Array.IndexOf(DialRotation, id) >= 0;
}
