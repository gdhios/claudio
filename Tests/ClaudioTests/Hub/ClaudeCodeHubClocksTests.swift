import XCTest
@testable import Claudio

/// The hub on several clocks. Every clock with the flags ticked hears every
/// command, each on its own queue, so one out of reach holds no other back;
/// a press on any of them acts on the one board; what the clocks made of a
/// command goes back to the board once all have answered: a hold or a
/// dismissal one of them took is done. The server and its token outlive any
/// change of the list but the last clock going. The devices are
/// `FakeUlanzi`, one per address; the server is never started.
@MainActor
final class ClaudeCodeHubClocksTests: XCTestCase {

    private let port: UInt16 = 51234
    private let session = "5f0c2a9e-aaaa-4bbb-8ccc-000000000001"
    private let alert = "cc-5f0c2a9e"
    private let desk = UlanziClock(name: "Bureau", address: URL(string: "http://192.168.1.22")!)
    private let lounge = UlanziClock(name: "Salon", address: URL(string: "http://192.168.1.23")!)
    private let elsewhere = URL(string: "http://192.168.1.42")!
    private var devices: [URL: FakeUlanzi] = [:]
    private var folder: URL!
    private var opened: [URL] = []
    private var statuses: [ClaudeCodeHub.Status] = []
    private var clockStatuses: [(id: UUID, status: ClaudeCodeHub.ClockStatus)] = []
    private var listened = 0
    private var hub: ClaudeCodeHub!

    override func setUp() async throws {
        folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ClaudioTests.hubClocks.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("sessions"),
                                                withIntermediateDirectories: true)
        for address in [desk.address, lounge.address, elsewhere] { devices[address] = FakeUlanzi() }
        hub = makeHub()
    }

    override func tearDown() async throws {
        hub = nil
        try? FileManager.default.removeItem(at: folder)
    }

    private func makeHub() -> ClaudeCodeHub {
        let support = folder.appendingPathComponent("Claudio")
        let hub = ClaudeCodeHub(
            makeClient: { [unowned self] in UlanziClient(baseURL: $0, transport: device($0).transport) },
            localAddress: { "192.168.1.50" },
            sessionsDirectory: folder.appendingPathComponent("sessions"),
            openURL: { [unowned self] in opened.append($0) },
            now: { Date(timeIntervalSince1970: 1_800_000_000) },
            handshake: BridgeHandshakeFile(directory: support, name: ClaudeCodeHub.handshakeName),
            boardFile: ClaudeCodeBoardFile(directory: support),
            listen: { [unowned self] _ in listened += 1 })
        hub.onStatusChange = { [unowned self] in statuses.append($0) }
        hub.onClockStatusChange = { [unowned self] in clockStatuses.append(($0, $1)) }
        return hub
    }

    // MARK: - Helpers

    private func device(_ address: URL) -> FakeUlanzi {
        devices[address]!
    }

    private var deskDevice: FakeUlanzi { device(desk.address) }
    private var loungeDevice: FakeUlanzi { device(lounge.address) }

    private var handshakeURL: URL {
        folder.appendingPathComponent("Claudio").appendingPathComponent("claude-code-hub.json")
    }

    private func token() throws -> String {
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: handshakeURL)) as? [String: Any]
        return try XCTUnwrap(object?["token"] as? String)
    }

    /// Everything queued for every clock, calls queued meanwhile included.
    private func settle() async {
        var tails = hub.sending
        while !tails.isEmpty {
            for tail in tails { await tail.value }
            let now = hub.sending
            if now == tails { break }
            tails = now
        }
    }

    /// The clocks applied, the listener ready, settled, requests forgotten.
    private func listening(_ clocks: [UlanziClock]) async {
        hub.apply(clocks)
        hub.listenerReady(port: port)
        await settle()
        devices.values.forEach { $0.clearRequests() }
    }

    private func hook(_ json: String) {
        hub.receive(.hookEvent(Data(json.utf8)))
    }

    private func decision() {
        hook(#"{"hook_event_name":"Stop","session_id":"\#(session)","cwd":"/Users/g/BAGUETTE","last_assistant_message":"🟧 DÉCISION"}"#)
    }

    private func press() {
        hub.receive(.button(Data(#"{"button":"middle","state":true,"uid":"awtrix_1a2b3c"}"#.utf8)))
    }

    private func writeSession() throws {
        let json = #"{"pid":4242,"sessionId":"\#(session)","hostSessionId":"local_a","entrypoint":"claude-desktop","updatedAt":1791206181815}"#
        try Data(json.utf8).write(to: folder.appendingPathComponent("sessions/4242.json"))
    }

    private let conversation = URL(string: "claude://claude.ai/epitaxy/local_a")!
    private let decisionCalls = ["DELETE /api/v1/notifications/cc-5f0c2a9e", "POST /api/v1/notifications",
                                 "PUT /api/v1/indicators/1"]

    // MARK: - Every clock hears every command

    /// Both clocks are told where to post their buttons, the same door for
    /// both, and both hear the decision: its alert dismissed, held, and the
    /// indicator lit.
    func testEveryClockHearsEveryCommand() async throws {
        hub.apply([desk, lounge])
        hub.listenerReady(port: port)
        await settle()
        let door = "http://192.168.1.50:51234/ulanzi/button/\(try token())"
        XCTAssertEqual(deskDevice.buttonCallback, door)
        XCTAssertEqual(loungeDevice.buttonCallback, door)
        devices.values.forEach { $0.clearRequests() }

        decision()
        await settle()

        for device in [deskDevice, loungeDevice] {
            XCTAssertEqual(device.calls, decisionCalls)
            XCTAssertEqual(device.heldNotifications, [alert])
            XCTAssertEqual(device.indicator, ##"{"blinkMs":0,"color":"#FF851B","fadeMs":2000}"##)
        }
    }

    /// The press comes from the lounge, whose firmware took the alert away
    /// itself: Claudio takes it off the desk's screen too, and opens the
    /// conversation once.
    func testAPressOnOneClockClearsTheAlertOnTheOther() async throws {
        await listening([desk, lounge])
        try writeSession()
        decision()
        await settle()

        loungeDevice.dismissOnScreen()
        press()
        await settle()

        XCTAssertEqual(deskDevice.heldNotifications, [])
        XCTAssertEqual(loungeDevice.heldNotifications, [])
        XCTAssertEqual(opened, [conversation])
        XCTAssertEqual(hub.clockStatus(of: lounge.id), .ready, "the 404 of the lounge is no failure")
    }

    /// A clock that doesn't answer holds the other back in nothing: the
    /// lounge hears the whole decision while the desk still sits on its
    /// first call.
    func testAClockOutOfReachHoldsTheOtherBackInNothing() async {
        await listening([desk, lounge])
        deskDevice.holdAnswers()

        decision()
        await loungeDevice.waitUntilReceived(3)

        XCTAssertEqual(loungeDevice.calls, decisionCalls)
        XCTAssertEqual(deskDevice.requests.count, 1)

        deskDevice.isUnplugged = true
        deskDevice.releaseAnswers()
        await settle()
        XCTAssertEqual(deskDevice.requests.count, 1, "one try for the event, not one per call")
        guard case .unreachable = hub.clockStatus(of: desk.id) else {
            return XCTFail("desk \(hub.clockStatus(of: desk.id))")
        }
        XCTAssertEqual(hub.clockStatus(of: lounge.id), .ready)
        XCTAssertEqual(hub.status, .listening(port: port))
    }

    // MARK: - What the board is told

    /// A hold the desk refused and the lounge took is held: the session
    /// still waits, the indicator stays on, and the press opens it.
    func testAHoldOneClockTookIsHeld() async throws {
        await listening([desk, lounge])
        try writeSession()
        deskDevice.answer("POST /api/v1/notifications", status: 500, body: FakeUlanzi.refusal("internal", "no memory"))

        decision()
        await settle()
        XCTAssertEqual(loungeDevice.calls, decisionCalls)
        XCTAssertTrue(clockStatuses.contains { $0.id == desk.id && $0.status == .rejected("no memory") },
                      "\(clockStatuses)")

        loungeDevice.dismissOnScreen()
        press()
        await settle()
        XCTAssertEqual(opened, [conversation])
    }

    /// A hold both clocks refused is no hold: the session waits no more,
    /// the indicator goes out on both, and a press opens nothing.
    func testAHoldEveryClockRefusedIsForgotten() async throws {
        await listening([desk, lounge])
        try writeSession()
        for device in [deskDevice, loungeDevice] {
            device.answer("POST /api/v1/notifications", status: 500, body: FakeUlanzi.refusal("internal", "no memory"))
        }

        decision()
        await settle()
        for device in [deskDevice, loungeDevice] {
            XCTAssertEqual(device.calls, decisionCalls + ["DELETE /api/v1/indicators/1"])
            XCTAssertNil(device.indicator)
        }

        press()
        await settle()
        XCTAssertEqual(opened, [])
    }

    /// A dismissal one clock took is done: the alert left the queue, and a
    /// press finds nothing to open.
    func testADismissalOneClockTookIsDone() async throws {
        await listening([desk, lounge])
        try writeSession()
        decision()
        await settle()
        deskDevice.answer("DELETE /api/v1/notifications/\(alert)", status: 500,
                          body: FakeUlanzi.refusal("internal", "no memory"))

        hook(#"{"hook_event_name":"UserPromptSubmit","session_id":"\#(session)","prompt":"go"}"#)
        await settle()
        press()
        await settle()

        XCTAssertEqual(opened, [])
        XCTAssertEqual(loungeDevice.heldNotifications, [])
    }

    /// A dismissal both clocks missed leaves the alert where it was, at the
    /// head of the queue: the press opens its conversation.
    func testADismissalEveryClockMissedKeepsTheAlert() async throws {
        await listening([desk, lounge])
        try writeSession()
        decision()
        await settle()
        for device in [deskDevice, loungeDevice] {
            device.answer("DELETE /api/v1/notifications/\(alert)", status: 500,
                          body: FakeUlanzi.refusal("internal", "no memory"))
        }

        hook(#"{"hook_event_name":"UserPromptSubmit","session_id":"\#(session)","prompt":"go"}"#)
        await settle()
        press()
        await settle()

        XCTAssertEqual(opened, [conversation])
    }

    // MARK: - The list changing

    /// A clock added, then another removed: same server, same token, same
    /// door; the clock added is told where to post its buttons at once.
    func testTheListChangingKeepsTheDoor() async throws {
        await listening([desk])
        let first = try token()

        hub.apply([desk, lounge])
        await settle()
        XCTAssertEqual(try token(), first)
        XCTAssertEqual(loungeDevice.calls, ["PUT /api/v1/system"])
        XCTAssertEqual(loungeDevice.buttonCallback, "http://192.168.1.50:51234/ulanzi/button/\(first)")
        XCTAssertEqual(deskDevice.calls, [], "the desk knows the door already")

        hub.apply([lounge])
        await settle()
        XCTAssertEqual(try token(), first)
        XCTAssertEqual(listened, 1)
        XCTAssertEqual(statuses, [.listening(port: port)])
    }

    /// The last clock with the flags gone: the door goes, and the hub is
    /// off.
    func testNoClockWithTheFlagsTakesTheDoorAway() async {
        await listening([desk, lounge])
        var quietDesk = desk
        quietDesk.alerts = false
        var quietLounge = lounge
        quietLounge.alerts = false

        hub.apply([quietDesk, quietLounge])

        XCTAssertEqual(hub.status, .off)
        XCTAssertFalse(FileManager.default.fileExists(atPath: handshakeURL.path))
    }

    /// A clock whose flags are unticked hears nothing more; the other goes
    /// on.
    func testAClockUntickedHearsNothingMore() async {
        await listening([desk, lounge])
        var quiet = lounge
        quiet.alerts = false
        hub.apply([desk, quiet])

        decision()
        await settle()

        XCTAssertEqual(deskDevice.calls, decisionCalls)
        XCTAssertEqual(loungeDevice.calls, [])
    }

    /// A clock that moved is a new clock: the new address is told where to
    /// post its buttons and hears what follows, the old one nothing more.
    func testAClockThatMovedIsSpokenToWhereItIsNow() async throws {
        await listening([desk, lounge])
        var moved = lounge
        moved.address = elsewhere

        hub.apply([desk, moved])
        decision()
        await settle()

        XCTAssertEqual(device(elsewhere).calls, ["PUT /api/v1/system"] + decisionCalls)
        XCTAssertEqual(loungeDevice.calls, [])
        XCTAssertEqual(hub.clockStatus(of: lounge.id), .ready)
    }

    /// A clock let go while a hold to it is still on its way holds nothing
    /// back: the board hears what the other made of it.
    func testAClockLetGoMidCallHoldsNothingBack() async throws {
        await listening([desk, lounge])
        try writeSession()
        deskDevice.holdAnswers()
        decision()
        await loungeDevice.waitUntilReceived(3)

        hub.apply([lounge])
        await settle()
        deskDevice.releaseAnswers()

        loungeDevice.dismissOnScreen()
        press()
        await settle()
        XCTAssertEqual(opened, [conversation])
        XCTAssertEqual(deskDevice.requests.count, 1, "nothing more for a clock let go")
    }

    // MARK: - Each clock's own status

    /// Each clock says where it stands, on its own: waiting until it first
    /// answers, ready once it has, out of reach or refusing on its own,
    /// while the relay's door stays open.
    func testEachClockHasItsOwnStatus() async {
        hub.apply([desk, lounge])
        XCTAssertEqual(hub.clockStatus(of: desk.id), .pending)
        XCTAssertEqual(hub.clockStatus(of: lounge.id), .pending)
        XCTAssertEqual(clockStatuses.map(\.status), [.pending, .pending])

        hub.listenerReady(port: port)
        await settle()
        XCTAssertEqual(hub.clockStatus(of: desk.id), .ready)
        XCTAssertEqual(hub.clockStatus(of: lounge.id), .ready)

        for call in ["POST /api/v1/notifications", "PUT /api/v1/indicators/1"] {
            loungeDevice.answer(call, status: 503, body: FakeUlanzi.refusal("serviceBusy", "busy"))
        }
        decision()
        await settle()
        XCTAssertEqual(hub.clockStatus(of: lounge.id), .rejected("busy"))
        XCTAssertEqual(hub.clockStatus(of: desk.id), .ready)
        XCTAssertEqual(clockStatuses.last?.id, lounge.id)
        XCTAssertEqual(hub.status, .listening(port: port))
        XCTAssertEqual(hub.clockStatus(of: UUID()), .pending)
    }

    /// The hub stopped, every clock is waiting again.
    func testStoppingLeavesEveryClockWaiting() async {
        await listening([desk, lounge])
        clockStatuses = []

        hub.stop()

        XCTAssertEqual(Set(clockStatuses.map(\.id)), [desk.id, lounge.id])
        XCTAssertEqual(clockStatuses.map(\.status), [.pending, .pending])
        XCTAssertEqual(hub.clockStatus(of: desk.id), .pending)
    }
}
