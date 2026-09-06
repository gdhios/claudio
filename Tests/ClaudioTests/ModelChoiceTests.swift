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
        for model in ClaudioModel.allCases {
            XCTAssertEqual(ModelChoice.claude(model).cost(inputTokens: 200, outputTokens: 200),
                           model.cost(inputTokens: 200, outputTokens: 200),
                           accuracy: 1e-12, model.rawValue)
            XCTAssertFalse(ModelChoice.claude(model).isLocal, model.rawValue)
        }
    }

    /// The marker shown next to the selector: the price for Claude, "free"
    /// for local.
    func testTheCostHintAnnouncesLocalIsFree() {
        let previous = AppSettings.language
        AppSettings.language = .french
        defer { AppSettings.language = previous }

        XCTAssertEqual(ModelChoice.ollama(model: "llama3.2").costHint, "Gratuit (local)")
        XCTAssertEqual(ModelChoice.claude(.haiku45).costHint, ClaudioModel.haiku45.costHint)
    }

    // MARK: - Settings encoding

    func testAClaudeChoiceReadsBackAfterWriting() {
        for model in ClaudioModel.allCases {
            let choice = ModelChoice.claude(model)
            XCTAssertEqual(choice.storageValue, "claude:\(model.rawValue)")
            XCTAssertEqual(ModelChoice(storageValue: choice.storageValue), choice, model.rawValue)
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

    /// The panel's footer has no room for the qualifier: the bare name is
    /// enough, and a local model's name is already short.
    func testTheShortNameDropsTheQualifier() {
        XCTAssertEqual(ModelChoice.claude(.haiku45).shortName, "Haiku 4.5")
        XCTAssertEqual(ModelChoice.ollama(model: "qwen2.5:14b").shortName, "qwen2.5:14b")
    }

    // MARK: - An action's setting

    /// The real settings path, storage key included: a setting written before
    /// Ollama must still load, a local engine must read back, and reverting
    /// to the default must remove the key so it follows app updates.
    func testAnActionsSettingReadsBackAndToleratesLegacyValues() {
        let key = "model.\(ClaudioAction.correct.rawValue)"
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: key)
        defer {
            if let previous { defaults.set(previous, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }

        // Legacy case: the bare value that pre-Ollama versions stored.
        defaults.set("claude-sonnet-5", forKey: key)
        XCTAssertEqual(AppSettings.customModel(for: .correct), .claude(.sonnet5))
        XCTAssertEqual(ClaudioAction.correct.model, .claude(.sonnet5))

        // Round trip through a local engine.
        AppSettings.setCustomModel(.ollama(model: "qwen2.5:14b"), for: .correct)
        XCTAssertEqual(defaults.string(forKey: key), "ollama:qwen2.5:14b")
        XCTAssertEqual(ClaudioAction.correct.model, .ollama(model: "qwen2.5:14b"))

        // The default isn't stored: the action follows the app's updates.
        AppSettings.setCustomModel(.claude(ClaudioAction.correct.defaultModel), for: .correct)
        XCTAssertNil(defaults.string(forKey: key))
        XCTAssertEqual(ClaudioAction.correct.model, .claude(ClaudioAction.correct.defaultModel))
    }

    /// A value that can't be read (a setting written by a future version,
    /// corrupted storage) yields nil: the action then falls back to its
    /// default.
    func testAnUnreadableValueYieldsNoChoice() {
        XCTAssertNil(ModelChoice(storageValue: ""))
        XCTAssertNil(ModelChoice(storageValue: "ollama:"))
        XCTAssertNil(ModelChoice(storageValue: "claude:claude-inconnu-9"))
        XCTAssertNil(ModelChoice(storageValue: "openrouter:mixtral"))
        XCTAssertNil(ModelChoice(storageValue: "gpt-4"))
    }
}
