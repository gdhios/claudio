import Foundation

/// The languages dictation can be started in: a closed list, because each one
/// has to exist as an on-device model on the machine, and because two
/// shortcuts pick from it.
///
/// The `rawValue` is a BCP-47 identifier: it is both the storage key in
/// UserDefaults and what the speech engine is started with. It is never
/// renamed; languages are only added.
enum DictationLanguage: String, CaseIterable, Sendable {
    case frFR = "fr-FR"
    case enUS = "en-US"
    case enGB = "en-GB"
    case esES = "es-ES"
    case deDE = "de-DE"
    case itIT = "it-IT"
    case ptBR = "pt-BR"
    case nlNL = "nl-NL"

    /// What the recognizer is asked for. The region matters: "en-US" and
    /// "en-GB" are two different models.
    var locale: Locale { Locale(identifier: rawValue) }

    /// Label in Settings. The region is spelled out only where the same
    /// language appears twice: otherwise it is noise.
    var displayName: String {
        switch self {
        case .frFR: loc("Français", en: "French")
        case .enUS: loc("Anglais (États-Unis)", en: "English (US)")
        case .enGB: loc("Anglais (Royaume-Uni)", en: "English (UK)")
        case .esES: loc("Espagnol", en: "Spanish")
        case .deDE: loc("Allemand", en: "German")
        case .itIT: loc("Italien", en: "Italian")
        case .ptBR: loc("Portugais (Brésil)", en: "Portuguese (Brazil)")
        case .nlNL: loc("Néerlandais", en: "Dutch")
        }
    }
}
