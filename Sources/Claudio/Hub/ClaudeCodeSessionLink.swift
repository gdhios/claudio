import Foundation

/// The way back from a Claude Code session to its conversation in the
/// Claude app. The hook names a session by the engine's id; the app opens it
/// by its own (`local_…`); the one place that holds both is the file each
/// live Claude Code process keeps in `~/.claude/sessions/<pid>.json`, under
/// `sessionId` and `hostSessionId`.
enum ClaudeCodeSessionLink {
    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/sessions")
    }

    /// The app's link to the session the engine calls `id`: the file written
    /// last when several name it. nil when none names it with an app id, as
    /// for a session in a terminal. A file that can't be read is passed over.
    static func url(forSession id: String, in directory: URL = defaultDirectory) -> URL? {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                  includingPropertiesForKeys: nil)) ?? []
        let latest = files.filter { $0.pathExtension == "json" }
            .compactMap(Entry.init(contentsOf:))
            .filter { $0.sessionID == id }
            .max { $0.updatedAt < $1.updatedAt }
        guard let app = latest?.appSessionID.addingPercentEncoding(withAllowedCharacters: unreserved) else {
            return nil
        }
        return URL(string: "claude://claude.ai/epitaxy/\(app)")
    }

    /// What an id may hold as it is in a path: the rest is escaped.
    private static let unreserved = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    /// One session file, as far as the link needs it.
    private struct Entry {
        let sessionID: String
        let appSessionID: String
        let updatedAt: Date

        init?(contentsOf url: URL) {
            guard let data = try? Data(contentsOf: url),
                  let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let sessionID = object["sessionId"] as? String,
                  let app = object["hostSessionId"] as? String, !app.isEmpty else { return nil }
            self.sessionID = sessionID
            appSessionID = app
            updatedAt = Self.date(object["updatedAt"])
        }

        /// `updatedAt` read as a date whichever way it is written: a number
        /// of milliseconds or of seconds since 1970, or ISO 8601 text.
        /// Anything else is older than any date.
        private static func date(_ value: Any?) -> Date {
            if let number = value as? Double {
                return Date(timeIntervalSince1970: number > 100_000_000_000 ? number / 1000 : number)
            }
            guard let text = value as? String else { return .distantPast }
            return (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text))
                ?? (try? Date.ISO8601FormatStyle().parse(text))
                ?? .distantPast
        }
    }
}
