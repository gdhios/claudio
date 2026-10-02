import XCTest
@testable import Claudio

/// The cover the player itself knows: asked of Spotify alone, by the URL
/// its dictionary exposes, and read back from what `osascript` printed.
final class LocalArtworkTests: XCTestCase {

    /// Only Spotify is asked: it is the one player whose dictionary gives
    /// the cover's URL. Any other player, or none named, gets no script at
    /// all — not a script that would fail.
    func testOnlySpotifyIsAskedForItsCover() throws {
        let script = try XCTUnwrap(LocalArtwork.script(for: .sample))
        XCTAssertTrue(script.contains("Spotify"))
        XCTAssertTrue(script.contains("artworkUrl"))
        XCTAssertTrue(script.contains("running()"), "Spotify must not be launched to be asked")

        XCTAssertNil(LocalArtwork.script(for: NowPlayingTrack(title: "Clip", appName: "Safari",
                                                              bundleID: "com.apple.Safari")))
        XCTAssertNil(LocalArtwork.script(for: NowPlayingTrack(title: "Clip")))
    }

    /// What `osascript` printed, trimmed, is the URL — when it is one, and
    /// a secure one: an empty answer, "missing value" or a plain word give
    /// nothing rather than a request to nowhere.
    func testThePrintedURLReadsBack() {
        XCTAssertEqual(LocalArtwork.url(printed: "https://i.scdn.co/image/ab67616d0000b273d72de202\n"),
                       URL(string: "https://i.scdn.co/image/ab67616d0000b273d72de202"))
        XCTAssertNil(LocalArtwork.url(printed: ""))
        XCTAssertNil(LocalArtwork.url(printed: "\n"))
        XCTAssertNil(LocalArtwork.url(printed: "missing value\n"))
        XCTAssertNil(LocalArtwork.url(printed: "not a url"))
        XCTAssertNil(LocalArtwork.url(printed: "http://i.scdn.co/image/abc"), "only https is fetched")
    }
}

private extension NowPlayingTrack {
    static let sample = NowPlayingTrack(title: "真夜中のジョーク", artist: "間宮貴子", album: "LOVE TRIP",
                                        appName: "Spotify", bundleID: "com.spotify.client")
}
