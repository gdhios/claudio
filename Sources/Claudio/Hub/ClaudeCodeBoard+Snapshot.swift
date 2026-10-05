import Foundation

extension ClaudeCodeBoard {
    /// What of the board outlives Claudio, the clock keeping its held alerts
    /// when Claudio quits and the sessions their waits: the alerts the clock
    /// said it holds, in their places, and who waits since when. A call
    /// still on its way is not in it: after a restart, no answer comes for
    /// it.
    struct Snapshot: Equatable {
        struct Held: Codable, Equatable {
            let name: String
            let sessionID: String
            /// Its place: the clock shows the lowest first.
            let order: Int
        }

        struct Waiting: Codable, Equatable {
            let sessionID: String
            let level: Level
            let since: Date
        }

        /// In the order the clock shows them.
        var held: [Held] = []
        /// By session.
        var waits: [Waiting] = []
    }
}
