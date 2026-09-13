import XCTest
@testable import Claudio

/// The dictation settings. `AppSettings` is static on the standard defaults,
/// so these tests go through the real storage keys — the point being that a
/// value written today reads back tomorrow — and put every key back the way
/// they found it in `tearDown`.
final class AppSettingsDictationTests: XCTestCase {

    private static let keys = ["dictationPrimaryLanguage", "dictationSecondaryLanguage",
                               "dictationModel", "dictationSystemPrompt"]

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
    /// one, a fast Claude model for the cleanup, and the code's prompt.
    func testTheDefaultsHoldWithNothingStored() {
        XCTAssertEqual(AppSettings.dictationPrimaryLanguage, .frFR)
        XCTAssertEqual(AppSettings.dictationSecondaryLanguage, .enUS)
        XCTAssertEqual(AppSettings.dictationModel, .claude(.haiku45))
        XCTAssertNil(AppSettings.dictationSystemPrompt)
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
        AppSettings.dictationModel = .ollama(model: "qwen3.5:4b")
        XCTAssertEqual(UserDefaults.standard.string(forKey: "dictationModel"), "ollama:qwen3.5:4b")
        XCTAssertEqual(AppSettings.dictationModel, .ollama(model: "qwen3.5:4b"))

        AppSettings.dictationModel = .raw
        XCTAssertEqual(UserDefaults.standard.string(forKey: "dictationModel"), "raw")
        XCTAssertEqual(AppSettings.dictationModel, .raw)

        // Unreadable value: back to the default rather than no model at all.
        UserDefaults.standard.set("openrouter:mixtral", forKey: "dictationModel")
        XCTAssertEqual(AppSettings.dictationModel, .claude(.haiku45))
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
}
