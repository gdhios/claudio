import Foundation

/// The bridge as one thing to switch on and off. It holds the socket, the
/// handshake file and the publisher, and hands the frames it receives to the
/// dispatcher — so the app only ever calls `start()`, `stop()` and `attach`.
///
/// Wiring, and nothing else: every piece it holds is proved on its own, and
/// what this file adds — the order they start in — is proved by running the
/// app with the probe.
@MainActor
final class StreamDeckBridge {
    /// What Settings shows. `waiting` means the socket is up and the
    /// handshake file written: everything Claudio can do is done, and the
    /// plugin is the one that hasn't come.
    enum Status: Equatable {
        case off
        case waiting
        case connected(clients: Int)
    }

    /// The app's own version, sent in the welcome. `swift run` has no
    /// bundle, hence the fallback.
    static var bundleVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private let dispatcher: BridgeDispatcher
    private let handshake: BridgeHandshakeFile
    private let appVersion: String

    private var server: BridgeServer?
    private var publisher: BridgeStatePublisher?
    /// The two coordinators, whose hooks stay in place between a stop and
    /// the next start. Weak: the app owns them, and outlives the bridge.
    private weak var correction: CorrectionCoordinator?
    private weak var dictation: DictationCoordinator?

    private(set) var status: Status = .off {
        didSet {
            guard status != oldValue else { return }
            onStatusChange?(status)
        }
    }
    var onStatusChange: ((Status) -> Void)?

    init(dispatcher: BridgeDispatcher,
         handshake: BridgeHandshakeFile = .init(),
         appVersion: String = StreamDeckBridge.bundleVersion) {
        self.dispatcher = dispatcher
        self.handshake = handshake
        self.appVersion = appVersion
    }

    // MARK: - Switching on

    /// Opens the socket, then publishes the way in. In that order: a
    /// handshake file naming a port that isn't listening yet sends the
    /// plugin knocking on nothing.
    func start() {
        guard server == nil else { return }

        let token = BridgeHandshakeFile.makeToken()
        let publisher = BridgeStatePublisher(send: { [weak self] in self?.server?.broadcast($0) })
        let server = BridgeServer(
            token: token,
            onCommand: { [weak self] message in _ = self?.dispatcher.dispatch(message) },
            // Read at the handshake, never cached: a plugin starting
            // mid-dictation is told about the dictation.
            welcomeState: { [weak self] in self?.publisher?.current ?? .idle },
            appVersion: appVersion)

        server.onReady = { [weak self] port in
            guard let self else { return }
            // A file that can't be written is a bridge nobody can find:
            // better off than listening in silence.
            do {
                try handshake.write(port: port, token: token,
                                    pid: ProcessInfo.processInfo.processIdentifier)
            } catch {
                return stop()
            }
            status = .waiting
        }
        server.onClientCountChange = { [weak self] count in
            self?.status = count > 0 ? .connected(clients: count) : .waiting
        }

        self.publisher = publisher
        self.server = server
        do {
            try server.start()
        } catch {
            return stop()
        }
        adoptCurrentSessions()
    }

    /// Says goodbye, closes the socket and takes the handshake file away.
    func stop() {
        server?.stop()
        server = nil
        publisher = nil
        handshake.remove()
        status = .off
    }

    // MARK: - What it watches

    /// Hooks the two coordinators up for good: the hooks stay in place
    /// across a stop and the next start, and say nothing while the bridge is
    /// off, since there is no publisher to tell.
    func attach(correction: CorrectionCoordinator, dictation: DictationCoordinator) {
        self.correction = correction
        self.dictation = dictation
        correction.onSessionChange = { [weak self] session in
            self?.publisher?.correctionSessionChanged(session)
        }
        dictation.onSessionChange = { [weak self] session in
            self?.publisher?.dictationSessionChanged(session)
        }
        adoptCurrentSessions()
    }

    /// The hooks only report changes, so a bridge switched on while
    /// something is already under way reads it once, here.
    private func adoptCurrentSessions() {
        publisher?.correctionSessionChanged(correction?.session)
        publisher?.dictationSessionChanged(dictation?.session)
    }
}
