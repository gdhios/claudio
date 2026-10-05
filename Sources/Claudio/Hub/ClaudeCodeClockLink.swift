import Foundation

/// One clock the Claude Code hub speaks to: its client, the Mac's address
/// it was last told to post its buttons to, whether it is out of reach,
/// and where it stands for Settings. Its calls wait in its device's line,
/// which the hub keeps by address. A clock that moves gets a new link:
/// nothing of the old address carries over.
@MainActor
final class ClaudeCodeClockLink {
    let id: UUID
    let address: URL
    let client: UlanziClient

    /// The Mac's address in the button callback last sent. nil while one is
    /// still to set: from the moment the listener is ready, and again after
    /// a setting that failed.
    var callbackHost: String?
    /// A button callback went out to the device from this link, answered or
    /// not: only then is the button given back when the clock leaves. One
    /// still waiting its turn when the clock leaves never goes.
    var doorSent = false
    /// Found out of reach, and the hub's last event then: every call of
    /// that event or an earlier one, still queued, fails at once, and the
    /// next event tries the clock again.
    var outOfReach: (through: Int, reason: String)?

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
}
