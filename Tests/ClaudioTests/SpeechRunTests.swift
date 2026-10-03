import XCTest
@testable import Claudio

/// A stop or a cancel can land while a dictation is still setting up, before
/// the microphone is on. What the run says at `adopt` decides what follows:
/// after a stop, the key is already up, and a microphone turned on then would
/// stay on for nobody; after a cancel, nothing may be left registered.
final class SpeechRunTests: XCTestCase {

    /// Nothing came during the setup: the microphone can open, and the stop
    /// that comes later runs the stop hook, once.
    func testARunLeftAloneGoesOnAndHearsItsStopOnce() {
        let run = SpeechRun(sink: TranscriptSink(AsyncStream.makeStream(of: TranscriptEvent.self).continuation))
        var stops = 0
        XCTAssertEqual(run.adopt(teardown: {}, onStop: { stops += 1 }), .running)
        XCTAssertEqual(stops, 0)

        run.requestStop()
        run.requestStop()
        XCTAssertEqual(stops, 1)
    }

    /// The bug: the key came up during the setup, the stop hook ran at once,
    /// and both paths turned the microphone on anyway. The run now says it
    /// is stopping, and the path ends there without opening anything.
    func testAStopDuringTheSetupKeepsTheMicrophoneOff() {
        let run = SpeechRun(sink: TranscriptSink(AsyncStream.makeStream(of: TranscriptEvent.self).continuation))
        run.requestStop()
        var stops = 0
        XCTAssertEqual(run.adopt(teardown: {}, onStop: { stops += 1 }), .stopping)
        XCTAssertEqual(stops, 0, "nothing is on yet for the stop hook to close")
    }

    /// Stopped during the setup, the run still holds its teardown: whatever
    /// the setup made is released on the way out.
    func testAStopDuringTheSetupStillReleasesWhatTheSetupMade() {
        let run = SpeechRun(sink: TranscriptSink(AsyncStream.makeStream(of: TranscriptEvent.self).continuation))
        run.requestStop()
        var teardowns = 0
        _ = run.adopt(teardown: { teardowns += 1 }, onStop: {})

        run.releaseResources()
        XCTAssertEqual(teardowns, 1)
    }

    /// Cancelled during the setup: nothing is registered, the caller undoes
    /// its own setup, and no hook of the cancelled run ever runs.
    func testACancelDuringTheSetupRegistersNothing() {
        let run = SpeechRun(sink: TranscriptSink(AsyncStream.makeStream(of: TranscriptEvent.self).continuation))
        run.requestCancel()
        var hooks = 0
        XCTAssertEqual(run.adopt(teardown: { hooks += 1 }, onStop: { hooks += 1 }), .cancelled)

        run.requestStop()
        run.releaseResources()
        XCTAssertEqual(hooks, 0)
    }

    /// A recognizer that gives up with an error ends the run as the run
    /// stands: on the words already heard once the key is up — a dictation
    /// is never lost — on nothing after a cancel, whose teardown caused the
    /// error, and on a failure otherwise.
    func testARecognizerErrorEndsTheRunAsTheRunStands() async {
        let error = URLError(.cancelled)

        let (stopped, stoppedSink) = AsyncStream.makeStream(of: TranscriptEvent.self)
        let stopping = SpeechRun(sink: TranscriptSink(stoppedSink))
        stopping.sink.emitPartial("bonjour")
        stopping.requestStop()
        stopping.recognizerEnded(with: error)
        let afterStop = await describe(stopped)
        XCTAssertEqual(afterStop, ["partial:bonjour", "final:bonjour"])

        let (cancelled, cancelledSink) = AsyncStream.makeStream(of: TranscriptEvent.self)
        let cancelling = SpeechRun(sink: TranscriptSink(cancelledSink))
        cancelling.requestCancel()
        cancelling.recognizerEnded(with: error)
        let afterCancel = await describe(cancelled)
        XCTAssertEqual(afterCancel, [])

        let (failed, failedSink) = AsyncStream.makeStream(of: TranscriptEvent.self)
        let running = SpeechRun(sink: TranscriptSink(failedSink))
        running.recognizerEnded(with: error)
        let otherwise = await describe(failed)
        XCTAssertEqual(otherwise, ["failed"])
    }

    /// Every event of a stream that has ended, as comparable strings.
    private func describe(_ stream: AsyncStream<TranscriptEvent>) async -> [String] {
        var described: [String] = []
        for await event in stream {
            switch event {
            case .partial(let text): described.append("partial:\(text)")
            case .final(let text): described.append("final:\(text)")
            case .failed: described.append("failed")
            case .level(let value): described.append("level:\(value)")
            }
        }
        return described
    }
}
