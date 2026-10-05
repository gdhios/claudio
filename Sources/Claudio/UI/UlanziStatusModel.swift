import Foundation

/// What the Ulanzi tab shows, and what it asks for. One object the app
/// fills in and the tab reads, like `StreamDeckStatusModel`: the clocks as
/// kept, with where each one's face and flags stand; the relay's door; and
/// whether the hook is in Claude Code.
///
/// It stores nothing and calls nothing itself. The app hands it
/// `applyClocks`, which writes the list down and brings the faces and the
/// hub in line with it, `test`, and the two hook actions. A preview sets
/// none: it fills the fields by hand and shows a screen that is the same on
/// every machine.
@MainActor
final class UlanziStatusModel: ObservableObject {
    /// The one the tab reads. The app feeds it; a preview overwrites it.
    static let shared = UlanziStatusModel()

    /// A clock kept, and where its two roles stand.
    struct ClockRow: Identifiable, Equatable {
        var clock: UlanziClock
        var faceStatus: UlanziBridge.Status = .off
        /// nil while the flags are not ticked.
        var alertsStatus: ClaudeCodeHub.ClockStatus?

        var id: UUID { clock.id }
    }

    /// One card of the tab as typed: a clock kept, or one being added. The
    /// address is the text in the field.
    struct ClockDraft: Identifiable, Equatable {
        let id: UUID
        var name: String
        var address: String
        var face: Bool
        var alerts: Bool
    }

    @Published private(set) var clocks: [ClockRow] = []
    @Published var hub: ClaudeCodeHub.Status = .off
    @Published var hook: ClaudeCodeHookInstaller.HookState = .absent
    /// What went wrong the last time the hook was installed or removed, nil
    /// when it went well.
    @Published var hookFailure: String?
    /// The cards whose address could not be read, each when last submitted.
    @Published private(set) var unreadable: Set<UUID> = []

    /// Called with the list submitted, when it changed. The app stores it
    /// and brings the faces and the flags in line with it.
    var applyClocks: (([UlanziClock]) -> Void)?
    /// Called by a card's Test button: Claudio smiles on that clock.
    var test: ((UUID) -> Void)?
    var installHook: (() -> Void)?
    var removeHook: (() -> Void)?

    // MARK: - The clocks

    /// The clocks as kept. A clock still there keeps its statuses, unless
    /// it moved, which starts it over; a role unticked has nothing to say.
    func show(_ list: [UlanziClock]) {
        clocks = list.map { clock in
            guard var row = clocks.first(where: { $0.id == clock.id }) else {
                return ClockRow(clock: clock, alertsStatus: clock.alerts ? .pending : nil)
            }
            let moved = row.clock.address != clock.address
            row.clock = clock
            if moved || !clock.face { row.faceStatus = .off }
            row.alertsStatus = clock.alerts ? ((moved ? nil : row.alertsStatus) ?? .pending) : nil
            return row
        }
    }

    /// The cards the tab starts with: one per clock, its address written
    /// the way it is called.
    var drafts: [ClockDraft] {
        clocks.map { ClockDraft(clock: $0.clock) }
    }

    /// A card added: the first free name, both roles, no address yet.
    func newDraft(among drafts: [ClockDraft]) -> ClockDraft {
        ClockDraft(id: UUID(), name: UlanziClock.defaultName(notIn: Set(drafts.map(\.name))),
                   address: "", face: true, alerts: true)
    }

    /// One card submitted, on its own: its clock becomes the card as
    /// typed, and every other clock stays as kept, whatever its card shows
    /// meanwhile. An address that reads is kept the way it will be called;
    /// one that doesn't leaves the clock its own, and a new card no clock
    /// yet, which `unreadable` and `false` say. A new card left blank is
    /// only not finished. A blank name is the clock's own, or the first
    /// free. The list is applied only when it changed: a bridge started
    /// over installs and puts the face away for nothing.
    @discardableResult
    func submit(_ id: UUID, in drafts: [ClockDraft]) -> Bool {
        guard let draft = drafts.first(where: { $0.id == id }) else { return true }
        let kept = clocks.first { $0.id == id }?.clock
        let typed = AppSettings.normalizedUlanziURL(draft.address)
        let readable = typed != nil || (kept == nil && draft.address.isBlank)
        if readable { unreadable.remove(id) } else { unreadable.insert(id) }
        guard let address = typed ?? kept?.address else { return readable }
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let clock = UlanziClock(id: id, name: name.isEmpty ? kept?.name ?? freeName(drafts) : name,
                                address: address, face: draft.face, alerts: draft.alerts)
        var list = clocks.map(\.clock)
        if let index = list.firstIndex(where: { $0.id == id }) {
            list[index] = clock
        } else {
            list.append(clock)
        }
        apply(list)
        return readable
    }

    /// A card removed: its clock goes, every other stays as kept.
    func remove(_ id: UUID) {
        unreadable.remove(id)
        apply(clocks.map(\.clock).filter { $0.id != id })
    }

    private func apply(_ list: [UlanziClock]) {
        guard list != clocks.map(\.clock) else { return }
        show(list)
        applyClocks?(list)
    }

    private func freeName(_ drafts: [ClockDraft]) -> String {
        UlanziClock.defaultName(notIn: Set(clocks.map(\.clock.name) + drafts.map(\.name)))
    }

    /// The cards after `id`'s was submitted: that one shows its clock as
    /// kept, if it is one; every other stays as typed.
    func redrafted(_ drafts: [ClockDraft], after id: UUID) -> [ClockDraft] {
        drafts.map { draft in
            guard draft.id == id, let row = clocks.first(where: { $0.id == id }) else { return draft }
            return ClockDraft(clock: row.clock)
        }
    }

    /// A card's Test button: that card is kept first, then its clock
    /// smiles, if it has the face. An address nobody could call tries
    /// nothing, and says so with `false`: the old one smiling would say the
    /// typo works.
    @discardableResult
    func testTyped(_ id: UUID, in drafts: [ClockDraft]) -> Bool {
        guard submit(id, in: drafts) else { return false }
        if clocks.first(where: { $0.id == id })?.clock.face == true { test?(id) }
        return true
    }

    // MARK: - What the app reports

    func faceStatusChanged(_ status: UlanziBridge.Status, of id: UUID) {
        guard let index = clocks.firstIndex(where: { $0.id == id }) else { return }
        clocks[index].faceStatus = status
    }

    /// Taken only while the clock has the flags ticked.
    func alertsStatusChanged(_ status: ClaudeCodeHub.ClockStatus, of id: UUID) {
        guard let index = clocks.firstIndex(where: { $0.id == id }), clocks[index].clock.alerts else { return }
        clocks[index].alertsStatus = status
    }

    // MARK: - The lines

    /// The face's status in one line. Out of reach and in error are two
    /// things to fix: a cable or an address, against a clock that answered
    /// no, in its own words.
    nonisolated static func faceLine(_ status: UlanziBridge.Status) -> String {
        switch status {
        case .off: loc("Désactivé", en: "Off")
        case .installing: loc("Installation du visage…", en: "Installing the face…")
        case .ready: loc("Prêt", en: "Ready")
        case .failed(.unreachable(let reason)): loc("Injoignable : \(reason)", en: "Unreachable: \(reason)")
        case .failed(let failure):
            loc("Erreur : \(failure.localizedDescription)", en: "Error: \(failure.localizedDescription)")
        }
    }

    /// The flags' status on one clock, in one line.
    nonisolated static func alertsLine(_ status: ClaudeCodeHub.ClockStatus) -> String {
        switch status {
        case .pending: loc("En attente", en: "Waiting")
        case .ready: loc("Prêt", en: "Ready")
        case .unreachable(let reason): loc("Injoignable : \(reason)", en: "Unreachable: \(reason)")
        case .rejected(let reason): loc("Refusé : \(reason)", en: "Refused: \(reason)")
        }
    }

    /// The relay's door.
    var hubLine: String {
        switch hub {
        case .off: loc("Désactivé : aucune horloge avec les fanions", en: "Off: no clock with the flags")
        case .listening(let port): loc("À l'écoute sur le port \(port)", en: "Listening on port \(port)")
        case .failed(let reason): loc("Erreur : \(reason)", en: "Error: \(reason)")
        }
    }

    var hookLine: String {
        switch hook {
        case .installed: loc("Hook installé dans Claude Code", en: "Hook installed in Claude Code")
        case .absent: loc("Hook absent", en: "Hook not installed")
        case .unreadable(let reason):
            loc("Réglages Claude Code illisibles : \(reason)", en: "Claude Code settings unreadable: \(reason)")
        case .noRelay: loc("Relais absent de cette version", en: "No relay in this version")
        }
    }
}

extension UlanziStatusModel.ClockDraft {
    /// The card of a clock kept.
    init(clock: UlanziClock) {
        self.init(id: clock.id, name: clock.name, address: clock.address.absoluteString,
                  face: clock.face, alerts: clock.alerts)
    }
}

private extension String {
    var isBlank: Bool { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}
