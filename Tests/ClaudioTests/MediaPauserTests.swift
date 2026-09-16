import XCTest
@testable import Claudio

/// The pause's own promise, apart from any coordinator: one read, one pause,
/// one resume per listening, however many times it is told. The paths a
/// dictation or an instruction ends by are tested with their coordinators.
@MainActor
final class MediaPauserTests: XCTestCase {

    /// Told twice that a listening started, it doesn't read twice, nor pause
    /// twice — so it can't lose track of the pause it has to give back.
    func testASecondPauseForTheSameListeningChangesNothing() async {
        let media = FakeMediaPlayback()
        let pauser = MediaPauser(playback: media.playback)

        pauser.pause()
        await pauser.read?.value
        pauser.pause()
        await pauser.read?.value
        XCTAssertEqual(media.reads, 1)
        XCTAssertEqual(media.commands, [.pause])

        pauser.resume()
        pauser.resume()
        XCTAssertEqual(media.commands, [.pause, .play])
    }

    /// A resume with nothing paused sends nothing: that's every way out of a
    /// dictation that found nothing playing, or never looked.
    func testAResumeWithoutAPauseSendsNothing() {
        let media = FakeMediaPlayback()
        let pauser = MediaPauser(playback: media.playback)
        pauser.resume()
        XCTAssertEqual(media.reads, 0)
        XCTAssertEqual(media.commands, [])
    }
}
