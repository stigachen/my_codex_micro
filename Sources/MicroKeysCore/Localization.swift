import Foundation

/// The two UI languages MicroKeys ships with.
public enum Language: String, CaseIterable {
    case zhHans = "zh-Hans"
    case en = "en"

    /// What the system prefers: Chinese if the user's first preferred language
    /// is any Chinese variant, English otherwise.
    public static var systemDefault: Language {
        let first = Locale.preferredLanguages.first?.lowercased() ?? "en"
        return first.hasPrefix("zh") ? .zhHans : .en
    }
}

/// Process-wide current language. The app sets it from its saved preference;
/// Core's error messages read it so config errors come out in the right language.
public enum L10n {
    public static var language: Language = .systemDefault

    public static func pick(_ zh: String, _ en: String) -> String {
        language == .zhHans ? zh : en
    }
}
