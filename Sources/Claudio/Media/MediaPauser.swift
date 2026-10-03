/// Pausing whatever plays while Claudio listens, and giving back only what it
/// paused. A coordinator says when its microphone opens and when it closes;
/// the rest is decided here:
///
/// - the state is read on the side, so the microphone never waits for it;
/// - the pause only goes out for a listening still under way when the answer
///   comes — a tap, Esc or a failure can end one before that;
/// - the resume only goes out after a pause sent here, and only once, however
///   many ways out of a dictation end up calling it.
///
/// Injected like `MicrophoneGate`, on top of a `MediaPlayback`: a test scripts
/// what plays and when the answer comes, and nothing in a test or a preview
/// ever pauses the machine it runs on.
@MainActor
final class MediaPauser {
    private let playback: MediaPlayback
    /// The listening under way, from `pause()` to `resume()`. `nil` between
    /// two: a read that answers then has nothing left to pause for.
    private var listening: Listening?
    /// The latest listening's read. Nothing waits on it but a test.
    private(set) var read: Task<Void, Never>?

    init(playback: MediaPlayback = .system) {
        self.playback = playback
    }

    /// The microphone has opened: whatever plays is paused as soon as the
    /// state is known, if the listening is still under way by then. A
    /// listening already under way keeps its own read and its own pause.
    func pause() {
        guard listening == nil else { return }
        let listening = Listening()
        self.listening = listening
        read = Task { [weak self, playback] in
            let playing = await playback.isPlaying()
            // Answered after the end: the microphone this was for has closed,
            // and pausing now would leave the music off for nobody.
            guard playing, let self, self.listening === listening else { return }
            playback.pause()
            listening.pausedPlayback = true
        }
    }

    /// The microphone has closed, whichever way. Resumes what this listening
    /// paused and nothing else: music that wasn't playing when the microphone
    /// opened stays as it is. Idempotent.
    func resume() {
        guard let listening else { return }
        self.listening = nil
        if listening.pausedPlayback { playback.play() }
    }

    /// One listening, as the pause sees it: whether the pause the end has to
    /// give back went out.
    @MainActor
    private final class Listening {
        var pausedPlayback = false
    }
}
