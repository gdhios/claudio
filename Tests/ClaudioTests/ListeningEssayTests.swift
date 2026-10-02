import XCTest
@testable import Claudio

/// What Claude is asked when someone wants more than three sentences: a
/// long text about the album or the artist, the facts in hand first.
final class ListeningEssayTests: XCTestCase {

    func testTheSubjectGoesOutAsItsBlock() {
        let subject = MusicSubject(kind: .artist, artist: "間宮貴子")
        XCTAssertEqual(ListeningEssay.userMessage(for: subject), subject.promptBlock)
        XCTAssertEqual(ListeningEssay.maxTokens, 900)
    }

    /// The artist's facts follow the subject, in their own block, so the
    /// discography is under Claude's eyes before his first word.
    func testTheArtistsFactsFollowTheSubject() {
        let subject = MusicSubject(kind: .artist, artist: "The Supermen Lovers")
        let artist = ArtistFacts(artistID: "0df6d50f", name: "The Supermen Lovers", type: "Person",
                                 country: "FR", beginDate: "1975-02-09", releases: [])
        XCTAssertEqual(ListeningEssay.userMessage(for: subject, artist: artist),
                       subject.promptBlock + "\n" + artist.promptBlock)
        XCTAssertEqual(ListeningEssay.userMessage(for: subject, artist: nil), subject.promptBlock)
    }

    /// The prompt lays out the text for each kind of subject, keeps the
    /// honesty rule, trusts the block over memory, and ends in the
    /// interface's language like the notes' prompt.
    func testTheSystemPromptLaysOutTheTextAndKeepsTheRules() {
        let french = ListeningEssay.system(language: .french)
        XCTAssertTrue(french.contains("<sujet>"), french)
        XCTAssertTrue(french.contains("<artiste>"), french)
        XCTAssertTrue(french.contains("priment"), french)
        XCTAssertTrue(french.contains("discographie"), french)
        XCTAssertTrue(french.contains("liste de référence"), french)
        XCTAssertTrue(french.contains("album"), french)
        XCTAssertTrue(french.contains("artiste"), french)
        XCTAssertTrue(french.contains("dis-le en une phrase"), french)
        XCTAssertTrue(french.hasSuffix("\n- Réponds en français."), french)
        XCTAssertTrue(ListeningEssay.system(language: .english).hasSuffix("\n- Réponds en anglais."))
    }
}
