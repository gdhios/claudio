import Foundation

/// The stream side of one dictation.
///
/// The recognizer answers on its own queues while the caller lives on the
/// main actor, so every mutation goes through the lock. The continuation is
/// dropped the moment the stream ends: whatever arrives afterwards is
/// ignored instead of speaking to a consumer that is gone, and only one
/// terminal event can ever escape.
final class TranscriptSink: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<TranscriptEvent>.Continuation?
    private var latest = ""

    init(_ continuation: AsyncStream<TranscriptEvent>.Continuation) {
        self.continuation = continuation
    }

    /// Yielded under the lock, unlike the terminal events below: `yield`
    /// never blocks, and outside the lock a partial held by another thread
    /// could slip in between the final's yield and the end of the stream —
    /// the panel showing again what it had just pasted.
    func emitPartial(_ text: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let continuation else { return }
        latest = text
        continuation.yield(.partial(text))
    }

    /// Loudness for the waveform, straight from the microphone's tap. Under
    /// the lock for the same reason as a partial, and without touching the
    /// text kept for the final.
    func emitLevel(_ level: Float) {
        lock.lock()
        defer { lock.unlock() }
        continuation?.yield(.level(level))
    }

    /// Ends the session with its text. `nil` means "whatever we have":
    /// that is how a recognizer that goes quiet still gives back the words.
    func emitFinal(_ text: String? = nil) {
        let (continuation, value) = lock.withLock { (takeContinuation(), text ?? latest) }
        guard let continuation else { return }
        continuation.yield(.final(value))
        continuation.finish()
    }

    func fail(_ error: SpeechEngineError) {
        guard let continuation = lock.withLock({ takeContinuation() }) else { return }
        continuation.yield(.failed(error))
        continuation.finish()
    }

    /// Ends the stream with nothing more, which is what `cancel()` promises.
    /// Also the last word of every run: a stream that never finishes leaves
    /// its consumer suspended forever.
    func finishSilently() {
        lock.withLock { takeContinuation() }?.finish()
    }

    /// The continuation, taken under the lock by whichever terminal event
    /// gets there first: the stream is that one's to end, and every event
    /// after it finds nothing to yield to.
    private func takeContinuation() -> AsyncStream<TranscriptEvent>.Continuation? {
        defer { continuation = nil }
        return continuation
    }
}

/// A one-shot gate. Whoever opens it resumes the waiter, once; opening it
/// twice, or opening it before anyone waits, is a no-op.
final class SpeechGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var opened = false

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if opened {
                lock.unlock()
                continuation.resume()
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
    }

    func open() {
        lock.lock()
        if opened { lock.unlock(); return }
        opened = true
        let waiting = continuation
        continuation = nil
        lock.unlock()
        waiting?.resume()
    }
}

/// One dictation, from `start` to the end of its stream.
///
/// `stop()` and `cancel()` can land at any moment, including before the
/// microphone is even open. They set a flag and run whatever teardown has
/// been registered so far; the driving task checks the flag at every step.
/// `adopt` is the meeting point of the two: under the same lock, a cancel
/// either happens before it — nothing was opened — or after it, and finds
/// something to close. A stop that happens before it finds nothing to close
/// either, and `adopt` says so: the microphone then never opens.
final class SpeechRun: @unchecked Sendable {
    /// Where a run stands once its setup is done, as `adopt` tells it.
    enum State {
        /// Nothing ended it during the setup: the microphone can open.
        case running
        /// `stop()` came during the setup. The key is already up and nothing
        /// was heard: the run ends on its final, and the microphone stays
        /// off — turned on now, it would stay on after the key.
        case stopping
        /// `cancel()` came during the setup: nothing was registered, and the
        /// caller undoes its own setup.
        case cancelled
    }

    let sink: TranscriptSink
    private let lock = NSLock()
    private var cancelled = false
    private var stopping = false
    private var teardown: (() -> Void)?
    private var onStop: (() -> Void)?

    init(sink: TranscriptSink) { self.sink = sink }

    var isCancelled: Bool { lock.withLock { cancelled } }
    var isStopping: Bool { lock.withLock { stopping } }

    /// Registers what closing down means, and says where the run stands:
    /// only a run still `.running` goes on to turn the microphone on.
    func adopt(teardown: @escaping () -> Void, onStop: @escaping () -> Void) -> State {
        lock.withLock {
            if cancelled { return .cancelled }
            self.teardown = teardown
            self.onStop = onStop
            return stopping ? .stopping : .running
        }
    }

    /// Closes the microphone and lets the recognizer have its last word.
    func requestStop() {
        lock.lock()
        if cancelled || stopping { lock.unlock(); return }
        stopping = true
        let hook = onStop
        lock.unlock()
        hook?()
    }

    /// Tears everything down and ends the stream with no further event.
    func requestCancel() {
        lock.lock()
        if cancelled { lock.unlock(); return }
        cancelled = true
        let hook = teardown
        teardown = nil
        onStop = nil
        lock.unlock()
        // The stream is closed first, on purpose: tearing down wakes the
        // recognizer with a cancellation error, and a closed stream is what
        // keeps that error from arriving as an event after a cancel.
        sink.finishSilently()
        hook?()
    }

    /// The run is over on its own terms: release the microphone.
    func releaseResources() {
        lock.lock()
        let hook = teardown
        teardown = nil
        onStop = nil
        lock.unlock()
        hook?()
    }

    // MARK: - The recognizer's last word

    /// The recognizer gave up with an error. A cancelled run says nothing
    /// more: the error is the one its own teardown caused. A run asked to
    /// stop still owes the words it already has — a dictation is never
    /// lost. Anything else is the dictation failing.
    func recognizerEnded(with error: Error) {
        if isCancelled { return }
        if isStopping {
            sink.emitFinal()
        } else {
            sink.fail(.recognizer(error.localizedDescription))
        }
    }

    /// Armed by a stop, for a recognizer that never sends its own final:
    /// past `AppleSpeechEngine.finalTimeout`, the last partial stands in for
    /// it and the run stops waiting.
    func armFinalWatchdog(_ gate: SpeechGate) {
        let sink = self.sink
        Task {
            try? await Task.sleep(for: AppleSpeechEngine.finalTimeout)
            sink.emitFinal()
            gate.open()
        }
    }
}
