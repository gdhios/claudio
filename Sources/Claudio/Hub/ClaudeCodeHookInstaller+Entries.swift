import Foundation

/// The relay's entries in Claude Code's settings, as values: what goes in,
/// what comes out, and whether it is there, on the settings as
/// `JSONSerialization` reads them. Nothing else in them is touched.
///
/// Claude Code keeps its hooks by event, each event a list of groups, each
/// group an optional matcher and its list of commands. The relay gets one
/// group of its own per event, after whatever was there.
extension ClaudeCodeHookInstaller {
    /// The relay's file name: an entry whose command holds it runs the
    /// relay, wherever it lives.
    static let relayName = "claudio-claude-code.py"

    /// The four events the relay listens to, and the one matcher: only the
    /// notifications that wait for Guillaume.
    static let events: [(name: String, matcher: String?)] = [
        ("Stop", nil),
        ("Notification", "permission_prompt|idle_prompt|agent_needs_input|elicitation_dialog|elicitation_url_dialog"),
        ("UserPromptSubmit", nil),
        ("SessionEnd", nil),
    ]

    /// What runs the relay at `path`: Python 3, the path in single quotes
    /// as a shell reads them, a quote in it included.
    static func command(for path: URL) -> String {
        "python3 '" + path.path.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// The four entries running `command`, in place of any running the
    /// relay already: installed twice is installed once.
    static func install(into settings: [String: Any], command: String) -> [String: Any] {
        var settings = remove(from: settings)
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for event in events {
            var group: [String: Any] = ["hooks": [handler(command)]]
            if let matcher = event.matcher { group["matcher"] = matcher }
            hooks[event.name] = (hooks[event.name] as? [Any] ?? []) + [group]
        }
        settings["hooks"] = hooks
        return settings
    }

    /// Every entry running the relay taken out, and only those: a group
    /// they leave empty goes, and so does an event they leave without a
    /// group, and the hooks they leave without an event. What was empty
    /// before stays.
    static func remove(from settings: [String: Any]) -> [String: Any] {
        guard var hooks = settings["hooks"] as? [String: Any] else { return settings }
        var changed = false
        for (event, value) in hooks {
            guard let groups = value as? [Any], let kept = withoutRelay(groups) else { continue }
            changed = true
            hooks[event] = kept.isEmpty ? nil : kept
        }
        guard changed else { return settings }
        var settings = settings
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        return settings
    }

    /// Installed: a Stop entry runs the relay.
    static func isInstalled(_ settings: [String: Any]) -> Bool {
        let groups = (settings["hooks"] as? [String: Any])?["Stop"] as? [Any] ?? []
        return groups.contains { group in
            ((group as? [String: Any])?["hooks"] as? [Any] ?? []).contains(where: runsRelay)
        }
    }

    /// Whether settings read as an object have hooks Claude Code would
    /// read: none, or an object whose four events, when there, are lists.
    /// Anything else is no file to write over.
    static func hasReadableHooks(_ settings: [String: Any]) -> Bool {
        guard let value = settings["hooks"] else { return true }
        guard let hooks = value as? [String: Any] else { return false }
        return events.allSatisfy { hooks[$0.name] == nil || hooks[$0.name] is [Any] }
    }

    // MARK: - One entry

    private static func handler(_ command: String) -> [String: Any] {
        ["type": "command", "command": command, "timeout": 10, "async": true]
    }

    private static func runsRelay(_ handler: Any) -> Bool {
        ((handler as? [String: Any])?["command"] as? String)?.contains(relayName) == true
    }

    /// `groups` without the relay's entries, a group left empty gone; nil
    /// when the relay ran in none of them.
    private static func withoutRelay(_ groups: [Any]) -> [Any]? {
        var changed = false
        var kept: [Any] = []
        for group in groups {
            guard var object = group as? [String: Any], let handlers = object["hooks"] as? [Any],
                  handlers.contains(where: runsRelay) else {
                kept.append(group)
                continue
            }
            changed = true
            let others = handlers.filter { !runsRelay($0) }
            guard !others.isEmpty else { continue }
            object["hooks"] = others
            kept.append(object)
        }
        return changed ? kept : nil
    }
}
