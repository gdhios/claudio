import Foundation

/// One event of a Claude Code session, read from its hook's JSON as the
/// relay hands it on, untouched. Only what the board reads is kept.
struct ClaudeCodeEvent: Equatable {
    enum Kind: Equatable {
        /// The end of a turn (`Stop`): its last message carries the flag.
        case stop
        /// `Notification`, with its `notification_type`, empty without one.
        case notification(type: String)
        /// `UserPromptSubmit`: Guillaume answered in the session.
        case promptSubmitted
        /// `SessionEnd`.
        case sessionEnded
        /// Any other hook: nothing to show.
        case other
    }

    let kind: Kind
    /// The engine's id of the session (`session_id`), which names its alert.
    let sessionID: String
    let cwd: String?
    let lastAssistantMessage: String?
}

extension ClaudeCodeEvent {
    /// nil for anything without a hook name or a session id: there is
    /// nothing to decide, and no alert to hold, without them.
    init?(_ data: Data) {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let name = object["hook_event_name"] as? String,
              let sessionID = object["session_id"] as? String, !sessionID.isEmpty else { return nil }
        let kind: Kind = switch name {
        case "Stop": .stop
        case "Notification": .notification(type: object["notification_type"] as? String ?? "")
        case "UserPromptSubmit": .promptSubmitted
        case "SessionEnd": .sessionEnded
        default: .other
        }
        self.init(kind: kind, sessionID: sessionID, cwd: object["cwd"] as? String,
                  lastAssistantMessage: object["last_assistant_message"] as? String)
    }
}
