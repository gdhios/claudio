import Foundation

/// La langue de l'interface, réglable dans Réglages → Général.
///
/// Le `rawValue` est la clé de stockage dans UserDefaults : il ne change plus.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system
    case french = "fr"
    case english = "en"

    var id: String { rawValue }

    /// Chaque langue s'annonce dans sa propre langue : c'est le seul libellé
    /// qu'on doit pouvoir lire avant d'avoir choisi.
    var title: String {
        switch self {
        case .system: loc("Système", en: "System")
        case .french: "Français"
        case .english: "English"
        }
    }

    /// Vrai quand l'interface doit s'afficher en anglais. Sur « Système », le
    /// français ne l'emporte que si c'est bien la langue préférée de la
    /// machine : partout ailleurs, l'anglais est le repli le plus large.
    var showsEnglish: Bool {
        switch self {
        case .french: false
        case .english: true
        case .system: !(Locale.preferredLanguages.first ?? "en").hasPrefix("fr")
        }
    }
}

/// Un libellé dans les deux langues, choisi au moment de l'affichage.
///
/// Pas de `Localizable.strings` : le réglage doit pouvoir contredire la langue
/// du système, ce que le mécanisme d'Apple ne fait pas sans détour. Et garder
/// les deux versions côte à côte évite les tables qui se désynchronisent.
func loc(_ french: String, en english: String) -> String {
    AppSettings.language.showsEnglish ? english : french
}
