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
///
/// The queue follows the clock, not only the sessions: a call the clock
/// never heard of is crossed out, a dismissal's alert going back where it
/// was and a hold's alert leaving, so the head of the queue stays the alert
/// on screen. A session whose alert never made it waits no more, and the
/// indicator follows.
struct ClaudeCodeBoard {
    enum Level: String, Hashable, Codable { case orange, red }

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
    private var queue = HeldQueue()
    /// The indicator last sent, and whether one was and landed: the first is
    /// always sent, and so is the one after a failure; any other only when
    /// it differs.
    private var indicator: UlanziIndicator?
    private var hasSentIndicator = false

    /// The held alerts, in the order the clock shows them.
    var alerts: [Alert] { queue.alerts }

    mutating func handle(_ event: ClaudeCodeEvent, now: Date) -> [UlanziCommand] {
        let id = event.sessionID
        let name = Self.alertName(for: id)
        let project = Self.project(of: event.cwd)
        switch event.kind {
        case .stop:
            let dismissal = release(id)
            let flag = ClaudeCodeFlag.in(event.lastAssistantMessage)
            if let level = flag?.waitLevel { wait(id, level, now: now) }
            let notification = Self.notification(for: flag, project: project, name: name)
            return [dismissal, .notify(notification)] + refreshIndicator(now: now)
        case .notification(let type) where Self.waitingTypes.contains(type):
            wait(id, .orange, now: now)
            return [.notify(UlanziNotification(name: name, text: "\(project) ?", textColor: Self.waitingColor,
                                               hold: true, wakeup: true, soundRtttl: Melody.waiting))]
                + refreshIndicator(now: now)
        case .promptSubmitted, .sessionEnded:
            return [release(id)] + refreshIndicator(now: now)
        case .notification, .other:
            return []
        }
    }

    /// The press takes the alert on screen away, the oldest held, and says
    /// whose session it was, to open it. Nothing held: nothing to do.
    mutating func middleButtonPressed(now: Date) -> (commands: [UlanziCommand], sessionID: String?) {
        guard let head = queue.press() else { return ([], nil) }
        waits[head.sessionID] = nil
        return ([.dismiss(name: head.name)] + refreshIndicator(now: now), head.sessionID)
    }

    // MARK: - What the clock answered

    /// The clock took the dismissal of `name`.
    mutating func dismissLanded(name: String) {
        queue.landed(name)
    }

    /// The clock never heard of the dismissal of `name`, and still shows the
    /// alert: it goes back to its place. Unless a call sent since under the
    /// name, a hold or another dismissal, has the last word.
    mutating func dismissFailed(name: String) {
        _ = queue.failed(name)
    }

    /// The clock took the hold of `name`.
    mutating func notifyLanded(name: String) {
        queue.landed(name)
    }

    /// The clock never heard of the hold of `name`: its alert leaves the
    /// queue, and the one it was to replace, still on the clock, comes back.
    /// Unless a newer hold of the name is on its way, which wins. A session
    /// left with nothing on the clock waits no more: what the indicator then
    /// needs comes back, to send.
    mutating func notifyFailed(name: String, now: Date) -> [UlanziCommand] {
        guard let lost = queue.failed(name),
              queue.alert(named: name)?.sessionID != lost.sessionID else { return [] }
        waits[lost.sessionID] = nil
        return refreshIndicator(now: now)
    }

    /// The clock may not show the indicator last sent: the next one goes,
    /// changed or not.
    mutating func indicatorFailed() {
        hasSentIndicator = false
    }

    // MARK: - Waits and alerts

    /// Waits, and holds its alert at the back of the queue.
    private mutating func wait(_ id: String, _ level: Level, now: Date) {
        waits[id] = Wait(level: level, since: now)
        queue.hold(Alert(name: Self.alertName(for: id), sessionID: id))
    }

    /// Lets the session go: no more wait, and its alert dismissed.
    private mutating func release(_ id: String) -> UlanziCommand {
        waits[id] = nil
        let name = Self.alertName(for: id)
        queue.dismiss(name)
        return .dismiss(name: name)
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

// MARK: - Outliving Claudio

extension ClaudeCodeBoard {
    /// The board as `snapshot` left it, less the waits twelve hours old at
    /// `now`: nothing on its way, and the first indicator sent whatever it
    /// is.
    init(restoring snapshot: Snapshot, now: Date) {
        self.init()
        queue = HeldQueue(confirmed: snapshot.held)
        for wait in snapshot.waits where now.timeIntervalSince(wait.since) < Self.expiry {
            waits[wait.sessionID] = Wait(level: wait.level, since: wait.since)
        }
    }

    /// What outlives Claudio, as it stands.
    var snapshot: Snapshot {
        let waiting = waits.map { Snapshot.Waiting(sessionID: $0.key, level: $0.value.level, since: $0.value.since) }
        return Snapshot(held: queue.confirmed, waits: waiting.sorted { $0.sessionID < $1.sessionID })
    }
}
