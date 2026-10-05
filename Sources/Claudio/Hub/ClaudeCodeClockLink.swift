import Foundation

/// One clock the Claude Code hub speaks to: its client, its own queue of
/// calls, the Mac's address it was last told to post its buttons to,
/// whether it is out of reach, and where it stands for Settings. A clock
/// that moves gets a new link: nothing of the old address carries over.
@MainActor
final class ClaudeCodeClockLink {
    let id: UUID
    let address: URL
    let client: UlanziClient

    /// The Mac's address in the button callback last sent. nil while one is
    /// still to set: from the moment the listener is ready, and again after
    /// a setting that failed.
    var callbackHost: String?
    /// Found out of reach, and the hub's last event then: every call of
    /// that event or an earlier one, still queued, fails at once, and the
    /// next event tries the clock again.
    var outOfReach: (through: Int, reason: String)?

    /// The last call queued for the clock. Each waits for the one before.
    private(set) var sending: Task<Void, Never>?

    private(set) var status: ClaudeCodeHub.ClockStatus = .pending
    var onStatusChange: ((ClaudeCodeHub.ClockStatus) -> Void)?

    init(id: UUID, address: URL, client: UlanziClient) {
        self.id = id
        self.address = address
        self.client = client
    }

    /// Where the clock stands after its last call.
    func update(_ status: ClaudeCodeHub.ClockStatus) {
        guard status != self.status else { return }
        self.status = status
        onStatusChange?(status)
    }

    /// Runs `work` once every call queued before it is done.
    func chain(_ work: @escaping @MainActor () async -> Void) {
        let previous = sending
        sending = Task { @MainActor in
            await previous?.value
            await work()
        }
    }
}
