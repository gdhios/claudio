import Foundation

extension CorrectionSession.Phase {
    /// How long the panel stays on screen once it has nothing left to do,
    /// `nil` when it waits for the user instead. A shortcut fired on an empty
    /// selection used to leave its message in the middle of the screen until
    /// someone pressed Esc: nothing was being asked, and the window outlived
    /// what it had to say.
    ///
    /// The delay is the dictation's own "Nothing heard", for the same reason:
    /// a glance is enough, and the two kinds of panel should not drift apart.
    ///
    /// `instructionNotHeard` closes itself too, and isn't answered here: the
    /// coordinator that opened the microphone picks between a silence and a
    /// failure, a difference this cannot see. Answering would close it twice.
    func autoDismissDelay(
        _ durations: DictationCoordinator.MessageDurations = .standard
    ) -> Duration? {
        switch self {
        case .noSelection: durations.empty
        default: nil
        }
    }
}
