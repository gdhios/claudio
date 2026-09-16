import Foundation
@testable import Claudio

/// What plays on the Mac, as a test scripts it: whether something is
/// playing, whether the read answers at once or only when told to, and every
/// command sent back. Nothing here reads or pauses the real thing.
@MainActor
final class FakeMediaPlayback {
    enum Command: Equatable { case pause, play }

    /// What every read answers.
    var playing: Bool
    /// Reads wait for `answerRead()` instead of answering at once: that's
    /// the state still being read when the listening ends.
    let readsWait: Bool
    /// How many times the state was read: zero proves nothing was asked.
    private(set) var reads = 0
    /// Every command, in the order it was sent.
    private(set) var commands: [Command] = []
    /// How many times the microphone had closed each time playback was
    /// resumed: it must already have closed once.
    private(set) var microphoneClosesAtResume: [Int] = []
    /// Read on every resume, for the list above.
    var microphoneCloses: @MainActor () -> Int = { 0 }

    private var waitingReads: [CheckedContinuation<Bool, Never>] = []

    init(playing: Bool = true, readsWait: Bool = false) {
        self.playing = playing
        self.readsWait = readsWait
    }

    /// A pause nothing has resumed yet: the music left off.
    var leftPaused: Bool { commands.last == .pause }

    var playback: MediaPlayback {
        MediaPlayback(
            isPlaying: { [self] in
                reads += 1
                guard readsWait else { return playing }
                return await withCheckedContinuation { waitingReads.append($0) }
            },
            pause: { [self] in commands.append(.pause) },
            play: { [self] in
                commands.append(.play)
                microphoneClosesAtResume.append(microphoneCloses())
            }
        )
    }

    /// Answers the oldest read still waiting, with what plays now.
    func answerRead() {
        guard !waitingReads.isEmpty else { return }
        waitingReads.removeFirst().resume(returning: playing)
    }
}
