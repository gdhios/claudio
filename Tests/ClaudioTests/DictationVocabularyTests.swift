import XCTest
@testable import Claudio

/// The vocabulary as typed in Settings › Dictation. What is at stake: each
/// line is read the way its author meant it — a term to spell right, or a
/// mistake to fix — and a line that can't be read is dropped rather than
/// guessed at, since whatever is guessed ends up pasted.
final class DictationVocabularyTests: XCTestCase {

    private typealias Replacement = DictationVocabulary.Replacement

    func testAPlainLineIsATerm() {
        let vocabulary = DictationVocabulary(parsing: "Okonoma")
        XCTAssertEqual(vocabulary.terms, ["Okonoma"])
        XCTAssertTrue(vocabulary.replacements.isEmpty)
    }

    /// The written side is a spelling to keep like any other: recognition
    /// is biased towards it, and the cleanup is told to leave it alone.
    func testAnArrowLineIsAReplacementWhoseWrittenSideIsATerm() {
        let vocabulary = DictationVocabulary(parsing: "l'a pas compris → Lapacompris")
        XCTAssertEqual(vocabulary.replacements,
                       [Replacement(heard: "l'a pas compris", written: "Lapacompris")])
        XCTAssertEqual(vocabulary.terms, ["Lapacompris"])
    }

    /// `→` is what the footnote shows, `->` is what a keyboard types.
    func testBothArrowSpellingsAreAccepted() {
        let vocabulary = DictationVocabulary(parsing: "claude io -> Claudio\nokonoma→Okonoma")
        XCTAssertEqual(vocabulary.replacements,
                       [Replacement(heard: "claude io", written: "Claudio"),
                        Replacement(heard: "okonoma", written: "Okonoma")])
        XCTAssertEqual(vocabulary.terms, ["Claudio", "Okonoma"])
    }

    func testBlankLinesAreIgnoredAndWhitespaceIsTrimmed() {
        let vocabulary = DictationVocabulary(parsing: "\n  Okonoma \t\n\n   \n  claude io   →   Claudio  \n")
        XCTAssertEqual(vocabulary.terms, ["Okonoma", "Claudio"])
        XCTAssertEqual(vocabulary.replacements, [Replacement(heard: "claude io", written: "Claudio")])
    }

    /// An arrow with nothing on one side says nothing usable: replacing a
    /// phrase with nothing, or nothing with a word, is never what was meant.
    func testALineWithAnEmptySideIsIgnored() {
        let text = "→ Claudio\nclaude io →\n→\n  ->  \nOkonoma"
        let vocabulary = DictationVocabulary(parsing: text)
        XCTAssertEqual(vocabulary.terms, ["Okonoma"])
        XCTAssertTrue(vocabulary.replacements.isEmpty)
    }

    /// Two arrows can't say which side is heard: the line is dropped rather
    /// than pasting an arrow into someone's text.
    func testALineWithTwoArrowsIsIgnored() {
        let vocabulary = DictationVocabulary(parsing: "cloud → claude -> Claude\nOkonoma")
        XCTAssertEqual(vocabulary.terms, ["Okonoma"])
        XCTAssertTrue(vocabulary.replacements.isEmpty)
    }

    /// Recognition is handed each spelling once, in the order typed.
    func testTermsKeepTheirOrderAndAppearOnce() {
        let vocabulary = DictationVocabulary(parsing: "Okonoma\nClaudio\nOkonoma\nclaude io → Claudio")
        XCTAssertEqual(vocabulary.terms, ["Okonoma", "Claudio"])
        XCTAssertEqual(vocabulary.replacements.count, 1)
    }

    /// A vocabulary pasted from elsewhere may carry Windows line endings.
    func testCarriageReturnsSeparateLinesToo() {
        let vocabulary = DictationVocabulary(parsing: "Okonoma\r\nClaudio\rLapacompris")
        XCTAssertEqual(vocabulary.terms, ["Okonoma", "Claudio", "Lapacompris"])
    }

    /// Nothing typed is the default, and it has to mean nothing at all.
    func testBlankTextIsTheEmptyVocabulary() {
        XCTAssertEqual(DictationVocabulary(parsing: ""), .empty)
        XCTAssertEqual(DictationVocabulary(parsing: "  \n\t\n"), .empty)
        XCTAssertTrue(DictationVocabulary.empty.terms.isEmpty)
        XCTAssertTrue(DictationVocabulary.empty.replacements.isEmpty)
    }
}
