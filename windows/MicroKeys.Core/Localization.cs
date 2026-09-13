namespace MicroKeys.Core;

/// <summary>The two UI languages MicroKeys ships with.</summary>
public enum Language { ZhHans, En }

/// <summary>
/// Process-wide current language. The app sets it from its saved preference;
/// Core's error messages read it so config errors come out in the right language.
/// </summary>
public static class L10n
{
    public static Language Language { get; set; } = SystemDefault;

    /// <summary>Chinese if the user's UI culture is any Chinese variant, English otherwise.</summary>
    public static Language SystemDefault =>
        System.Globalization.CultureInfo.CurrentUICulture.Name.StartsWith("zh", StringComparison.OrdinalIgnoreCase)
            ? Language.ZhHans : Language.En;

    public static string Pick(string zh, string en) => Language == Language.ZhHans ? zh : en;
}
