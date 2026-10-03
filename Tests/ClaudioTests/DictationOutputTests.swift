import XCTest
@testable import Claudio

/// What a dictation becomes once it is said: cleaned up as it always was,
/// translated to English, or turned into a prompt. One model call either
/// way, so what is pinned here is the prompt that call is composed of — the
/// dictation preamble, then the action's own instruction — and the room its
/// answer is given.
final class DictationOutputTests: XCTestCase {

    private var previousPrompt: String?

    override func setUp() {
        super.setUp()
        previousPrompt = AppSettings.dictationSystemPrompt
    }

    override func tearDown() {
        AppSettings.dictationSystemPrompt = previousPrompt
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
        useLanguage(.french)
        XCTAssertEqual(DictationOutput.cleanup.title, "Nettoyer")
        XCTAssertEqual(DictationOutput.translateEN.title, "Traduire en anglais")
        XCTAssertEqual(DictationOutput.makePrompt.title, "Structurer en prompt")
    }

    /// The panel says which of the three is running while the model works,
    /// rather than "cleaning up" for all of them.
    func testThePanelLabelNamesWhatIsRunning() {
        useLanguage(.french)
        XCTAssertEqual(DictationOutput.cleanup.progressLabel, "Nettoyage…")
        XCTAssertEqual(DictationOutput.translateEN.progressLabel, "Traduction…")
        XCTAssertEqual(DictationOutput.makePrompt.progressLabel, "Structuration…")
    }

    // MARK: - The composed prompt

    /// The default output changes nothing at all: what it sends is the
    /// cleanup prompt of before there was a choice, to the byte, vocabulary
    /// included.
    func testTheCleanupSendsTodaysPromptToTheByte() {
        useLanguage(.french)
        XCTAssertEqual(Array(DictationOutput.cleanup.systemPrompt(keeping: []).utf8),
                       Array(DictationCleanup.systemPrompt.utf8))
        XCTAssertEqual(Array(DictationOutput.cleanup.systemPrompt(keeping: ["Okonoma"]).utf8),
                       Array(DictationCleanup.systemPrompt(keeping: ["Okonoma"]).utf8))
    }

    /// Speak French, paste corrected English: a short transcript preamble,
    /// then the translation action. One call, and one instruction.
    func testTranslatingComposesTheTranscriptPreambleThenTheAction() {
        useLanguage(.french)
        let prompt = DictationOutput.translateEN.systemPrompt(keeping: [])

        XCTAssertTrue(prompt.hasPrefix(DictationOutput.transcriptPreamble), prompt)
        XCTAssertTrue(prompt.hasSuffix(ClaudioAction.translateEN.system), prompt)
        // The transcript is still tidied on the way through.
        XCTAssertTrue(prompt.contains("hésitations"), prompt)
    }

    /// The bug this replaced: the cleanup prompt was glued in front of the
    /// action, so a translation carried "keep the transcript's language" and
    /// "never rephrase" above the instruction to translate and rephrase. The
    /// model obeyed whichever it felt like — Guillaume got French roughly
    /// one time in two, same keystroke. A transforming output must carry no
    /// rule it is about to break.
    func testATransformingOutputCarriesNoneOfTheCleanupsContradictions() {
        useLanguage(.french)
        for output in DictationOutput.allCases where output != .cleanup {
            let prompt = output.systemPrompt(keeping: [])
            // The cleanup's own wording, not the actions': an action saying
            // "keep the text's language" about its own job is right, and the
            // prompt structurer does say it.
            XCTAssertFalse(prompt.contains("Conserve la langue de la transcription"),
                           output.rawValue)
            XCTAssertFalse(prompt.contains("Ne reformule jamais"), output.rawValue)
            XCTAssertFalse(prompt.contains("Réponds uniquement avec le texte mis au propre"),
                           output.rawValue)
            XCTAssertFalse(prompt.contains(DictationCleanup.defaultSystemPrompt),
                           output.rawValue)
        }
    }

    /// No arbitration paragraph left to write: there is nothing to arbitrate
    /// between any more. Its absence is the fix, so it is pinned.
    func testNothingArbitratesBetweenTwoPromptsAnyMore() {
        useLanguage(.french)
        let prompt = DictationOutput.translateEN.systemPrompt(keeping: [])
        XCTAssertFalse(prompt.contains("Deuxième étape"), prompt)
        XCTAssertFalse(prompt.contains("ce sont elles qui l'emportent"), prompt)
    }

    /// The action prompts speak of a text inside <texte_source> tags, because
    /// that is how the correction cycle sends a selection. A dictation sends
    /// its transcript the same way, so the prompt is used in the conditions
    /// it was written for. The cleanup has its own envelope: sent bare, a
    /// transcript that says "you" was answered rather than cleaned up.
    func testEveryOutputWrapsTheTranscript() {
        XCTAssertEqual(DictationOutput.cleanup.userMessage(for: "bonjour"),
                       DictationCleanup.wrappingTranscript("bonjour"))
        for output in DictationOutput.allCases where output != .cleanup {
            let message = output.userMessage(for: "bonjour")
            XCTAssertTrue(message.contains("<texte_source>"), output.rawValue)
            XCTAssertTrue(message.contains("bonjour"), output.rawValue)
        }
    }

    /// "Turn a rough idea into a clear prompt" is the simple action, not the
    /// expert one: a dictation is one breath, not a spec.
    func testStructuringReusesTheSimplePromptActionNotTheExpertOne() {
        useLanguage(.french)
        let prompt = DictationOutput.makePrompt.systemPrompt(keeping: [])

        XCTAssertTrue(prompt.hasSuffix(ClaudioAction.makePrompt.system), prompt)
        XCTAssertTrue(prompt.contains("reformulation de demandes"), prompt)
        XCTAssertFalse(prompt.contains("ingénierie de prompts"), prompt)
    }

    /// The vocabulary clause stays where it has always been: last, after
    /// everything the model is asked to do.
    func testTheVocabularyClauseComesAfterTheWholeComposition() {
        useLanguage(.french)
        let prompt = DictationOutput.translateEN.systemPrompt(keeping: ["Okonoma"])

        XCTAssertTrue(prompt.hasPrefix(DictationOutput.translateEN.systemPrompt(keeping: [])),
                      prompt)
        XCTAssertTrue(prompt.hasSuffix("« Okonoma »."), prompt)
    }

    /// A cleanup prompt edited in Settings is a cleanup prompt: it leads the
    /// cleanup, and it has no say over a translation. Letting it through was
    /// a second way for a rule like "keep the language" to reach an output
    /// whose whole job is to change it.
    func testAnEditedCleanupPromptSteersTheCleanupAndNothingElse() {
        useLanguage(.french)
        AppSettings.dictationSystemPrompt = "Ponctue seulement, et garde le français."

        XCTAssertTrue(DictationOutput.cleanup.systemPrompt(keeping: [])
            .hasPrefix("Ponctue seulement, et garde le français."))
        XCTAssertFalse(DictationOutput.translateEN.systemPrompt(keeping: [])
            .contains("garde le français"))
    }

    /// The transcript preamble is said in English too.
    func testTheTranscriptPreambleIsSaidInEnglishAsWell() {
        useLanguage(.english)
        let prompt = DictationOutput.translateEN.systemPrompt(keeping: [])
        XCTAssertTrue(prompt.contains("voice dictation"), prompt)
        XCTAssertTrue(prompt.hasSuffix(ClaudioAction.translateEN.system), prompt)
    }

    // MARK: - Where the text is going

    /// A dictation always lands somewhere: whichever of the three the
    /// shortcut asked for, the model is told the name of the app it is
    /// writing into.
    func testEveryOutputIsToldWhichAppTheTextIsGoingInto() {
        useLanguage(.french)
        for output in DictationOutput.allCases {
            let prompt = output.systemPrompt(keeping: [], landingIn: DictationDestination(name: "Slack", bundleID: nil))
            XCTAssertTrue(prompt.contains("Ce texte sera collé dans Slack."), output.rawValue)
        }
    }

    /// The destination sits after the whole composition and before the
    /// vocabulary, which stays the last word whatever else is said.
    func testTheDestinationSitsBetweenTheCompositionAndTheVocabulary() {
        useLanguage(.french)
        let prompt = DictationOutput.translateEN.systemPrompt(keeping: ["Okonoma"],
                                                              landingIn: DictationDestination(name: "Mail", bundleID: nil))

        XCTAssertTrue(prompt.hasPrefix(DictationOutput.translateEN.systemPrompt(keeping: [])),
                      prompt)
        XCTAssertTrue(prompt.contains("Ce texte sera collé dans Mail."), prompt)
        XCTAssertTrue(prompt.hasSuffix("« Okonoma »."), prompt)
    }

    /// An app with no name adds nothing at all: every output sends the prompt
    /// it sent before there was a destination, byte for byte.
    func testANamelessAppAddsNothingToAnyOutput() {
        useLanguage(.french)
        for output in DictationOutput.allCases {
            let prompt = output.systemPrompt(keeping: ["Okonoma"], landingIn: DictationDestination(name: "  ", bundleID: nil))
            XCTAssertEqual(Array(prompt.utf8),
                           Array(output.systemPrompt(keeping: ["Okonoma"]).utf8), output.rawValue)
            XCTAssertFalse(prompt.contains("collé dans"), output.rawValue)
        }
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
