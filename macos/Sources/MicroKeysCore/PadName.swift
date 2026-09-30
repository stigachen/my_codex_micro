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

    /// A pad's name for display: its product name, or a generic one in the
    /// current language. Chosen at display time, never stored, so switching
    /// the language applies to a pad that is already connected.
    public static func label(_ name: String?, language: Language = L10n.language) -> String {
        name ?? (language == .zhHans ? "Work Louder 键盘" : "Work Louder pad")
    }
}
