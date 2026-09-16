import Foundation

/// Whether something is playing on this Mac, as MediaRemote itself says:
/// the flag the Now Playing controls in the menu bar show.
///
/// Since macOS 15.4 MediaRemote keeps that answer for Apple's own binaries:
/// asked from Claudio's process, every read says nothing is playing. Apple's
/// `osascript` still gets it, through its JavaScript bridge, in about a tenth
/// of a second and without asking for any permission.
///
/// Anything short of a clear yes in time — a script that fails or hangs, an
/// answer that doesn't read — counts as "not playing": nothing is paused, so
/// nothing is resumed either.
enum NowPlaying {
    /// Loads MediaRemote inside `osascript` and reads the flag. Prints `true`
    /// or `false`, and nothing at all on a macOS without the class or the flag.
    static let script = """
        ObjC.import('Foundation');
        $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/').load;
        $.NSClassFromString('MRNowPlayingRequest').localIsPlaying;
        """

    /// A read takes a tenth of a second. Past this one it is abandoned, and
    /// the pause that would have followed never comes.
    static let timeout: TimeInterval = 1

    /// Runs the script in a child process, on a queue of its own: neither the
    /// main actor nor the concurrency pool waits on it.
    static func isPlaying() async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runScript())
            }
        }
    }

    /// What the script printed, read. Pure, so it is tested without running
    /// anything.
    static func isPlaying(printed output: String) -> Bool {
        output.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    private static func runScript() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", script]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do { try process.run() } catch { return false }

        guard exited.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            return false
        }
        // A few bytes at most: the pipe can't fill up before the exit.
        let printed = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else { return false }
        return isPlaying(printed: String(decoding: printed, as: UTF8.self))
    }
}
