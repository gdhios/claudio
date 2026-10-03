import Foundation

/// Dictation's settings: languages, outputs, prompt, vocabulary, lone keys.
extension AppSettings {
    // MARK: - Master switch

    private static let dictationEnabledKey = "dictationEnabled"

    /// Master switch for dictation, on by default. Off, the shortcuts are
    /// unregistered and the lone key is let go, so those keys fall back to
    /// whatever they did before Claudio.
    static func dictationEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.flag(dictationEnabledKey)
    }

    static func setDictationEnabled(_ enabled: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: dictationEnabledKey)
    }

    private static let dictationPrimaryLanguageKey = "dictationPrimaryLanguage"
    private static let dictationSecondaryLanguageKey = "dictationSecondaryLanguage"
    private static let dictationSystemPromptKey = "dictationSystemPrompt"
    private static let dictationVocabularyKey = "dictationVocabulary"
    private static let dictationOutputKey = "dictationOutput"
    private static let dictationSecondaryOutputKey = "dictationSecondaryOutput"

    private static let dictationPausesMediaKey = "dictationPausesMedia"

    /// Pause whatever is playing while dictation listens, and resume it when
    /// the microphone closes. On by default: dictating over music is what
    /// it's for.
    static var dictationPausesMedia: Bool {
        get { UserDefaults.standard.flag(dictationPausesMediaKey) }
        set { UserDefaults.standard.set(newValue, forKey: dictationPausesMediaKey) }
    }

    /// Language of the "Dictate" shortcut. Missing or unknown value (a
    /// setting written by a future version) falls back to French.
    static var dictationPrimaryLanguage: DictationLanguage {
        get { UserDefaults.standard.choice(dictationPrimaryLanguageKey, default: .frFR) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: dictationPrimaryLanguageKey) }
    }

    /// Language of the "Dictate in the other language" shortcut.
    static var dictationSecondaryLanguage: DictationLanguage {
        get { UserDefaults.standard.choice(dictationSecondaryLanguageKey, default: .enUS) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: dictationSecondaryLanguageKey) }
    }

    /// What the "Dictate" shortcut's dictation becomes. Cleanup by default:
    /// what every dictation did before there was a choice. A value written
    /// by a future version falls back to it rather than to no output at all.
    static var dictationOutput: DictationOutput {
        get { UserDefaults.standard.choice(dictationOutputKey, default: .cleanup) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: dictationOutputKey) }
    }

    /// Same, for the other-language shortcut, and its own setting: speaking
    /// French to paste English is what a second shortcut is good for.
    static var dictationSecondaryOutput: DictationOutput {
        get { UserDefaults.standard.choice(dictationSecondaryOutputKey, default: .cleanup) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: dictationSecondaryOutputKey) }
    }

    /// Custom cleanup prompt (nil = the code's default). Same contract as the
    /// actions' prompts: blank removes the key, so the prompt follows app
    /// updates.
    static var dictationSystemPrompt: String? {
        get { UserDefaults.standard.nonBlankString(dictationSystemPromptKey) }
        set { UserDefaults.standard.setNonBlank(newValue, forKey: dictationSystemPromptKey) }
    }

    // MARK: - Dictation lone keys

    /// Posted with the defaults written to, whenever a dictation shortcut's
    /// lone key changes: the keyboard monitor and the Settings fields follow.
    static let dictationLoneKeysDidChange = Notification.Name("ClaudioDictationLoneKeysDidChange")

    private static func loneKeyStorageKey(for shortcut: DictationShortcut) -> String {
        switch shortcut {
        case .dictate: "dictationLoneKey"
        case .dictateOtherLanguage: "dictationSecondaryLoneKey"
        }
    }

    /// The modifier key a dictation shortcut is set to on its own, `nil` when
    /// it is a key combination — or nothing. A key written by a future
    /// version reads as none.
    static func dictationLoneKey(for shortcut: DictationShortcut,
                                 in defaults: UserDefaults = .standard) -> LoneModifierKey? {
        defaults.string(forKey: loneKeyStorageKey(for: shortcut))
            .flatMap(LoneModifierKey.init(rawValue:))
    }

    /// `nil` removes the storage key. A lone key serves one shortcut only:
    /// given to this one, it is taken from the other. The shortcut's key
    /// combination is Settings' to remove, through the library that stores it.
    static func setDictationLoneKey(_ key: LoneModifierKey?,
                                    for shortcut: DictationShortcut,
                                    in defaults: UserDefaults = .standard) {
        var changed = false
        if let key {
            for other in DictationShortcut.allCases
            where other != shortcut && dictationLoneKey(for: other, in: defaults) == key {
                defaults.removeObject(forKey: loneKeyStorageKey(for: other))
                changed = true
            }
        }
        let storageKey = loneKeyStorageKey(for: shortcut)
        if defaults.string(forKey: storageKey) != key?.rawValue {
            if let key {
                defaults.set(key.rawValue, forKey: storageKey)
            } else {
                defaults.removeObject(forKey: storageKey)
            }
            changed = true
        }
        if changed {
            NotificationCenter.default.post(name: dictationLoneKeysDidChange, object: defaults)
        }
    }

    // MARK: - Dictation vocabulary

    /// The personal vocabulary, as typed in Settings: one entry per line,
    /// read by `DictationVocabulary`. Empty by default; blank removes the key.
    static var dictationVocabulary: String {
        get { UserDefaults.standard.nonBlankString(dictationVocabularyKey) ?? "" }
        set { UserDefaults.standard.setNonBlank(newValue, forKey: dictationVocabularyKey) }
    }
}
