import Foundation
import XCTest
@testable import Claudio

/// What can be checked of the real engine without a microphone: the promises
/// it makes to the coordinator. Nothing here records anything — every case
/// is settled before the microphone would be opened, either by a permission
/// that isn't granted (a runner) or by a language that doesn't exist
/// (anywhere). That is the point: a dictation that can't happen must fail
/// fast, not hold the microphone open.
final class AppleSpeechEngineTests: XCTestCase {

    /// A language identifier no recognizer will ever know. It is what keeps
    /// these tests off the hardware: the run gives up before the audio.
    private let unknownLanguage = Locale(identifier: "zz-ZZ")

    /// The contract: an engine that can't start says so once, then ends.
    /// Not two events, not zero — the coordinator waits for exactly one.
    func testADictationThatCannotStartEndsWithASingleFailure() async {
        let engine = AppleSpeechEngine()
        let events = await drain(engine.start(locale: unknownLanguage))
        XCTAssertEqual(events.count, 1)
        guard case .failed = events.first else {
            return XCTFail("attendu un .failed, reçu \(String(describing: events.first))")
        }
    }

    /// `cancel()` promises a stream that ends with no further event. The
    /// stream ending at all is the half that matters: a consumer left
    /// suspended never releases the panel.
    func testCancelRightAfterStartEndsTheStream() async {
        let engine = AppleSpeechEngine()
        let stream = engine.start(locale: unknownLanguage)
        engine.cancel()
        for event in await drain(stream) {
            switch event {
            case .partial, .final:
                XCTFail("un cancel ne rend jamais de texte : \(event)")
            case .failed:
                break  // The run had already given up on the language.
            }
        }
    }

    /// Started twice without a stop: the first session goes. Whatever it
    /// had to say, its stream ends — the coordinator is already consuming
    /// the second one.
    func testStartingTwiceEndsTheFirstStream() async {
        let engine = AppleSpeechEngine()
        let first = engine.start(locale: unknownLanguage)
        let second = engine.start(locale: unknownLanguage)
        _ = await drain(first)
        _ = await drain(second)
    }

    /// `stop()` and `cancel()` on an engine that isn't listening are the
    /// normal case, not a programming error: the coordinator calls
    /// `dismiss()` before it knows whether anything was running.
    func testStopAndCancelWithoutAStartAreHarmless() async {
        let engine = AppleSpeechEngine()
        engine.stop()
        engine.cancel()
        engine.stop()
        let events = await drain(engine.start(locale: unknownLanguage))
        XCTAssertEqual(events.count, 1)
    }

    /// Collects a stream to its end, or fails the test rather than hanging
    /// the whole suite: "the stream always finishes" is what's under test,
    /// so it can't be assumed while testing it.
    private func drain(_ stream: AsyncStream<TranscriptEvent>,
                       timeout: Duration = .seconds(20),
                       file: StaticString = #filePath,
                       line: UInt = #line) async -> [TranscriptEvent] {
        let outcome: [TranscriptEvent]? = await withTaskGroup(of: [TranscriptEvent]?.self) { group in
            group.addTask {
                var events: [TranscriptEvent] = []
                for await event in stream { events.append(event) }
                return events
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard let outcome else {
            XCTFail("le flux ne s'est pas terminé : un consommateur reste suspendu.",
                    file: file, line: line)
            return []
        }
        return outcome
    }
}
