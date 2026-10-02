import XCTest
@testable import Claudio

/// What MusicBrainz knows of an artist, read before the long text is
/// written: who they are, and the dated list of their albums and EPs —
/// the list Claude may cite from, and nothing else. The answers are
/// captures of 2026-10-03 on The Supermen Lovers, trimmed to four release
/// groups of the sixteen.
final class ArtistFactsTests: XCTestCase {

    // MARK: - The questions

    func testTheArtistIsSearchedByName() {
        let url = MusicBrainzLookup.artistSearchURL(name: "The \"Supermen\" Lovers")
        XCTAssertEqual(url.path, "/ws/2/artist")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first { $0.name == "query" }?.value, #"artist:"The \"Supermen\" Lovers""#)
        XCTAssertEqual(query.first { $0.name == "limit" }?.value, "5")
        XCTAssertEqual(query.first { $0.name == "fmt" }?.value, "json")
    }

    func testTheArtistIsLookedUpByID() {
        XCTAssertEqual(MusicBrainzLookup.artistURL(id: "0df6d50f").absoluteString,
                       "https://musicbrainz.org/ws/2/artist/0df6d50f?fmt=json")
    }

    /// Albums and EPs only, a hundred at most: the service's browse, with
    /// the types joined by the bar it expects.
    func testTheReleaseGroupsAreBrowsedByArtist() {
        let url = MusicBrainzLookup.releaseGroupsURL(artist: "0df6d50f")
        XCTAssertEqual(url.path, "/ws/2/release-group")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first { $0.name == "artist" }?.value, "0df6d50f")
        XCTAssertEqual(query.first { $0.name == "type" }?.value, "album|ep")
        XCTAssertEqual(query.first { $0.name == "limit" }?.value, "100")
        XCTAssertEqual(query.first { $0.name == "fmt" }?.value, "json")
    }

    // MARK: - The answers

    /// The best artist at a score of 90 or more, with what the search
    /// already says of them; no release yet.
    func testTheSearchGivesTheArtist() throws {
        let facts = try XCTUnwrap(MusicBrainzLookup.parseArtistSearch(Self.artistSearch))
        XCTAssertEqual(facts.artistID, "0df6d50f-7e43-4c6a-8220-61932b67c9c5")
        XCTAssertEqual(facts.name, "The Supermen Lovers")
        XCTAssertEqual(facts.type, "Person")
        XCTAssertEqual(facts.country, "FR")
        XCTAssertEqual(facts.beginDate, "1975-02-09")
        XCTAssertNil(facts.endDate)
        XCTAssertEqual(facts.releases, [])

        let weak = Self.artistSearch.replacingOccurrences(of: "\"score\":100", with: "\"score\":60")
        XCTAssertNil(MusicBrainzLookup.parseArtistSearch(weak))
        XCTAssertNil(MusicBrainzLookup.parseArtistSearch(#"{"count":0,"offset":0,"artists":[]}"#))
    }

    /// The artist's own record, when the id is already known.
    func testTheLookupGivesTheArtist() throws {
        let facts = try XCTUnwrap(MusicBrainzLookup.parseArtist(Self.artistLookup))
        XCTAssertEqual(facts.artistID, "0df6d50f-7e43-4c6a-8220-61932b67c9c5")
        XCTAssertEqual(facts.name, "The Supermen Lovers")
        XCTAssertEqual(facts.country, "FR")
        XCTAssertEqual(facts.beginDate, "1975-02-09")
        XCTAssertNil(MusicBrainzLookup.parseArtist("oops"))
    }

    /// The browse lists the release groups in no order and with their
    /// types: they are kept by first release, the plain ones only.
    func testTheReleaseGroupsAreKeptInOrderOfRelease() throws {
        let artist = try XCTUnwrap(MusicBrainzLookup.parseArtist(Self.artistLookup))
        let withLive = Self.releaseGroups.replacingOccurrences(
            of: #""secondary-types":[],"title":"Body Double""#,
            with: #""secondary-types":["Live"],"title":"Body Double""#)
        let facts = MusicBrainzLookup.parseReleaseGroups(withLive, into: artist)
        XCTAssertEqual(facts.releases.map(\.title), ["Starlight", "The Player", "Staralight 20th anniversary edition"])
        XCTAssertEqual(facts.releases.map(\.firstReleaseDate), ["2001-01-01", "2002-03-01", "2022-10-14"])
        XCTAssertEqual(facts.releases.map(\.primaryType), ["EP", "Album", "EP"])
        XCTAssertEqual(MusicBrainzLookup.parseReleaseGroups("oops", into: artist), artist)
    }

    // MARK: - The block

    /// Claude's block: who, from where, since when, and the dated list.
    func testThePromptBlockListsTheDiscography() throws {
        let artist = try XCTUnwrap(MusicBrainzLookup.parseArtist(Self.artistLookup))
        let facts = MusicBrainzLookup.parseReleaseGroups(Self.releaseGroups, into: artist)
        XCTAssertEqual(facts.promptBlock, """
            <artiste source="MusicBrainz">
            nom : The Supermen Lovers
            type : personne
            pays : FR
            naissance : 1975-02-09
            discographie (albums et EP, par première sortie) :
            - 2001 · EP · Starlight
            - 2002 · album · The Player
            - 2022 · album · Body Double
            - 2022 · EP · Staralight 20th anniversary edition
            </artiste>
            """)
    }

    /// A group is formed rather than born, an end is said, and a release
    /// without a date says so; without any release, no list at all.
    func testTheBlockAdaptsToAGroup() {
        var facts = ArtistFacts(artistID: "x", name: "Daft Punk", type: "Group", country: "FR",
                                beginDate: "1993", endDate: "2021-02-22", releases: [])
        XCTAssertEqual(facts.promptBlock, """
            <artiste source="MusicBrainz">
            nom : Daft Punk
            type : groupe
            pays : FR
            formation : 1993
            fin : 2021-02-22
            </artiste>
            """)
        facts.releases = [ArtistFacts.Release(id: "r", title: "Homework", primaryType: "Album",
                                              secondaryTypes: [], firstReleaseDate: nil)]
        XCTAssertTrue(facts.promptBlock.contains("- sans date · album · Homework"), facts.promptBlock)
    }

    // MARK: - Captures

    static let artistSearch = """
        {"created":"2026-10-02T23:10:47.187Z","count":1,"offset":0,"artists":[{"id":"0df6d50f-7e43-4c6a-8220-61932b67c9c5","type":"Person","type-id":"b6e035f4-3ce9-331c-97df-83397230b0df","score":100,"name":"The Supermen Lovers","sort-name":"Supermen Lovers, The","gender":"male","country":"FR","area":{"id":"08310658-51eb-3801-80de-5a0739207115","type":"Country","name":"France","sort-name":"France","life-span":{"ended":null}},"begin-area":{"id":"dc10c22b-e510-4006-8b7f-fecb4f36436e","type":"City","name":"Paris","sort-name":"Paris","life-span":{"ended":null}},"life-span":{"begin":"1975-02-09","ended":null},"aliases":[{"sort-name":"Superman Lovers","name":"Superman Lovers","locale":null,"type":null,"primary":null,"begin-date":null,"end-date":null}],"tags":[{"count":1,"name":"pop and chart"}]}]}
        """

    static let artistLookup = """
        {"begin-area":{"sort-name":"Paris","type-id":null,"name":"Paris","type":null,"iso-3166-2-codes":["FR-75"],"disambiguation":"","id":"dc10c22b-e510-4006-8b7f-fecb4f36436e"},"id":"0df6d50f-7e43-4c6a-8220-61932b67c9c5","type":"Person","name":"The Supermen Lovers","ipis":[],"disambiguation":"","life-span":{"end":null,"ended":false,"begin":"1975-02-09"},"isnis":["0000000092859349"],"end-area":null,"gender":"Male","area":{"iso-3166-1-codes":["FR"],"disambiguation":"","id":"08310658-51eb-3801-80de-5a0739207115","type":null,"sort-name":"France","type-id":null,"name":"France"},"sort-name":"Supermen Lovers, The","type-id":"b6e035f4-3ce9-331c-97df-83397230b0df","country":"FR"}
        """

    static let releaseGroups = """
        {"release-group-offset":0,"release-group-count":16,"release-groups":[{"first-release-date":"2022-05-27","disambiguation":"","primary-type":"Album","secondary-type-ids":[],"secondary-types":[],"title":"Body Double","primary-type-id":"f529b476-6e62-324f-b0aa-1f3e33d313fc","id":"0768e6ac-fbf2-404f-9f85-2c68846832da"},{"title":"Starlight","secondary-type-ids":[],"secondary-types":[],"primary-type":"EP","disambiguation":"","first-release-date":"2001-01-01","id":"2ee4b81b-a8ce-4832-a366-bcd0e0515863","primary-type-id":"6d0c5bf6-7a33-3420-a519-44fc63eedebf"},{"primary-type-id":"f529b476-6e62-324f-b0aa-1f3e33d313fc","id":"3d1ae2e5-1111-302e-a2fb-013fe37d0aff","first-release-date":"2002-03-01","disambiguation":"","primary-type":"Album","secondary-type-ids":[],"secondary-types":[],"title":"The Player"},{"disambiguation":"","first-release-date":"2022-10-14","title":"Staralight 20th anniversary edition","secondary-type-ids":[],"secondary-types":[],"primary-type":"EP","primary-type-id":"6d0c5bf6-7a33-3420-a519-44fc63eedebf","id":"ae2d476f-7ab6-4349-b776-0b4d1b7a855d"}]}
        """
}
