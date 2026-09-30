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
}
