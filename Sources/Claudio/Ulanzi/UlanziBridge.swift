import Foundation

/// Claudio's face on an Ulanzi clock, kept in step with what he does. The
/// clock draws and animates the face itself (`UlanziFaceScript`); this side
/// installs it, then sends one word each time the gaze he wears changes, and
/// summons the face when it comes back from off.
///
/// It reads the state the Stream Deck reads, through a publisher of its own,
/// and keeps the state alone: every config change restarts the script on the
/// clock, and the microphone's loudness moves dozens of times a second.
///
/// Time is injected: the Settings test's smile and the retry after a
/// failure sleep through `sleep`, which a test runs by hand.
@MainActor
final class UlanziBridge {
    /// What Settings shows.
    enum Status: Equatable {
        case off
        case installing
        case ready
        case failed(UlanziClient.Failure)
    }

    /// The gaze that hides the face and gives the screen back to the
    /// clock's own rotation.
    nonisolated static let off = "off"
    /// How long the Settings test keeps Claudio smiling.
    nonisolated static let testHold: Duration = .seconds(4)
    /// How long a failed gaze waits for its one retry: a clock that was busy
    /// for a moment answers the second time.
    nonisolated static let retryDelay: Duration = .seconds(2)

    private let makeClient: (URL) -> UlanziClient
    private let sleep: @MainActor (Duration) async throws -> Void

    private var client: UlanziClient?
    private var publisher: BridgeStatePublisher?
    /// The sessions the app last announced, held weakly, so a bridge switched
    /// on mid-dictation adopts it, as StreamDeckBridge reads its coordinators.
    /// Weak, because a finished dictation, and its transcript, is nobody's to
    /// keep.
    private weak var correction: CorrectionSession?
    private weak var dictation: DictationSession?

    /// The gaze the device last confirmed. nil when unknown: before its first
    /// answer, and after any failure, since a request that timed out may have
    /// landed all the same.
    private var lastSent: String?
    /// The gazes queued and not delivered yet. A failure retries only when
    /// nothing newer waits behind it.
    private var queued = 0
    /// Whether the face is known to be on the device. A failure forgets it:
    /// the next send looks again, and installs if it has to.
    private var isInstalled = false
    /// Bumped by every start and stop. A send still under way from an
    /// earlier run must not write its outcome over the current one.
    private var run = 0

    /// The last thing queued for the device. Each send waits for the one
    /// before, so the clock hears the gazes one at a time, in order.
    private(set) var sending: Task<Void, Never>?
    /// The Settings test under way, its smile and its hold.
    private(set) var testing: Task<Void, Never>?
    /// The retry of a failed gaze, waiting its delay or under way.
    private(set) var retrying: Task<Void, Never>?

    private(set) var status: Status = .off {
        didSet {
            guard status != oldValue else { return }
            onStatusChange?(status)
        }
    }
    var onStatusChange: ((Status) -> Void)?

    init(client: @escaping (URL) -> UlanziClient = { UlanziClient(baseURL: $0) },
         sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        makeClient = client
        self.sleep = sleep
    }

    /// The word the script knows a state by: off while Claudio waits, the
    /// mascot's own gaze while he works.
    nonisolated static func gazeName(for state: BridgeState) -> String {
        state.activity == .idle ? off : state.gaze.rawValue
    }

    /// Whether the clock may be showing the face: a gaze is on its way, or
    /// the last one it confirmed is not off, or nothing is known since a
    /// failure. Quitting then could leave the face up.
    var faceMayBeUp: Bool {
        client != nil && (queued > 0 || lastSent != Self.off)
    }

    // MARK: - Switching on and off

    /// Installs the face if the clock doesn't have it, puts it away (a face
    /// left up by a crash goes at launch), then follows Claudio.
    func start(address: URL) {
        if client != nil { stop() }
        run += 1
        client = makeClient(address)
        status = .installing
        enqueue(Self.off)

        let publisher = BridgeStatePublisher(send: { [weak self] outbound in
            guard case .state(let state) = outbound else { return }
            self?.enqueue(Self.gazeName(for: state))
        })
        self.publisher = publisher
        // The hooks only report changes: what is already under way is read
        // once, here.
        publisher.correctionSessionChanged(correction)
        publisher.dictationSessionChanged(dictation)
    }

    /// Puts the face away, at best, behind whatever is already queued: a
    /// gaze still on its way can't land after it. Nothing else goes out.
    func stop() {
        guard let client = letGo() else { return }
        chain { try? await client.setGaze(Self.off) }
    }

    /// The off a bridge let go at quit still has to send. It runs off the
    /// main actor, which waits for it.
    typealias PutAway = @Sendable () async -> Void

    /// Quitting: the bridge lets go, and the face, if it may be up, goes
    /// before the app does, or is given up on after `limit` seconds,
    /// whichever comes first: a clock that doesn't answer never holds the
    /// quit back.
    func prepareToQuit(within limit: TimeInterval) {
        Self.putAway([letGoForQuit()].compactMap { $0 }, within: limit)
    }

    /// Lets go for good, and hands back the off to send, nil when the face
    /// can't be up: what `prepareToQuit` does before it waits, for a fleet
    /// that waits for all its clocks at once.
    func letGoForQuit() -> PutAway? {
        let mayBeUp = faceMayBeUp
        guard let client = letGo(), mayBeUp else { return nil }
        return { try? await client.setGaze(Self.off) }
    }

    /// Sends every off at once, and waits for them all, `limit` seconds at
    /// most: the clocks answer side by side, so the wait is the slowest
    /// one's, never the sum.
    ///
    /// It waits right here, holding the main thread, so the offs can't go
    /// through the main actor, behind the gazes: they go at once, on their
    /// own, and a gaze already on its way got there first. Quit can come
    /// from a task of the main actor too (the updater's), which then runs
    /// nothing more before the app is gone: a `.terminateLater` waiting on
    /// the main actor would never be answered.
    nonisolated static func putAway(_ offs: [PutAway], within limit: TimeInterval) {
        guard !offs.isEmpty else { return }
        let answered = DispatchSemaphore(value: 0)
        Task.detached {
            await withTaskGroup(of: Void.self) { group in
                for off in offs { group.addTask { await off() } }
            }
            answered.signal()
        }
        _ = answered.wait(timeout: .now() + limit)
    }

    /// Follows nothing more, and forgets the device: the client it called,
    /// nil when it was off already.
    private func letGo() -> UlanziClient? {
        guard let client else { return nil }
        run += 1
        testing?.cancel()
        retrying?.cancel()
        retrying = nil
        self.client = nil
        publisher = nil
        lastSent = nil
        queued = 0
        isInstalled = false
        status = .off
        return client
    }

    // MARK: - What it watches

    /// A correction started or ended, relayed by the app from the
    /// coordinator's hook.
    func correctionSessionChanged(_ session: CorrectionSession?) {
        correction = session
        publisher?.correctionSessionChanged(session)
    }

    /// A dictation started or ended, relayed the same way.
    func dictationSessionChanged(_ session: DictationSession?) {
        dictation = session
        publisher?.dictationSessionChanged(session)
    }

    // MARK: - The Settings button

    /// Claudio smiles on the clock, then the screen goes back to what it
    /// should show: the rotation while he waits, his face if he works. The
    /// smile goes through the same queue as every gaze, so the two never
    /// cross, and is remembered like any other: work starting during the
    /// test takes the screen at once, and the end of the test leaves it be.
    func test() {
        guard client != nil else { return }
        let run = self.run
        testing?.cancel()
        testing = Task { [weak self] in
            await self?.enqueue(ClaudioMascot.Gaze.done.rawValue)?.value
            try? await self?.sleep(Self.testHold)
            guard !Task.isCancelled, let self, self.run == run else { return }
            await enqueue(Self.gazeName(for: publisher?.current ?? .idle))?.value
        }
    }

    // MARK: - Sending

    /// Queues `gaze` for the device, behind everything queued before it. A
    /// newer gaze makes a waiting retry pointless: the clock is to show where
    /// Claudio is now.
    @discardableResult
    private func enqueue(_ gaze: String, retry: Bool = false) -> Task<Void, Never>? {
        guard let client else { return nil }
        if !retry {
            retrying?.cancel()
            retrying = nil
        }
        queued += 1
        let run = self.run
        return chain { [weak self] in
            guard let self, self.run == run else { return }
            let failed = await deliver(gaze, through: client, run: run)
            guard self.run == run else { return }
            queued -= 1
            // The queue ran dry on a failure: one more try in a moment.
            if failed, !retry, queued == 0 { scheduleRetry(of: gaze) }
        }
    }

    /// One more try of `gaze` after `retryDelay`, unless a newer gaze or a
    /// stop comes first. Once: a retry that fails waits for Claudio to move.
    private func scheduleRetry(of gaze: String) {
        let run = self.run
        retrying = Task { [weak self] in
            try? await self?.sleep(Self.retryDelay)
            guard !Task.isCancelled, let self, self.run == run else { return }
            await enqueue(gaze, retry: true)?.value
        }
    }

    /// Runs `work` once everything queued before it is done.
    @discardableResult
    private func chain(_ work: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let previous = sending
        let task = Task { @MainActor in
            await previous?.value
            await work()
        }
        sending = task
        return task
    }

    /// One gaze, and what it takes first: the face installed when that isn't
    /// known, the gaze, then the face summoned if it was hidden. A gaze the
    /// device already shows costs nothing. True when the device failed it,
    /// in the run still current.
    private func deliver(_ gaze: String, through client: UlanziClient, run: Int) async -> Bool {
        do {
            if !isInstalled {
                if try await client.installedScript() != UlanziFaceScript.source {
                    try await client.install(UlanziFaceScript.source)
                }
                guard self.run == run else { return false }
                isInstalled = true
            }
            if gaze != lastSent {
                try await client.setGaze(gaze)
                // Summoned after the gaze: before, it would show the old one.
                if gaze != Self.off, lastSent == nil || lastSent == Self.off {
                    try await client.show()
                }
                guard self.run == run else { return false }
                lastSent = gaze
            }
            status = .ready
            return false
        } catch {
            guard self.run == run else { return false }
            isInstalled = false
            lastSent = nil
            status = .failed(error as? UlanziClient.Failure ?? .unreachable(error.localizedDescription))
            return true
        }
    }
}
