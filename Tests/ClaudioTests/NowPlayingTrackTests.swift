import XCTest
@testable import Claudio

/// What "What's playing?" knows about the track comes from what `osascript`
/// printed: a JSON object whose missing fields are simply absent. A track
/// only exists when it has a title — anything else is "nothing playing", and
/// the panel says so instead of showing an empty card. Nothing here runs a
/// script.
final class NowPlayingTrackTests: XCTestCase {

    /// Everything the script reads, the way Spotify gives it.
    func testAFullReadGivesEveryField() throws {
        let track = try XCTUnwrap(NowPlayingTrack(printed: """
            {"title":"真夜中のジョーク","artist":"間宮貴子","album":"LOVE TRIP",\
            "duration":245.3,"playing":true,"app":"Spotify","bundle":"com.spotify.client"}

            """))
        XCTAssertEqual(track, NowPlayingTrack(title: "真夜中のジョーク",
                                              artist: "間宮貴子",
                                              album: "LOVE TRIP",
                                              appName: "Spotify",
                                              bundleID: "com.spotify.client",
                                              isPlaying: true,
                                              duration: 245.3))
        // Equality is the track's: what the player is doing is read apart.
        XCTAssertEqual(track.appName, "Spotify")
        XCTAssertTrue(track.isPlaying)
        XCTAssertEqual(track.duration, 245.3)
    }

    /// Paused, the track is still the one the Now Playing widget shows: the
    /// panel answers anyway, and its card says it's paused.
    func testAPausedTrackIsStillATrack() throws {
        let track = try XCTUnwrap(NowPlayingTrack(printed: """
            {"title":"Rainy Night Lady","artist":"RA MU","playing":false,"app":"Spotify"}
            """))
        XCTAssertEqual(track.title, "Rainy Night Lady")
        XCTAssertFalse(track.isPlaying)
    }

    /// A player that names nothing but the title still makes a track. The
    /// card only claims "paused" when the player says so.
    func testATitleAloneIsEnough() throws {
        let track = try XCTUnwrap(NowPlayingTrack(printed: #"{"title":"Some podcast episode"}"#))
        XCTAssertEqual(track, NowPlayingTrack(title: "Some podcast episode",
                                              artist: nil,
                                              album: nil,
                                              appName: nil,
                                              bundleID: nil,
                                              isPlaying: true,
                                              duration: nil))
        XCTAssertNil(track.appName)
        XCTAssertTrue(track.isPlaying)
        XCTAssertNil(track.duration)
    }

    /// No title, nothing playing — even when a player is known: an app that
    /// played something once stays the Now Playing client with nothing in it.
    /// The way back to the player: its name on the button when macOS gave
    /// the app behind the track, nothing for a card from a link.
    func testThePlayerIsNamedWhenMacOSGaveTheApp() {
        let spotify = NowPlayingTrack(title: "Bleu", artist: "Lescop", appName: "Spotify", bundleID: "com.spotify.client")
        XCTAssertEqual(spotify.playerName, "Spotify")
        XCTAssertNil(NowPlayingTrack(title: "LOVE TRIP", artist: "間宮貴子", appName: "Galette").playerName)
        XCTAssertNil(NowPlayingTrack(title: "Bleu", bundleID: "com.spotify.client").playerName)
    }

    func testNoTitleMeansNothingPlaying() {
        XCTAssertNil(NowPlayingTrack(printed: #"{"playing":false,"app":"Music"}"#))
        XCTAssertNil(NowPlayingTrack(printed: #"{"title":"","artist":"RA MU","app":"Spotify"}"#))
        XCTAssertNil(NowPlayingTrack(printed: #"{"title":"  \n","app":"Safari"}"#))
    }

    /// Whatever doesn't read as the object the script prints — nothing at
    /// all, an error, something a later macOS answers instead — is nothing
    /// playing rather than a card full of holes.
    func testAnOutputThatDoesNotReadIsNothingPlaying() {
        for printed in ["", "\n", "undefined", "null", "[]", "{", "true",
                        "execution error: Error: TypeError: undefined is not an object (-2700)"] {
            XCTAssertNil(NowPlayingTrack(printed: printed), printed)
        }
    }

    /// Paused or playing, it is the same track: "Try again" after a pause
    /// keeps the card's cover and facts. Another title, artist, album or
    /// player is another track.
    func testAPausedTrackIsTheSameTrack() {
        let playing = NowPlayingTrack(title: "Bleu", artist: "Lescop", album: "Rêve parti",
                                      appName: "Spotify", bundleID: "com.spotify.client")
        var paused = playing
        paused.isPlaying = false
        XCTAssertEqual(playing, paused)

        for other in [NowPlayingTrack(title: "Ljubljana", artist: "Lescop", album: "Rêve parti",
                                      appName: "Spotify", bundleID: "com.spotify.client"),
                      NowPlayingTrack(title: "Bleu", artist: "Bleu", album: "Rêve parti",
                                      appName: "Spotify", bundleID: "com.spotify.client"),
                      NowPlayingTrack(title: "Bleu", artist: "Lescop", album: "Live",
                                      appName: "Spotify", bundleID: "com.spotify.client"),
                      NowPlayingTrack(title: "Bleu", artist: "Lescop", album: "Rêve parti",
                                      appName: "Music", bundleID: "com.apple.Music")] {
            XCTAssertNotEqual(playing, other)
        }
    }

    /// ⌘C copies the track the way one would write it to someone.
    func testTheCopyLineIsTheTitleThenTheArtist() {
        let track = NowPlayingTrack(title: "真夜中のジョーク", artist: "間宮貴子", isPlaying: true)
        XCTAssertEqual(track.copyLine, "真夜中のジョーク — 間宮貴子")
    }

    func testWithoutAnArtistTheCopyLineIsTheTitle() {
        let track = NowPlayingTrack(title: "Some podcast episode", artist: nil, isPlaying: false)
        XCTAssertEqual(track.copyLine, "Some podcast episode")
    }
}
