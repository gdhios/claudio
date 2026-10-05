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
/// The queue follows the clock, not only the sessions: a dismissal the
/// clock never heard of puts its alert back where it was, since the clock
/// still shows it, and the head of the queue stays the alert on screen.
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

    /// A held alert, and when it was posted, which is its place in the queue.
    private struct Held {
        let alert: Alert
        let order: Int
    }

    /// A dismissal sent, its answer still to come.
    private enum Dismissal {
        /// A session let go: the alert it took off the queue, if any, which
        /// goes back to its place if the clock never heard of it.
        case release(took: Held?)
        /// The middle button: the firmware took the alert off itself, and
        /// nothing comes back.
        case press
    }

    private(set) var waits: [String: Wait] = [:]
    private var held: [Held] = []
    private var posted = 0
    /// The dismissals on their way, by name, in the order they were sent:
    /// the clock answers them in that order.
    private var dismissals: [String: [Dismissal]] = [:]
    /// The indicator last sent, and whether one was and landed: the first is
    /// always sent, and so is the one after a failure; any other only when
    /// it differs.
    private var indicator: UlanziIndicator?
    private var hasSentIndicator = false

    /// The held alerts, in the order the clock shows them.
    var alerts: [Alert] { held.map(\.alert) }

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
        guard let head = held.first?.alert else { return ([], nil) }
        waits[head.sessionID] = nil
        held.removeFirst()
        dismissals[head.name, default: []].append(.press)
        return ([.dismiss(name: head.name)] + refreshIndicator(now: now), head.sessionID)
    }

    // MARK: - What the clock answered

    /// The clock took the dismissal of `name`.
    mutating func dismissLanded(name: String) {
        _ = nextDismissal(of: name)
    }

    /// The clock never heard of the dismissal of `name`, and still shows the
    /// alert: it goes back to its place. Unless the name is held again since,
    /// the clock having replaced the old alert with the new one, or a later
    /// dismissal of the name is on its way, which then has the last word.
    mutating func dismissFailed(name: String) {
        guard case .release(let took?) = nextDismissal(of: name) else { return }
        if let later = dismissals[name]?.first {
            if case .release(nil) = later { dismissals[name]?[0] = .release(took: took) }
            return
        }
        guard !held.contains(where: { $0.alert.name == name }) else { return }
        held.insert(took, at: held.firstIndex { $0.order > took.order } ?? held.endIndex)
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
        held.removeAll { $0.alert.name == name }
        held.append(Held(alert: Alert(name: name, sessionID: id), order: posted))
        posted += 1
    }

    /// Lets the session go: no more wait, its alert off the queue, and the
    /// dismissal to send, written down until the clock answers it.
    private mutating func release(_ id: String) -> UlanziCommand {
        waits[id] = nil
        let name = Self.alertName(for: id)
        let took = held.first { $0.alert.name == name }
        held.removeAll { $0.alert.name == name }
        dismissals[name, default: []].append(.release(took: took))
        return .dismiss(name: name)
    }

    private mutating func nextDismissal(of name: String) -> Dismissal? {
        guard var pending = dismissals[name], !pending.isEmpty else { return nil }
        let next = pending.removeFirst()
        dismissals[name] = pending.isEmpty ? nil : pending
        return next
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
