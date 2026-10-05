import AppKit

/// Claudio as the hub between Claude Code and the Ulanzi. The hook relay
/// posts each session's events here; the board turns them into what the
/// clock shows; and the clock's middle button comes back here, to take the
/// alert on screen away and bring its conversation to the front in the
/// Claude app.
///
/// It holds the server, the handshake file, the board and the client, and
/// sends to the clock one call at a time, in order. What it reaches outside
/// is injected: the device, the Mac's address, the sessions folder, how a
/// link opens, the time, and the listening itself, which a test skips.
@MainActor
final class ClaudeCodeHub {
    /// For Settings, which shows none of it yet.
    enum Status: Equatable {
        case off
        case listening(port: UInt16)
        case failed(String)
    }

    /// The file the relay reads, in Claudio's Application Support folder.
    nonisolated static let handshakeName = "claude-code-hub.json"

    private let makeClient: (URL) -> UlanziClient
    private let localAddress: () -> String?
    private let sessionsDirectory: URL
    private let openURL: (URL) -> Void
    private let now: () -> Date
    private let handshake: BridgeHandshakeFile
    private let listen: (HubServer) throws -> Void

    private var server: HubServer?
    private var client: UlanziClient?
    private var token: String?
    private var port: UInt16?
    private var board = ClaudeCodeBoard()
    /// The button callback is still to be set on the clock: from the moment
    /// the listener is ready until a setting lands. A failure sets it back,
    /// and the next hook event tries again.
    private var callbackPending = false
    /// Bumped by every start and stop: a call still on its way from an
    /// earlier run writes nothing over the current one.
    private var run = 0

    /// The last call queued for the clock. Each waits for the one before.
    private(set) var sending: Task<Void, Never>?

    private(set) var status: Status = .off {
        didSet {
            guard status != oldValue else { return }
            onStatusChange?(status)
        }
    }
    var onStatusChange: ((Status) -> Void)?

    init(makeClient: @escaping (URL) -> UlanziClient = { UlanziClient(baseURL: $0) },
         localAddress: @escaping () -> String? = LocalNetworkAddress.current,
         sessionsDirectory: URL = ClaudeCodeSessionLink.defaultDirectory,
         openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) },
         now: @escaping () -> Date = { Date() },
         handshake: BridgeHandshakeFile = BridgeHandshakeFile(name: ClaudeCodeHub.handshakeName),
         listen: @escaping @MainActor (HubServer) throws -> Void = { try $0.start() }) {
        self.makeClient = makeClient
        self.localAddress = localAddress
        self.sessionsDirectory = sessionsDirectory
        self.openURL = openURL
        self.now = now
        self.handshake = handshake
        self.listen = listen
    }

    // MARK: - Switching on and off

    /// Listens for the relay and the clock, on the clock at `address`. The
    /// way in is published once the listener is ready.
    func start(address: URL) {
        if client != nil { stop() }
        run += 1
        let token = BridgeHandshakeFile.makeToken()
        let server = HubServer(token: token, onRoute: { [weak self] in self?.receive($0) })
        server.onReady = { [weak self] in self?.listenerReady(port: $0) }
        server.onFailure = { [weak self] in self?.fail($0) }
        self.token = token
        self.server = server
        client = makeClient(address)
        do {
            try listen(server)
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// Stops listening, takes the way in away and forgets everything. The
    /// button callback stays on the clock: a press posted to a port nobody
    /// listens on does nothing, and the next start sets it again.
    func stop() {
        run += 1
        server?.stop()
        server = nil
        handshake.remove()
        client = nil
        token = nil
        port = nil
        board = ClaudeCodeBoard()
        callbackPending = false
        status = .off
    }

    /// Off, saying why.
    private func fail(_ reason: String) {
        stop()
        status = .failed(reason)
    }

    // MARK: - What the server hands on

    /// The listener is up on `port`: the relay can find it, and the clock is
    /// told where to post its buttons. A file that can't be written is a
    /// hub nobody finds: better off than listening in silence.
    func listenerReady(port: UInt16) {
        guard let token else { return }
        do {
            try handshake.write(port: port, token: token, pid: ProcessInfo.processInfo.processIdentifier)
        } catch {
            return fail(error.localizedDescription)
        }
        self.port = port
        status = .listening(port: port)
        callbackPending = true
        setButtonCallbackIfPending()
    }

    /// A route the server let in, and has answered already.
    func receive(_ route: HubRoute) {
        guard client != nil else { return }
        switch route {
        case .hookEvent(let body):
            if let event = ClaudeCodeEvent(body) {
                board.handle(event, now: now()).forEach { enqueue(.command($0)) }
            }
            setButtonCallbackIfPending()
        case .button(let body):
            guard UlanziButtonReport.isMiddlePress(body) else { return }
            let press = board.middleButtonPressed(now: now())
            press.commands.forEach { enqueue(.command($0)) }
            // Opened at once, without waiting for the clock: the firmware
            // took the alert off the screen already.
            if let id = press.sessionID,
               let link = ClaudeCodeSessionLink.url(forSession: id, in: sessionsDirectory) {
                openURL(link)
            }
        }
    }

    // MARK: - Sending

    private enum Call: Sendable {
        case command(UlanziCommand)
        case buttonCallback(URL)
    }

    /// The Mac's address, the port and the token, for the clock to post its
    /// buttons to. Without an address, nothing yet: it is looked for again
    /// at the next event.
    private func setButtonCallbackIfPending() {
        guard callbackPending, let port, let token, let host = localAddress(),
              let url = URL(string: "http://\(host):\(port)/ulanzi/button/\(token)") else { return }
        callbackPending = false
        enqueue(.buttonCallback(url))
    }

    /// Queues `call` behind every call before it. One that fails is said in
    /// the status, and the next goes all the same; a callback or an
    /// indicator that failed goes again with the next event. Every
    /// dismissal's answer goes back to the board, which keeps its queue in
    /// step with what the clock shows.
    private func enqueue(_ call: Call) {
        guard let client else { return }
        let run = self.run
        let previous = sending
        sending = Task { [weak self] in
            await previous?.value
            guard let self, self.run == run else { return }
            do {
                switch call {
                case .command(let command): try await client.perform(command)
                case .buttonCallback(let url): try await client.setButtonCallback(url)
                }
                guard self.run == run else { return }
                if case .command(.dismiss(let name)) = call { board.dismissLanded(name: name) }
                if let port { status = .listening(port: port) }
            } catch {
                guard self.run == run else { return }
                switch call {
                case .buttonCallback: callbackPending = true
                case .command(.indicator): board.indicatorFailed()
                case .command(.dismiss(let name)): board.dismissFailed(name: name)
                case .command(.notify): break
                }
                status = .failed(error.localizedDescription)
            }
        }
    }
}
