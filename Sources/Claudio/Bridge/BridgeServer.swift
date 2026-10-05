import Foundation
import Network

/// The socket the plugin talks to: a WebSocket listener on the loopback
/// address and an ephemeral port, whose number and token are published in
/// the handshake file. Nothing here decides anything — it hands the frames
/// it admits to `onCommand` and writes back what it is given.
///
/// Transport only, which is why no test starts one: the frames are values
/// (`BridgeMessage`), and the one decision this file makes — who is let in —
/// is `admit(firstFrame:token:)`, a pure function proved in `BridgeHelloTests`.
@MainActor
final class BridgeServer {
    /// A frame bigger than this is nobody's: a command is a few dozen bytes.
    static let maximumFrameSize = 65_536
    /// How long a fresh connection has to say `hello`. A socket held open
    /// saying nothing is not a plugin.
    static let handshakeTimeout: Duration = .seconds(2)
    /// How many connections are held at once, those still to say `hello`
    /// included. A Stream Deck runs one plugin, and its property inspector
    /// may hold a second: sixteen is far past anyone's use, and it keeps
    /// something looping on connect from eating the app's descriptors.
    static let maximumClients = 16

    private let token: String
    private let onCommand: (BridgeInbound) -> Void
    /// What a plugin is told Claudio is doing the moment it is let in: read
    /// at that moment, never cached, so a plugin starting mid-dictation sees
    /// the dictation.
    private let welcomeState: () -> BridgeState
    private let appVersion: String

    private var listener: NWListener?
    /// Every live connection, those still to say `hello` included.
    private var clients: [Client] = []
    /// The last count handed to `onClientCountChange`, so a connection that
    /// comes and goes without ever saying hello changes nothing on screen.
    private var announcedClientCount = 0

    /// Handed the port the listener landed on, once it is ready.
    var onReady: ((UInt16) -> Void)?
    var onClientCountChange: ((Int) -> Void)?
    /// The listener gave up. Whoever published the way in is the one that
    /// has to take it back: this file knows nothing of a handshake file.
    var onFailure: (() -> Void)?

    /// How many plugins are actually connected: a connection counts once it
    /// has said `hello`, not before.
    private var clientCount: Int { clients.count(where: \.hasSaidHello) }

    init(token: String,
         onCommand: @escaping (BridgeInbound) -> Void,
         welcomeState: @escaping () -> BridgeState,
         appVersion: String) {
        self.token = token
        self.onCommand = onCommand
        self.welcomeState = welcomeState
        self.appVersion = appVersion
    }

    // MARK: - Listening

    /// Binds to 127.0.0.1 on a port the system picks. Loopback only: the
    /// bridge is never reachable from another machine, whatever the network
    /// Claudio sits on.
    func start() throws {
        guard listener == nil else { return }

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let websocket = NWProtocolWebSocket.Options()
        websocket.autoReplyPing = true
        // Refused by the stack rather than buffered whole and thrown away
        // here. The check on the frame below stays all the same: this is a
        // setting, not a guarantee.
        websocket.maximumMessageSize = Self.maximumFrameSize
        parameters.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)

        let listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in self?.listenerMoved(to: state) }
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        self.listener = listener
        listener.start(queue: .main)
    }

    private func listenerMoved(to state: NWListener.State) {
        switch state {
        case .ready:
            guard let port = listener?.port?.rawValue else { return }
            // The handshake file is written from here: a port published
            // before the listener answers is a plugin knocking on nothing.
            onReady?(port)
        case .failed:
            // Nothing left to answer with. Said out loud, because a failure
            // after `.ready` leaves a handshake file pointing at a port
            // nobody is on — and only the facade can take that back.
            stop()
            onFailure?()
        default:
            break
        }
    }

    /// Says goodbye, then closes everything. The `bye` matters: a plugin
    /// that only sees its socket drop can't tell a quit from a crash.
    func stop() {
        let leaving = clients
        clients = []
        announceClientCount()
        for client in leaving {
            client.handshakeTimer?.cancel()
            client.handshakeTimer = nil
            send(.bye, to: client, thenClose: true)
        }
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        // Stopped between the listener's handoff and this hop: nothing left
        // to be a client of. Past the cap, the answer is the same — turned
        // away at the door rather than given a timer and a buffer.
        guard listener != nil, clients.count < Self.maximumClients else {
            connection.cancel()
            return
        }
        let client = Client(connection: connection)
        clients.append(client)

        connection.stateUpdateHandler = { [weak self, weak client] state in
            Task { @MainActor in
                guard let self, let client else { return }
                switch state {
                case .failed, .cancelled: self.drop(client)
                default: break
                }
            }
        }
        client.handshakeTimer = Task { [weak self, weak client] in
            try? await Task.sleep(for: Self.handshakeTimeout)
            guard !Task.isCancelled, let self, let client else { return }
            self.drop(client)
        }
        connection.start(queue: .main)
        receive(on: client)
    }

    private func receive(on client: Client) {
        client.connection.receiveMessage { [weak self, weak client] data, context, _, error in
            Task { @MainActor in
                guard let self, let client else { return }
                self.received(data, context: context, error: error, on: client)
            }
        }
    }

    private func received(_ data: Data?, context: NWConnection.ContentContext?,
                          error: NWError?, on client: Client) {
        guard isLive(client) else { return }  // dropped while this was in flight
        guard error == nil else {
            drop(client)
            return
        }
        let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
            as? NWProtocolWebSocket.Metadata
        switch metadata?.opcode {
        case .text:
            // Anything past the ceiling is not a command. Dropped rather
            // than read: a frame that big is either a bug or an attack.
            guard let data, data.count <= Self.maximumFrameSize else {
                drop(client)
                return
            }
            handle(data, on: client)
        case .ping, .pong:
            break  // answered by the stack itself
        default:
            // A close, a binary frame, a continuation: this protocol is text.
            drop(client)
            return
        }
        guard isLive(client) else { return }
        receive(on: client)
    }

    /// The first frame is the handshake, every later one a command.
    private func handle(_ data: Data, on client: Client) {
        guard client.hasSaidHello else {
            switch Self.admit(firstFrame: data, token: token) {
            case .failure(let code):
                send(Self.refusal(code), to: client, thenClose: true)
            case .success:
                client.hasSaidHello = true
                client.handshakeTimer?.cancel()
                client.handshakeTimer = nil
                send(.welcome(version: BridgeProtocol.version, app: appVersion,
                              state: welcomeState()), to: client)
                announceClientCount()
            }
            return
        }
        // A frame from a plugin that speaks a newer dialect: ignored, never
        // guessed at. The connection stays — the keys that do parse go on
        // working.
        guard let message = try? JSONDecoder().decode(BridgeInbound.self, from: data) else { return }
        onCommand(message)
    }

    private func drop(_ client: Client) {
        client.handshakeTimer?.cancel()
        client.handshakeTimer = nil
        client.connection.cancel()
        clients.removeAll { $0 === client }
        announceClientCount()
    }

    private func isLive(_ client: Client) -> Bool {
        clients.contains { $0 === client }
    }

    private func announceClientCount() {
        let count = clientCount
        guard count != announcedClientCount else { return }
        announcedClientCount = count
        onClientCountChange?(count)
    }

    // MARK: - Writing

    /// Sends to every plugin that has said `hello`. The state goes out
    /// whole, so a plugin that misses one frame is right at the next.
    func broadcast(_ message: BridgeOutbound) {
        for client in clients where client.hasSaidHello {
            send(message, to: client)
        }
    }

    /// `thenClose` waits for the frame to actually go out before cancelling:
    /// a refusal cancelled on the spot would never be read.
    private func send(_ message: BridgeOutbound, to client: Client, thenClose: Bool = false) {
        guard let data = try? JSONEncoder().encode(message) else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "bridge", metadata: [metadata])
        // The connection is what the closing path holds, not the client:
        // `stop()` lets go of every client before the `bye` has gone out,
        // and a socket nobody cancels stays open until the app quits.
        let connection = client.connection
        connection.send(
            content: data, contentContext: context, isComplete: true,
            completion: .contentProcessed { [weak self, weak client] _ in
                guard thenClose else { return }
                connection.cancel()
                // Bookkeeping, for a client still on the list — a refusal
                // rather than a stop. Its own cancel above is what closes.
                Task { @MainActor in
                    guard let self, let client else { return }
                    self.drop(client)
                }
            })
    }

    // MARK: - The door

    /// Whether a connection's first frame lets it in. Pure, so the one
    /// decision the bridge makes is proved without a socket.
    ///
    /// `.version` for a plugin speaking another protocol, `.token` for
    /// everything else — a wrong token, a command sent before the handshake,
    /// or bytes that are no frame at all: there is nothing in those to read
    /// a version from, so they are strangers rather than old plugins.
    nonisolated static func admit(firstFrame: Data,
                                  token: String) -> Result<Void, BridgeErrorCode> {
        guard let message = try? JSONDecoder().decode(BridgeInbound.self, from: firstFrame),
              case .hello(let version, let sent, _) = message else {
            return .failure(.token)
        }
        guard version == BridgeProtocol.version else { return .failure(.version) }
        guard sent.isEqualInConstantTime(to: token) else { return .failure(.token) }
        return .success(())
    }

    /// What goes back before the door closes. English, like every frame on
    /// this wire: it is read in a plugin's log, never shown in Claudio.
    nonisolated static func refusal(_ code: BridgeErrorCode) -> BridgeOutbound {
        switch code {
        case .version: .error(code: code, message: "Unsupported protocol version")
        case .token: .error(code: code, message: "Unknown token")
        }
    }
}

/// One connection and what the server remembers about it.
@MainActor
private final class Client {
    let connection: NWConnection
    /// Until this is true, the only frame that will be read is a handshake.
    var hasSaidHello = false
    /// Closes a connection that says nothing. Cancelled by the handshake,
    /// and by anything else that ends the connection first.
    var handshakeTimer: Task<Void, Never>?

    init(connection: NWConnection) {
        self.connection = connection
    }
}
