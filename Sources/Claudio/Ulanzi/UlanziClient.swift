import Foundation

/// The four calls Claudio makes to an Ulanzi under AWTRIX NG 1.1.2: read the
/// face script installed, install it, set its gaze, summon the face. Nothing
/// else: the clock animates the face itself, and the bridge decides when to
/// call.
///
/// The transport is injected, URLSession by default: a test hands it a fake
/// device and no socket is opened. A clock on the local network answers in a
/// few milliseconds or not at all, so every call gives up after 2.5 s.
struct UlanziClient: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    /// What can go wrong, said the way Settings shows it: in the device's
    /// own words when it gave some, never as its JSON.
    enum Failure: Error, Equatable {
        /// No answer at all: unplugged, another network, a typo in the address.
        case unreachable(String)
        /// An answer, and a no: the status, and the device's message.
        case rejected(status: Int, message: String)
        /// The device took the script and can't run it, as it says.
        case scriptBroken(String)
    }

    static let timeout: TimeInterval = 2.5

    let baseURL: URL
    private let transport: Transport

    init(baseURL: URL, transport: @escaping Transport = UlanziClient.urlSession) {
        self.baseURL = baseURL
        self.transport = transport
    }

    /// URLSession, which is how the app calls the clock.
    static let urlSession: Transport = { request in
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }

    // MARK: - The face script

    private var scriptPath: String { "api/v1/apps/script/\(UlanziFaceScript.appName)" }

    /// The source the device holds, as it holds it: the firmware hands it
    /// back byte for byte. `nil` when it has none.
    func installedScript() async throws -> String? {
        let (data, status) = try await send("GET", scriptPath)
        if status == 404 { return nil }
        guard (200..<300).contains(status) else {
            throw Failure.rejected(status: status, message: Self.message(in: data))
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Installs `source`, or replaces the script there. The device takes a
    /// script it can't run all the same, and says so in `error`.
    func install(_ source: String) async throws {
        try await expectSuccess(send("PUT", scriptPath, body: Data(source.utf8), type: "text/plain"))
    }

    // MARK: - The gaze, and the face

    /// Sets the gaze, and only the gaze: the colours stay as the device has
    /// them, and a key the script doesn't declare gets the whole body
    /// refused. The script restarts in its place in the rotation.
    func setGaze(_ gaze: String) async throws {
        let body = try Self.json(["gaze": gaze])
        try await expectSuccess(send("PATCH", "api/v1/apps/\(UlanziFaceScript.appName)/config",
                                     body: body, type: "application/json"))
    }

    /// Brings the face on screen now, rather than at its turn in the rotation.
    func show() async throws {
        let body = try Self.json(["name": UlanziFaceScript.appName, "fast": true])
        try await expectSuccess(send("PUT", "api/v1/apps/active", body: body, type: "application/json"))
    }

    // MARK: - Transport

    /// Every failure to get an answer is the same one for whoever reads it:
    /// the device is out of reach.
    private func send(_ method: String, _ path: String,
                      body: Data? = nil, type: String? = nil) async throws -> (data: Data, status: Int) {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = Self.timeout
        // The script read has to be what the device holds now, not a copy.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let type { request.setValue(type, forHTTPHeaderField: "Content-Type") }
        request.httpBody = body
        do {
            let (data, response) = try await transport(request)
            return (data, response.statusCode)
        } catch {
            throw Failure.unreachable(error.localizedDescription)
        }
    }

    /// What the firmware says when all is well: a 2xx, `"error":null`, and
    /// no `ok: false`. A refusal comes under its own status. An `error` under
    /// a 2xx is the script's: the firmware takes a script it can't run, and
    /// says so there, at install and at the restart every config change
    /// triggers; it is an object, never a string.
    private func expectSuccess(_ answer: (data: Data, status: Int)) throws {
        let object = Self.object(answer.data)
        guard (200..<300).contains(answer.status) else {
            throw Failure.rejected(status: answer.status, message: Self.message(in: answer.data))
        }
        if let error = object?["error"], !(error is NSNull) {
            throw Failure.scriptBroken(Self.message(in: answer.data))
        }
        guard object?["ok"] as? Bool != false else {
            throw Failure.rejected(status: answer.status, message: Self.message(in: answer.data))
        }
    }

    /// Sorted keys: the same body for the same call, every time.
    private static func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// What the device said, for a line in Settings: the `message` of its
    /// `error` object when it gave one, the answer itself otherwise, cut
    /// short.
    private static func message(in data: Data) -> String {
        let error = object(data)?["error"]
        if let message = (error as? [String: Any])?["message"] as? String ?? error as? String {
            return message
        }
        return String(decoding: data.prefix(200), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension UlanziClient.Failure: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unreachable(let reason):
            reason
        case .rejected(let status, let message) where message.isEmpty:
            loc("l'appareil a répondu \(status)", en: "the device answered \(status)")
        case .rejected(_, let message):
            message
        case .scriptBroken(let message):
            message
        }
    }
}
