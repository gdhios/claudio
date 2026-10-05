import Foundation

/// What the Ulanzi shows of the Claude Code sessions, as a value: who waits
/// for Guillaume, and the alerts held on the clock in the order they were
/// posted, which is the order it shows them in. An event, or a press of the
/// middle button, comes out as the commands to send, in order.
///
/// The rules are those of the Python hook that drove the clock before
/// Claudio, ported as they were: same texts, colours, sounds and indicator,
/// and a wait forgotten after 12 h. Only the indicator is sent less often:
/// when it changes, or when the last one sent may not have landed.
struct ClaudeCodeBoard {
    enum Level: Hashable { case orange, red }

    struct Wait: Equatable {
        let level: Level
        let since: Date
    }

    /// A held alert: its notification's name on the clock, and whose it is.
    struct Alert: Equatable {
        let name: String
        let sessionID: String
    }

    /// Past this, a wait is a session killed without a SessionEnd: it no
    /// longer lights the indicator.
    static let expiry: TimeInterval = 12 * 3600
    /// The five notifications that wait for Guillaume.
    static let waitingTypes: Set<String> = ["permission_prompt", "idle_prompt", "agent_needs_input",
                                            "elicitation_dialog", "elicitation_url_dialog"]

    private(set) var waits: [String: Wait] = [:]
    private(set) var alerts: [Alert] = []
    /// The indicator last sent, and whether one was and landed: the first is
    /// always sent, and so is the one after a failure; any other only when
    /// it differs.
    private var indicator: UlanziIndicator?
    private var hasSentIndicator = false

    mutating func handle(_ event: ClaudeCodeEvent, now: Date) -> [UlanziCommand] {
        let id = event.sessionID
        let name = Self.alertName(for: id)
        let project = Self.project(of: event.cwd)
        switch event.kind {
        case .stop:
            release(id)
            let flag = ClaudeCodeFlag.in(event.lastAssistantMessage)
            if let level = flag?.waitLevel { wait(id, level, now: now) }
            let notification = Self.notification(for: flag, project: project, name: name)
            return [.dismiss(name: name), .notify(notification)] + refreshIndicator(now: now)
        case .notification(let type) where Self.waitingTypes.contains(type):
            wait(id, .orange, now: now)
            return [.notify(UlanziNotification(name: name, text: "\(project) ?", textColor: Self.waitingColor,
                                               hold: true, wakeup: true, soundRtttl: Melody.waiting))]
                + refreshIndicator(now: now)
        case .promptSubmitted, .sessionEnded:
            release(id)
            return [.dismiss(name: name)] + refreshIndicator(now: now)
        case .notification, .other:
            return []
        }
    }

    /// The press takes the alert on screen away, the oldest held, and says
    /// whose session it was, to open it. Nothing held: nothing to do.
    mutating func middleButtonPressed(now: Date) -> (commands: [UlanziCommand], sessionID: String?) {
        guard let head = alerts.first else { return ([], nil) }
        release(head.sessionID)
        return ([.dismiss(name: head.name)] + refreshIndicator(now: now), head.sessionID)
    }

    /// The clock may not show the indicator last sent: the next one goes,
    /// changed or not.
    mutating func indicatorFailed() {
        hasSentIndicator = false
    }

    // MARK: - Waits and alerts

    /// Waits, and holds its alert at the back of the queue: the clock puts a
    /// notification posted again under its name at the back too.
    private mutating func wait(_ id: String, _ level: Level, now: Date) {
        waits[id] = Wait(level: level, since: now)
        let name = Self.alertName(for: id)
        alerts.removeAll { $0.name == name }
        alerts.append(Alert(name: name, sessionID: id))
    }

    private mutating func release(_ id: String) {
        waits[id] = nil
        let name = Self.alertName(for: id)
        alerts.removeAll { $0.name == name }
    }

    /// Red while a session is blocked, orange while one waits, off after;
    /// sent only when it changes, but always the first time.
    private mutating func refreshIndicator(now: Date) -> [UlanziCommand] {
        waits = waits.filter { now.timeIntervalSince($0.value.since) < Self.expiry }
        let levels = Set(waits.values.map(\.level))
        let wanted: UlanziIndicator? = levels.contains(.red) ? Self.blockedIndicator
            : levels.isEmpty ? nil : Self.waitingIndicator
        guard !hasSentIndicator || wanted != indicator else { return [] }
        hasSentIndicator = true
        indicator = wanted
        return [.indicator(wanted)]
    }
}
