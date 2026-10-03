import XCTest
@testable import Claudio

/// The two MusicBrainz questions "What's playing?" asks, and how their
/// answers are read. The answers are captures of 2026-10-02 on
/// 真夜中のジョーク by 間宮貴子, trimmed to what the reader looks at.
final class MusicBrainzLookupTests: XCTestCase {

    // MARK: - The questions

    /// A fielded Lucene query, the title and artist quoted and escaped, the
    /// whole thing percent-encoded so the service reads it as written.
    func testTheSearchAsksForTheRecordingByTitleAndArtist() {
        let url = MusicBrainzLookup.searchURL(title: "Midnight \"Joke\"", artist: "Mamiya \\ Takako")
        XCTAssertEqual(url.host, "musicbrainz.org")
        XCTAssertEqual(url.path, "/ws/2/recording")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first { $0.name == "query" }?.value,
                       #"recording:"Midnight \"Joke\"" AND artist:"Mamiya \\ Takako""#)
        XCTAssertEqual(query.first { $0.name == "limit" }?.value, "5")
        XCTAssertEqual(query.first { $0.name == "fmt" }?.value, "json")
    }

    /// The version tail a player adds isn't in the index: the plain title
    /// is asked for.
    func testTheSearchDropsTheVersionTail() {
        let url = MusicBrainzLookup.searchURL(title: "Am I Wrong - Olympic Mix", artist: "Etienne de Crécy")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first { $0.name == "query" }?.value,
                       #"recording:"Am I Wrong" AND artist:"Etienne de Crécy""#)
    }

    /// Without an artist the title alone is asked for: a browser's "artist"
    /// is a channel name, better left out than matched.
    func testWithoutAnArtistTheTitleAloneIsAskedFor() {
        let url = MusicBrainzLookup.searchURL(title: "Midnight Joke", artist: nil)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first { $0.name == "query" }?.value, #"recording:"Midnight Joke""#)
    }

    func testTheReleaseGroupIsLookedUpByID() {
        XCTAssertEqual(MusicBrainzLookup.releaseGroupURL(id: "3b03f2df-1fc0-4572-8b90-8f952a2a9fcb").absoluteString,
                       "https://musicbrainz.org/ws/2/release-group/3b03f2df-1fc0-4572-8b90-8f952a2a9fcb?fmt=json")
    }

    /// MusicBrainz asks who calls: the app, its version, where to reach it.
    func testTheRequestNamesClaudioAndAsksForJSON() {
        let request = MusicBrainzLookup.request(MusicBrainzLookup.releaseGroupURL(id: "x"), version: "1.13.0")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"),
                       "Claudio/1.13.0 ( https://github.com/gdhios/claudio )")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
    }

    // MARK: - The answers

    /// The best recording at a score of 90 or more is the track. Among its
    /// release groups, the compilations come first in the answer: the one
    /// bearing the player's album title wins.
    func testTheSearchGivesTheRecordingAndThePlayersAlbum() throws {
        let facts = try XCTUnwrap(MusicBrainzLookup.parseSearch(Self.search, playerAlbum: "LOVE TRIP"))
        XCTAssertEqual(facts.recordingID, "783dfef9-87f4-4056-b944-c7ae624d5964")
        XCTAssertEqual(facts.releaseGroupID, "3b03f2df-1fc0-4572-8b90-8f952a2a9fcb")
        XCTAssertEqual(facts.albumTitle, "LOVE TRIP")
        XCTAssertEqual(facts.primaryType, "Album")
        XCTAssertEqual(facts.secondaryTypes, [])
        // The recording's own first release, until the release group says.
        XCTAssertEqual(facts.firstReleaseDate, "1982-11-25")
        // The artist's id, for the long text to look them up without a search.
        XCTAssertEqual(facts.artistID, "c3a2c5d6-1")
    }

    /// Without the player's album, an album with no secondary type is the
    /// origin: not the compilations listed before it.
    func testWithoutThePlayersAlbumAPlainAlbumIsTheOrigin() throws {
        let facts = try XCTUnwrap(MusicBrainzLookup.parseSearch(Self.search, playerAlbum: nil))
        XCTAssertEqual(facts.releaseGroupID, "3b03f2df-1fc0-4572-8b90-8f952a2a9fcb")
        XCTAssertEqual(facts.albumTitle, "LOVE TRIP")
    }

    /// A weak match is no match: better nothing than another song's facts.
    func testAScoreUnderNinetyIsNoMatch() {
        let weak = Self.search.replacingOccurrences(of: "\"score\":100", with: "\"score\":74")
        XCTAssertNil(MusicBrainzLookup.parseSearch(weak, playerAlbum: nil))
        XCTAssertNil(MusicBrainzLookup.parseSearch(#"{"count":0,"offset":0,"recordings":[]}"#, playerAlbum: nil))
        XCTAssertNil(MusicBrainzLookup.parseSearch("not json", playerAlbum: nil))
    }

    /// The release group's own record: its title, types and first release
    /// replace what the search guessed.
    func testTheReleaseGroupFillsInTheFacts() throws {
        var facts = try XCTUnwrap(MusicBrainzLookup.parseSearch(Self.search, playerAlbum: "LOVE TRIP"))
        facts.firstReleaseDate = nil
        let filled = MusicBrainzLookup.parseReleaseGroup(Self.releaseGroup, into: facts)
        XCTAssertEqual(filled.albumTitle, "LOVE TRIP")
        XCTAssertEqual(filled.primaryType, "Album")
        XCTAssertEqual(filled.secondaryTypes, [])
        XCTAssertEqual(filled.firstReleaseDate, "1982-11-25")
        // An answer that doesn't read leaves the facts as they were.
        XCTAssertEqual(MusicBrainzLookup.parseReleaseGroup("oops", into: facts), facts)
    }

    // MARK: - Captures

    static let search = """
        {"created":"2026-10-02T20:17:03.112Z","count":1,"offset":0,"recordings":[{"id":"783dfef9-87f4-4056-b944-c7ae624d5964","score":100,"title":"真夜中のジョーク","length":245000,"video":null,"artist-credit":[{"name":"間宮貴子","artist":{"id":"c3a2c5d6-1","name":"間宮貴子","sort-name":"Mamiya, Takako"}}],"first-release-date":"1982-11-25","releases":[{"id":"r1","status-id":"s","count":1,"title":"City Pop Essentials ~ Female Voices ~","status":"Official","release-group":{"id":"9b410f4b-d33c-489f-93b9-73a411784c5b","type-id":"t","primary-type-id":"p","title":"City Pop Essentials ~ Female Voices ~","primary-type":"Album","secondary-types":["Compilation"],"secondary-type-ids":["c"]},"track-count":12,"media":[]},{"id":"r2","count":1,"title":"City Pop Essentials ~ Idols 2 ~","status":"Official","release-group":{"id":"5d2d3279-e632-4307-bac8-99d5fbf7dd5a","title":"City Pop Essentials - Idols 2 -","primary-type":"Album","secondary-types":["Compilation"]},"track-count":12,"media":[]},{"id":"r3","count":1,"title":"LOVE TRIP","status":"Official","release-group":{"id":"3b03f2df-1fc0-4572-8b90-8f952a2a9fcb","title":"LOVE TRIP","primary-type":"Album"},"track-count":8,"media":[]},{"id":"r4","count":1,"title":"LOVE TRIP","status":"Official","date":"2023-03-01","country":"JP","release-group":{"id":"3b03f2df-1fc0-4572-8b90-8f952a2a9fcb","title":"LOVE TRIP","primary-type":"Album"},"track-count":8,"media":[]}]}]}
        """

    static let releaseGroup = """
        {"disambiguation":"","first-release-date":"1982-11-25","primary-type":"Album","secondary-type-ids":[],"primary-type-id":"f529b476","secondary-types":[],"id":"3b03f2df-1fc0-4572-8b90-8f952a2a9fcb","title":"LOVE TRIP"}
        """
}
