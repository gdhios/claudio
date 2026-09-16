import XCTest
@testable import Claudio

/// What a dictation becomes once it is said: cleaned up as it always was,
/// translated to English, or turned into a prompt. One model call either
/// way, so what is pinned here is the prompt that call is composed of — the
/// dictation preamble, then the action's own instruction — and the room its
/// answer is given.
final class DictationOutputTests: XCTestCase {

    private var previousLanguage: AppLanguage = .system

    override func setUp() {
        super.setUp()
        previousLanguage = AppSettings.language
    }

    override func tearDown() {
        AppSettings.language = previousLanguage
        super.tearDown()
    }

    // MARK: - The catalog

    /// The rawValues are storage keys: a setting written today has to read
    /// back after the next release. They are added to, never renamed.
    func testTheRawValuesAreTheStorageKeys() {
        XCTAssertEqual(DictationOutput.allCases.map(\.rawValue),
                       ["cleanup", "translateEN", "makePrompt"])
    }

    /// The two model-backed outputs borrow the name of the action they
    /// reuse, so the picker and the palette say the same thing.
    func testEachOutputNamesItselfAfterTheActionItReuses() {
        AppSettings.language = .french
        XCTAssertEqual(DictationOutput.cleanup.title, "Nettoyer")
        XCTAssertEqual(DictationOutput.translateEN.title, "Traduire en anglais")
        XCTAssertEqual(DictationOutput.makePrompt.title, "Structurer en prompt")
    }

    /// The panel says which of the three is running while the model works,
    /// rather than "cleaning up" for all of them.
    func testThePanelLabelNamesWhatIsRunning() {
        AppSettings.language = .french
        XCTAssertEqual(DictationOutput.cleanup.progressLabel, "Nettoyage…")
        XCTAssertEqual(DictationOutput.translateEN.progressLabel, "Traduction…")
        XCTAssertEqual(DictationOutput.makePrompt.progressLabel, "Structuration…")
    }

    // MARK: - The composed prompt

    /// The default output changes nothing at all: what it sends is the
    /// cleanup prompt of before there was a choice, to the byte, vocabulary
    /// included.
    func testTheCleanupSendsTodaysPromptToTheByte() {
        AppSettings.language = .french
        XCTAssertEqual(Array(DictationOutput.cleanup.systemPrompt(keeping: []).utf8),
                       Array(DictationCleanup.systemPrompt.utf8))
        XCTAssertEqual(Array(DictationOutput.cleanup.systemPrompt(keeping: ["Okonoma"]).utf8),
                       Array(DictationCleanup.systemPrompt(keeping: ["Okonoma"]).utf8))
    }

    /// Speak French, paste corrected English: the preamble drops the
    /// hesitations, the action translates, and the answer is the
    /// translation alone — one call, not two.
    func testTranslatingComposesThePreambleThenTheTranslationAction() {
        AppSettings.language = .french
        let prompt = DictationOutput.translateEN.systemPrompt(keeping: [])

        XCTAssertTrue(prompt.hasPrefix(DictationCleanup.systemPrompt), prompt)
        XCTAssertTrue(prompt.hasSuffix(ClaudioAction.translateEN.system), prompt)
        // The preamble's own work survives the composition.
        XCTAssertTrue(prompt.contains("Retire les hésitations"), prompt)
        // And the second step is what comes out, not the transcript.
        XCTAssertTrue(prompt.contains("ne réponds qu'avec leur résultat"), prompt)
    }

    /// "Turn a rough idea into a clear prompt" is the simple action, not the
    /// expert one: a dictation is one breath, not a spec.
    func testStructuringReusesTheSimplePromptActionNotTheExpertOne() {
        AppSettings.language = .french
        let prompt = DictationOutput.makePrompt.systemPrompt(keeping: [])

        XCTAssertTrue(prompt.hasSuffix(ClaudioAction.makePrompt.system), prompt)
        XCTAssertTrue(prompt.contains("reformulation de demandes"), prompt)
        XCTAssertFalse(prompt.contains("ingénierie de prompts"), prompt)
    }

    /// The vocabulary clause stays where it has always been: last, after
    /// everything the model is asked to do.
    func testTheVocabularyClauseComesAfterTheWholeComposition() {
        AppSettings.language = .french
        let prompt = DictationOutput.translateEN.systemPrompt(keeping: ["Okonoma"])

        XCTAssertTrue(prompt.hasPrefix(DictationOutput.translateEN.systemPrompt(keeping: [])),
                      prompt)
        XCTAssertTrue(prompt.hasSuffix("« Okonoma »."), prompt)
    }

    /// The preamble is the one Settings would send: a cleanup prompt edited
    /// there still leads, and the output is added behind it.
    func testTheOutputIsAddedBehindTheEditedPreamble() {
        AppSettings.language = .french
        let prompt = DictationOutput.makePrompt.systemPrompt(keeping: [],
                                                             preamble: "Ponctue seulement.")
        XCTAssertTrue(prompt.hasPrefix("Ponctue seulement.\n\n"), prompt)
        XCTAssertTrue(prompt.hasSuffix(ClaudioAction.makePrompt.system), prompt)
    }

    /// The second step carries its own paragraph in English too: without it
    /// the model reads two contradictory system prompts glued together.
    func testTheSecondStepIsSaidInEnglishAsWell() {
        AppSettings.language = .english
        let prompt = DictationOutput.translateEN.systemPrompt(keeping: [])
        XCTAssertTrue(prompt.contains("answer with their result only"), prompt)
    }

    // MARK: - The budget

    /// The cleanup keeps the budget it has always had.
    func testTheCleanupKeepsItsOwnBudget() {
        XCTAssertEqual(DictationOutput.cleanup.maxTokens(forRawLength: 1_000),
                       DictationCleanup.maxTokens(forRawLength: 1_000))
        XCTAssertEqual(DictationOutput.cleanup.maxTokens(forRawLength: 100_000), 4_096)
    }

    /// Three words of rough idea still become a whole prompt: the floor is
    /// the action's, well above the cleanup's.
    func testAShortIdeaGetsAPromptSizedBudget() {
        XCTAssertEqual(DictationCleanup.maxTokens(forRawLength: 40), 128)
        XCTAssertEqual(DictationOutput.makePrompt.maxTokens(forRawLength: 40), 512)
    }

    /// A long dictation turned into a prompt would hit the cleanup's ceiling
    /// of 4096 and be cut off mid-sentence: the action's own budget applies.
    func testALongIdeaBreaksThroughTheCleanupCeiling() {
        XCTAssertEqual(DictationCleanup.maxTokens(forRawLength: 10_000), 4_096)
        XCTAssertEqual(DictationOutput.makePrompt.maxTokens(forRawLength: 10_000),
                       ClaudioRequest.Budget.expand.maxTokens(forLength: 10_000))
        XCTAssertGreaterThan(DictationOutput.makePrompt.maxTokens(forRawLength: 10_000), 4_096)
    }

    /// Whatever the length, no output is ever given less room than the
    /// cleanup had: nothing that used to fit gets cut off now.
    func testNoOutputIsEverGivenLessRoomThanTheCleanup() {
        for length in stride(from: 0, through: 20_000, by: 311) {
            let cleanup = DictationCleanup.maxTokens(forRawLength: length)
            for output in DictationOutput.allCases {
                XCTAssertGreaterThanOrEqual(output.maxTokens(forRawLength: length), cleanup,
                                            "\(output.rawValue), length \(length)")
            }
        }
    }
}
