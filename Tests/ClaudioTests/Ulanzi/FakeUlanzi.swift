import XCTest
@testable import Claudio

/// An Ulanzi under AWTRIX NG as the tests have it. It answers the four calls
/// Claudio makes with the bodies the firmware documents: `"error":null` when
/// all is well, the script's own error as an object when it can't run, and a
/// refusal as `{"error":{"code":…,"message":…}}` under its status. It keeps
/// the script it is sent and hands it back as it came, refuses a gaze outside
/// the script's list, and knows no app called Claudio before the script is
/// there. Every request is written down. No socket is opened: `transport` is
/// what the client gets in place of URLSession.
///
/// No time passes here either: a request a test needs in flight is held at
/// the device until the test lets it through. The wall clock only bounds a
/// wait for requests that never come, so that it fails instead of hanging.
///
/// `@unchecked Sendable`: the client calls it off the main actor and the test
/// reads it on the main actor, so a lock keeps the two apart.
final class FakeUlanzi: @unchecked Sendable {
    /// One request as the device received it.
    struct Request {
        let method: String
        let path: String
        let contentType: String?
        let timeout: TimeInterval
        let cachePolicy: URLRequest.CachePolicy
        let body: String
    }

    // MARK: - The firmware's bodies

    static let accepted = #"{"ok":true,"name":"Claudio","error":null}"#

    static func refusal(_ code: String, _ message: String) -> String {
        #"{"error":{"code":"\#(code)","message":"\#(message)"}}"#
    }

    static func broken(_ message: String, line: Int = 12) -> String {
        #"{"ok":true,"name":"Claudio","error":{"message":"\#(message)","line":\#(line)}}"#
    }

    private let lock = NSLock()
    private var received: [Request] = []
    private var installed: String?
    private var shown = "off"
    private var unplugged = false
    private var failure: String?
    private var overrides: [String: (status: Int, body: String)] = [:]
    private var holding = false
    private var held: [CheckedContinuation<Void, Never>] = []
    private var arrivals: [(id: Int, count: Int, continuation: CheckedContinuation<Bool, Never>)] = []
    private var lastArrivalID = 0
    private var atOnce = 0
    private var mostAtOnce = 0

    init(script: String? = nil) {
        installed = script
    }

    // MARK: - What the test reads

    var requests: [Request] { lock.withLock { received } }

    /// "METHOD /path", in order: what most tests compare.
    var calls: [String] { requests.map { "\($0.method) \($0.path)" } }

    /// The script the device holds, `nil` when it has none.
    var script: String? { lock.withLock { installed } }

    /// The gaze the script was last configured with.
    var gaze: String { lock.withLock { shown } }

    /// The most requests the device was ever handling at the same time.
    var mostRequestsAtOnce: Int { lock.withLock { mostAtOnce } }

    /// Returns once the device has received `count` requests since the last
    /// `clearRequests()`, answered or not. Past two seconds they never will,
    /// and the test fails.
    func waitUntilReceived(_ count: Int, file: StaticString = #filePath, line: UInt = #line) async {
        let id = lock.withLock { () -> Int in
            lastArrivalID += 1
            return lastArrivalID
        }
        let ceiling = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.release(arrival: id, reached: false)
        }
        let reached = await withCheckedContinuation { continuation in
            let already = lock.withLock { () -> Bool in
                guard received.count < count else { return true }
                arrivals.append((id, count, continuation))
                return false
            }
            if already { continuation.resume(returning: true) }
        }
        ceiling.cancel()
        if !reached {
            XCTFail("\(count) request(s) awaited, \(requests.count) received", file: file, line: line)
        }
    }

    private func release(arrival id: Int, reached: Bool) {
        let waiting = lock.withLock { () -> CheckedContinuation<Bool, Never>? in
            guard let index = arrivals.firstIndex(where: { $0.id == id }) else { return nil }
            return arrivals.remove(at: index).continuation
        }
        waiting?.resume(returning: reached)
    }

    // MARK: - What the test sets

    /// Unplugged: every request fails the way a host that doesn't answer does.
    var isUnplugged: Bool {
        get { lock.withLock { unplugged } }
        set { lock.withLock { unplugged = newValue } }
    }

    /// The script can't run, and the firmware says so with this message, at
    /// install and at the restart every config change triggers.
    var scriptError: String? {
        get { lock.withLock { failure } }
        set { lock.withLock { failure = newValue } }
    }

    /// Answers `call` ("METHOD /path") with this, whatever the firmware would
    /// have said, until `forget(_:)`.
    func answer(_ call: String, status: Int, body: String) {
        lock.withLock { overrides[call] = (status, body) }
    }

    func forget(_ call: String) {
        lock.withLock { overrides[call] = nil }
    }

    /// Forgets the requests received so far, and nothing else.
    func clearRequests() {
        lock.withLock { received = [] }
    }

    /// From now on, every request waits at the device, unanswered.
    func holdAnswers() {
        lock.withLock { holding = true }
    }

    /// Lets every held request through, in the order they came, and holds
    /// nothing more.
    func releaseAnswers() {
        let waiting = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            holding = false
            defer { held = [] }
            return held
        }
        waiting.forEach { $0.resume() }
    }

    // MARK: - The device

    var transport: UlanziClient.Transport {
        { [self] request in try await receive(request) }
    }

    private func receive(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url else { throw URLError(.badURL) }
        let entry = Request(method: request.httpMethod ?? "GET",
                            path: url.path,
                            contentType: request.value(forHTTPHeaderField: "Content-Type"),
                            timeout: request.timeoutInterval,
                            cachePolicy: request.cachePolicy,
                            body: request.httpBody.map { String(decoding: $0, as: UTF8.self) } ?? "")
        let (mustWait, reached) = lock.withLock { () -> (Bool, [CheckedContinuation<Bool, Never>]) in
            received.append(entry)
            atOnce += 1
            mostAtOnce = max(mostAtOnce, atOnce)
            let reached = arrivals.filter { received.count >= $0.count }.map(\.continuation)
            arrivals.removeAll { received.count >= $0.count }
            return (holding, reached)
        }
        reached.forEach { $0.resume(returning: true) }
        defer { lock.withLock { atOnce -= 1 } }

        if mustWait { await waitForRelease() }
        if isUnplugged { throw URLError(.cannotConnectToHost) }

        let (status, body) = lock.withLock { respond(to: entry) }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: nil)!
        return (Data(body.utf8), response)
    }

    private func waitForRelease() async {
        await withCheckedContinuation { continuation in
            let free = lock.withLock { () -> Bool in
                guard holding else { return true }
                held.append(continuation)
                return false
            }
            if free { continuation.resume() }
        }
    }

    /// The firmware's answers (AWTRIX NG 1.1.2, section 4 of the spec).
    /// Called under the lock.
    private func respond(to request: Request) -> (Int, String) {
        let call = "\(request.method) \(request.path)"
        if let override = overrides[call] { return override }
        switch call {
        case "GET /api/v1/apps/script/Claudio":
            guard let installed else { return (404, Self.refusal("notFound", "script not found")) }
            return (200, installed)
        case "PUT /api/v1/apps/script/Claudio":
            installed = request.body
            return (200, failure.map { Self.broken($0) } ?? Self.accepted)
        case "PATCH /api/v1/apps/Claudio/config":
            guard installed != nil else { return (404, Self.refusal("notFound", "app not found")) }
            guard let object = Self.object(request.body), object.count == 1,
                  let gaze = object["gaze"] as? String,
                  ["off", "repos", "veille", "fait", "vide"].contains(gaze) else {
                return (422, Self.refusal("invalidConfig", "gaze is not one of the options"))
            }
            shown = gaze
            return (200, failure.map { Self.broken($0) } ?? Self.accepted)
        case "PUT /api/v1/apps/active":
            guard let object = Self.object(request.body), object.count == 2,
                  object["fast"] as? Bool == true, let name = object["name"] as? String else {
                return (422, Self.refusal("invalidBody", "expected name and fast"))
            }
            guard name == "Claudio", installed != nil else {
                return (404, Self.refusal("notFound", "app not found"))
            }
            return (200, #"{"ok":true}"#)
        default:
            return (404, Self.refusal("notFound", "no such route"))
        }
    }

    private static func object(_ body: String) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any]
    }
}
