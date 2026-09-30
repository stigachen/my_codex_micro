using System.Text.RegularExpressions;

namespace MicroKeys.Core;

/// <summary>The name to show for a connected pad.</summary>
public static class PadName
{
    private static readonly Regex BluetoothSuffix = new(@"\s+#\d+$");

    /// <summary>The HID product string, tidied: Bluetooth appends " #1" to it
    /// ("Codex Micro #1"), which says nothing to the user. Null when the
    /// device reports no usable name.</summary>
    public static string? Display(string? product)
    {
        var name = product?.Trim();
        if (string.IsNullOrEmpty(name)) return null;
        name = BluetoothSuffix.Replace(name, "");
        return name.Length == 0 ? null : name;
    }

    /// <summary>A pad's name for display: its product name, or a generic one in
    /// the current language. Chosen at display time, never stored, so switching
    /// the language applies to a pad that is already connected.</summary>
    public static string Label(string? name) => Label(name, L10n.Language);

    public static string Label(string? name, Language language) =>
        name ?? (language == Language.ZhHans ? "Work Louder 键盘" : "Work Louder pad");
}
