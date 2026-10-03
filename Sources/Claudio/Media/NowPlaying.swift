import Foundation

/// Whether something is playing on this Mac, as MediaRemote itself says:
/// the flag the Now Playing controls in the menu bar show.
///
/// Since macOS 15.4 MediaRemote keeps that answer for Apple's own binaries:
/// asked from Claudio's process, every read says nothing is playing. Apple's
/// `osascript` still gets it (`JXAScript`), in about a tenth of a second and
/// without asking for any permission.
///
/// Anything short of a clear yes in time — a script that fails or hangs, an
/// answer that doesn't read — counts as "not playing": nothing is paused, so
/// nothing is resumed either.
enum NowPlaying {
    /// Loads MediaRemote inside `osascript` and reads the flag. Prints `true`
    /// or `false`, and nothing at all on a macOS without the class or the flag.
    ///
    /// Only the flag, and not the whole track "What's playing?" reads: this
    /// one sits on the way into every dictation, and the less it asks, the
    /// less there is to go wrong there.
    static let script = """
        \(MediaRemote.jxaPrelude)
        $.NSClassFromString('MRNowPlayingRequest').localIsPlaying;
        """

    /// A read takes a tenth of a second. Past this one it is abandoned, and
    /// the pause that would have followed never comes.
    static let timeout: TimeInterval = 1

    static func isPlaying() async -> Bool {
        guard let printed = await JXAScript.run(script, timeout: timeout) else { return false }
        return isPlaying(printed: printed)
    }

    /// What the script printed, read. Pure, so it is tested without running
    /// anything.
    static func isPlaying(printed output: String) -> Bool {
        output.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }
}
