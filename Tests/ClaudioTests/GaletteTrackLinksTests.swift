import AppKit
import XCTest
@testable import Claudio

/// Which Galette buttons a track gets, and for what names. A wrong button is
/// worse than none: it opens Galette on someone the track has nothing to do
/// with. Hence the browser's rule — a video's "artist" is the channel that
/// posted it.
final class GaletteTrackLinksTests: XCTestCase {

    // MARK: - An app's track

    func testAnAppTrackGetsTheArtistThenTheAlbum() {
        XCTAssertEqual(GaletteLink.links(for: .sample, playerIsBrowser: false),
                       [.artist(name: "間宮貴子"), .album(artist: "間宮貴子", title: "LOVE TRIP")])
    }

    func testAlbumOnlyShowsWhenTheAlbumIsKnown() {
        var track = NowPlayingTrack.sample
        track.album = nil
        XCTAssertEqual(GaletteLink.links(for: track, playerIsBrowser: false), [.artist(name: "間宮貴子")])
    }

    /// An album link needs its artist too: without one, nothing opens.
    func testWithoutAnArtistNoButtonShows() {
        var track = NowPlayingTrack.sample
        track.artist = nil
        XCTAssertEqual(GaletteLink.links(for: track, playerIsBrowser: false), [])
    }

    /// Names go as the player gives them: « Earth, Wind & Fire » is one
    /// artist, not three.
    func testANameGoesWholeNeverSplit() {
        let track = NowPlayingTrack(title: "September", artist: "Earth, Wind & Fire",
                                    album: "The Best of Earth, Wind & Fire, Vol. 1",
                                    appName: "Music", bundleID: "com.apple.Music")
        XCTAssertEqual(GaletteLink.links(for: track, playerIsBrowser: false),
                       [.artist(name: "Earth, Wind & Fire"),
                        .album(artist: "Earth, Wind & Fire", title: "The Best of Earth, Wind & Fire, Vol. 1")])
    }

    /// An app gives real metadata: a dash in its title is part of the title.
    func testAnAppTrackNeverTakesItsArtistFromTheTitle() {
        var track = NowPlayingTrack.youTubeInZen
        track.appName = "Music"
        track.bundleID = "com.apple.Music"
        XCTAssertEqual(GaletteLink.links(for: track, playerIsBrowser: false), [.artist(name: "HK Disco Club")])
    }

    // MARK: - A browser's track

    /// A site that sets an album — Spotify's web player, YouTube Music,
    /// Bandcamp — sets real metadata: its track reads like an app's.
    func testABrowserTrackWithAnAlbumReadsLikeAnAppTrack() {
        let track = NowPlayingTrack(title: "Around the World", artist: "Daft Punk", album: "Homework",
                                    appName: "Safari", bundleID: "com.apple.Safari")
        XCTAssertEqual(GaletteLink.links(for: track, playerIsBrowser: true),
                       [.artist(name: "Daft Punk"), .album(artist: "Daft Punk", title: "Homework")])
    }

    /// A real case: a YouTube video played in Zen, the channel given as the
    /// artist. The one button names the band in the title.
    func testABrowserTrackWithoutAnAlbumTakesItsArtistFromTheTitle() {
        XCTAssertEqual(GaletteLink.links(for: .youTubeInZen, playerIsBrowser: true),
                       [.artist(name: "The Chemical Brothers")])
    }

    /// The channel is never offered in the artist's place.
    func testABrowserTrackWithoutAnAlbumOrAnArtistInItsTitleGetsNoButton() {
        let track = NowPlayingTrack(title: "Brothers Gonna Work It Out (Full Album)",
                                    artist: "HK Disco Club", appName: "Zen", bundleID: "app.zen-browser.zen")
        XCTAssertEqual(GaletteLink.links(for: track, playerIsBrowser: true), [])
    }

    /// A player is a browser when its bundle id is among the apps that open
    /// `https://` links, as found with Galette: no list of browsers to keep.
    func testAPlayerIsABrowserWhenItOpensWebLinks() {
        let galette = GaletteApp(icon: NSImage(), browsers: ["app.zen-browser.zen", "com.apple.Safari"])
        XCTAssertEqual(galette.links(for: .youTubeInZen), [.artist(name: "The Chemical Brothers")])

        var elsewhere = NowPlayingTrack.youTubeInZen
        elsewhere.bundleID = "com.example.player"
        XCTAssertEqual(galette.links(for: elsewhere), [.artist(name: "HK Disco Club")])
    }

    // MARK: - The artist in a title

    func testAnEnDashSplitsTheTitle() {
        XCTAssertEqual(GaletteLink.artistName(inTitle: "The Chemical Brothers – Brothers Gonna Work It Out (Full Album)"),
                       "The Chemical Brothers")
    }

    func testAnEmDashSplitsTheTitle() {
        XCTAssertEqual(GaletteLink.artistName(inTitle: "Nina Simone — Feeling Good"), "Nina Simone")
    }

    func testASpacedHyphenSplitsTheTitle() {
        XCTAssertEqual(GaletteLink.artistName(inTitle: "Daft Punk - Around the World"), "Daft Punk")
    }

    /// A hyphen with no space on each side is inside a name, not between two.
    func testAHyphenInsideAWordIsLeftAlone() {
        XCTAssertEqual(GaletteLink.artistName(inTitle: "Jay-Z - 99 Problems"), "Jay-Z")
        XCTAssertNil(GaletteLink.artistName(inTitle: "Lo-fi beats to study to"))
    }

    func testATitleWithoutASeparatorNamesNoArtist() {
        XCTAssertNil(GaletteLink.artistName(inTitle: "Brothers Gonna Work It Out"))
    }

    /// The first separator cuts: what comes after it may hold more dashes.
    func testTheFirstSeparatorCuts() {
        XCTAssertEqual(GaletteLink.artistName(inTitle: "Air - Moon Safari – Full Album"), "Air")
    }

    /// A dash with nothing on one side is no « Artist – Title ».
    func testADashWithNothingOnOneSideNamesNoArtist() {
        XCTAssertNil(GaletteLink.artistName(inTitle: "– Intro"))
        XCTAssertNil(GaletteLink.artistName(inTitle: "Outro –"))
    }
}

private extension NowPlayingTrack {
    static let youTubeInZen = NowPlayingTrack(title: "The Chemical Brothers – Brothers Gonna Work It Out (Full Album)",
                                              artist: "HK Disco Club",
                                              appName: "Zen", bundleID: "app.zen-browser.zen")
}
