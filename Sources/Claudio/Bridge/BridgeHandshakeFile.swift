import Foundation
import Security

/// Where the plugin learns how to reach Claudio: a small JSON file naming
/// the port the bridge listens on and the token it expects. The port is
/// ephemeral and the token is new at every start, so nothing about the
/// bridge can be guessed — it has to be read here.
///
/// Which makes the file's permissions the whole of the security: 0600, so
/// only the account running Claudio can read the token that drives it.
///
/// The Claude Code hub publishes its own door the same way, under its own
/// name: the same four keys, read by its hook relay.
struct BridgeHandshakeFile {
    /// The Stream Deck plugin's file.
    static let streamDeckName = "streamdeck-bridge.json"

    /// Claudio's own Application Support folder, which may not exist yet.
    /// Injectable so the tests write to a temporary one.
    let directory: URL
    /// The name is a contract: whoever reads the file looks it up by path,
    /// having no way to ask where it is.
    let name: String

    init(directory: URL = BridgeHandshakeFile.defaultDirectory,
         name: String = BridgeHandshakeFile.streamDeckName) {
        self.directory = directory
        self.name = name
    }

    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claudio")
    }

    var url: URL { directory.appendingPathComponent(name) }

    /// 32 random bytes in hex. Lowercase, so both sides compare the same
    /// string, and long enough that the socket is protected by the file's
    /// permissions rather than by luck.
    static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        if SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) != errSecSuccess {
            // Not seen in practice. The system generator is a CSPRNG on
            // Apple platforms too, and taking the whole app down over this
            // would be worse than the bridge it protects.
            bytes = (0..<bytes.count).map { _ in UInt8.random(in: .min ... .max) }
        }
        return hex(bytes)
    }

    private static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// The four keys the plugin reads. Written under fresh permissions
    /// rather than over an older file: overwriting keeps whatever mode was
    /// there, and a token that became readable would stay so.
    func write(port: UInt16, token: String, pid: Int32) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(
            Payload(v: BridgeProtocol.version, port: Int(port), token: token, pid: Int(pid)))
        remove()
        guard FileManager.default.createFile(atPath: url.path, contents: data,
                                             attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
    }

    /// The bridge stopping takes its file with it: one left behind sends the
    /// plugin knocking on a port nobody answers. Nothing to remove is an
    /// ordinary outcome, not a failure.
    func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    private struct Payload: Encodable {
        let v: Int
        let port: Int
        let token: String
        let pid: Int
    }
}
