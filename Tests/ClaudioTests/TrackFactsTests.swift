import XCTest
@testable import Claudio

/// Facts cached before Deezer existed carry no origin: they are
/// MusicBrainz's, and read back as such.
final class TrackFactsOriginTests: XCTestCase {
    func testAnOriginlessEntryIsMusicBrainzs() throws {
        let json = #"{"recordingID":"r","secondaryTypes":[],"albumTitle":"LOVE TRIP"}"#
        let facts = try JSONDecoder().decode(TrackFacts.self, from: Data(json.utf8))
        XCTAssertNil(facts.origin)
        XCTAssertTrue(facts.promptBlock.hasPrefix("<faits source=\"MusicBrainz\">"), facts.promptBlock)
    }
}

/// What MusicBrainz said about the track, as the card shows it and as
/// Claude reads it.
final class TrackFactsTests: XCTestCase {

    private let loveTrip = TrackFacts(recordingID: "783dfef9", releaseGroupID: "3b03f2df",
                                      albumTitle: "LOVE TRIP", primaryType: "Album",
                                      secondaryTypes: [], firstReleaseDate: "1982-11-25")

    /// The line under the card: the album when it isn't the one the player
    /// named, the year, the type — whichever are known.
    func testTheSummaryNamesTheAlbumOnlyWhenItDiffersFromThePlayers() {
        XCTAssertEqual(loveTrip.summary(playerAlbum: "LOVE TRIP", english: false), "1982 · album")
        XCTAssertEqual(loveTrip.summary(playerAlbum: "City Pop Essentials", english: false),
                       "LOVE TRIP · 1982 · album")
        XCTAssertEqual(loveTrip.summary(playerAlbum: nil, english: true), "LOVE TRIP · 1982 · album")
    }

    func testTheSummaryShowsTheDateAtItsPrecisionAndTheSecondaryType() {
        var facts = loveTrip
        facts.firstReleaseDate = "2026-09"
        facts.secondaryTypes = ["Compilation"]
        XCTAssertEqual(facts.summary(playerAlbum: "LOVE TRIP", english: false), "2026 · compilation")
        facts.firstReleaseDate = nil
        facts.primaryType = "Single"
        facts.secondaryTypes = []
        XCTAssertEqual(facts.summary(playerAlbum: "LOVE TRIP", english: true), "single")
        facts.primaryType = nil
        XCTAssertNil(facts.summary(playerAlbum: "LOVE TRIP", english: true))
    }

    /// Claude's block: one line per known fact, in French like every prompt,
    /// the source named so the system prompt's rule applies to it.
    func testThePromptBlockCarriesEveryKnownFactAndNoOther() {
        XCTAssertEqual(loveTrip.promptBlock, """
            <faits source="MusicBrainz">
            album d'origine : LOVE TRIP
            type : album
            première sortie : 1982-11-25
            </faits>
            """)
        var bare = loveTrip
        bare.albumTitle = nil
        bare.primaryType = nil
        bare.firstReleaseDate = "1982"
        XCTAssertEqual(bare.promptBlock, """
            <faits source="MusicBrainz">
            première sortie : 1982
            </faits>
            """)
    }
}
