import Foundation

/// The two dictation shortcuts, "Dictate" and "Dictate in the other
/// language". Each is a key combination or a lone modifier key, never both,
/// and the two differ only by what they are set to: the language they
/// listen in and what they turn it into — both read on the press, never
/// mid-dictation.
enum DictationShortcut: CaseIterable, Sendable {
    case dictate
    case dictateOtherLanguage

    var language: DictationLanguage {
        switch self {
        case .dictate: AppSettings.dictationPrimaryLanguage
        case .dictateOtherLanguage: AppSettings.dictationSecondaryLanguage
        }
    }

    var output: DictationOutput {
        switch self {
        case .dictate: AppSettings.dictationOutput
        case .dictateOtherLanguage: AppSettings.dictationSecondaryOutput
        }
    }
}
