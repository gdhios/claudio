import Combine
import Foundation

/// What the keys are told, and how often. It watches the two sessions and
/// turns them into frames: the whole state whenever it changes, and the
/// microphone's loudness while a dictation listens.
///
/// Two economies, both on purpose. A state that hasn't changed isn't sent —
/// a plugin redraws a key for every frame, and the Stream Deck allows ten
/// images a second. And the loudness, which moves dozens of times a second,
/// is capped: readings that fall inside the interval are dropped, never
/// queued, because a waveform bar sent late is a lie about now.
@MainActor
final class BridgeStatePublisher {
    private let send: (BridgeOutbound) -> Void
    private let now: () -> Date
    private let minimumLevelInterval: TimeInterval

    /// The session each coordinator holds, as last announced. Held for as
    /// long as that announcement stands and no longer: the end of one is
    /// announced too, and that is what lets go of it — a finished dictation,
    /// and its transcript, is nobody's to keep.
    private var correction: CorrectionSession?
    private var dictation: DictationSession?
    private var correctionSubscriptions: Set<AnyCancellable> = []
    private var dictationSubscriptions: Set<AnyCancellable> = []

    private var lastSent = BridgeState.idle
    private var lastLevelSentAt: Date?
    private var refreshQueued = false
    private var levelQueued = false

    init(send: @escaping (BridgeOutbound) -> Void,
         now: @escaping () -> Date = Date.init,
         minimumLevelInterval: TimeInterval = 0.125) {
        self.send = send
        self.now = now
        self.minimumLevelInterval = minimumLevelInterval
    }

    /// What Claudio is doing right now, read from the sessions themselves.
    var current: BridgeState { BridgeState(correction: correction, dictation: dictation) }

    // MARK: - What it watches

    /// A correction started, or ended. Only its phase can change what the
    /// keys show.
    func correctionSessionChanged(_ session: CorrectionSession?) {
        correction = session
        correctionSubscriptions = []
        if let session {
            watch(session.$phase, in: &correctionSubscriptions)
        }
        schedule()
    }

    /// A dictation started, or ended. Its phase, the lock a tap puts on it,
    /// and the microphone's loudness all reach the keys.
    func dictationSessionChanged(_ session: DictationSession?) {
        dictation = session
        dictationSubscriptions = []
        // A fresh dictation is not held to the last one's budget: its first
        // reading is what tells the plugin the waveform has started.
        lastLevelSentAt = nil
        if let session {
            watch(session.$phase, in: &dictationSubscriptions)
            watch(session.$isLocked, in: &dictationSubscriptions)
            watch(session.$levels, in: &dictationSubscriptions, carriesLevel: true)
        }
        schedule()
    }

    /// Subscribing is no change: `@Published` hands its current value to a
    /// new subscriber, and the announcement below is what asks for the first
    /// frame.
    private func watch<Value>(_ published: Published<Value>.Publisher,
                              in subscriptions: inout Set<AnyCancellable>,
                              carriesLevel: Bool = false) {
        published.dropFirst()
            .sink { [weak self] _ in self?.schedule(withLevel: carriesLevel) }
            .store(in: &subscriptions)
    }

    // MARK: - When it says it

    /// Deferred by one turn, and coalesced. Deferred because a `@Published`
    /// property tells its subscribers *before* it is written: a state read
    /// on the spot would carry the phase the session is leaving. Coalesced
    /// because a coordinator often moves two of them in the same breath, and
    /// that is one thing happening, not two.
    private func schedule(withLevel level: Bool = false) {
        levelQueued = levelQueued || level
        guard !refreshQueued else { return }
        refreshQueued = true
        Task { [weak self] in self?.refresh() }
    }

    private func refresh() {
        refreshQueued = false
        let levelAsked = levelQueued
        levelQueued = false
        publishState()
        // After the state: a plugin learning that a dictation listens, then
        // reading its first bar, is the right order to draw them in.
        if levelAsked { publishLevel() }
    }

    private func publishState() {
        let state = current
        guard state != lastSent else { return }
        lastSent = state
        send(.state(state))
    }

    private func publishLevel() {
        guard let dictation, dictation.phase == .listening,
              let value = dictation.levels.values.last else { return }
        let moment = now()
        if let lastLevelSentAt,
           moment.timeIntervalSince(lastLevelSentAt) < minimumLevelInterval { return }
        lastLevelSentAt = moment
        send(.level(value))
    }
}
