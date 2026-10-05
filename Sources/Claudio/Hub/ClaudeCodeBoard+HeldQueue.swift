extension ClaudeCodeBoard {
    /// The held alerts as the clock shows them, oldest first: the one on
    /// screen, which the middle button takes away, leads.
    ///
    /// The clock holds one alert per name at most, and each call sent under
    /// a name replaces it: a hold with its alert, posted at the back, a
    /// dismissal with nothing. So once the calls on their way have landed,
    /// the last one sent under a name says what the clock shows. The clock
    /// answers them in the order they went; one it never heard of is crossed
    /// out, and the name falls back on the call before, or on what the clock
    /// last said it holds. A failed dismissal puts its alert back where it
    /// was; a failed hold takes its alert away, and gives back the one it
    /// was to replace, if any.
    struct HeldQueue {
        /// An alert, and when it was posted, which is its place.
        private struct Entry {
            let alert: Alert
            let order: Int
        }

        /// One name: what the clock holds under it by its answers so far, and
        /// the calls on their way, a hold as its entry and a dismissal as nil,
        /// in the order sent.
        private struct Slot {
            var landed: Entry?
            var onTheirWay: [Entry?] = []

            /// What the clock shows under the name once every call has landed.
            var expected: Entry? {
                guard let last = onTheirWay.last else { return landed }
                return last
            }
        }

        private var slots: [String: Slot] = [:]
        private var posted = 0

        var alerts: [Alert] { entries.map(\.alert) }

        /// The alerts the clock said it holds, in their places: what
        /// outlives Claudio, the calls on their way left out.
        var confirmed: [Snapshot.Held] {
            slots.values.compactMap(\.landed).sorted { $0.order < $1.order }
                .map { Snapshot.Held(name: $0.alert.name, sessionID: $0.alert.sessionID, order: $0.order,
                                     notification: $0.alert.notification) }
        }

        /// What the clock shows under `name` once every call has landed.
        func alert(named name: String) -> Alert? {
            slots[name]?.expected?.alert
        }

        /// A hold sent: its alert goes to the back, as the clock puts a
        /// notification posted again under its name at the back too.
        mutating func hold(_ alert: Alert) {
            slots[alert.name, default: Slot()].onTheirWay.append(Entry(alert: alert, order: posted))
            posted += 1
        }

        /// A dismissal of `name` sent.
        mutating func dismiss(_ name: String) {
            slots[name, default: Slot()].onTheirWay.append(nil)
        }

        /// The middle button: the firmware took the alert on screen away
        /// itself. Nothing on its way under its name brings it back, nor
        /// does the dismissal sent after the press, written down here too.
        /// Returns the alert taken, nil with nothing held.
        mutating func press() -> Alert? {
            guard let head = entries.first?.alert else { return nil }
            let calls = (slots[head.name]?.onTheirWay.count ?? 0) + 1
            slots[head.name] = Slot(landed: nil, onTheirWay: Array(repeating: nil, count: calls))
            return head
        }

        /// The clock took the next call of `name`.
        mutating func landed(_ name: String) {
            guard var slot = slots[name], !slot.onTheirWay.isEmpty else { return }
            slot.landed = slot.onTheirWay.removeFirst()
            keep(slot, as: name)
        }

        /// The clock never heard of the next call of `name`: it is crossed
        /// out. Returns its alert when it was a hold.
        mutating func failed(_ name: String) -> Alert? {
            guard var slot = slots[name], !slot.onTheirWay.isEmpty else { return nil }
            let lost = slot.onTheirWay.removeFirst()
            keep(slot, as: name)
            return lost?.alert
        }

        private var entries: [Entry] {
            slots.values.compactMap(\.expected).sorted { $0.order < $1.order }
        }

        /// A name with nothing on the clock and nothing on its way is
        /// forgotten.
        private mutating func keep(_ slot: Slot, as name: String) {
            slots[name] = slot.landed == nil && slot.onTheirWay.isEmpty ? nil : slot
        }
    }
}

extension ClaudeCodeBoard.HeldQueue {
    /// The queue as the clock held it when Claudio last heard from it,
    /// nothing on its way. A new hold goes behind them all.
    init(confirmed held: [ClaudeCodeBoard.Snapshot.Held]) {
        self.init()
        for alert in held {
            let entry = Entry(alert: ClaudeCodeBoard.Alert(name: alert.name, sessionID: alert.sessionID,
                                                           notification: alert.notification),
                              order: alert.order)
            slots[alert.name] = Slot(landed: entry)
        }
        posted = (held.map(\.order).max() ?? -1) + 1
    }
}
