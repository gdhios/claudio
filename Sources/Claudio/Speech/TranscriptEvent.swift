import Foundation

/// What a speech engine emits while listening. The engine always sends the
/// whole text of the session, never a delta: the coordinator displays what it
/// receives without stitching anything together.
enum TranscriptEvent: Sendable {
    /// Recognition in progress: the text can still change.
    case partial(String)
    /// Final text of the session. Nothing follows it.
    case final(String)
    /// The session ends without text. Nothing follows it.
    case failed(SpeechEngineError)
}

/// Why a dictation couldn't happen. The messages are shown in the panel, so
/// each one says what to do next.
enum SpeechEngineError: LocalizedError {
    case microphoneDenied
    case recognitionDenied
    /// The language has no on-device model installed: the app downloads
    /// nothing by itself.
    case languageUnavailable(Locale)
    case audioEngine(String)
    case recognizer(String)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return loc("Claudio n'a pas accès au micro. Autorise-le dans Réglages Système > Confidentialité et sécurité > Microphone.",
                       en: "Claudio can't use the microphone. Allow it in System Settings > Privacy & Security > Microphone.")
        case .recognitionDenied:
            return loc("Claudio n'a pas accès à la reconnaissance vocale. Autorise-la dans Réglages Système > Confidentialité et sécurité > Reconnaissance vocale.",
                       en: "Claudio can't use speech recognition. Allow it in System Settings > Privacy & Security > Speech Recognition.")
        case .languageUnavailable(let locale):
            return loc("La dictée pour \(locale.identifier) n'est pas installée sur cet ordinateur. Ajoute la langue dans Réglages Système > Clavier > Dictée.",
                       en: "Dictation for \(locale.identifier) isn't installed on this Mac. Add the language in System Settings > Keyboard > Dictation.")
        case .audioEngine(let message):
            return loc("Le micro n'a pas pu démarrer : \(message)",
                       en: "The microphone couldn't start: \(message)")
        case .recognizer(let message):
            return loc("La reconnaissance vocale a échoué : \(message)",
                       en: "Speech recognition failed: \(message)")
        }
    }

    /// Where the panel can send someone to fix it, when it can. Only the
    /// missing language: Claudio downloads no model by itself, and that pane
    /// is where one is added. The two refusals already come with their own
    /// alert, which opens its own pane — a button here would be a second
    /// answer to a question already asked.
    var settingsURL: URL? {
        switch self {
        case .languageUnavailable:
            // Keyboard, where Dictation lists its languages. The identifier
            // is the settings extension's own (macOS 13+).
            return URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")
        case .microphoneDenied, .recognitionDenied, .audioEngine, .recognizer:
            return nil
        }
    }
}
