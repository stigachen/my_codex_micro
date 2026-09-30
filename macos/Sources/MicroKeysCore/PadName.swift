import Foundation

/// The name to show for a connected pad.
public enum PadName {
    /// The HID product string, tidied: Bluetooth appends " #1" to it
    /// ("Codex Micro #1"), which says nothing to the user. nil when the
    /// device reports no usable name.
    public static func display(_ product: String?) -> String? {
        guard var name = product?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        if let range = name.range(of: #"\s+#\d+$"#, options: .regularExpression) {
            name.removeSubrange(range)
        }
        return name.isEmpty ? nil : name
    }
}
