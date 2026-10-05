import Foundation

/// Claudio's face on every clock that has it ticked: one bridge per clock,
/// all following the same two sessions. The app hands it the clock list and
/// the sessions as they come and go; Settings reads each bridge's status by
/// its clock's id, and tests one clock at a time.
///
/// A bridge that starts installs the face and puts it away: one only starts
/// for a clock new to the face, or one that moved, and stays as it is
/// through any other change of the list.
@MainActor
final class UlanziFaceFleet {
    private struct Member {
        let address: URL
        let bridge: any UlanziFaceBridging
    }

    private let makeBridge: @MainActor (URL) -> any UlanziFaceBridging
    private var members: [UUID: Member] = [:]
    /// The sessions under way, held weakly as each bridge holds them, for a
    /// bridge that starts mid-dictation.
    private weak var correction: CorrectionSession?
    private weak var dictation: DictationSession?

    /// A bridge's status moved: the clock's id, and where it stands.
    var onStatusChange: ((UUID, UlanziBridge.Status) -> Void)?

    /// `makeBridge` hands back a bridge already started on the address.
    init(makeBridge: @escaping @MainActor (URL) -> any UlanziFaceBridging = UlanziFaceFleet.startedBridge) {
        self.makeBridge = makeBridge
    }

    /// The real one: a `UlanziBridge`, started.
    static func startedBridge(on address: URL) -> any UlanziFaceBridging {
        let bridge = UlanziBridge()
        bridge.start(address: address)
        return bridge
    }

    // MARK: - The list

    /// Brings the bridges in line with `clocks`: one stops for a clock gone,
    /// unticked or moved, and one starts for a clock new to the face or
    /// moved; every other stays as it is.
    func apply(_ clocks: [UlanziClock]) {
        let wanted = Self.faces(in: clocks)
        for (id, member) in members where wanted.first(where: { $0.id == id })?.address != member.address {
            members[id] = nil
            member.bridge.stop()
            member.bridge.onStatusChange = nil
        }
        for clock in wanted where members[clock.id] == nil {
            start(clock)
        }
    }

    /// A bridge for `clock`, told of the sessions under way, and its status
    /// said at once: it started before anyone listened.
    private func start(_ clock: UlanziClock) {
        let id = clock.id
        let bridge = makeBridge(clock.address)
        members[id] = Member(address: clock.address, bridge: bridge)
        bridge.onStatusChange = { [weak self] status in self?.onStatusChange?(id, status) }
        bridge.correctionSessionChanged(correction)
        bridge.dictationSessionChanged(dictation)
        onStatusChange?(id, bridge.status)
    }

    /// The clocks with the face, each id once: its first entry decides.
    private static func faces(in clocks: [UlanziClock]) -> [UlanziClock] {
        var seen = Set<UUID>()
        return clocks.filter { seen.insert($0.id).inserted && $0.face }
    }

    // MARK: - Settings

    /// Off for a clock without the face.
    func status(of id: UUID) -> UlanziBridge.Status {
        members[id]?.bridge.status ?? .off
    }

    /// Claudio smiles on that clock, and on no other.
    func test(_ id: UUID) {
        members[id]?.bridge.test()
    }

    // MARK: - What it watches

    func correctionSessionChanged(_ session: CorrectionSession?) {
        correction = session
        members.values.forEach { $0.bridge.correctionSessionChanged(session) }
    }

    func dictationSessionChanged(_ session: DictationSession?) {
        dictation = session
        members.values.forEach { $0.bridge.dictationSessionChanged(session) }
    }

    // MARK: - Quitting

    /// Every bridge lets go, and every face that may be up goes before the
    /// app does, all at once: `limit` seconds at most in all, however many
    /// clocks there are.
    func prepareToQuit(within limit: TimeInterval) {
        UlanziBridge.putAway(members.values.compactMap { $0.bridge.letGoForQuit() }, within: limit)
    }
}
