import Foundation

/// Playback on this Mac, reduced to what a dictation needs of it: is
/// something playing, pause it, play it. Injected under `MediaPauser`, like
/// `MicrophoneGate`: a test scripts what plays and when the answer comes, and
/// nothing in a test ever reads or pauses the machine it runs on.
@MainActor
struct MediaPlayback {
    var isPlaying: @MainActor () async -> Bool
    var pause: @MainActor () -> Void
    var play: @MainActor () -> Void

    /// The state is read through Apple's `osascript`, which MediaRemote still
    /// answers; the commands go out from Claudio itself, which it still obeys.
    /// A preview never reads, so it never pauses anything either.
    static let system = MediaPlayback(
        isPlaying: { PreviewRun.isActive ? false : await NowPlaying.isPlaying() },
        pause: { MediaRemoteCommand.pause.send() },
        play: { MediaRemoteCommand.play.send() }
    )
}

/// The two commands Claudio sends to whatever is playing, under MediaRemote's
/// own numbers. Never the toggle: sent to something already paused it would
/// start it, and resuming only what Claudio paused is the whole promise.
enum MediaRemoteCommand: UInt32 {
    case play = 0   // kMRPlay
    case pause = 1  // kMRPause

    /// MediaRemote is a private framework: loaded by name, and a symbol it no
    /// longer has sends nothing rather than failing the dictation.
    @MainActor
    func send() {
        guard let send = Self.sendCommand else { return }
        _ = send(rawValue, nil)
    }

    private typealias SendCommand = @convention(c) (UInt32, CFDictionary?) -> DarwinBoolean

    @MainActor
    private static let sendCommand: SendCommand? = {
        guard let framework = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",
                                     RTLD_LAZY),
              let symbol = dlsym(framework, "MRMediaRemoteSendCommand") else { return nil }
        return unsafeBitCast(symbol, to: SendCommand.self)
    }()
}
