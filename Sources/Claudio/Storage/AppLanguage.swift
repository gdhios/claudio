import Foundation

/// The interface language, adjustable in Settings → General.
///
/// The `rawValue` is the storage key in UserDefaults: it no longer changes.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case french = "fr"
    case english = "en"

    var id: String { rawValue }

    /// Each language announces itself in its own language: it's the only
    /// label that must be readable before making a choice.
    var title: String {
        switch self {
        case .system: loc("Système", en: "System")
        case .french: "Français"
        case .english: "English"
        }
    }

    /// True when the interface must display in English. On "System", French
    /// only wins if it's really the machine's preferred language: everywhere
    /// else, English is the broadest fallback.
    var showsEnglish: Bool {
        switch self {
        case .french: false
        case .english: true
        case .system: !(Locale.preferredLanguages.first ?? "en").hasPrefix("fr")
        }
    }
}

/// A label in both languages, chosen at display time.
///
/// No `Localizable.strings`: the setting must be able to contradict the
/// system language, which Apple's mechanism doesn't do without a detour. And
/// keeping both versions side by side avoids tables that drift out of sync.
func loc(_ french: String, en english: String) -> String {
    AppSettings.language.showsEnglish ? english : french
}
