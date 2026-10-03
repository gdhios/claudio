import XCTest
@testable import Claudio

/// Deezer, behind MusicBrainz: a community base lags on new releases,
/// Deezer's public API has them the day they come out. Asked only when
/// MusicBrainz had nothing and the player named the album. The answers
/// are captures of 2026-10-03 on "Holding Space" by Benjamin Adamson,
/// released three days earlier and unknown to MusicBrainz.
final class DeezerLookupTests: XCTestCase {

    func testTheAlbumIsSearchedByArtistAndTitle() {
        let url = DeezerLookup.albumSearchURL(artist: "Benjamin Adamson", album: "Holding \"Space\"")
        XCTAssertEqual(url.host, "api.deezer.com")
        XCTAssertEqual(url.path, "/search/album")
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(query.first { $0.name == "q" }?.value, #"artist:"Benjamin Adamson" album:"Holding Space""#)
        XCTAssertEqual(query.first { $0.name == "limit" }?.value, "5")
    }

    func testTheAlbumIsLookedUpByID() {
        XCTAssertEqual(DeezerLookup.albumURL(id: 1001749391).absoluteString, "https://api.deezer.com/album/1001749391")
    }

    /// The first album by the artist asked for; a single under the same
    /// name doesn't come first.
    func testTheSearchGivesTheAlbumsID() {
        XCTAssertEqual(DeezerLookup.parseAlbumSearch(Self.search, artist: "Benjamin Adamson"), 1001749391)
        XCTAssertEqual(DeezerLookup.parseAlbumSearch(Self.search, artist: "Someone Else"), nil)
        XCTAssertNil(DeezerLookup.parseAlbumSearch(#"{"data":[],"total":0}"#, artist: "X"))
        XCTAssertNil(DeezerLookup.parseAlbumSearch("oops", artist: "X"))
    }

    /// The album's record: the facts the card shows, marked as Deezer's.
    func testTheAlbumGivesTheFacts() throws {
        let facts = try XCTUnwrap(DeezerLookup.parseAlbum(Self.album))
        XCTAssertEqual(facts.albumTitle, "Holding Space")
        XCTAssertEqual(facts.primaryType, "Album")
        XCTAssertEqual(facts.secondaryTypes, [])
        XCTAssertEqual(facts.firstReleaseDate, "2026-09-30")
        XCTAssertEqual(facts.origin, .deezer)
        XCTAssertNil(facts.releaseGroupID, "no cover from the archive without a release group")
        XCTAssertEqual(facts.summary(playerAlbum: "Holding Space", english: false), "2026 · album")
        XCTAssertTrue(facts.promptBlock.hasPrefix("<faits source=\"Deezer\">"), facts.promptBlock)
        XCTAssertNil(DeezerLookup.parseAlbum("oops"))
    }

    /// Deezer's record types, in MusicBrainz's words: the card speaks one
    /// language.
    func testTheRecordTypesAreMusicBrainzs() {
        func type(_ record: String) -> (String?, [String]) {
            let json = Self.album.replacingOccurrences(of: #""record_type":"album""#, with: #""record_type":"\#(record)""#)
            let facts = DeezerLookup.parseAlbum(json)!
            return (facts.primaryType, facts.secondaryTypes)
        }
        XCTAssertEqual(type("single").0, "Single")
        XCTAssertEqual(type("ep").0, "EP")
        XCTAssertEqual(type("compile").0, "Album")
        XCTAssertEqual(type("compile").1, ["Compilation"])
    }

    // MARK: - Captures

    static let search = """
        {"data":[{"id":1001749391,"title":"Holding Space","link":"https://www.deezer.com/album/1001749391","cover_medium":"https://cdn-images.dzcdn.net/images/cover/de18445a690dfc79df81438a77ddadca/250x250-000000-80-0-0.jpg","nb_tracks":5,"record_type":"album","explicit_lyrics":false,"artist":{"id":12703773,"name":"Benjamin Adamson","link":"https://www.deezer.com/artist/12703773","type":"artist"},"type":"album"},{"id":1046094912,"title":"Holding Space","link":"https://www.deezer.com/album/1046094912","nb_tracks":1,"record_type":"single","explicit_lyrics":false,"artist":{"id":12703773,"name":"Benjamin Adamson","type":"artist"},"type":"album"}],"total":2}
        """

    static let album = """
        {"id":1001749391,"title":"Holding Space","upc":"883306797047","link":"https://www.deezer.com/album/1001749391","cover_medium":"https://cdn-images.dzcdn.net/images/cover/de18445a690dfc79df81438a77ddadca/250x250-000000-80-0-0.jpg","label":"Madd Galaxy Records","nb_tracks":5,"release_date":"2026-09-30","record_type":"album","available":true,"artist":{"id":12703773,"name":"Benjamin Adamson","type":"artist"},"type":"album"}
        """
}
