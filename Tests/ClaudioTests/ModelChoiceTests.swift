import XCTest
@testable import Claudio

/// An action's engine is stored as text in settings: what's locked down here
/// is that a setting written yesterday reads back correctly tomorrow, and
/// that a local call costs nothing.
final class ModelChoiceTests: XCTestCase {

    // MARK: - Cost

    func testALocalCallCostsNothing() {
        XCTAssertEqual(ModelChoice.ollama(model: "qwen2.5:14b")
            .cost(inputTokens: 100_000, outputTokens: 100_000), 0)
        XCTAssertTrue(ModelChoice.ollama(model: "qwen2.5:14b").isLocal)
    }

    func testClaudeCostStaysTheModels() {
        for model in ClaudioModel.bundled {
            XCTAssertEqual(ModelChoice.claude(model).cost(inputTokens: 200, outputTokens: 200),
                           model.cost(inputTokens: 200, outputTokens: 200),
                           accuracy: 1e-12, model.id)
            XCTAssertFalse(ModelChoice.claude(model).isLocal, model.id)
        }
    }

    /// "Raw" isn't a model: it's the dictation setting that skips the
    /// cleanup pass. Nothing leaves the machine, nothing is billed.
    func testRawCostsNothingAndStaysLocal() {
        XCTAssertEqual(ModelChoice.raw.cost(inputTokens: 100_000, outputTokens: 100_000), 0)
        XCTAssertTrue(ModelChoice.raw.isLocal)
    }

    /// The marker shown next to the selector: the price for Claude, "free"
    /// for local.
    func testTheCostHintAnnouncesLocalIsFree() {
        useLanguage(.french)

        XCTAssertEqual(ModelChoice.ollama(model: "llama3.2").costHint, "Gratuit (local)")
        XCTAssertEqual(ModelChoice.claude(.haiku45).costHint, ClaudioModel.haiku45.costHint)
        XCTAssertEqual(ModelChoice.raw.costHint, "Aucun modèle")
        XCTAssertEqual(ModelChoice.raw.displayName, "Brut")
        XCTAssertEqual(ModelChoice.raw.shortName, "Brut")
    }

    // MARK: - Settings encoding

    func testAClaudeChoiceReadsBackAfterWriting() {
        for model in ClaudioModel.bundled {
            let choice = ModelChoice.claude(model)
            XCTAssertEqual(choice.storageValue, "claude:\(model.id)")
            XCTAssertEqual(ModelChoice(storageValue: choice.storageValue), choice, model.id)
        }
    }

    /// An Ollama model's name carries its version tag after a ":": splitting
    /// must happen only on the first one.
    func testAnOllamaChoiceKeepsTheColonsInItsVersion() {
        let choice = ModelChoice.ollama(model: "qwen2.5:14b")
        XCTAssertEqual(choice.storageValue, "ollama:qwen2.5:14b")
        XCTAssertEqual(ModelChoice(storageValue: choice.storageValue), choice)
        XCTAssertEqual(ModelChoice(storageValue: "ollama:llama3.2"), .ollama(model: "llama3.2"))
    }

    /// Legacy case: settings written before Ollama stored only the Claude
    /// model's rawValue, with no prefix. They must read back unchanged.
    func testALegacySettingReadsBackAsClaude() {
        XCTAssertEqual(ModelChoice(storageValue: "claude-haiku-4-5"), .claude(.haiku45))
        XCTAssertEqual(ModelChoice(storageValue: "claude-sonnet-5"), .claude(.sonnet5))
        XCTAssertEqual(ModelChoice(storageValue: "claude-opus-5"), .claude(.opus5))
    }

    /// "Raw" is stored as a bare word: no provider prefix, since no provider
    /// answers. Reading it back must not go looking for a Claude model.
    func testRawReadsBackAfterWriting() {
        XCTAssertEqual(ModelChoice.raw.storageValue, "raw")
        XCTAssertEqual(ModelChoice(storageValue: "raw"), .raw)
    }

    /// The panel's footer has no room for the qualifier: the bare name is
    /// enough, and a local model's name is already short.
    func testTheShortNameDropsTheQualifier() {
        XCTAssertEqual(ModelChoice.claude(.haiku45).shortName, "Haiku 4.5")
        XCTAssertEqual(ModelChoice.ollama(model: "qwen2.5:14b").shortName, "qwen2.5:14b")
    }

    // MARK: - An action's setting

    /// The real storage key: a setting written before Ollama must still
    /// load, a local engine must read back, and reverting to the default
    /// must remove the key so it follows app updates.
    func testAnActionsSettingReadsBackAndToleratesLegacyValues() {
        let key = "model.\(ClaudioAction.correct.rawValue)"
        let slot = ModelSlot.action(.correct)
        let defaults = InMemoryDefaults()

        // Legacy case: the bare value that pre-Ollama versions stored.
        defaults.set("claude-sonnet-5", forKey: key)
        XCTAssertEqual(slot.current(in: defaults), .claude(.sonnet5))

        // Round trip through a local engine.
        slot.set(.ollama(model: "qwen2.5:14b"), in: defaults)
        XCTAssertEqual(defaults.string(forKey: key), "ollama:qwen2.5:14b")
        XCTAssertEqual(slot.current(in: defaults), .ollama(model: "qwen2.5:14b"))

        // The default isn't stored: the action follows the app's updates.
        slot.set(.claude(ClaudioAction.correct.defaultModel), in: defaults)
        XCTAssertNil(defaults.string(forKey: key))
        XCTAssertEqual(slot.current(in: defaults), .claude(ClaudioAction.correct.defaultModel))
    }

    /// A Claude identifier the app has never shipped still reads: it was
    /// picked from the API's list, or it is a model newer than this version.
    /// Whether the API still serves it is the call's business, not the
    /// setting's.
    func testAClaudeIdentifierTheAppDoesntKnowStillReads() {
        XCTAssertEqual(ModelChoice(storageValue: "claude:claude-sonnet-9"),
                       .claude(ClaudioModel(id: "claude-sonnet-9")))
        XCTAssertEqual(ModelChoice(storageValue: "claude-sonnet-9"),
                       .claude(ClaudioModel(id: "claude-sonnet-9")), "legacy bare form")
    }

    /// A value that can't be read (a setting written by a future version,
    /// corrupted storage) yields nil: the action then falls back to its
    /// default.
    func testAnUnreadableValueYieldsNoChoice() {
        XCTAssertNil(ModelChoice(storageValue: ""))
        XCTAssertNil(ModelChoice(storageValue: "ollama:"))
        XCTAssertNil(ModelChoice(storageValue: "openrouter:mixtral"))
        XCTAssertNil(ModelChoice(storageValue: "gpt-4"))
        XCTAssertNil(ModelChoice(storageValue: "raw:"))
        XCTAssertNil(ModelChoice(storageValue: "claude:raw"))
        XCTAssertNil(ModelChoice(storageValue: "claude-x:y"), "unknown provider, not a legacy ID")
    }
}
