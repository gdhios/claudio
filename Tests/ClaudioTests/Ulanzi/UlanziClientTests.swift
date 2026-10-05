import XCTest
@testable import Claudio

/// The four calls Claudio makes to the clock, as AWTRIX NG 1.1.2 takes them:
/// the method, the path, the type and the body, to the byte where the device
/// is strict. A JSON body with a key it doesn't know is refused, and the
/// installed script is compared to Claudio's own byte for byte.
///
/// And the answers, as the firmware documents them: `"error":null` when all
/// is well, the script's error as an object when it can't run (under a 200,
/// with `ok` still true), and a refusal as `{"error":{"code","message"}}`
/// under its status. What Settings shows is the device's message, never its
/// JSON. Answered by `FakeUlanzi`: no socket is opened.
final class UlanziClientTests: XCTestCase {

    private var device: FakeUlanzi!
    private var client: UlanziClient!

    override func setUp() {
        super.setUp()
        connect(to: FakeUlanzi())
    }

    override func tearDown() {
        client = nil
        device = nil
        super.tearDown()
    }

    private func connect(to device: FakeUlanzi, at address: String = "http://192.168.1.22") {
        self.device = device
        client = UlanziClient(baseURL: URL(string: address)!, transport: device.transport)
    }

    // MARK: - The script

    /// The source comes back as the device holds it, untouched: it is what
    /// decides whether Claudio installs his face again.
    func testTheInstalledScriptIsReadAsItIs() async throws {
        connect(to: FakeUlanzi(script: "return 1\n"))

        let script = try await client.installedScript()
        XCTAssertEqual(script, "return 1\n")
        XCTAssertEqual(device.calls, ["GET /api/v1/apps/script/Claudio"])
    }

    /// A device that never had the face answers 404: that is no script, not
    /// a failure.
    func testNoScriptOnTheDeviceIsNil() async throws {
        let script = try await client.installedScript()
        XCTAssertNil(script)
    }

    /// Anything else the device says to the read is a refusal, carrying its
    /// message.
    func testAnotherAnswerToTheReadIsARefusal() async {
        device.answer("GET /api/v1/apps/script/Claudio", status: 503,
                      body: FakeUlanzi.refusal("serviceBusy", "busy, try again"))
        await assertFailure(.rejected(status: 503, message: "busy, try again")) {
            _ = try await self.client.installedScript()
        }
    }

    /// The source goes as raw text, byte for byte: the device hands back what
    /// it was sent, and the next comparison depends on it. `"error":null` is
    /// the firmware saying all went well.
    func testInstallingSendsTheSourceAsPlainText() async throws {
        try await client.install(UlanziFaceScript.source)

        let request = try XCTUnwrap(device.requests.first)
        XCTAssertEqual(device.calls, ["PUT /api/v1/apps/script/Claudio"])
        XCTAssertEqual(request.contentType, "text/plain")
        XCTAssertEqual(request.body, UlanziFaceScript.source)
        XCTAssertEqual(device.script, UlanziFaceScript.source)
    }

    /// The device took the file and the script doesn't run: a 200, `ok`
    /// still true, and the error as an object. The install has failed all
    /// the same, in the script's own words.
    func testAScriptTheDeviceCannotRunIsBroken() async {
        device.scriptError = "syntax_error: unexpected 'end'"
        await assertFailure(.scriptBroken("syntax_error: unexpected 'end'")) {
            try await self.client.install(UlanziFaceScript.source)
        }
    }

    /// Every gaze restarts the script, and a script that fails to restart
    /// says so the same way: that gaze is not on the screen.
    func testAGazeTheScriptCannotRunIsBroken() async {
        connect(to: FakeUlanzi(script: UlanziFaceScript.source))
        device.scriptError = "runtime_error: division by zero"
        await assertFailure(.scriptBroken("runtime_error: division by zero")) {
            try await self.client.setGaze("repos")
        }
    }

    /// An error with no message to show is shown as the device sent it.
    func testAnErrorWithoutAMessageIsShownAsSent() async {
        device.answer("PUT /api/v1/apps/script/Claudio", status: 200, body: #"{"ok":true,"error":{"line":3}}"#)
        await assertFailure(.scriptBroken(#"{"ok":true,"error":{"line":3}}"#)) {
            try await self.client.install(UlanziFaceScript.source)
        }
    }

    // MARK: - The gaze, and the face

    /// The gaze travels as the script's config, alone under its own key: a
    /// key the script doesn't declare would get the whole body refused.
    func testTheGazeIsTheScriptsConfig() async throws {
        connect(to: FakeUlanzi(script: UlanziFaceScript.source))

        try await client.setGaze("repos")

        let request = try XCTUnwrap(device.requests.first)
        XCTAssertEqual(device.calls, ["PATCH /api/v1/apps/Claudio/config"])
        XCTAssertEqual(request.contentType, "application/json")
        XCTAssertEqual(request.body, #"{"gaze":"repos"}"#)
        XCTAssertEqual(device.gaze, "repos")
    }

    /// A script that isn't there, or a gaze the script doesn't list: the
    /// device says no, and its message comes back with the status.
    func testARefusedGazeCarriesTheDevicesMessage() async {
        await assertFailure(.rejected(status: 404, message: "app not found")) {
            try await self.client.setGaze("repos")
        }
        connect(to: FakeUlanzi(script: UlanziFaceScript.source))
        await assertFailure(.rejected(status: 422, message: "gaze is not one of the options")) {
            try await self.client.setGaze("sleepy")
        }
    }

    /// A refusal that isn't JSON is shown as the text it is.
    func testARefusalThatIsNotJSONIsShownAsSent() async {
        device.answer("PUT /api/v1/apps/active", status: 500, body: "busy\n")
        await assertFailure(.rejected(status: 500, message: "busy")) {
            try await self.client.show()
        }
    }

    /// Summoning the face names the app and asks for it at once, `fast` as a
    /// JSON boolean.
    func testShowingTheFaceNamesItsApp() async throws {
        connect(to: FakeUlanzi(script: UlanziFaceScript.source))

        try await client.show()

        let request = try XCTUnwrap(device.requests.first)
        XCTAssertEqual(device.calls, ["PUT /api/v1/apps/active"])
        XCTAssertEqual(request.contentType, "application/json")
        XCTAssertEqual(request.body, #"{"fast":true,"name":"Claudio"}"#)
    }

    /// A 2xx that says `ok: false` is still a no.
    func testAnAnswerThatSaysNoIsARefusal() async {
        device.answer("PUT /api/v1/apps/active", status: 200, body: #"{"ok":false}"#)
        await assertFailure(.rejected(status: 200, message: #"{"ok":false}"#)) {
            try await self.client.show()
        }
    }

    // MARK: - The road there

    /// A clock that is unplugged, or not on this network, is unreachable,
    /// whatever URLSession called it.
    func testADeviceThatDoesNotAnswerIsUnreachable() async {
        device.isUnplugged = true
        do {
            try await client.setGaze("off")
            XCTFail("an unplugged device answered")
        } catch UlanziClient.Failure.unreachable(let reason) {
            XCTAssertFalse(reason.isEmpty)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    /// Every call gives up after two and a half seconds, and none is answered
    /// from a cache: the script read has to be what the device holds now.
    func testEveryCallIsQuickAndFresh() async throws {
        connect(to: FakeUlanzi(script: UlanziFaceScript.source))

        _ = try await client.installedScript()
        try await client.install(UlanziFaceScript.source)
        try await client.setGaze("fait")
        try await client.show()

        XCTAssertEqual(device.requests.count, 4)
        for request in device.requests {
            XCTAssertEqual(request.timeout, 2.5, request.path)
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData, request.path)
        }
    }

    /// An address typed with a trailing slash reaches the same paths.
    func testATrailingSlashInTheAddressChangesNoPath() async throws {
        connect(to: FakeUlanzi(), at: "http://192.168.1.22/")
        _ = try await client.installedScript()
        XCTAssertEqual(device.calls, ["GET /api/v1/apps/script/Claudio"])
    }

    // MARK: - What Settings shows

    /// The device's own words, never its JSON; the status alone when it
    /// gave none.
    func testAFailureReadsAsTheDevicesMessage() {
        useLanguage(.french)
        XCTAssertEqual(UlanziClient.Failure.rejected(status: 503, message: "busy").localizedDescription, "busy")
        XCTAssertEqual(UlanziClient.Failure.rejected(status: 503, message: "").localizedDescription,
                       "l'appareil a répondu 503")
        XCTAssertEqual(UlanziClient.Failure.scriptBroken("syntax_error: x").localizedDescription, "syntax_error: x")
        XCTAssertEqual(UlanziClient.Failure.unreachable("Délai dépassé").localizedDescription, "Délai dépassé")
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
