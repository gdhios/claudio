import Foundation

/// Runs a JavaScript for Automation script in Apple's own `osascript`.
///
/// Since macOS 15.4 MediaRemote only answers Apple's binaries: asked from
/// Claudio's process it says nothing is playing, and names no track. Asked
/// from `osascript`, through its Objective-C bridge, it answers in about a
/// tenth of a second, without any permission. Everything Claudio reads about
/// what plays goes through here.
enum JXAScript {
    /// What the script printed on standard output, `nil` when it couldn't
    /// start, failed, or was still running after `timeout` — it is then
    /// terminated, and whoever asked goes on without an answer.
    ///
    /// The child process is waited on in a queue of its own: neither the
    /// main actor nor the concurrency pool blocks on it.
    static func run(_ script: String, timeout: TimeInterval) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runBlocking(script, timeout: timeout))
            }
        }
    }

    private static func runBlocking(_ script: String, timeout: TimeInterval) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", script]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do { try process.run() } catch { return nil }

        guard exited.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            return nil
        }
        // A few hundred bytes at most: the pipe can't fill up before the exit.
        let printed = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else { return nil }
        return String(decoding: printed, as: UTF8.self)
    }
}
