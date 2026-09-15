import XCTest
@testable import Claudio

/// A replacement fixes, in the transcript, what recognition keeps getting
/// wrong — before the cleanup, the paste and the history see it. What is at
/// stake: it rewrites the words it names and nothing else. A hit inside
/// another word, or on a neighbouring accent, would corrupt a dictation that
/// was right, and silently, since nobody rereads a pasted text for that.
final class VocabularyReplacementTests: XCTestCase {

    private func replacing(_ transcript: String, with vocabulary: String) -> String {
        DictationVocabulary(parsing: vocabulary).applyingReplacements(to: transcript)
    }

    func testAHeardWordIsWrittenAsTyped() {
        XCTAssertEqual(replacing("je bosse chez okonoma", with: "okonoma → Okonoma"),
                       "je bosse chez Okonoma")
    }

    /// Recognition capitalises as it likes; the written form is the author's.
    func testTheMatchIgnoresCaseAndTheWrittenFormIsVerbatim() {
        XCTAssertEqual(replacing("OKONOMA, Okonoma et okonoma", with: "okonoma → OkoNoma"),
                       "OkoNoma, OkoNoma et OkoNoma")
    }

    /// A made-up word is heard as several real ones: the phrase is replaced
    /// whole, however the recognizer spaced it.
    func testAMultiWordHeardSideIsReplacedAsAPhrase() {
        let vocabulary = "l'a pas compris → Lapacompris"
        XCTAssertEqual(replacing("ouvre l'a pas compris", with: vocabulary), "ouvre Lapacompris")
        XCTAssertEqual(replacing("ouvre L'a  pas\ncompris vite", with: vocabulary), "ouvre Lapacompris vite")
        // Not all of the phrase: nothing to replace.
        XCTAssertEqual(replacing("il l'a pas vu", with: vocabulary), "il l'a pas vu")
    }

    /// The Settings editor may curl the apostrophe typed, and recognition
    /// may write either one: the two match each other.
    func testEitherApostropheMatchesTheOther() {
        XCTAssertEqual(replacing("ouvre l’a pas compris", with: "l'a pas compris → Lapacompris"),
                       "ouvre Lapacompris")
        XCTAssertEqual(replacing("ouvre l'a pas compris", with: "l’a pas compris → Lapacompris"),
                       "ouvre Lapacompris")
    }

    func testNoHitInsideAnotherWord() {
        let vocabulary = "claudio → Claudio"
        XCTAssertEqual(replacing("un claudiophile", with: vocabulary), "un claudiophile")
        XCTAssertEqual(replacing("leclaudio", with: vocabulary), "leclaudio")
        XCTAssertEqual(replacing("claudio2", with: vocabulary), "claudio2")
    }

    /// Punctuation isn't part of a word: the name is replaced, the marks
    /// around it stay where they were.
    func testPunctuationNextToTheWordStillMatches() {
        XCTAssertEqual(replacing("claudio, (claudio) «claudio» l'claudio claudio.",
                                 with: "claudio → Claudio"),
                       "Claudio, (Claudio) «Claudio» l'Claudio Claudio.")
    }

    /// An accented letter is a letter: it ends no word, so "cote" is not in
    /// "côté". And accents are part of what is matched — in French, "cote",
    /// "côte" and "côté" are three different words.
    func testAccentsAreLettersAndAreMatchedExactly() {
        XCTAssertEqual(replacing("à côté de la cote", with: "cote → Côte"), "à côté de la Côte")
        XCTAssertEqual(replacing("mais une coteé", with: "cote → Côte"), "mais une coteé")
        XCTAssertEqual(replacing("merci ÉLODIE", with: "élodie → Élodie"), "merci Élodie")
    }

    /// Unicode spells "é" two ways, which look the same: both match.
    func testADecomposedAccentMatchesAComposedOne() {
        XCTAssertEqual(replacing("merci e\u{301}lodie", with: "élodie → Élodie"), "merci Élodie")
    }

    /// Each part of the transcript is replaced once: the written form of one
    /// line is never read as the heard form of another.
    func testAReplacementIsNeverReplacedAgain() {
        XCTAssertEqual(replacing("claudia et claudio", with: "claudia → Claudio\nclaudio → Claudia"),
                       "Claudio et Claudia")
    }

    /// Where two heard phrases start at the same word, the longer one wins,
    /// whatever the order of the lines.
    func testTheLongestHeardPhraseWins() {
        XCTAssertEqual(replacing("claude code et claude",
                                 with: "claude → Claude\nclaude code → Claude Code"),
                       "Claude Code et Claude")
    }

    /// A dot, a dollar: typed characters, never pattern syntax.
    func testSpecialCharactersAreTakenLiterally() {
        XCTAssertEqual(replacing("claudexai puis claude.ai", with: "claude.ai → Claude.ai"),
                       "claudexai puis Claude.ai")
        XCTAssertEqual(replacing("ça coûte cinq dollars", with: "cinq dollars → $5 \\0"),
                       "ça coûte $5 \\0")
    }

    /// Terms alone replace nothing, and no vocabulary leaves the transcript
    /// as it came — to the scalar, which `==` alone wouldn't prove: Swift
    /// strings compare equal across the two spellings of "é".
    func testWithoutReplacementsTheTranscriptIsUntouched() {
        let decomposed = "merci e\u{301}lodie"
        let scalars = Array(decomposed.unicodeScalars)
        XCTAssertEqual(Array(replacing(decomposed, with: "Okonoma\nClaudio").unicodeScalars), scalars)
        XCTAssertEqual(Array(DictationVocabulary.empty.applyingReplacements(to: decomposed).unicodeScalars),
                       scalars)
        XCTAssertEqual(Array(replacing(decomposed, with: "okonoma → Okonoma").unicodeScalars), scalars)
        XCTAssertEqual(replacing("", with: "okonoma → Okonoma"), "")
    }
}
