import AppKit

/// Claudio as the hub between Claude Code and the Ulanzi clocks. The hook
/// relay posts each session's events here; the board turns them into what
/// the clocks show; and the middle button of any of them comes back here,
/// to take the alert on screen away and bring its conversation to the front
/// in the Claude app.
///
/// It holds the server, the handshake file and the one board, and a link
/// per clock with the flags ticked (`ClaudeCodeHub+Clocks.swift`): every
/// clock hears every command, one call at a time, in order, on its own. The
/// board outlives Claudio in a file of its own, as the clocks outlive it.
/// What the hub reaches outside is injected: the devices, the Mac's
/// address, the sessions folder, how a link opens, the time, the two files,
/// and the listening itself, which a test skips.
@MainActor
final class ClaudeCodeHub {
    /// The relay's door, for Settings. Each clock has a status of its own.
    enum Status: Equatable {
        case off
        case listening(port: UInt16)
        /// The server could not listen, or stopped listening: why.
        case failed(String)
    }

    /// The file the relay reads, in Claudio's Application Support folder.
    nonisolated static let handshakeName = "claude-code-hub.json"

    // Internal rather than private, for the clocks' own file.
    let makeClient: (URL) -> UlanziClient
    let localAddress: () -> String?
    let now: () -> Date
    private let sessionsDirectory: URL
    private let openURL: (URL) -> Void
    private let handshake: BridgeHandshakeFile
    private let boardFile: ClaudeCodeBoardFile
    private let listen: (HubServer) throws -> Void

    private var server: HubServer?
    private(set) var token: String?
    private(set) var port: UInt16?
    var board = ClaudeCodeBoard()
    /// The board as last written, so as not to write it again unchanged.
    private var savedBoard: ClaudeCodeBoard.Snapshot?
    /// The clocks with the flags, in Settings' order.
    var links: [ClaudeCodeClockLink] = []
    /// The board's commands on their way, until every clock has answered.
    var deliveries = ClaudeCodeDeliveries()
    /// Bumped by every start and stop: a call still on its way from an
    /// earlier run writes nothing over the current one.
    private(set) var run = 0
    /// Every hook event and every report of a button, numbered, and the
    /// listener's readiness too: each call carries the number of the one
    /// that brought it.
    private(set) var events = 0

    private(set) var status: Status = .off {
        didSet {
            guard status != oldValue else { return }
            onStatusChange?(status)
        }
    }
    var onStatusChange: ((Status) -> Void)?
    /// A clock's status moved: its id, and where it stands.
    var onClockStatusChange: ((UUID, ClockStatus) -> Void)?

    init(makeClient: @escaping (URL) -> UlanziClient = { UlanziClient(baseURL: $0) },
         localAddress: @escaping () -> String? = LocalNetworkAddress.current,
         sessionsDirectory: URL = ClaudeCodeSessionLink.defaultDirectory,
         openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) },
         now: @escaping () -> Date = { Date() },
         handshake: BridgeHandshakeFile = BridgeHandshakeFile(name: ClaudeCodeHub.handshakeName),
         boardFile: ClaudeCodeBoardFile = ClaudeCodeBoardFile(),
         listen: @escaping @MainActor (HubServer) throws -> Void = { try $0.start() }) {
        self.makeClient = makeClient
        self.localAddress = localAddress
        self.sessionsDirectory = sessionsDirectory
        self.openURL = openURL
        self.now = now
        self.handshake = handshake
        self.boardFile = boardFile
        self.listen = listen
    }

    // MARK: - Switching on and off

    /// Brings the hub in line with `clocks`: it speaks to those with the
    /// flags ticked. The first one starts the server; the last one gone
    /// stops it; in between, the server and its token stay as they are,
    /// and only the clocks that came or moved get a link of their own.
    func apply(_ clocks: [UlanziClock]) {
        let flagged = Self.flagged(in: clocks)
        guard !flagged.isEmpty else { return stop() }
        let starting = server == nil
        if starting { prepareRun() }
        relink(to: flagged)
        if starting {
            listenNow()
        } else {
            setButtonCallbackIfNeeded()
        }
    }

    /// The clocks with the flags, each id once: its first entry decides.
    private static func flagged(in clocks: [UlanziClock]) -> [UlanziClock] {
        var seen = Set<UUID>()
        return clocks.filter { seen.insert($0.id).inserted && $0.alerts }
    }

    /// A new run: the board taken back as the last run left it, since the
    /// clocks kept their alerts meanwhile, and a server with a new token,
    /// not listening yet. The way in is published once the listener is
    /// ready.
    private func prepareRun() {
        run += 1
        board = ClaudeCodeBoard(restoring: boardFile.load() ?? ClaudeCodeBoard.Snapshot(), now: now())
        savedBoard = board.snapshot
        let token = BridgeHandshakeFile.makeToken()
        let server = HubServer(token: token, onRoute: { [weak self] in self?.receive($0) })
        server.onReady = { [weak self] in self?.listenerReady(port: $0) }
        server.onFailure = { [weak self] in self?.fail($0) }
        self.token = token
        self.server = server
    }

    private func listenNow() {
        guard let server else { return }
        do {
            try listen(server)
        } catch {
            fail(error.localizedDescription)
        }
    }

    /// Stops listening, takes the way in away, lets every clock go and
    /// forgets the run. The board file stays, the clocks keeping their
    /// alerts; so does the button callback on each clock: a press posted
    /// to a port nobody listens on does nothing, and the next start sets it
    /// again.
    func stop() {
        run += 1
        server?.stop()
        server = nil
        handshake.remove()
        let dropped = links
        links = []
        deliveries = ClaudeCodeDeliveries()
        token = nil
        port = nil
        board = ClaudeCodeBoard()
        savedBoard = nil
        status = .off
        dropped.forEach(forget)
    }

    /// Off, saying why.
    private func fail(_ reason: String) {
        stop()
        status = .failed(reason)
    }

    // MARK: - What the server hands on

    /// The listener is up on `port`: the relay can find it, and every clock
    /// is told where to post its buttons. A file that can't be written is a
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
        links.forEach { $0.callbackHost = nil }
        events += 1
        setButtonCallbackIfNeeded()
    }

    /// A route the server let in, and has answered already. A press on any
    /// clock acts on the one board.
    func receive(_ route: HubRoute) {
        guard !links.isEmpty else { return }
        events += 1
        defer { saveBoard() }
        switch route {
        case .hookEvent(let body):
            if let event = ClaudeCodeEvent(body) {
                board.handle(event, now: now()).forEach(enqueue)
            }
            setButtonCallbackIfNeeded()
        case .button(let body):
            guard UlanziButtonReport.isMiddlePress(body) else { return }
            let press = board.middleButtonPressed(now: now())
            press.commands.forEach(enqueue)
            // Opened at once, without waiting for the clocks: the firmware
            // of the one pressed took the alert off its screen already.
            if let id = press.sessionID,
               let link = ClaudeCodeSessionLink.url(forSession: id, in: sessionsDirectory) {
                openURL(link)
            }
        }
    }

    /// Writes the board down when it changed. One that can't be written is
    /// tried again at the next change.
    func saveBoard() {
        let snapshot = board.snapshot
        guard snapshot != savedBoard, (try? boardFile.save(snapshot)) != nil else { return }
        savedBoard = snapshot
    }
}
