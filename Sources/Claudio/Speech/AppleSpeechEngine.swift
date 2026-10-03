import Foundation
import Speech

/// Apple's dictation behind the `SpeechEngine` contract: `AVAudioEngine`
/// opens the microphone, Apple's recognizer turns it into text.
///
/// Two recognizers, one behaviour. On macOS 26, `SpeechAnalyzer` +
/// `SpeechTranscriber` (`SpeechRun+Analyzer.swift`); below it,
/// `SFSpeechRecognizer` forced on device (`SpeechRun+Legacy.swift`). Both
/// always emit the whole text of the session, never a delta, and both end
/// their stream exactly once.
///
/// Thread safety: `start`, `stop` and `cancel` come from the main actor
/// while the audio and recognition callbacks arrive on their own queues.
/// Everything mutable therefore lives behind a lock — in `SpeechRun` and
/// `TranscriptSink`; this class only remembers which run is current.
final class AppleSpeechEngine: SpeechEngine, @unchecked Sendable {
    /// How long a `stop()` waits for the recognizer's own final before
    /// settling for the last partial. A caller that hangs on a silent
    /// recognizer is worse than a dictation that ends one word short.
    static let finalTimeout: Duration = .seconds(2)
    /// How many vocabulary terms `SFSpeechRecognizer` is handed. Its header
    /// asks for no more than 100 contextual strings; the first ones typed
    /// are kept.
    static let contextualStringsLimit = 100

    private let lock = NSLock()
    private var current: SpeechRun?

    init() {}

    func start(locale: Locale, contextualStrings: [String]) -> AsyncStream<TranscriptEvent> {
        let (stream, continuation) = AsyncStream<TranscriptEvent>.makeStream()
        let run = SpeechRun(sink: TranscriptSink(continuation))

        lock.lock()
        let previous = current
        current = run
        lock.unlock()
        // Started twice without a stop: the first session goes, silently.
        previous?.requestCancel()

        Task { [weak self] in
            await run.drive(locale: locale, contextualStrings: contextualStrings)
            self?.forget(run)
        }
        return stream
    }

    func stop() { currentRun?.requestStop() }

    func cancel() {
        let run = takeCurrent()
        run?.requestCancel()
    }

    private var currentRun: SpeechRun? { lock.withLock { current } }

    private func takeCurrent() -> SpeechRun? {
        lock.lock()
        defer { lock.unlock() }
        let run = current
        current = nil
        return run
    }

    private func forget(_ run: SpeechRun) {
        lock.lock()
        if current === run { current = nil }
        lock.unlock()
    }
}

extension SpeechRun {
    /// The whole life of one dictation. Whatever happens — a refused
    /// permission, a missing language, a cancel, a recognizer that goes
    /// quiet — the microphone is released and the stream is finished.
    func drive(locale: Locale, contextualStrings: [String]) async {
        defer {
            releaseResources()
            sink.finishSilently()
        }
        // A preview renders a screen on any machine, including a runner
        // where nothing is listening: it never opens the microphone.
        if PreviewRun.isActive { return }
        if let missing = MicrophonePermission.missingAccess() {
            sink.fail(missing)
            return
        }
        if isCancelled { return }
        #if canImport(Speech) && compiler(>=6.2)
        // The macOS 26 path only compiles against an SDK that knows
        // `SpeechAnalyzer`, which shipped with the Swift 6.2 toolchain.
        if #available(macOS 26, *), SpeechTranscriber.isAvailable {
            await driveAnalyzer(locale: locale, contextualStrings: contextualStrings)
            return
        }
        #endif
        await driveLegacy(locale: locale, contextualStrings: contextualStrings)
    }
}
