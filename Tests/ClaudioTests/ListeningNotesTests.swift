import XCTest
@testable import Claudio

/// What Claude is sent about the track. The metadata goes out tagged, one
/// line per field the player gave — a line for a field it didn't give would
/// read as "unknown", and invite a guess. The answer's language follows the
/// app's, which is passed in here rather than read from this Mac's settings.
final class ListeningNotesTests: XCTestCase {

    func testTheTrackGoesOutTaggedWithEveryFieldThePlayerGave() {
        let track = NowPlayingTrack(title: "真夜中のジョーク",
                                    artist: "間宮貴子",
                                    album: "LOVE TRIP",
                                    appName: "Spotify",
                                    bundleID: "com.spotify.client",
                                    isPlaying: false,
                                    duration: 245.3)
        XCTAssertEqual(ListeningNotes.userMessage(for: track), """
            <morceau>
            titre : 真夜中のジョーク
            artiste : 間宮貴子
            album : LOVE TRIP
            lecteur : Spotify
            </morceau>
            """)
    }

    /// No album line when there's no album, and no word about the pause,
    /// which changes nothing to what the track is.
    func testAFieldThePlayerDidNotGiveIsLeftOut() {
        let track = NowPlayingTrack(title: "Some podcast episode", appName: "Podcasts", isPlaying: false)
        XCTAssertEqual(ListeningNotes.userMessage(for: track), """
            <morceau>
            titre : Some podcast episode
            lecteur : Podcasts
            </morceau>
            """)
    }

    /// The prompt is written once, in French; only its last line changes,
    /// and it follows the interface language.
    func testTheAnswerLanguageFollowsTheAppLanguage() {
        let french = ListeningNotes.system(language: .french)
        let english = ListeningNotes.system(language: .english)
        XCTAssertTrue(french.hasSuffix("\n- Réponds en français."), french)
        XCTAssertTrue(english.hasSuffix("\n- Réponds en anglais."), english)
        XCTAssertEqual(french.dropLast("Réponds en français.".count),
                       english.dropLast("Réponds en anglais.".count))
        XCTAssertTrue(french.contains("<morceau>"))
    }
}
