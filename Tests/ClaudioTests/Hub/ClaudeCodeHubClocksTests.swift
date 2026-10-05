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

    private func blocked() {
        hook(#"{"hook_event_name":"Stop","session_id":"\#(session)","cwd":"/Users/g/BAGUETTE","last_assistant_message":"🟥 BLOCAGE"}"#)
    }

    /// A clock added while a session is blocked shows the red indicator at
    /// once, as the other does, rather than at the next event, which may be
    /// long in coming while the session waits; so does a clock that moved.
    /// The alert held on the other can't follow: the board keeps its name,
    /// not its text.
    func testAClockJoiningWhileASessionWaitsIsShownTheIndicator() async throws {
        await listening([desk])
        blocked()
        await settle()
        let red = try XCTUnwrap(deskDevice.indicator)

        hub.apply([desk, lounge])
        await settle()
        XCTAssertEqual(loungeDevice.indicator, red)
        XCTAssertEqual(loungeDevice.calls, ["PUT /api/v1/indicators/1", "PUT /api/v1/system"])
        XCTAssertEqual(loungeDevice.heldNotifications, [])

        var moved = lounge
        moved.address = elsewhere
        hub.apply([desk, moved])
        await settle()
        XCTAssertEqual(device(elsewhere).indicator, red)
    }

    /// The indicator a joining clock missed goes again with the next event,
    /// to every clock, though it did not change.
    func testAnIndicatorAJoiningClockMissedGoesAgain() async {
        await listening([desk])
        blocked()
        await settle()
        loungeDevice.answer("PUT /api/v1/indicators/1", status: 503, body: FakeUlanzi.refusal("serviceBusy", "busy"))

        hub.apply([desk, lounge])
        await settle()
        loungeDevice.forget("PUT /api/v1/indicators/1")
        deskDevice.clearRequests()
        hook(#"{"hook_event_name":"UserPromptSubmit","session_id":"99999999-aaaa-4bbb-8ccc-000000000002","prompt":"go"}"#)
        await settle()

        XCTAssertNotNil(loungeDevice.indicator)
        XCTAssertTrue(deskDevice.calls.contains("PUT /api/v1/indicators/1"), "\(deskDevice.calls)")
    }

    /// A clock added before any indicator went is only told the door: the
    /// first indicator goes to every clock with the next event.
    func testAClockJoiningBeforeAnyIndicatorIsOnlyToldTheDoor() async {
        await listening([desk])

        hub.apply([desk, lounge])
        await settle()

        XCTAssertEqual(loungeDevice.calls, ["PUT /api/v1/system"])
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

    /// A clock whose flags are unticked hears nothing more of them, its
    /// button given back aside; the other goes on.
    func testAClockUntickedHearsNothingMore() async {
        await listening([desk, lounge])
        var quiet = lounge
        quiet.alerts = false
        hub.apply([desk, quiet])

        decision()
        await settle()
        await loungeDevice.waitUntilReceived(1)

        XCTAssertEqual(deskDevice.calls, decisionCalls)
        XCTAssertEqual(loungeDevice.calls, ["PUT /api/v1/system"])
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

        await loungeDevice.waitUntilReceived(1)

        XCTAssertEqual(device(elsewhere).calls, ["PUT /api/v1/system"] + decisionCalls)
        XCTAssertEqual(loungeDevice.calls, ["PUT /api/v1/system"], "its button given back, nothing more")
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
        await deskDevice.waitUntilReceived(2)
        XCTAssertEqual(deskDevice.calls, ["DELETE /api/v1/notifications/\(alert)", "PUT /api/v1/system"],
                       "nothing more for a clock let go, its button given back aside")
    }

    /// One change of the list moves the desk and removes the lounge, whose
    /// answer a hold still waited for: the hold missed everywhere, the
    /// indicator goes off at once on the desk where it is now. Its answer
    /// counts, though its clock's old link is let go in the same change: a
    /// refusal there sends the indicator again with the next event.
    func testAClockMovedInTheSameChangeIsHeardForItsNewLink() async {
        await listening([lounge, desk])
        deskDevice.answer("POST /api/v1/notifications", status: 500, body: FakeUlanzi.refusal("internal", "no memory"))
        loungeDevice.holdAnswers()
        decision()
        await deskDevice.waitUntilReceived(3)
        await hub.lines[desk.address]?.value
        let moved = device(elsewhere)
        moved.answer("DELETE /api/v1/indicators/1", status: 500, body: FakeUlanzi.refusal("internal", "no memory"))
        var away = desk
        away.address = elsewhere

        hub.apply([away])
        await settle()
        XCTAssertTrue(moved.calls.contains("DELETE /api/v1/indicators/1"), "\(moved.calls)")
        moved.clearRequests()
        hook(#"{"hook_event_name":"UserPromptSubmit","session_id":"99999999-aaaa-4bbb-8ccc-000000000002","prompt":"go"}"#)
        await settle()

        XCTAssertTrue(moved.calls.contains("DELETE /api/v1/indicators/1"), "\(moved.calls)")
        loungeDevice.releaseAnswers()
    }

    // MARK: - The middle button given back

    /// A clock leaving the flags while the door stays open is told to post
    /// its buttons nowhere: its middle button is its own again, not a
    /// press on the other clock's alerts. The other keeps its door.
    func testAClockLeavingTheFlagsGetsItsButtonBack() async throws {
        await listening([desk, lounge])
        let door = "http://192.168.1.50:51234/ulanzi/button/\(try token())"
        var quiet = lounge
        quiet.alerts = false

        hub.apply([desk, quiet])
        await loungeDevice.waitUntilReceived(1)

        XCTAssertEqual(loungeDevice.calls, ["PUT /api/v1/system"])
        XCTAssertEqual(loungeDevice.buttonCallback, "")
        XCTAssertEqual(deskDevice.calls, [])
        XCTAssertEqual(deskDevice.buttonCallback, door)
    }

    /// A clock removed, or moved, gets its button back at the address it
    /// had, and the one that moved is told the door where it is now.
    func testAClockRemovedOrMovedGetsItsButtonBack() async throws {
        await listening([desk, lounge])
        let door = "http://192.168.1.50:51234/ulanzi/button/\(try token())"
        var moved = desk
        moved.address = elsewhere

        hub.apply([moved])
        await loungeDevice.waitUntilReceived(1)
        await deskDevice.waitUntilReceived(1)
        await settle()

        XCTAssertEqual(loungeDevice.buttonCallback, "")
        XCTAssertEqual(deskDevice.buttonCallback, "")
        XCTAssertEqual(device(elsewhere).buttonCallback, door)
    }

    /// Nothing was ever set on it, nothing is taken back: a callback
    /// someone else set stays.
    func testAClockNeverToldTheDoorIsLeftAlone() async {
        hub.apply([desk, lounge])
        hub.apply([desk])
        hub.listenerReady(port: port)
        await settle()

        XCTAssertEqual(loungeDevice.calls, [])
    }

    /// The last clock leaving the flags closes the door: a press posted to
    /// it goes nowhere, and nothing is sent on the way out.
    func testClosingTheDoorLeavesTheButtonsAsTheyAre() async throws {
        await listening([desk])

        hub.apply([])
        hub.apply([lounge])
        await settle()

        XCTAssertEqual(deskDevice.calls, [])
    }

    /// Two entries at one address, one leaving the flags: the device still
    /// serves the other, and keeps its door.
    func testADeviceStillServedKeepsItsDoor() async throws {
        let twin = UlanziClock(name: "Bureau bis", address: desk.address)
        await listening([desk, twin])
        var quiet = twin
        quiet.alerts = false

        hub.apply([desk, quiet])
        decision()
        await settle()

        XCTAssertEqual(deskDevice.buttonCallback, "http://192.168.1.50:51234/ulanzi/button/\(try token())")
        XCTAssertFalse(deskDevice.requests.contains { $0.body == #"{"buttonCallback":""}"# })
    }

    // MARK: - One line per device

    /// The doors a device was told to post its buttons to, in order: the
    /// empty one is its button given back.
    private func doors(toldTo device: FakeUlanzi) -> [String] {
        device.requests.filter { $0.path == "/api/v1/system" }.compactMap { request in
            let object = try? JSONSerialization.jsonObject(with: Data(request.body.utf8)) as? [String: String]
            return object?["buttonCallback"]
        }
    }

    /// The desk leaves the flags while a call to it is still on its way,
    /// held at the device, then comes back: its button given back waits
    /// behind that call, and the door told again waits behind it.
    private func deskComesBackMidCall(leaving: [UlanziClock], back: [UlanziClock]) async throws -> String {
        await listening([desk, lounge])
        let door = "http://192.168.1.50:51234/ulanzi/button/\(try token())"
        deskDevice.holdAnswers()
        decision()
        await deskDevice.waitUntilReceived(1)

        hub.apply(leaving)
        hub.apply(back)
        deskDevice.releaseAnswers()
        await settle()
        return door
    }

    /// Unticked then ticked again mid-call: the button given back lands
    /// before the door, never after, and the desk's middle button still
    /// reaches Claudio, at the next event as well.
    func testFlagsTickedAgainMidCallKeepTheDoor() async throws {
        var quiet = desk
        quiet.alerts = false

        let door = try await deskComesBackMidCall(leaving: [quiet, lounge], back: [desk, lounge])

        XCTAssertEqual(doors(toldTo: deskDevice), ["", door])
        XCTAssertEqual(deskDevice.buttonCallback, door)
        decision()
        await settle()
        XCTAssertEqual(deskDevice.buttonCallback, door)
    }

    /// Moved elsewhere then back mid-call: the same. The address it went
    /// through for a moment was never told the door, its turn not come
    /// yet, and is told nothing at all.
    func testAClockMovedAwayAndBackMidCallKeepsTheDoor() async throws {
        var away = desk
        away.address = elsewhere

        let door = try await deskComesBackMidCall(leaving: [away, lounge], back: [desk, lounge])

        XCTAssertEqual(doors(toldTo: deskDevice), ["", door])
        XCTAssertEqual(deskDevice.buttonCallback, door)
        await hub.lines[elsewhere]?.value
        XCTAssertEqual(device(elsewhere).calls, [])
    }

    /// Removed then added again mid-call, a new clock at the same address:
    /// the same.
    func testAClockRemovedAndAddedAgainMidCallKeepsTheDoor() async throws {
        let again = UlanziClock(name: "Bureau", address: desk.address)

        let door = try await deskComesBackMidCall(leaving: [lounge], back: [again, lounge])

        XCTAssertEqual(doors(toldTo: deskDevice), ["", door])
        XCTAssertEqual(deskDevice.buttonCallback, door)
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
