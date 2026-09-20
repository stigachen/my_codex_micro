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

    /// <summary>The second switch under the double-width MIC keycap. Only bindable
    /// when options.split_mic_key is on.</summary>
    public const string MicSecondHalf = "ACT11";

    /// <summary>
    /// Friendly names accepted in config. ACT10 and ACT11 are the two switches
    /// under one double-width keycap (the MIC key); each half reports its own id.
    /// By default ACT11 is folded into ACT10 so the whole cap acts as one MIC key,
    /// like the vendor app; with split_mic_key the halves are separate keys (the
    /// vendor app's "use independent microphone keys").
    /// </summary>
    public static readonly IReadOnlyDictionary<string, string> Aliases = new Dictionary<string, string>
    {
        ["MIC"] = "ACT10", ["ACT10_ACT11"] = "ACT10", ["ACT11"] = "ACT10",
        ["DIAL"] = "ENC_CLK", ["DIAL_CLICK"] = "ENC_CLK", ["ENC"] = "ENC_CLK",
        ["DIAL_CW"] = "ENC_CW", ["DIAL_CC"] = "ENC_CC", ["DIAL_CCW"] = "ENC_CC", ["ENC_CCW"] = "ENC_CC",
    };

    /// <summary>Resolve a config key (any case, alias allowed) to a wire id, or null.
    /// With splitMic, ACT11 is its own key instead of an alias of ACT10.</summary>
    public static string? Resolve(string name, bool splitMic = false)
    {
        var upper = name.Trim().ToUpperInvariant();
        if (splitMic && upper == MicSecondHalf) return upper;
        if (Aliases.TryGetValue(upper, out var alias)) return alias;
        return Array.IndexOf(All, upper) >= 0 ? upper : null;
    }

    /// <summary>Map an incoming wire id to the id bindings are keyed on. Unless the MIC
    /// key is split, ACT11 becomes ACT10 so either half of the cap works.</summary>
    public static string? NormalizeEvent(string wireId, bool splitMic = false)
        => wireId == MicSecondHalf && !splitMic ? Aliases[MicSecondHalf] : wireId;

    public static bool IsRotation(string id) => Array.IndexOf(DialRotation, id) >= 0;
}
