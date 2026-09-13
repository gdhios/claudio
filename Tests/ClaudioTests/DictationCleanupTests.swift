import XCTest
@testable import Claudio

/// The cleanup pass turns a raw transcript into pasteable text. What is
/// locked down here: the prompt still forbids what makes a dictation
/// unusable (rewriting, additions, markdown), and the output budget follows
/// the length of what was said.
final class DictationCleanupTests: XCTestCase {

    private var previousLanguage: AppLanguage = .system

    override func setUp() {
        super.setUp()
        previousLanguage = AppSettings.language
    }

    override func tearDown() {
        AppSettings.language = previousLanguage
        super.tearDown()
    }

    /// The prohibitions are the whole point of the prompt: without them the
    /// model rewrites, comments, or answers the dictation.
    func testTheFrenchPromptForbidsRewritingAddingAndMarkdown() {
        AppSettings.language = .french
        let prompt = DictationCleanup.defaultSystemPrompt

        XCTAssertTrue(prompt.contains("Ne reformule jamais"), prompt)
        XCTAssertTrue(prompt.contains("N'ajoute rien"), prompt)
        XCTAssertTrue(prompt.contains("markdown"), prompt)
        // Self-corrections: the example is in the prompt, corrected version kept.
        XCTAssertTrue(prompt.contains("mardi, non, mercredi"), prompt)
        // The language of the dictation is never traded for the prompt's own.
        XCTAssertTrue(prompt.contains("langue"), prompt)
    }

    func testTheEnglishPromptCarriesTheSameProhibitions() {
        AppSettings.language = .english
        let prompt = DictationCleanup.defaultSystemPrompt

        XCTAssertTrue(prompt.contains("Never rephrase"), prompt)
        XCTAssertTrue(prompt.contains("Add nothing"), prompt)
        XCTAssertTrue(prompt.contains("markdown"), prompt)
        XCTAssertTrue(prompt.contains("Tuesday, no, Wednesday"), prompt)
        XCTAssertTrue(prompt.contains("language"), prompt)
    }

    /// The cleaned text is about as long as the raw one: the budget follows
    /// it, with room for punctuation, and never leaves its bounds.
    func testTheBudgetFollowsTheLengthOfTheTranscript() {
        XCTAssertEqual(DictationCleanup.maxTokens(forRawLength: 1_000), 1_564)
        XCTAssertEqual(DictationCleanup.maxTokens(forRawLength: 200), 364)
    }

    /// A two-word dictation still needs a usable budget, and a monologue
    /// must not ask for a fortune.
    func testTheBudgetHasAFloorAndACap() {
        XCTAssertEqual(DictationCleanup.maxTokens(forRawLength: 0), 128)
        XCTAssertEqual(DictationCleanup.maxTokens(forRawLength: 10), 128)
        XCTAssertEqual(DictationCleanup.maxTokens(forRawLength: 100_000), 4_096)
        // Monotonic between the two: a longer dictation never gets less room.
        var previous = 0
        for length in stride(from: 0, through: 5_000, by: 137) {
            let budget = DictationCleanup.maxTokens(forRawLength: length)
            XCTAssertGreaterThanOrEqual(budget, previous, "length \(length)")
            XCTAssertGreaterThanOrEqual(budget, 128, "length \(length)")
            XCTAssertLessThanOrEqual(budget, 4_096, "length \(length)")
            previous = budget
        }
    }
}
