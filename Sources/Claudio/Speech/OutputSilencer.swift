/// Silencing the other apps while dictating, as the coordinator sees it.
/// Injected like `MicrophoneGate`: a test counts the calls, and nothing in a
/// test or a preview ever silences the machine it runs on.
@MainActor
struct OutputSilencer {
    var silence: @MainActor () -> Void
    var restore: @MainActor () -> Void

    static let system = OutputSilencer(silence: { SystemAudioMute.shared.silence() },
                                       restore: { SystemAudioMute.shared.restore() })
}
