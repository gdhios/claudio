import Foundation
import Network

/// The hub's door: plain TCP and just enough HTTP/1.1, on every interface,
/// since the Ulanzi calls from the local network, and on a port the system
/// picks. One request per connection, answered at once and closed: the
/// relay and the clock wait for nothing, and the hub does its work after.
///
/// Transport only, which is why no test opens one, as with `BridgeServer`:
/// the request is a value (`HubRequest`), and so is the one decision made
/// here, what to answer and what to hand on (`HubRoute.answer`).
@MainActor
final class HubServer {
    /// A request bigger than this is nobody's: an event is a few kilobytes.
    static let maximumRequestSize = 65_536
    /// How long a connection has to send its whole request.
    static let receiveTimeout: Duration = .seconds(2)
    /// How many connections are held at once. The relay sends one request
    /// per hook and the clock one per press and release: sixteen keeps
    /// something looping on connect from eating the app's descriptors.
    static let maximumConnections = 16

    private let token: String
    private let onRoute: (HubRoute) -> Void
    private var listener: NWListener?
    private var connections: [HubConnection] = []

    /// Handed the port the listener landed on, once it is ready.
    var onReady: ((UInt16) -> Void)?
    /// The listener gave up, for this reason. Whoever published the way in
    /// takes it back.
    var onFailure: ((String) -> Void)?

    init(token: String, onRoute: @escaping (HubRoute) -> Void) {
        self.token = token
        self.onRoute = onRoute
    }

    // MARK: - Listening

    /// Listens on every interface, on a port the system picks.
    func start() throws {
        guard listener == nil else { return }
        let listener = try NWListener(using: .tcp)
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            Task { @MainActor in
                // A listener stopped since says nothing more.
                guard let self, let listener, self.listener === listener else { return }
                self.listenerMoved(to: state)
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        self.listener = listener
        listener.start(queue: .main)
    }

    func stop() {
        let open = connections
        connections = []
        open.forEach { $0.close() }
        listener?.cancel()
        listener = nil
    }

    private func listenerMoved(to state: NWListener.State) {
        switch state {
        case .ready:
            guard let port = listener?.port?.rawValue else { return }
            onReady?(port)
        case .failed(let error):
            stop()
            onFailure?(error.localizedDescription)
        default:
            break
        }
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        // Stopped since, or past the cap: turned away at the door.
        guard listener != nil, connections.count < Self.maximumConnections else {
            connection.cancel()
            return
        }
        let client = HubConnection(connection)
        connections.append(client)
        connection.stateUpdateHandler = { [weak self, weak client] state in
            Task { @MainActor in
                guard let self, let client else { return }
                switch state {
                case .failed, .cancelled: self.drop(client)
                default: break
                }
            }
        }
        client.timer = Task { [weak self, weak client] in
            try? await Task.sleep(for: Self.receiveTimeout)
            guard !Task.isCancelled, let self, let client else { return }
            self.drop(client)
        }
        connection.start(queue: .main)
        receive(on: client)
    }

    private func receive(on client: HubConnection) {
        let most = Self.maximumRequestSize + 1
        client.connection.receive(minimumIncompleteLength: 1, maximumLength: most) {
            [weak self, weak client] data, _, isComplete, error in
            let failed = error != nil
            Task { @MainActor in
                guard let self, let client else { return }
                self.received(data, isComplete: isComplete, failed: failed, on: client)
            }
        }
    }

    private func received(_ data: Data?, isComplete: Bool, failed: Bool, on client: HubConnection) {
        guard connections.contains(where: { $0 === client }), !client.answered else { return }
        if let data { client.buffer.append(data) }
        guard !failed else { return drop(client) }
        guard client.buffer.count <= Self.maximumRequestSize else { return answer(413, to: client) }
        switch HubRequest.read(client.buffer) {
        case .complete(let request):
            let (status, route) = HubRoute.answer(request, token: token)
            // Answered before the hub does anything: neither the relay nor
            // the clock waits for the work.
            answer(status, to: client)
            if let route { onRoute(route) }
        case .malformed:
            answer(400, to: client)
        case .incomplete where isComplete:
            answer(400, to: client)  // the sender stopped short
        case .incomplete:
            receive(on: client)
        }
    }

    /// Answers, and closes once the answer is out.
    private func answer(_ status: Int, to client: HubConnection) {
        client.answered = true
        let connection = client.connection
        connection.send(content: HubResponse.data(status: status), isComplete: true,
                        completion: .contentProcessed { _ in connection.cancel() })
    }

    private func drop(_ client: HubConnection) {
        client.close()
        connections.removeAll { $0 === client }
    }
}

/// One connection and what the server keeps of it.
@MainActor
private final class HubConnection {
    let connection: NWConnection
    var buffer = Data()
    /// The answer is on its way: nothing more is read.
    var answered = false
    /// Closes a connection that hasn't sent its whole request in time, or
    /// whose answer never went out.
    var timer: Task<Void, Never>?

    init(_ connection: NWConnection) {
        self.connection = connection
    }

    func close() {
        timer?.cancel()
        timer = nil
        connection.cancel()
    }
}
