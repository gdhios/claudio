import Foundation

/// The three status lines at the foot of the menu bar's menu: where
/// dictation, the Ulanzi clocks and the Stream Deck stand, each one a click
/// away from its tab. The text is worked out here from plain values; the
/// menu reads the settings and the models, and only shows what comes back.
struct StatusMenuLines: Equatable {
    var dictation: String
    var ulanzi: String
    var streamDeck: String

    // MARK: - Dictation

    /// "Hold" and the key, as the Shortcuts tab shows it. `key` is nil when
    /// no dictation shortcut has one.
    static func dictation(enabled: Bool, key: String?) -> String {
        guard enabled else { return loc("Dictée : désactivée", en: "Dictation: off") }
        guard let key else { return loc("Dictée : aucun raccourci", en: "Dictation: no shortcut") }
        return loc("Dictée : maintenir \(key)", en: "Dictation: hold \(key)")
    }

    /// The key the line names, from the shortcuts in their order, "Dictate"
    /// first: a lone key, which takes its combination's place in Settings,
    /// else the combination as described (empty when cleared).
    static func dictationKey(_ shortcuts: [(loneKey: String?, combination: String)]) -> String? {
        for shortcut in shortcuts {
            if let loneKey = shortcut.loneKey { return loneKey }
            if !shortcut.combination.isEmpty { return shortcut.combination }
        }
        return nil
    }

    // MARK: - Ulanzi

    /// A clock that fails on one of its ticked roles is the news, whatever
    /// the others do; then the ones not settled yet; then all ready.
    static func ulanzi(_ clocks: [UlanziStatusModel.ClockRow]) -> String {
        guard !clocks.isEmpty else { return loc("Ulanzi : aucune horloge", en: "Ulanzi: no clock") }
        let health = clocks.map(ClockHealth.init)
        let failing = health.filter { $0 == .failing }.count
        if failing > 0 {
            return failing == 1
                ? loc("Ulanzi : 1 horloge injoignable", en: "Ulanzi: 1 clock unreachable")
                : loc("Ulanzi : \(failing) horloges injoignables", en: "Ulanzi: \(failing) clocks unreachable")
        }
        let waiting = health.filter { $0 == .waiting }.count
        if waiting > 0 {
            return waiting == 1
                ? loc("Ulanzi : 1 horloge en attente", en: "Ulanzi: 1 clock waiting")
                : loc("Ulanzi : \(waiting) horloges en attente", en: "Ulanzi: \(waiting) clocks waiting")
        }
        return clocks.count == 1
            ? loc("Ulanzi : 1 horloge prête", en: "Ulanzi: 1 clock ready")
            : loc("Ulanzi : \(clocks.count) horloges prêtes", en: "Ulanzi: \(clocks.count) clocks ready")
    }

    /// One clock, summed up over the roles it has ticked.
    private enum ClockHealth {
        case ready, waiting, failing

        init(_ row: UlanziStatusModel.ClockRow) {
            var faceFails = false
            if case .failed = row.faceStatus { faceFails = row.clock.face }
            var alertsFail = false
            switch row.alertsStatus {
            case .unreachable?, .rejected?: alertsFail = row.clock.alerts
            case .pending?, .ready?, nil: break
            }
            if faceFails || alertsFail {
                self = .failing
            } else if (!row.clock.face || row.faceStatus == .ready)
                        && (!row.clock.alerts || row.alertsStatus == .ready) {
                self = .ready
            } else {
                self = .waiting
            }
        }
    }

    // MARK: - Stream Deck

    /// In the tab's words. Switched off by hand says so first; then a
    /// plugin on the line, or an open door nobody came to; a bridge left to
    /// itself without the plugin says what's missing.
    static func streamDeck(status: StreamDeckBridge.Status, pluginInstalled: Bool, choice: Bool?) -> String {
        switch status {
        case .connected:
            return loc("Stream Deck : connecté", en: "Stream Deck: connected")
        case .waiting:
            return loc("Stream Deck : non connecté", en: "Stream Deck: not connected")
        case .off where choice == false:
            return loc("Stream Deck : désactivé", en: "Stream Deck: off")
        case .off where !pluginInstalled:
            return loc("Stream Deck : plugin absent", en: "Stream Deck: plugin not found")
        case .off:
            return loc("Stream Deck : non connecté", en: "Stream Deck: not connected")
        }
    }
}
