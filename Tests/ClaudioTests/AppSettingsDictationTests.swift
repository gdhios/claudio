import XCTest
@testable import Claudio

/// The dictation settings. `AppSettings` is static on the standard defaults,
/// so these tests go through the real storage keys — the point being that a
/// value written today reads back tomorrow — and put every key back the way
/// they found it in `tearDown`.
final class AppSettingsDictationTests: XCTestCase {

    private static let keys = ["dictationPrimaryLanguage", "dictationSecondaryLanguage",
                               "dictationModel", "dictationSystemPrompt", "dictationPausesMedia",
                               "dictationVocabulary", "dictationOutput", "dictationSecondaryOutput"]

    private var saved: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        for key in Self.keys {
            if let value = defaults.object(forKey: key) { saved[key] = value }
            defaults.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        let defaults = UserDefaults.standard
        for key in Self.keys {
            if let value = saved[key] { defaults.set(value, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        saved = [:]
        super.tearDown()
    }

    /// Nothing stored yet: French on the main shortcut, English on the other
    /// one, a fast Claude model for the cleanup, the code's prompt, and both
    /// shortcuts doing what every dictation did before there was a choice.
    func testTheDefaultsHoldWithNothingStored() {
        XCTAssertEqual(AppSettings.dictationPrimaryLanguage, .frFR)
        XCTAssertEqual(AppSettings.dictationSecondaryLanguage, .enUS)
        XCTAssertEqual(ModelSlot.dictation.current(), .claude(.haiku45))
        XCTAssertNil(AppSettings.dictationSystemPrompt)
        XCTAssertEqual(AppSettings.dictationOutput, .cleanup)
        XCTAssertEqual(AppSettings.dictationSecondaryOutput, .cleanup)
    }

    func testTheLanguagesReadBackUnderTheirOwnKeys() {
        AppSettings.dictationPrimaryLanguage = .enGB
        AppSettings.dictationSecondaryLanguage = .deDE

        XCTAssertEqual(UserDefaults.standard.string(forKey: "dictationPrimaryLanguage"), "en-GB")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "dictationSecondaryLanguage"), "de-DE")
        XCTAssertEqual(AppSettings.dictationPrimaryLanguage, .enGB)
        XCTAssertEqual(AppSettings.dictationSecondaryLanguage, .deDE)
    }

    /// A value written by a future version (a language that doesn't exist
    /// here yet) must not leave dictation without a language.
    func testAnUnknownLanguageFallsBackToTheDefault() {
        UserDefaults.standard.set("ja-JP", forKey: "dictationPrimaryLanguage")
        UserDefaults.standard.set("", forKey: "dictationSecondaryLanguage")

        XCTAssertEqual(AppSettings.dictationPrimaryLanguage, .frFR)
        XCTAssertEqual(AppSettings.dictationSecondaryLanguage, .enUS)
    }

    /// The cleanup model is stored the same way as an action's: prefixed
    /// storage value, "raw" included, which only dictation can pick.
    func testTheModelReadsBackIncludingRaw() {
        ModelSlot.dictation.set(.ollama(model: "qwen3.5:4b"))
        XCTAssertEqual(UserDefaults.standard.string(forKey: "dictationModel"), "ollama:qwen3.5:4b")
        XCTAssertEqual(ModelSlot.dictation.current(), .ollama(model: "qwen3.5:4b"))

        ModelSlot.dictation.set(.raw)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "dictationModel"), "raw")
        XCTAssertEqual(ModelSlot.dictation.current(), .raw)

        // Unreadable value: back to the default rather than no model at all.
        UserDefaults.standard.set("openrouter:mixtral", forKey: "dictationModel")
        XCTAssertEqual(ModelSlot.dictation.current(), .claude(.haiku45))
    }

    /// Same contract as the actions' prompts: nil or blank means "the code's
    /// default", and the key is removed so the prompt follows app updates.
    func testABlankPromptFallsBackToTheDefault() {
        AppSettings.dictationSystemPrompt = "Ponctue seulement."
        XCTAssertEqual(AppSettings.dictationSystemPrompt, "Ponctue seulement.")

        AppSettings.dictationSystemPrompt = "   \n "
        XCTAssertNil(AppSettings.dictationSystemPrompt)
        XCTAssertNil(UserDefaults.standard.string(forKey: "dictationSystemPrompt"))

        AppSettings.dictationSystemPrompt = "Ponctue seulement."
        AppSettings.dictationSystemPrompt = nil
        XCTAssertNil(AppSettings.dictationSystemPrompt)
        XCTAssertNil(UserDefaults.standard.string(forKey: "dictationSystemPrompt"))
    }

    /// On until switched off: dictating over music is the case it exists for.
    func testPausingMediaIsOnByDefaultAndRemembered() {
        XCTAssertTrue(AppSettings.dictationPausesMedia)
        AppSettings.dictationPausesMedia = false
        XCTAssertEqual(UserDefaults.standard.object(forKey: "dictationPausesMedia") as? Bool, false)
        XCTAssertFalse(AppSettings.dictationPausesMedia)
    }

    /// Empty until something is typed. The text is kept as typed, line
    /// breaks and all — it's what the editor shows again next time — and
    /// reading it is `DictationVocabulary`'s job, not the storage's.
    func testTheVocabularyIsEmptyByDefaultAndKeptAsTyped() {
        XCTAssertEqual(AppSettings.dictationVocabulary, "")

        let typed = "Okonoma\n\nl'a pas compris → Lapacompris\n"
        AppSettings.dictationVocabulary = typed
        XCTAssertEqual(UserDefaults.standard.string(forKey: "dictationVocabulary"), typed)
        XCTAssertEqual(AppSettings.dictationVocabulary, typed)
    }

    /// Each shortcut decides what its dictation becomes, under its own key:
    /// French in, English out on one of them, cleanup on the other.
    func testEachShortcutKeepsItsOwnOutput() {
        AppSettings.dictationOutput = .translateEN
        AppSettings.dictationSecondaryOutput = .makePrompt

        XCTAssertEqual(UserDefaults.standard.string(forKey: "dictationOutput"), "translateEN")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "dictationSecondaryOutput"), "makePrompt")
        XCTAssertEqual(AppSettings.dictationOutput, .translateEN)
        XCTAssertEqual(AppSettings.dictationSecondaryOutput, .makePrompt)
    }

    /// A shortcut dictates with its own language and output, whether it is
    /// pressed as a key combination or as a lone key: both read them here.
    func testEachShortcutReadsItsOwnLanguageAndOutput() {
        AppSettings.dictationPrimaryLanguage = .enGB
        AppSettings.dictationSecondaryLanguage = .deDE
        AppSettings.dictationOutput = .makePrompt
        AppSettings.dictationSecondaryOutput = .translateEN

        XCTAssertEqual(DictationShortcut.dictate.language, .enGB)
        XCTAssertEqual(DictationShortcut.dictate.output, .makePrompt)
        XCTAssertEqual(DictationShortcut.dictateOtherLanguage.language, .deDE)
        XCTAssertEqual(DictationShortcut.dictateOtherLanguage.output, .translateEN)
    }

    /// An output written by a future version must not leave a shortcut
    /// without one: it falls back to the cleanup, the behaviour of before.
    func testAnUnknownOutputFallsBackToTheCleanup() {
        UserDefaults.standard.set("summarise", forKey: "dictationOutput")
        UserDefaults.standard.set("", forKey: "dictationSecondaryOutput")

        XCTAssertEqual(AppSettings.dictationOutput, .cleanup)
        XCTAssertEqual(AppSettings.dictationSecondaryOutput, .cleanup)
    }

    /// Erasing every line leaves no key behind, like a blank prompt.
    func testABlankVocabularyRemovesTheKey() {
        AppSettings.dictationVocabulary = "Okonoma"
        AppSettings.dictationVocabulary = "  \n "
        XCTAssertNil(UserDefaults.standard.object(forKey: "dictationVocabulary"))
        XCTAssertEqual(AppSettings.dictationVocabulary, "")
    }
}
