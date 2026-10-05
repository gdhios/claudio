import XCTest
@testable import Claudio

/// The Claude Code hub's calls to the clock, as AWTRIX NG takes them: the
/// method, the path, and a JSON body with its keys sorted, only those set.
/// And the one no that is not a failure: a held notification already gone,
/// which the middle button takes off the screen itself before Claudio hears
/// of the press. Answered by `FakeUlanzi`: no socket is opened.
final class UlanziClientHubTests: XCTestCase {

    private var device: FakeUlanzi!
    private var client: UlanziClient!

    override func setUp() {
        super.setUp()
        device = FakeUlanzi()
        client = UlanziClient(baseURL: URL(string: "http://192.168.1.22")!, transport: device.transport)
    }

    override func tearDown() {
        client = nil
        device = nil
        super.tearDown()
    }

    // MARK: - Notifications

    /// A held alert carries every key the board set, sorted, and the device
    /// holds it under its name.
    func testAHeldNotificationSendsEveryKeySetSorted() async throws {
        try await client.notify(UlanziNotification(
            name: "cc-abcdef12", text: "BAGUETTE BLOCAGE", textColor: "#FF2D2D",
            hold: true, wakeup: true, textBlinkMs: 600, soundRtttl: "blk:d=16,o=5,b=140:g,f#,f,8e"))

        let request = try XCTUnwrap(device.requests.first)
        XCTAssertEqual(device.calls, ["POST /api/v1/notifications"])
        XCTAssertEqual(request.contentType, "application/json")
        XCTAssertEqual(request.body, ##"{"hold":true,"name":"cc-abcdef12","soundRtttl":"blk:d=16,o=5,b=140:g,f#,f,8e","text":"BAGUETTE BLOCAGE","textBlinkMs":600,"textColor":"#FF2D2D","wakeup":true}"##)
        XCTAssertEqual(device.heldNotifications, ["cc-abcdef12"])
    }

    /// A passing one carries only what it has: no name, no hold, no sound.
    func testAPassingNotificationLeavesOutTheKeysItLacks() async throws {
        try await client.notify(UlanziNotification(text: "BAGUETTE", textColor: "#AAAAAA", durationMs: 1500))

        XCTAssertEqual(device.requests.first?.body, ##"{"durationMs":1500,"text":"BAGUETTE","textColor":"#AAAAAA"}"##)
        XCTAssertEqual(device.heldNotifications, [])
    }

    /// The accent of DÉCISION travels as UTF-8, as the device shows it.
    func testTheTextGoesAsUTF8() async throws {
        try await client.notify(UlanziNotification(text: "CLAUDIO DÉCISION"))

        XCTAssertEqual(device.requests.first?.body, #"{"text":"CLAUDIO DÉCISION"}"#)
    }

    // MARK: - Dismissing

    /// A held notification goes by its name.
    func testDismissingDeletesTheNotificationByName() async throws {
        try await client.notify(UlanziNotification(name: "cc-abcdef12", text: "BAGUETTE ?", hold: true))
        try await client.dismiss(name: "cc-abcdef12")

        XCTAssertEqual(device.calls.last, "DELETE /api/v1/notifications/cc-abcdef12")
        XCTAssertEqual(device.heldNotifications, [])
    }

    /// Already gone, as after a press of the middle button: the device says
    /// 404, and nothing has failed.
    func testDismissingWhatIsAlreadyGoneIsNoFailure() async throws {
        try await client.dismiss(name: "cc-abcdef12")

        XCTAssertEqual(device.calls, ["DELETE /api/v1/notifications/cc-abcdef12"])
    }

    /// Any other no is still one.
    func testAnotherRefusalOfADismissalIsAFailure() async {
        device.answer("DELETE /api/v1/notifications/cc-abcdef12", status: 503,
                      body: FakeUlanzi.refusal("serviceBusy", "busy"))
        await assertFailure(.rejected(status: 503, message: "busy")) {
            try await self.client.dismiss(name: "cc-abcdef12")
        }
    }

    // MARK: - The indicator

    /// Indicator 1, lit with its three keys.
    func testTheIndicatorIsLitWithItsThreeKeys() async throws {
        try await client.setIndicator(UlanziIndicator(color: "#FF851B", blinkMs: 0, fadeMs: 2000))

        let request = try XCTUnwrap(device.requests.first)
        XCTAssertEqual(device.calls, ["PUT /api/v1/indicators/1"])
        XCTAssertEqual(request.contentType, "application/json")
        XCTAssertEqual(request.body, ##"{"blinkMs":0,"color":"#FF851B","fadeMs":2000}"##)
    }

    /// No indicator is the indicator switched off.
    func testNoIndicatorSwitchesItOff() async throws {
        try await client.setIndicator(UlanziIndicator(color: "#FF2D2D", blinkMs: 600, fadeMs: 0))
        try await client.setIndicator(nil)

        XCTAssertEqual(device.calls, ["PUT /api/v1/indicators/1", "DELETE /api/v1/indicators/1"])
        XCTAssertNil(device.indicator)
    }

    // MARK: - The button callback

    /// The address the device posts its buttons to is a system setting,
    /// sent with its slashes as they are.
    func testTheButtonCallbackIsASystemSetting() async throws {
        let url = URL(string: "http://192.168.1.50:51234/ulanzi/button/abc")!
        try await client.setButtonCallback(url)

        let request = try XCTUnwrap(device.requests.first)
        XCTAssertEqual(device.calls, ["PUT /api/v1/system"])
        XCTAssertEqual(request.contentType, "application/json")
        XCTAssertEqual(request.body, #"{"buttonCallback":"http://192.168.1.50:51234/ulanzi/button/abc"}"#)
        XCTAssertEqual(device.buttonCallback, url.absoluteString)
    }

    /// An empty address is the firmware's off: the device posts its buttons
    /// nowhere from then on.
    func testClearingTheButtonCallbackSendsAnEmptyAddress() async throws {
        try await client.setButtonCallback(URL(string: "http://192.168.1.50:51234/ulanzi/button/abc")!)
        try await client.clearButtonCallback()

        XCTAssertEqual(device.calls, ["PUT /api/v1/system", "PUT /api/v1/system"])
        XCTAssertEqual(device.requests.last?.body, #"{"buttonCallback":""}"#)
        XCTAssertEqual(device.buttonCallback, "")
    }

    // MARK: - Commands, and the road there

    /// Each command the board decides is the call it names.
    func testACommandIsTheCallItNames() async throws {
        try await client.perform(.notify(UlanziNotification(text: "CLAUDIO")))
        try await client.perform(.dismiss(name: "cc-1"))
        try await client.perform(.indicator(UlanziIndicator(color: "#FF851B", blinkMs: 0, fadeMs: 2000)))
        try await client.perform(.indicator(nil))

        XCTAssertEqual(device.calls, ["POST /api/v1/notifications", "DELETE /api/v1/notifications/cc-1",
                                      "PUT /api/v1/indicators/1", "DELETE /api/v1/indicators/1"])
    }

    /// The same two and a half seconds as the face's calls, and no cache.
    func testEveryHubCallIsQuickAndFresh() async throws {
        try await client.notify(UlanziNotification(text: "CLAUDIO"))
        try await client.dismiss(name: "cc-1")
        try await client.setIndicator(nil)
        try await client.setButtonCallback(URL(string: "http://192.168.1.50:1/ulanzi/button/t")!)

        XCTAssertEqual(device.requests.count, 4)
        for request in device.requests {
            XCTAssertEqual(request.timeout, 2.5, request.path)
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData, request.path)
        }
    }

    /// A clock that doesn't answer fails every call the same way.
    func testAnUnpluggedDeviceIsUnreachable() async {
        device.isUnplugged = true
        do {
            try await client.dismiss(name: "cc-1")
            XCTFail("an unplugged device answered")
        } catch UlanziClient.Failure.unreachable {
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    // MARK: - Helpers

    private func assertFailure(_ expected: UlanziClient.Failure,
                               file: StaticString = #filePath, line: UInt = #line,
                               _ call: @escaping () async throws -> Void) async {
        do {
            try await call()
            XCTFail("no failure, expected \(expected)", file: file, line: line)
        } catch let failure as UlanziClient.Failure {
            XCTAssertEqual(failure, expected, file: file, line: line)
        } catch {
            XCTFail("unexpected error: \(error)", file: file, line: line)
        }
    }
}
