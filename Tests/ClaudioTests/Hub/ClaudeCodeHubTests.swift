import XCTest
@testable import Claudio

/// The hub wired to its pieces, on one clock. The routes come in through
/// the entry the server calls, the listener's readiness too: the server is
/// never started and no socket is opened. The device is `FakeUlanzi`, which
/// outlives a restart as the clock does; the sessions and Application
/// Support folders are temporary; the Mac's address, the links opened and
/// the time are the test's. Several clocks have their own tests, in
/// `ClaudeCodeHubClocksTests`.
@MainActor
final class ClaudeCodeHubTests: XCTestCase, AsyncWaiting {

    private let address = URL(string: "http://192.168.1.22")!
    private let clock = UlanziClock(name: "Ulanzi", address: URL(string: "http://192.168.1.22")!)
    private let port: UInt16 = 51234
    private let session = "5f0c2a9e-aaaa-4bbb-8ccc-000000000001"
    private let alert = "cc-5f0c2a9e"
    private let otherSession = "77d1e3f0-aaaa-4bbb-8ccc-000000000002"
    private let otherAlert = "cc-77d1e3f0"
    private var device = FakeUlanzi()
    private var folder: URL!
    private var localAddress: String? = "192.168.1.50"
    private var opened: [URL] = []
    private var statuses: [ClaudeCodeHub.Status] = []
    private var clockStatuses: [ClaudeCodeHub.ClockStatus] = []
    private var listened = 0
    private var servers: [HubServer] = []
    private var listenFailure: Error?
    private var time = Date(timeIntervalSince1970: 1_800_000_000)
    private var hub: ClaudeCodeHub!

    override func setUp() async throws {
        folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ClaudioTests.hub.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("sessions"),
                                                withIntermediateDirectories: true)
        hub = makeHub()
    }

    /// A hub on the test's folders and device, as Claudio starts one.
    private func makeHub() -> ClaudeCodeHub {
        let support = folder.appendingPathComponent("Claudio")
        let hub = ClaudeCodeHub(
            makeClient: { [unowned self] in UlanziClient(baseURL: $0, transport: device.transport) },
            localAddress: { [unowned self] in localAddress },
            sessionsDirectory: folder.appendingPathComponent("sessions"),
            openURL: { [unowned self] in opened.append($0) },
            now: { [unowned self] in time },
            handshake: BridgeHandshakeFile(directory: support, name: ClaudeCodeHub.handshakeName),
            boardFile: ClaudeCodeBoardFile(directory: support),
            listen: { [unowned self] server in
                listened += 1
                servers.append(server)
                if let listenFailure { throw listenFailure }
            })
        hub.onStatusChange = { [unowned self] in statuses.append($0) }
        hub.onClockStatusChange = { [unowned self] in clockStatuses.append($1) }
        return hub
    }

    override func tearDown() async throws {
        hub = nil
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: - Helpers

    private var handshakeURL: URL {
        folder.appendingPathComponent("Claudio").appendingPathComponent("claude-code-hub.json")
    }

    private var boardURL: URL {
        folder.appendingPathComponent("Claudio").appendingPathComponent("claude-code-board.json")
    }

    /// The handshake file as the relay reads it.
    private func handshake() throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: handshakeURL))
        return try XCTUnwrap(object as? [String: Any])
    }

    private func token() throws -> String {
        try XCTUnwrap(handshake()["token"] as? String)
    }

    /// Everything the hub has queued for the device, calls queued meanwhile
    /// included.
    private func settle() async {
        var tails = hub.sending
        while !tails.isEmpty {
            for tail in tails { await tail.value }
            let now = hub.sending
            if now == tails { break }
            tails = now
        }
    }

    /// Started, ready, settled, and the requests forgotten.
    private func listening() async {
        hub.apply([clock])
        hub.listenerReady(port: port)
        await settle()
        device.clearRequests()
    }

    /// Claudio quitting and starting again: the hub stopped as at quit, and
    /// a new one on the same folders and the same clock, listening.
    private func restart() async {
        await settle()
        hub.stop()
        hub = makeHub()
        await listening()
    }

    private func hook(_ json: String) {
        hub.receive(.hookEvent(Data(json.utf8)))
    }

    private func stop(_ message: String, session: String? = nil) {
        hook(#"{"hook_event_name":"Stop","session_id":"\#(session ?? self.session)","cwd":"/Users/g/BAGUETTE","last_assistant_message":"\#(message)"}"#)
    }

    private func button(_ name: String, down: Bool) {
        hub.receive(.button(Data(#"{"button":"\#(name)","state":\#(down),"uid":"awtrix_1a2b3c"}"#.utf8)))
    }

    private func writeSession(_ id: String? = nil, app: String, pid: Int = 4242) throws {
        let json = #"{"pid":\#(pid),"sessionId":"\#(id ?? session)","hostSessionId":"\#(app)","entrypoint":"claude-desktop","updatedAt":1791206181815}"#
        try Data(json.utf8).write(to: folder.appendingPathComponent("sessions/\(pid).json"))
    }

    // MARK: - Coming on

    /// Starting listens, and publishes nothing before the listener is ready:
    /// a door published early is a relay knocking on nothing.
    func testStartingListensAndPublishesNothingYet() {
        hub.apply([clock])

        XCTAssertEqual(listened, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: handshakeURL.path))
        XCTAssertEqual(hub.status, .off)
        XCTAssertEqual(device.calls, [])
    }

    /// Ready: the relay's file names the port and the token, and the clock
    /// is told to post its buttons to this Mac, on that port, with that
    /// token.
    func testReadyPublishesTheDoorAndSetsTheButtonCallback() async throws {
        hub.apply([clock])
        hub.listenerReady(port: port)
        await settle()

        let file = try handshake()
        XCTAssertEqual(file["v"] as? Int, 1)
        XCTAssertEqual(file["port"] as? Int, 51234)
        XCTAssertEqual(file["pid"] as? Int, Int(ProcessInfo.processInfo.processIdentifier))
        let token = try token()
        XCTAssertEqual(token.count, 64)
        XCTAssertEqual(device.calls, ["PUT /api/v1/system"])
        XCTAssertEqual(device.buttonCallback, "http://192.168.1.50:51234/ulanzi/button/\(token)")
        XCTAssertEqual(hub.status, .listening(port: 51234))
    }

    /// A listener that can't open leaves the hub off, saying why.
    func testAListenerThatCannotOpenFails() {
        listenFailure = CocoaError(.featureUnsupported)
        hub.apply([clock])

        guard case .failed = hub.status else { return XCTFail("status \(hub.status)") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: handshakeURL.path))
    }

    // MARK: - A decision, and the middle button

    /// A turn ending on 🟧: its own alert dismissed, the decision held, the
    /// indicator orange, in that order. Then the press: the firmware takes
    /// the alert off the screen itself, the hub dismisses it all the same
    /// (404, no failure), puts the indicator out, and opens the
    /// conversation in the Claude app. The releases before and after it do
    /// nothing.
    func testADecisionThenTheMiddleButtonOpensItsConversation() async throws {
        await listening()
        try writeSession(app: "local_0d6e")

        stop("🟧 DÉCISION")
        await settle()
        XCTAssertEqual(device.calls, ["DELETE /api/v1/notifications/\(alert)", "POST /api/v1/notifications",
                                      "PUT /api/v1/indicators/1"])
        XCTAssertEqual(device.heldNotifications, [alert])
        XCTAssertEqual(device.indicator, ##"{"blinkMs":0,"color":"#FF851B","fadeMs":2000}"##)

        device.clearRequests()
        device.dismissOnScreen()
        button("middle", down: false)
        button("middle", down: true)
        button("middle", down: false)
        await settle()

        XCTAssertEqual(device.calls, ["DELETE /api/v1/notifications/\(alert)", "DELETE /api/v1/indicators/1"])
        XCTAssertNil(device.indicator)
        XCTAssertEqual(opened, [URL(string: "claude://claude.ai/epitaxy/local_0d6e")!])
        // Not one failure on the way, the two dismissals of nothing included.
        XCTAssertEqual(statuses, [.listening(port: 51234)])
    }

    /// Only the press takes an alert, not the releases around it: with two
    /// held, one goes, and the other stays on the clock.
    func testOnlyThePressTakesAnAlertNotItsReleases() async throws {
        await listening()
        try writeSession(app: "local_a")
        stop("🟧 DÉCISION")
        stop("🟧 DÉCISION", session: otherSession)
        await settle()
        device.clearRequests()

        device.dismissOnScreen()
        button("middle", down: false)
        button("middle", down: true)
        button("middle", down: false)
        await settle()

        XCTAssertEqual(device.calls, ["DELETE /api/v1/notifications/\(alert)"])
        XCTAssertEqual(device.heldNotifications, [otherAlert])
        XCTAssertEqual(opened, [URL(string: "claude://claude.ai/epitaxy/local_a")!])
    }

    /// The clock out of reach when A is answered: its alert stays on the
    /// clock, ahead of B's, so it stays at the head of the queue, and the
    /// press that follows opens A's conversation, not B's.
    func testAFailedDismissalKeepsThePressOnTheAlertOnScreen() async throws {
        await listening()
        try writeSession(app: "local_a")
        try writeSession(otherSession, app: "local_b", pid: 4343)
        stop("🟧 DÉCISION")
        stop("🟧 DÉCISION", session: otherSession)
        await settle()

        device.isUnplugged = true
        hook(#"{"hook_event_name":"UserPromptSubmit","session_id":"\#(session)","prompt":"go"}"#)
        await settle()
        device.isUnplugged = false
        XCTAssertEqual(device.heldNotifications, [alert, otherAlert])

        device.dismissOnScreen()
        button("middle", down: true)
        await settle()
        XCTAssertEqual(opened, [URL(string: "claude://claude.ai/epitaxy/local_a")!])

        device.dismissOnScreen()
        button("middle", down: true)
        await settle()
        XCTAssertEqual(opened.last, URL(string: "claude://claude.ai/epitaxy/local_b")!)
        XCTAssertEqual(device.heldNotifications, [])
    }

    /// The clock out of reach when A ends on 🟧: its alert never made it.
    /// B's 🟧 lands after it, and the press opens B's conversation, not
    /// A's, and puts the indicator out: A no longer counts as waiting.
    func testAHoldTheClockNeverHeardOfIsNotWhatThePressOpens() async throws {
        await listening()
        try writeSession(app: "local_a")
        try writeSession(otherSession, app: "local_b", pid: 4343)

        device.isUnplugged = true
        stop("🟧 DÉCISION")
        await settle()
        device.isUnplugged = false
        stop("🟧 DÉCISION", session: otherSession)
        await settle()
        XCTAssertEqual(device.heldNotifications, [otherAlert])

        device.dismissOnScreen()
        button("middle", down: true)
        await settle()

        XCTAssertEqual(opened, [URL(string: "claude://claude.ai/epitaxy/local_b")!])
        XCTAssertNil(device.indicator)
    }

    /// The left and right buttons, and a press with nothing held, open
    /// nothing and send nothing.
    func testOtherPressesDoNothing() async {
        await listening()

        button("middle", down: true)
        stop("🟧 DÉCISION")
        await settle()
        device.clearRequests()
        button("left", down: true)
        button("right", down: true)
        await settle()

        XCTAssertEqual(device.calls, [])
        XCTAssertEqual(opened, [])
    }

    /// A session without an app id, one in a terminal, is dismissed all
    /// the same, and nothing opens.
    func testASessionWithoutALinkIsDismissedAllTheSame() async {
        await listening()
        stop("🟥 BLOCAGE")
        await settle()
        device.clearRequests()

        button("middle", down: true)
        await settle()

        XCTAssertEqual(device.calls.first, "DELETE /api/v1/notifications/\(alert)")
        XCTAssertEqual(opened, [])
    }

    // MARK: - Sending

    /// The clock hears the calls one at a time, in order: the next waits for
    /// the device to answer the one before.
    func testTheCallsGoOneAtATime() async {
        await listening()
        device.holdAnswers()

        stop("🟧 DÉCISION")
        await device.waitUntilReceived(1)
        await drain()
        XCTAssertEqual(device.requests.count, 1)

        device.releaseAnswers()
        await settle()
        XCTAssertEqual(device.requests.count, 3)
        XCTAssertEqual(device.mostRequestsAtOnce, 1)
    }

    /// A call that fails is said, and the next one goes all the same. Here
    /// the hold: the indicator lit after it goes out again at once, the
    /// alert that never made it taking its wait along.
    func testAFailedCallDoesNotHoldTheNextBack() async {
        await listening()
        device.answer("POST /api/v1/notifications", status: 500, body: FakeUlanzi.refusal("internal", "no memory"))

        stop("🟧 DÉCISION")
        await settle()

        XCTAssertEqual(device.calls, ["DELETE /api/v1/notifications/\(alert)", "POST /api/v1/notifications",
                                      "PUT /api/v1/indicators/1", "DELETE /api/v1/indicators/1"])
        XCTAssertNil(device.indicator)
        XCTAssertTrue(clockStatuses.contains(.rejected("no memory")), "\(clockStatuses)")
        XCTAssertEqual(statuses, [.listening(port: 51234)])
    }

    /// Out of reach, the clock costs one try per event, not one per call:
    /// the calls queued behind the one that found nobody fail at once, the
    /// board hearing of each. Ten Stops, ten tries. The next event tries
    /// again, and finds a board that holds none of the ten.
    func testAnUnreachableClockIsTriedOncePerEvent() async {
        await listening()
        device.isUnplugged = true

        for index in 0..<10 {
            stop("🟧 DÉCISION", session: "0000000\(index)-aaaa-4bbb-8ccc-000000000000")
            await settle()
        }
        XCTAssertEqual(device.requests.count, 10)

        device.isUnplugged = false
        device.clearRequests()
        stop("🟩 FINI")
        await settle()
        XCTAssertEqual(device.calls, ["DELETE /api/v1/notifications/\(alert)", "POST /api/v1/notifications",
                                      "DELETE /api/v1/indicators/1"])
        XCTAssertEqual(hub.status, .listening(port: 51234))
    }

    /// Ten Stops while the first try is still out: one try in all.
    func testABurstAgainstAnUnreachableClockIsTriedOnce() async {
        await listening()
        device.isUnplugged = true
        device.holdAnswers()

        for index in 0..<10 {
            stop("🟧 DÉCISION", session: "0000000\(index)-aaaa-4bbb-8ccc-000000000000")
        }
        await device.waitUntilReceived(1)
        device.releaseAnswers()
        await settle()

        XCTAssertEqual(device.requests.count, 1)
        guard case .unreachable = hub.clockStatus(of: clock.id) else {
            return XCTFail("clock \(hub.clockStatus(of: clock.id))")
        }
        XCTAssertEqual(hub.status, .listening(port: 51234))
    }

    /// The outage of one run is not the next one's: started again, as on a
    /// new address, the hub tries the clock again, the button callback
    /// first.
    func testStartingAgainAfterTheClockWasOutOfReachTriesItAgain() async throws {
        await listening()
        device.isUnplugged = true
        stop("🟧 DÉCISION")
        await settle()
        device.isUnplugged = false

        hub.stop()
        await listening()

        XCTAssertEqual(device.buttonCallback, "http://192.168.1.50:51234/ulanzi/button/\(try token())")
    }

    /// A press after the clock was out of reach tries it again: the press
    /// itself says it is back.
    func testAPressAfterTheClockWasOutOfReachTriesItAgain() async throws {
        await listening()
        try writeSession(app: "local_a")
        stop("🟧 DÉCISION")
        await settle()
        device.isUnplugged = true
        hook(#"{"hook_event_name":"UserPromptSubmit","session_id":"\#(otherSession)","prompt":"go"}"#)
        await settle()
        device.isUnplugged = false
        device.clearRequests()

        device.dismissOnScreen()
        button("middle", down: true)
        await settle()

        XCTAssertEqual(device.calls, ["DELETE /api/v1/notifications/\(alert)", "DELETE /api/v1/indicators/1"])
        XCTAssertEqual(opened, [URL(string: "claude://claude.ai/epitaxy/local_a")!])
    }

    /// An indicator the clock refused goes again with the next event, even
    /// unchanged: a moment off the network doesn't leave it wrong for hours.
    func testARefusedIndicatorGoesAgainWithTheNextEvent() async {
        await listening()
        device.answer("PUT /api/v1/indicators/1", status: 503, body: FakeUlanzi.refusal("serviceBusy", "busy"))
        stop("🟧 DÉCISION")
        await settle()
        XCTAssertNil(device.indicator)

        device.forget("PUT /api/v1/indicators/1")
        device.clearRequests()
        hook(#"{"hook_event_name":"Notification","session_id":"77d1e3f0-0002","notification_type":"permission_prompt"}"#)
        await settle()

        XCTAssertEqual(device.calls, ["POST /api/v1/notifications", "PUT /api/v1/indicators/1"])
        XCTAssertEqual(device.indicator, ##"{"blinkMs":0,"color":"#FF851B","fadeMs":2000}"##)
    }

    /// A call still on its way when the hub starts again writes nothing over
    /// the new run: its failure doesn't reach the new status, and the calls
    /// queued behind it never go.
    func testACallInFlightAcrossARestartWritesNothingOverTheNewRun() async {
        await listening()
        device.answer("DELETE /api/v1/notifications/\(alert)", status: 500,
                      body: FakeUlanzi.refusal("internal", "no memory"))
        device.holdAnswers()
        stop("🟧 DÉCISION")
        await device.waitUntilReceived(1)

        hub.stop()
        statuses = []
        hub.apply([clock])
        hub.listenerReady(port: port)
        device.releaseAnswers()
        await settle()

        XCTAssertEqual(device.calls, ["DELETE /api/v1/notifications/\(alert)", "PUT /api/v1/system"])
        XCTAssertEqual(statuses, [.listening(port: 51234)])
        XCTAssertEqual(hub.status, .listening(port: 51234))
        XCTAssertFalse(clockStatuses.contains(.rejected("no memory")), "\(clockStatuses)")
    }

    /// What isn't an event, or an event of no interest, sends nothing.
    func testWhatIsNoEventSendsNothing() async {
        await listening()

        hook("{}")
        hook(#"{"hook_event_name":"PreToolUse","session_id":"s1"}"#)
        await settle()

        XCTAssertEqual(device.calls, [])
    }

    // MARK: - The button callback

    /// A callback the clock didn't take is tried again with the next hook
    /// event, after its calls, and only until it lands.
    func testAFailedButtonCallbackIsRetriedAtTheNextEvent() async throws {
        device.answer("PUT /api/v1/system", status: 503, body: FakeUlanzi.refusal("serviceBusy", "busy"))
        hub.apply([clock])
        hub.listenerReady(port: port)
        await settle()
        XCTAssertEqual(hub.clockStatus(of: clock.id), .rejected("busy"))
        XCTAssertEqual(hub.status, .listening(port: 51234))
        XCTAssertNil(device.buttonCallback)

        device.forget("PUT /api/v1/system")
        device.clearRequests()
        stop("🟩 FINI")
        await settle()

        XCTAssertEqual(device.calls, ["DELETE /api/v1/notifications/\(alert)", "POST /api/v1/notifications",
                                      "DELETE /api/v1/indicators/1", "PUT /api/v1/system"])
        XCTAssertEqual(device.buttonCallback, "http://192.168.1.50:51234/ulanzi/button/\(try token())")
        XCTAssertEqual(hub.clockStatus(of: clock.id), .ready)

        device.clearRequests()
        stop("🟩 FINI")
        await settle()
        XCTAssertFalse(device.calls.contains("PUT /api/v1/system"), "\(device.calls)")
    }

    /// The Mac on another address, the clock is told at the next hook
    /// event, and only then: the same address again sends nothing.
    func testANewLocalAddressSetsTheButtonCallbackAgain() async throws {
        await listening()
        XCTAssertEqual(device.buttonCallback, "http://192.168.1.50:51234/ulanzi/button/\(try token())")

        localAddress = "192.168.1.77"
        stop("🟩 FINI")
        await settle()
        XCTAssertEqual(device.calls.last, "PUT /api/v1/system")
        XCTAssertEqual(device.buttonCallback, "http://192.168.1.77:51234/ulanzi/button/\(try token())")

        device.clearRequests()
        stop("🟩 FINI")
        await settle()
        XCTAssertFalse(device.calls.contains("PUT /api/v1/system"), "\(device.calls)")
    }

    /// Off every network, there is no address to give the clock: the rest
    /// works, and the callback is set once there is one.
    func testWithoutALocalAddressTheRestWorks() async throws {
        localAddress = nil
        await listening()

        stop("🟩 FINI")
        await settle()
        XCTAssertEqual(device.calls, ["DELETE /api/v1/notifications/\(alert)", "POST /api/v1/notifications",
                                      "DELETE /api/v1/indicators/1"])
        XCTAssertEqual(hub.status, .listening(port: 51234))

        localAddress = "10.0.0.5"
        stop("🟩 FINI")
        await settle()
        XCTAssertEqual(device.buttonCallback, "http://10.0.0.5:51234/ulanzi/button/\(try token())")
    }

    // MARK: - Going off

    /// Stopping takes the door away, and an event that comes while stopped
    /// goes nowhere: a press after a new start finds nothing held.
    func testStoppingTakesTheDoorAway() async {
        await listening()

        hub.stop()
        XCTAssertEqual(hub.status, .off)
        XCTAssertFalse(FileManager.default.fileExists(atPath: handshakeURL.path))

        stop("🟧 DÉCISION")
        await listening()
        button("middle", down: true)
        await settle()
        XCTAssertEqual(device.calls, [])
        XCTAssertEqual(opened, [])
    }

    // MARK: - Outliving Claudio

    /// Claudio quits with A's decision on the clock, and starts again: the
    /// clock still shows A's alert, ahead of B's that comes after. The first
    /// press opens A, the second B.
    func testTheHeldAlertsOutliveARestart() async throws {
        await listening()
        try writeSession(app: "local_a")
        try writeSession(otherSession, app: "local_b", pid: 4343)
        stop("🟧 DÉCISION")

        await restart()
        XCTAssertTrue(FileManager.default.fileExists(atPath: boardURL.path))
        stop("🟧 DÉCISION", session: otherSession)
        await settle()
        XCTAssertEqual(device.heldNotifications, [alert, otherAlert])

        for _ in 0..<2 {
            device.dismissOnScreen()
            button("middle", down: true)
            await settle()
        }
        XCTAssertEqual(opened, [URL(string: "claude://claude.ai/epitaxy/local_a")!,
                                URL(string: "claude://claude.ai/epitaxy/local_b")!])
    }

    /// And who waits: after a restart, a FINI from another session leaves
    /// the indicator orange, A still waiting.
    func testTheWaitsOutliveARestart() async {
        await listening()
        stop("🟧 DÉCISION")

        await restart()
        stop("🟩 FINI", session: otherSession)
        await settle()

        XCTAssertEqual(device.calls.last, "PUT /api/v1/indicators/1")
        XCTAssertEqual(device.indicator, ##"{"blinkMs":0,"color":"#FF851B","fadeMs":2000}"##)
    }

    /// A wait twelve hours old by the restart is forgotten, and the
    /// indicator goes out. Its alert, still on the clock, is there for the
    /// press.
    func testAWaitPastTwelveHoursDoesNotOutliveARestart() async throws {
        await listening()
        try writeSession(app: "local_a")
        stop("🟧 DÉCISION")

        time += 12 * 3600
        await restart()
        stop("🟩 FINI", session: otherSession)
        await settle()
        XCTAssertNil(device.indicator)

        device.dismissOnScreen()
        button("middle", down: true)
        await settle()
        XCTAssertEqual(opened, [URL(string: "claude://claude.ai/epitaxy/local_a")!])
    }

    /// A board file that can't be read is no board: the hub starts with
    /// nothing held, works, and writes a good file at the first change.
    func testAnUnreadableBoardFileIsIgnored() async throws {
        try FileManager.default.createDirectory(at: boardURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(#"{"v":1,"held":[{"#.utf8).write(to: boardURL)
        await listening()
        try writeSession(app: "local_a")

        stop("🟧 DÉCISION")
        await settle()
        device.dismissOnScreen()
        button("middle", down: true)
        await settle()

        XCTAssertEqual(opened, [URL(string: "claude://claude.ai/epitaxy/local_a")!])
        XCTAssertEqual(ClaudeCodeBoardFile(directory: boardURL.deletingLastPathComponent()).load(),
                       ClaudeCodeBoard.Snapshot())
    }

    /// A new start is a new token: the old one opens nothing more, neither
    /// for the relay nor for the clock.
    func testEachStartHasItsOwnToken() async throws {
        await listening()
        let first = try token()

        hub.stop()
        await listening()
        let second = try token()
        XCTAssertNotEqual(second, first)

        let door = try XCTUnwrap(servers.last)
        for path in ["/claude-code/", "/ulanzi/button/"] {
            let body = Data(#"{"hook_event_name":"Stop","button":"middle","state":true}"#.utf8)
            XCTAssertEqual(door.answer(HubRequest(method: "POST", path: path + first, body: body),
                                       fromLoopback: true).status, 404, path)
            XCTAssertEqual(door.answer(HubRequest(method: "POST", path: path + second, body: body),
                                       fromLoopback: true).status, 200, path)
        }
    }
}
