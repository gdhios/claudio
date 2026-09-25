import XCTest
@testable import Claudio

/// The line under an answer that went out with the track playing names that
/// track the way "What's playing?" copies it: whether it shows at all is the
/// session's `sentTrack`, set from what was sent (`CorrectionCoordinatorTests`).
final class SentTrackLineTests: XCTestCase {

    func testTheLineNamesTheTrackAndItsArtist() {
        let track = NowPlayingTrack(title: "真夜中のジョーク", artist: "間宮貴子", album: "LOVE TRIP")
        XCTAssertEqual(SentTrackLine.text(for: track), "♪ 真夜中のジョーク — 間宮貴子")
    }

    /// No artist, no dash left hanging.
    func testATrackWithoutAnArtistIsNamedByItsTitleAlone() {
        XCTAssertEqual(SentTrackLine.text(for: NowPlayingTrack(title: "Some podcast episode")),
                       "♪ Some podcast episode")
    }
}
