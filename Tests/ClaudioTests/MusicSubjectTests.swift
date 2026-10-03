import XCTest
@testable import Claudio

/// What "Tell me more" is about: the track, its album or its artist, built
/// from the card and its facts; or an album or an artist read from a
/// `claudio://music` link.
final class MusicSubjectTests: XCTestCase {

    private let track = NowPlayingTrack(title: "真夜中のジョーク", artist: "間宮貴子",
                                        album: "City Pop Essentials", appName: "Spotify")
    private let facts = TrackFacts(recordingID: "783dfef9", releaseGroupID: "3b03f2df-1fc0",
                                   albumTitle: "LOVE TRIP", primaryType: "Album",
                                   secondaryTypes: [], firstReleaseDate: "1982-11-25",
                                   artistID: "c3a2c5d6-1")

    /// The album is the one of origin when MusicBrainz said, the player's
    /// otherwise; without any album, or any artist, there is no subject.
    func testTheAlbumSubjectPrefersTheFacts() {
        let subject = MusicSubject.album(of: track, facts: facts)
        XCTAssertEqual(subject, MusicSubject(kind: .album, artist: "間宮貴子", title: "LOVE TRIP",
                                             mbid: "3b03f2df-1fc0", firstReleaseDate: "1982-11-25", type: "Album",
                                             artistID: "c3a2c5d6-1", track: "真夜中のジョーク"))
        XCTAssertEqual(MusicSubject.album(of: track, facts: nil)?.title, "City Pop Essentials")
        XCTAssertNil(MusicSubject.album(of: NowPlayingTrack(title: "Clip", artist: "X"), facts: nil))
        XCTAssertNil(MusicSubject.album(of: NowPlayingTrack(title: "Clip", album: "A"), facts: nil))
    }

    func testTheArtistSubjectNeedsAnArtist() {
        XCTAssertEqual(MusicSubject.artist(of: track),
                       MusicSubject(kind: .artist, artist: "間宮貴子", track: "真夜中のジョーク"))
        XCTAssertEqual(MusicSubject.artist(of: track, facts: facts),
                       MusicSubject(kind: .artist, artist: "間宮貴子", artistID: "c3a2c5d6-1", track: "真夜中のジョーク"))
        XCTAssertNil(MusicSubject.artist(of: NowPlayingTrack(title: "Clip")))
    }

    /// The track itself, first of the subjects: Claude knows a title where
    /// an album means little. It carries the album and its facts as
    /// context, and needs a title and an artist.
    func testTheTrackSubjectIsTheTitlePlaying() {
        useLanguage(.french)
        XCTAssertEqual(MusicSubject.track(of: track, facts: facts),
                       MusicSubject(kind: .track, artist: "間宮貴子", title: "LOVE TRIP",
                                    mbid: "3b03f2df-1fc0", firstReleaseDate: "1982-11-25", type: "Album",
                                    artistID: "c3a2c5d6-1", track: "真夜中のジョーク"))
        XCTAssertEqual(MusicSubject.track(of: track, facts: nil)?.title, "City Pop Essentials")
        XCTAssertNil(MusicSubject.track(of: NowPlayingTrack(title: "Clip"), facts: nil))
        let subject = MusicSubject.track(of: track, facts: facts)!
        XCTAssertEqual(subject.buttonTitle, "Sur le morceau")
        XCTAssertEqual(subject.searchTitle, "Le morceau")
        XCTAssertEqual(subject.card, NowPlayingTrack(title: "真夜中のジョーク", artist: "間宮貴子",
                                                     album: "LOVE TRIP", appName: "Galette"))
        XCTAssertNil(subject.facts)
    }

    /// The card offers the track first, then its album, then its artist.
    @MainActor
    func testTheSubjectsStartWithTheTrack() {
        let session = ListeningSession()
        session.track = track
        session.facts = facts
        XCTAssertEqual(session.subjects.map(\.kind), [.track, .album, .artist])
        XCTAssertEqual(session.subjects.map(\.track), Array(repeating: "真夜中のジョーク", count: 3))
    }

    /// The artist's MusicBrainz id, wherever the subject got it: the
    /// recording search, or a link that names the artist.
    func testTheArtistsIDComesFromTheFactsOrFromTheLink() {
        XCTAssertEqual(MusicSubject(kind: .artist, artist: "X", mbid: "a1").artistMBID, "a1")
        XCTAssertEqual(MusicSubject(kind: .album, artist: "X", title: "T", mbid: "rg1", artistID: "a1").artistMBID, "a1")
        XCTAssertNil(MusicSubject(kind: .album, artist: "X", title: "T", mbid: "rg1").artistMBID)
    }

    /// The card a link opens on: the album over its artist, or the artist
    /// alone, from Galette.
    func testTheCardOfASubject() {
        let album = MusicSubject(kind: .album, artist: "間宮貴子", title: "LOVE TRIP")
        XCTAssertEqual(album.card, NowPlayingTrack(title: "LOVE TRIP", artist: "間宮貴子", appName: "Galette"))
        let artist = MusicSubject(kind: .artist, artist: "間宮貴子")
        XCTAssertEqual(artist.card, NowPlayingTrack(title: "間宮貴子", appName: "Galette"))
    }

    /// The track playing opens every block built from the card, so Claude
    /// anchors the album's or the artist's text on it; a track subject is
    /// its own genre.
    func testTheTrackPlayingOpensTheBlock() {
        let album = MusicSubject.album(of: track, facts: nil)!
        XCTAssertTrue(album.promptBlock.hasPrefix("<sujet genre=\"album\">\nmorceau : 真夜中のジョーク\nartiste : 間宮貴子\n"), album.promptBlock)
        let subject = MusicSubject.track(of: track, facts: facts)!
        XCTAssertTrue(subject.promptBlock.hasPrefix("<sujet genre=\"morceau\">\nmorceau : 真夜中のジョーク\nartiste : 間宮貴子\nalbum : LOVE TRIP\n"), subject.promptBlock)
    }

    /// Claude's block: the facts in hand, and only them.
    func testThePromptBlockCarriesTheFactsInHand() {
        let subject = MusicSubject(kind: .album, artist: "間宮貴子", title: "LOVE TRIP",
                                   mbid: "3b03f2df-1fc0", firstReleaseDate: "1982-11-25", type: "Album",
                                   label: "Columbia", country: "JP")
        XCTAssertEqual(subject.promptBlock, """
            <sujet genre="album">
            artiste : 間宮貴子
            album : LOVE TRIP
            première sortie : 1982-11-25
            type : album
            label : Columbia
            pays : JP
            mbid : 3b03f2df-1fc0
            </sujet>
            """)
        XCTAssertEqual(MusicSubject(kind: .artist, artist: "間宮貴子").promptBlock, """
            <sujet genre="artiste">
            artiste : 間宮貴子
            </sujet>
            """)
    }
}
