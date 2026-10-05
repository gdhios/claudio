import Foundation

/// Where the board outlives Claudio. The clock keeps its held alerts when
/// Claudio quits, and the sessions keep waiting: a start that knew neither
/// would open the wrong conversation at the first press, and put the
/// indicator out while a session still waits. A small JSON file in Claudio's
/// Application Support folder, next to the handshake files, which stays
/// when the hub stops: it is the clock's state, not the run's.
struct ClaudeCodeBoardFile {
    static let defaultName = "claude-code-board.json"

    /// Injectable so the tests write to a temporary one.
    let directory: URL
    let name: String

    init(directory: URL = BridgeHandshakeFile.defaultDirectory, name: String = ClaudeCodeBoardFile.defaultName) {
        self.directory = directory
        self.name = name
    }

    var url: URL { directory.appendingPathComponent(name) }

    /// The board last written. nil when there is none, or none this version
    /// reads whole: better no board than a wrong one.
    func load() -> ClaudeCodeBoard.Snapshot? {
        guard let data = try? Data(contentsOf: url),
              let contents = try? Self.decoder.decode(Contents.self, from: data),
              contents.v == Self.version else { return nil }
        return ClaudeCodeBoard.Snapshot(held: contents.held, waits: contents.waits)
    }

    /// Writes `snapshot` in place of the last one, whole or not at all.
    func save(_ snapshot: ClaudeCodeBoard.Snapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let contents = Contents(v: Self.version, held: snapshot.held, waits: snapshot.waits)
        try Self.encoder.encode(contents).write(to: url, options: .atomic)
    }

    private static let version = 1

    private struct Contents: Codable {
        let v: Int
        let held: [ClaudeCodeBoard.Snapshot.Held]
        let waits: [ClaudeCodeBoard.Snapshot.Waiting]
    }

    /// Dates in seconds since 1970, keys sorted: a file a person can read.
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
