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

    /// The whole text of the session so far — the best `.final` we could
    /// send if the recognizer never sends its own.
    var textSoFar: String { lock.withLock { latest } }

    /// True once a terminal event went out: nothing more will.
    var isFinished: Bool { lock.withLock { continuation == nil } }

    func emitPartial(_ text: String) {
        lock.lock()
        guard let continuation else { lock.unlock(); return }
        latest = text
        lock.unlock()
        continuation.yield(.partial(text))
    }

    /// Ends the session with its text. `nil` means "whatever we have":
    /// that is how a recognizer that goes quiet still gives back the words.
    func emitFinal(_ text: String? = nil) {
        lock.lock()
        guard let continuation else { lock.unlock(); return }
        let value = text ?? latest
        latest = value
        self.continuation = nil
        lock.unlock()
        continuation.yield(.final(value))
        continuation.finish()
    }

    func fail(_ error: SpeechEngineError) {
        lock.lock()
        guard let continuation else { lock.unlock(); return }
        self.continuation = nil
        lock.unlock()
        continuation.yield(.failed(error))
        continuation.finish()
    }

    /// Ends the stream with nothing more, which is what `cancel()` promises.
    /// Also the last word of every run: a stream that never finishes leaves
    /// its consumer suspended forever.
    func finishSilently() {
        lock.lock()
        guard let continuation else { lock.unlock(); return }
        self.continuation = nil
        lock.unlock()
        continuation.finish()
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
/// something to close.
final class SpeechRun: @unchecked Sendable {
    let sink: TranscriptSink
    private let lock = NSLock()
    private var cancelled = false
    private var stopping = false
    private var teardown: (() -> Void)?
    private var onStop: (() -> Void)?

    init(sink: TranscriptSink) { self.sink = sink }

    var isCancelled: Bool { lock.withLock { cancelled } }
    var isStopping: Bool { lock.withLock { stopping } }

    /// Registers what closing down means. Returns false when the run was
    /// already cancelled: the caller then undoes its own setup and gives up.
    func adopt(teardown: @escaping () -> Void, onStop: @escaping () -> Void) -> Bool {
        lock.lock()
        if cancelled {
            lock.unlock()
            return false
        }
        self.teardown = teardown
        self.onStop = onStop
        let alreadyStopping = stopping
        lock.unlock()
        // A `stop()` that arrived during the setup is honoured now.
        if alreadyStopping { onStop() }
        return true
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
}
