import XCTest
@testable import Claudio

/// The sink is where the recognizer's own queues meet the panel's main actor.
/// Its promise is an ordering: exactly one terminal event leaves it, and
/// nothing leaves it afterwards — whatever the recognizer is still doing.
final class TranscriptSinkTests: XCTestCase {

    /// The plain case: the final ends the session, and a partial that arrives
    /// after it is dropped rather than shown on top of the text that was kept.
    func testAPartialAfterTheFinalNeverReachesTheStream() async {
        let (stream, continuation) = AsyncStream.makeStream(of: TranscriptEvent.self)
        let sink = TranscriptSink(continuation)

        sink.emitPartial("bon")
        sink.emitFinal("bonjour")
        sink.emitPartial("bonjour, je")  // the recognizer hadn't heard the stop yet

        let events = await describe(stream)
        XCTAssertEqual(events, ["partial:bon", "final:bonjour"])
    }

    /// Loudness rides the same stream as the words without being one: it
    /// never changes the text kept for the final, and nothing of it leaves
    /// once the session is over.
    func testLevelsPassThroughWithoutTouchingTheText() async {
        let (stream, continuation) = AsyncStream.makeStream(of: TranscriptEvent.self)
        let sink = TranscriptSink(continuation)

        sink.emitLevel(0.25)
        sink.emitPartial("bon")
        sink.emitLevel(0.75)
        XCTAssertEqual(sink.textSoFar, "bon")
        sink.emitFinal()
        sink.emitLevel(0.5)  // the tap hadn't heard the stop yet

        let events = await describe(stream)
        XCTAssertEqual(events, ["level:0.25", "partial:bon", "level:0.75", "final:bon"])
    }

    /// The same ordering under the interleaving that really happens: partials
    /// coming off other threads while this one closes the session. A partial
    /// may be lost — that is what a final means — but none may come out after
    /// it, which on screen is the text coming back after it was pasted.
    func testPartialsNeverOvertakeTheFinal() async {
        for round in 0..<24 {
            let events = await describe(sixVoicesAndAFinal())
            guard events.last == "final:bonjour" else {
                return XCTFail("round \(round): a partial came out after the final — \(events.suffix(3))")
            }
        }
    }

    /// One round of the race: six threads emitting partials as fast as they
    /// can, the final landing while they are hot, and nobody left running by
    /// the time the stream is read. Synchronous on purpose — waiting on real
    /// threads is what this needs, and an async test can't do it.
    private func sixVoicesAndAFinal() -> AsyncStream<TranscriptEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: TranscriptEvent.self)
        let sink = TranscriptSink(continuation)
        let voices = Tally()

        for voice in 0..<6 {
            Thread.detachNewThread {
                voices.increment()
                for word in 0..<300 { sink.emitPartial("v\(voice) w\(word)") }
                voices.decrement()
            }
        }
        while voices.started < 6 { Thread.sleep(forTimeInterval: 0.0002) }
        sink.emitFinal("bonjour")
        while voices.running > 0 { Thread.sleep(forTimeInterval: 0.0002) }
        return stream
    }

    /// A failure is terminal too: whatever the recognizer says next, the
    /// coordinator has already given up on this dictation.
    func testNothingFollowsAFailure() async {
        let (stream, continuation) = AsyncStream.makeStream(of: TranscriptEvent.self)
        let sink = TranscriptSink(continuation)

        sink.fail(.microphoneDenied)
        sink.emitPartial("bonjour")
        sink.emitFinal("bonjour")

        let events = await describe(stream)
        XCTAssertEqual(events, ["failed"])
    }

    /// Every event of a finished stream, as comparable strings. The stream
    /// always ends here: each test emits a terminal event, which is what
    /// finishes it.
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

/// How many voices have started, and how many are still talking. Just enough
/// shared state to let the final land in the middle of the noise.
private final class Tally: @unchecked Sendable {
    private let lock = NSLock()
    private var startedCount = 0
    private var runningCount = 0

    var started: Int { lock.withLock { startedCount } }
    var running: Int { lock.withLock { runningCount } }

    func increment() { lock.withLock { startedCount += 1; runningCount += 1 } }
    func decrement() { lock.withLock { runningCount -= 1 } }
}
