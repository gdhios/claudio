import XCTest
@testable import Claudio

/// Every shortcut that calls a model is a slot: the Models tab lists them,
/// each slot reads and writes its own setting, and the two newcomers — the
/// custom action and "What's playing?" — get a setting at all.
final class ModelSlotTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = InMemoryDefaults()
    }

    /// One row per shortcut, in the order the tab shows them: the catalog's
    /// eight actions, the custom action, dictation, listening, the long text.
    func testTheTabListsEveryShortcutThatCallsAModel() {
        XCTAssertEqual(ModelSlot.all,
                       ClaudioAction.allCases.map(ModelSlot.action) + [.freeAction, .dictation, .listening, .essay])
    }

    /// Each slot keeps its historical storage key: a setting written by an
    /// earlier version reads back through its slot.
    func testTheStorageKeysAreTheHistoricalOnes() {
        XCTAssertEqual(ModelSlot.action(.correct).storageKey, "model.correct")
        XCTAssertEqual(ModelSlot.dictation.storageKey, "dictationModel")
        XCTAssertEqual(ModelSlot.freeAction.storageKey, "model.free")
        XCTAssertEqual(ModelSlot.listening.storageKey, "model.listening")
        XCTAssertEqual(ModelSlot.essay.storageKey, "model.essay")
    }

    func testTheDefaultsAreTheCodes() {
        XCTAssertEqual(ModelSlot.action(.correct).defaultChoice, .claude(.haiku45))
        XCTAssertEqual(ModelSlot.action(.expertPrompt).defaultChoice, .claude(.sonnet5))
        XCTAssertEqual(ModelSlot.freeAction.defaultChoice, .claude(.haiku45))
        XCTAssertEqual(ModelSlot.dictation.defaultChoice, AppSettings.defaultDictationModel)
        XCTAssertEqual(ModelSlot.listening.defaultChoice, ListeningNotes.model)
        XCTAssertEqual(ModelSlot.essay.defaultChoice, ListeningEssay.model)
        XCTAssertEqual(ListeningEssay.model, .claude(.sonnet55),
                       "the long text answers for the facts: never a small model by default")
    }

    /// "Raw" means no model at all: only dictation can paste the transcript
    /// as heard, every other slot has nothing to do without a model.
    func testOnlyDictationOffersRaw() {
        XCTAssertEqual(ModelSlot.all.filter(\.allowsRaw), [.dictation])
    }

    /// Unset, a slot is its default; set, it reads back; set back to the
    /// default, the key goes so the slot follows the app's updates.
    func testASlotReadsWritesAndForgetsItsSetting() {
        for slot in ModelSlot.all {
            XCTAssertEqual(slot.current(in: defaults), slot.defaultChoice, slot.storageKey)

            slot.set(.ollama(model: "qwen2.5:14b"), in: defaults)
            XCTAssertEqual(slot.current(in: defaults), .ollama(model: "qwen2.5:14b"), slot.storageKey)
            XCTAssertEqual(defaults.string(forKey: slot.storageKey), "ollama:qwen2.5:14b", slot.storageKey)

            slot.set(slot.defaultChoice, in: defaults)
            XCTAssertNil(defaults.string(forKey: slot.storageKey), slot.storageKey)
            XCTAssertEqual(slot.current(in: defaults), slot.defaultChoice, slot.storageKey)
        }
    }

    /// A value another version wrote and this one can't read falls back to
    /// the default rather than to nothing.
    func testAnUnreadableValueIsTheDefault() {
        defaults.set("openrouter:mixtral", forKey: ModelSlot.listening.storageKey)
        XCTAssertEqual(ModelSlot.listening.current(in: defaults), ListeningNotes.model)
    }

    // MARK: - The two new settings reach their shortcut

    /// The listening setting is what the coordinator reads for its session.
    func testTheListeningSettingIsReadFromTheDefaults() {
        ModelSlot.listening.set(.claude(.haiku45), in: defaults)
        XCTAssertEqual(AppSettings.listeningModel(in: defaults), .claude(.haiku45))
        XCTAssertEqual(AppSettings.listeningModel(in: InMemoryDefaults()),
                       ListeningNotes.model)
    }

    /// The long text has its own setting: Haiku on the notes leaves the
    /// text on its default.
    func testTheEssaySettingIsItsOwn() {
        ModelSlot.listening.set(.claude(.haiku45), in: defaults)
        XCTAssertEqual(AppSettings.essayModel(in: defaults), ListeningEssay.model)
        ModelSlot.essay.set(.claude(.opus55), in: defaults)
        XCTAssertEqual(AppSettings.essayModel(in: defaults), .claude(.opus55))
        XCTAssertEqual(AppSettings.listeningModel(in: defaults), .claude(.haiku45))
    }

    /// The custom action's request carries the model set for it. Through the
    /// real defaults, since the request's factory reads nothing else: the
    /// key is put back as it was.
    func testTheCustomActionsRequestCarriesTheModelSetForIt() {
        let key = ModelSlot.freeAction.storageKey
        let standard = UserDefaults.standard
        let previous = standard.string(forKey: key)
        defer {
            if let previous { standard.set(previous, forKey: key) }
            else { standard.removeObject(forKey: key) }
        }

        standard.removeObject(forKey: key)
        XCTAssertEqual(ClaudioRequest.free(instruction: "Traduis").model, .claude(.haiku45))

        ModelSlot.freeAction.set(.claude(.sonnet55), in: standard)
        XCTAssertEqual(ClaudioRequest.free(instruction: "Traduis").model, .claude(.sonnet55))
        XCTAssertEqual(ClaudioRequest.awaitingInstruction.model, .claude(.sonnet55),
                       "the footer names the model set now, not the one set at first use")
    }

    // MARK: - The tab

    /// The Models tab sits right after the API key: the key, then what it
    /// pays for.
    func testTheModelsTabSitsAfterTheAPIKey() {
        let sections = SettingsSection.allCases
        let key = sections.firstIndex(of: .apiKey)!
        XCTAssertEqual(sections[key + 1], .models)
        XCTAssertEqual(SettingsSection.models.rawValue, "models")
    }
}
