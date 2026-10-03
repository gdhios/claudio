import Foundation
@testable import Claudio

/// Replays a fixed list of events. The partials go out as soon as the engine
/// starts, as a real one does while the key is held; the final waits for
/// `stop()`, since it's the microphone closing that ends a session. A
/// failure doesn't wait for anything.
///
/// `@unchecked Sendable`: everything it does happens on the main actor.
final class FakeSpeechEngine: SpeechEngine, @unchecked Sendable {
    private let events: [TranscriptEvent]
    private var continuation: AsyncStream<TranscriptEvent>.Continuation?

    private(set) var starts = 0
    private(set) var stops = 0
    private(set) var cancels = 0
    private(set) var startedLocales: [Locale] = []
    /// The terms each start was biased towards, one list per start.
    private(set) var startedContextualStrings: [[String]] = []

    init(_ events: [TranscriptEvent]) { self.events = events }

    func start(locale: Locale, contextualStrings: [String]) -> AsyncStream<TranscriptEvent> {
        starts += 1
        startedLocales.append(locale)
        startedContextualStrings.append(contextualStrings)
        let (stream, continuation) = AsyncStream.makeStream(of: TranscriptEvent.self)
        self.continuation = continuation
        for event in events {
            switch event {
            case .partial, .level:
                continuation.yield(event)
            case .failed:
                continuation.yield(event)
                continuation.finish()
            case .final:
                break
            }
        }
        return stream
    }

    /// What the engine says later on, while the microphone is open: another
    /// partial, or an end it reaches by itself — a final, a failure.
    func say(_ event: TranscriptEvent) {
        continuation?.yield(event)
        switch event {
        case .final, .failed: continuation?.finish()
        case .partial, .level: break
        }
    }

    func stop() {
        stops += 1
        for case .final(let text) in events {
            continuation?.yield(.final(text))
        }
        continuation?.finish()
    }

    func cancel() {
        cancels += 1
        continuation?.finish()
    }
}
