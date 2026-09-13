import Foundation

/// The pad's bindable inputs, and how config names map onto wire ids.
public enum KeyID {
    public static let agentKeys = ["AG00", "AG01", "AG02", "AG03", "AG04", "AG05"]
    public static let actionKeys = ["ACT06", "ACT07", "ACT08", "ACT09", "ACT10", "ACT12"]
    public static let dialPress = "ENC_CLK"
    public static let dialRotation = ["ENC_CW", "ENC_CC"]

    /// Every id a binding may target, after alias resolution.
    public static let all: [String] = agentKeys + actionKeys + [dialPress] + dialRotation

    /// Friendly names accepted in config, resolved to the wire id.
    ///
    /// `ACT10` and `ACT11` are the two switches under one double-width keycap
    /// (the MIC key from the factory), and both fire on every press. We route
    /// the slot through `ACT10` and drop `ACT11`, exactly like the vendor app.
    public static let aliases: [String: String] = [
        "MIC": "ACT10", "ACT10_ACT11": "ACT10", "ACT11": "ACT10",
        "DIAL": "ENC_CLK", "DIAL_CLICK": "ENC_CLK", "ENC": "ENC_CLK",
        "DIAL_CW": "ENC_CW", "DIAL_CC": "ENC_CC", "DIAL_CCW": "ENC_CC", "ENC_CCW": "ENC_CC",
    ]

    /// Resolve a config key (any case, alias allowed) to a wire id, or nil.
    public static func resolve(_ name: String) -> String? {
        let upper = name.trimmingCharacters(in: .whitespaces).uppercased()
        if let alias = aliases[upper] { return alias }
        return all.contains(upper) ? upper : nil
    }

    /// Map an incoming wire id to the id bindings are keyed on. `ACT11` is the
    /// second half of the MIC slot and is dropped so the slot fires once.
    public static func normalizeEvent(_ wireID: String) -> String? {
        if wireID == "ACT11" { return nil }
        return wireID
    }

    public static func isRotation(_ id: String) -> Bool { dialRotation.contains(id) }
}
