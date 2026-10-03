import Foundation

/// How long a panel that has nothing left to do but speak stays on screen.
/// Injected so a test can watch one close itself without waiting four
/// seconds for it.
struct PanelMessageDurations: Sendable {
    /// "Nothing heard": a glance is enough.
    var empty: Duration = .milliseconds(1500)
    /// A failure: long enough to read a sentence and reach the button it
    /// may carry, short enough that the panel doesn't outlive the
    /// dictation. Esc and the next press still cut it short.
    var failure: Duration = .seconds(4)

    static let standard = PanelMessageDurations()
}

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
    func autoDismissDelay(_ durations: PanelMessageDurations) -> Duration? {
        switch self {
        case .noSelection: durations.empty
        default: nil
        }
    }
}
