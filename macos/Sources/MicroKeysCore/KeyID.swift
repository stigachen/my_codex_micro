import Foundation

/// The pad's bindable inputs, and how config names map onto wire ids.
public enum KeyID {
    public static let agentKeys = ["AG00", "AG01", "AG02", "AG03", "AG04", "AG05"]
    public static let actionKeys = ["ACT06", "ACT07", "ACT08", "ACT09", "ACT10", "ACT12"]
    public static let dialPress = "ENC_CLK"
    public static let dialRotation = ["ENC_CW", "ENC_CC"]

    /// Every id a binding may target, after alias resolution.
    public static let all: [String] = agentKeys + actionKeys + [dialPress] + dialRotation

    /// The second switch under the double-width MIC keycap. Only bindable when
    /// `options.split_mic_key` is on.
    public static let micSecondHalf = "ACT11"

    /// Friendly names accepted in config, resolved to the wire id.
    ///
    /// `ACT10` and `ACT11` are the two switches under one double-width keycap
    /// (the MIC key from the factory). Each half reports its own id, so a press
    /// lands on one or the other depending on where the cap is pushed. By
    /// default `ACT11` is folded into `ACT10` so the whole cap acts as one MIC
    /// key, like the vendor app; with `split_mic_key` the halves are separate
    /// keys (the vendor app's "use independent microphone keys").
    public static let aliases: [String: String] = [
        "MIC": "ACT10", "ACT10_ACT11": "ACT10", "ACT11": "ACT10",
        "DIAL": "ENC_CLK", "DIAL_CLICK": "ENC_CLK", "ENC": "ENC_CLK",
        "DIAL_CW": "ENC_CW", "DIAL_CC": "ENC_CC", "DIAL_CCW": "ENC_CC", "ENC_CCW": "ENC_CC",
    ]

    /// Resolve a config key (any case, alias allowed) to a wire id, or nil.
    /// With `splitMic`, `ACT11` is its own key instead of an alias of `ACT10`.
    public static func resolve(_ name: String, splitMic: Bool = false) -> String? {
        let upper = name.trimmingCharacters(in: .whitespaces).uppercased()
        if splitMic, upper == micSecondHalf { return upper }
        if let alias = aliases[upper] { return alias }
        return all.contains(upper) ? upper : nil
    }

    /// Map an incoming wire id to the id bindings are keyed on. Unless the MIC
    /// key is split, `ACT11` becomes `ACT10` so either half of the cap works.
    public static func normalizeEvent(_ wireID: String, splitMic: Bool = false) -> String? {
        if wireID == micSecondHalf, !splitMic { return aliases[micSecondHalf] }
        return wireID
    }

    public static func isRotation(_ id: String) -> Bool { dialRotation.contains(id) }
}
