import XCTest
@testable import Claudio

/// "Search in Claude": the card hands the subject to Claude in the
/// browser, where he searches the web before answering — no key, no API
/// cost. The link carries the facts in hand, in the interface's language.
final class ClaudeSearchTests: XCTestCase {

    private let album = MusicSubject(kind: .album, artist: "The Supermen Lovers", title: "The Player",
                                     mbid: "3d1ae2e5", firstReleaseDate: "2002-03-01", type: "Album")
    private let artist = MusicSubject(kind: .artist, artist: "The Supermen Lovers")
    private let facts = ArtistFacts(artistID: "0df6d50f", name: "The Supermen Lovers", type: "Person",
                                    country: "FR", beginDate: "1975-02-09", releases: [
                                        ArtistFacts.Release(id: "a", title: "Starlight", primaryType: "EP",
                                                            secondaryTypes: [], firstReleaseDate: "2001-01-01"),
                                        ArtistFacts.Release(id: "b", title: "The Player", primaryType: "Album",
                                                            secondaryTypes: [], firstReleaseDate: "2002-03-01"),
                                    ])

    /// A new conversation on claude.ai, the prompt in `q`.
    func testTheLinkOpensANewConversationWithThePrompt() throws {
        let url = ClaudeSearch.url(for: artist, artist: nil, language: .french)
        XCTAssertEqual(url.host, "claude.ai")
        XCTAssertEqual(url.path, "/new")
        let query = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.first { $0.name == "q" }?.value, ClaudeSearch.prompt(for: artist, artist: nil, language: .french))
    }

    /// The prompt asks for a web search first, names the subject with its
    /// facts, and lists the discography when the long text got it.
    func testThePromptAsksForAWebSearchAndCarriesTheFacts() {
        let plain = ClaudeSearch.prompt(for: album, artist: nil, language: .french)
        XCTAssertTrue(plain.hasPrefix("Cherche sur le web avant de répondre"), plain)
        XCTAssertTrue(plain.contains("l'album « The Player » de The Supermen Lovers (2002, album)"), plain)
        XCTAssertFalse(plain.contains("Discographie"), plain)

        let withFacts = ClaudeSearch.prompt(for: artist, artist: facts, language: .french)
        XCTAssertTrue(withFacts.contains("l'artiste The Supermen Lovers"), withFacts)
        XCTAssertTrue(withFacts.contains("Discographie connue (MusicBrainz) : Starlight (2001, EP) ; The Player (2002, album)."), withFacts)
        XCTAssertTrue(withFacts.contains("France") || withFacts.contains("FR"), withFacts)
    }

    func testThePromptFollowsTheInterfaceLanguage() {
        let english = ClaudeSearch.prompt(for: album, artist: facts, language: .english)
        XCTAssertTrue(english.hasPrefix("Search the web before answering"), english)
        XCTAssertTrue(english.contains("the album “The Player” by The Supermen Lovers (2002, album)"), english)
        XCTAssertTrue(english.contains("Known discography (MusicBrainz): Starlight (2001, EP); The Player (2002, album)."), english)
    }

    /// A long discography is cut to keep the link short: the latest
    /// twenty, since the browser's address bar has its limits.
    func testALongDiscographyIsCutToTwenty() {
        var many = facts
        many.releases = (1...30).map {
            ArtistFacts.Release(id: "\($0)", title: "R\($0)", primaryType: "Album", secondaryTypes: [],
                                firstReleaseDate: String(format: "%04d", 1990 + $0))
        }
        let prompt = ClaudeSearch.prompt(for: artist, artist: many, language: .french)
        XCTAssertFalse(prompt.contains("R1 ("), prompt)
        XCTAssertTrue(prompt.contains("R11 (2001, album)"), prompt)
        XCTAssertTrue(prompt.contains("R30 (2020, album)"), prompt)
        XCTAssertTrue(prompt.contains("entre autres"), prompt)
    }
}
