import Foundation
@testable import Claudio

/// One clock's face bridge as the fleet tests have it: it calls no device,
/// writes down what it is asked, and takes the status a test gives it. Its
/// off at quit is whatever the test hands it.
@MainActor
final class FakeFaceBridge: UlanziFaceBridging {
    let address: URL
    private(set) var status: UlanziBridge.Status
    var onStatusChange: ((UlanziBridge.Status) -> Void)?

    private(set) var corrections: [CorrectionSession?] = []
    private(set) var dictations: [DictationSession?] = []
    private(set) var tests = 0
    private(set) var stops = 0
    private(set) var quits = 0
    /// What putting the face away at quit does, off the main actor. nil: the
    /// face can't be up, and there is nothing to send.
    var putAway: UlanziBridge.PutAway?

    init(address: URL, status: UlanziBridge.Status = .installing) {
        self.address = address
        self.status = status
    }

    /// The bridge's status moves, as the device answers.
    func report(_ status: UlanziBridge.Status) {
        self.status = status
        onStatusChange?(status)
    }

    func correctionSessionChanged(_ session: CorrectionSession?) { corrections.append(session) }
    func dictationSessionChanged(_ session: DictationSession?) { dictations.append(session) }
    func test() { tests += 1 }

    func stop() {
        stops += 1
        report(.off)
    }

    func letGoForQuit() -> UlanziBridge.PutAway? {
        quits += 1
        report(.off)
        return putAway
    }
}

/// What the offs sent at quit wrote down, from whichever thread they ran on.
final class QuitLog: @unchecked Sendable {
    private let lock = NSLock()
    private var names: [String] = []

    var sent: [String] { lock.withLock { names } }

    func record(_ name: String) {
        lock.withLock { names.append(name) }
    }
}

/// Lets nobody through until `count` have come: two offs that each wait
/// for the other only both end if they run at the same time.
actor Rendezvous {
    private let count: Int
    private var arrived = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(count: Int) {
        self.count = count
    }

    func arrive() async {
        arrived += 1
        guard arrived < count else {
            waiting.forEach { $0.resume() }
            waiting = []
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }
}
