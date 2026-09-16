import XCTest
@testable import Claudio

/// Whether something plays is read from what `osascript` printed. Only a
/// clear yes pauses anything: every other answer leaves the music alone, and
/// with it the resume that would follow a pause. Nothing here runs a script
/// or sends a command.
final class NowPlayingTests: XCTestCase {

    func testAClearYesIsPlaying() {
        XCTAssertTrue(NowPlaying.isPlaying(printed: "true\n"))
        XCTAssertTrue(NowPlaying.isPlaying(printed: "true"))
    }

    func testANoIsNotPlaying() {
        XCTAssertFalse(NowPlaying.isPlaying(printed: "false\n"))
    }

    /// A class or a flag this macOS doesn't have: the script prints nothing
    /// at all, and exits as if it had answered.
    func testNothingPrintedIsNotPlaying() {
        XCTAssertFalse(NowPlaying.isPlaying(printed: ""))
        XCTAssertFalse(NowPlaying.isPlaying(printed: "\n"))
    }

    /// Anything that doesn't read as the yes the script prints — an error
    /// message, a number, a value some later macOS returns instead — is
    /// taken for a no.
    func testAnAnswerThatDoesNotReadIsNotPlaying() {
        XCTAssertFalse(NowPlaying.isPlaying(printed: "execution error: Error: x (-2700)"))
        XCTAssertFalse(NowPlaying.isPlaying(printed: "1\n"))
        XCTAssertFalse(NowPlaying.isPlaying(printed: "undefined"))
        XCTAssertFalse(NowPlaying.isPlaying(printed: "true false"))
    }

    /// Only the flag is read: the script loads MediaRemote in `osascript`,
    /// asks, and has no way to send anything.
    func testTheScriptOnlyReadsTheFlag() {
        XCTAssertTrue(NowPlaying.script.contains("MRNowPlayingRequest"))
        XCTAssertTrue(NowPlaying.script.contains("localIsPlaying"))
        XCTAssertFalse(NowPlaying.script.contains("Command"))
    }

    /// MediaRemote's own numbers, which Claudio can't import: a wrong one
    /// sends another command. Never the toggle, which would start what was
    /// already paused.
    func testTheCommandsAreMediaRemotesPlayAndPause() {
        XCTAssertEqual(MediaRemoteCommand.play.rawValue, 0)
        XCTAssertEqual(MediaRemoteCommand.pause.rawValue, 1)
    }
}
