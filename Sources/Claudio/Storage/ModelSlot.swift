import Foundation

/// A shortcut that calls a model, seen from Settings: the catalog's actions,
/// the custom action, dictation's cleanup, "What's playing?". Each slot owns
/// one setting, all written the same way (`ModelChoice.storageValue`) under
/// its historical key, and absent when the choice is the code's default so
/// the slot follows the app's updates. The Models tab lists them all.
enum ModelSlot: Hashable, Sendable {
    case action(ClaudioAction)
    /// The custom action and the spoken instruction, with or without a
    /// selection: one request factory, one model.
    case freeAction
    /// The pass that punctuates a dictation. The only slot that may name no
    /// model at all ("Raw").
    case dictation
    /// The notes under the track playing.
    case listening
    /// The long text "Tell me more" writes about the track, the album or the artist:
    /// its own slot, so a small model on the notes never writes the text
    /// that answers for the facts.
    case essay

    /// The UserDefaults key. Historical where a setting predates this type.
    var storageKey: String {
        switch self {
        case .action(let action): "model.\(action.rawValue)"
        case .freeAction: "model.free"
        case .dictation: "dictationModel"
        case .listening: "model.listening"
        case .essay: "model.essay"
        }
    }

    /// What the tab calls the shortcut.
    @MainActor
    var title: String {
        switch self {
        case .action(let action): action.menuTitle
        case .freeAction: loc("Action libre et instruction vocale", en: "Custom action and spoken instruction")
        case .dictation: loc("Dictée : nettoyage", en: "Dictation: cleanup")
        case .listening: ListeningSession.menuTitle
        case .essay: loc("Texte long « En savoir plus »", en: "Long text “Tell me more”")
        }
    }

    var defaultChoice: ModelChoice {
        switch self {
        case .action(let action): .claude(action.defaultModel)
        case .freeAction: .claude(.haiku45)
        // Static on purpose: probing Ollama to prefer a local model would
        // mean talking to the network to read a setting.
        case .dictation: .claude(.haiku45)
        case .listening: ListeningNotes.model
        case .essay: ListeningEssay.model
        }
    }

    /// Whether "Raw" is a valid choice: only dictation has something to do
    /// without a model.
    var allowsRaw: Bool { self == .dictation }

    /// The setting, or the default when there is none or it can't be read
    /// (written by another version).
    func current(in defaults: UserDefaults = .standard) -> ModelChoice {
        defaults.string(forKey: storageKey)
            .flatMap(ModelChoice.init(storageValue:)) ?? defaultChoice
    }

    /// Writes the choice; the default removes the key instead.
    func set(_ choice: ModelChoice, in defaults: UserDefaults = .standard) {
        if choice == defaultChoice {
            defaults.removeObject(forKey: storageKey)
        } else {
            defaults.set(choice.storageValue, forKey: storageKey)
        }
    }
}
