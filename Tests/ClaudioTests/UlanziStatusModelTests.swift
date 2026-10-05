import XCTest
@testable import Claudio

/// What the Ulanzi tab shows, and what its field and its Test button mean.
/// The field is read like Ollama's: a bare host gets its scheme, a blank
/// field switches the face off, an address nobody could call leaves the one
/// kept alone, and the same address again restarts nothing. The model stores
/// nothing and calls nothing itself (the app applies the address and runs the
/// test), so these tests touch no preference and no device.
@MainActor
final class UlanziStatusModelTests: XCTestCase {

    private var applied: [URL?] = []
    private var tests = 0

    private func wiredModel(address: String = "") -> UlanziStatusModel {
        let model = UlanziStatusModel()
        model.address = address
        model.applyAddress = { [unowned self] in applied.append($0) }
        model.test = { [unowned self] in tests += 1 }
        return model
    }

    // MARK: - The field

    /// Built and left alone: no address, nothing running.
    func testAFreshModelHasNoAddressAndIsOff() {
        let model = UlanziStatusModel()
        XCTAssertEqual(model.address, "")
        XCTAssertEqual(model.status, .off)
    }

    /// A bare IP is what people type: it is applied with its scheme, and the
    /// field shows the address as it will be called.
    func testATypedAddressIsAppliedAsItWillBeCalled() {
        let model = wiredModel()

        XCTAssertTrue(model.submit(" 192.168.1.22 "))

        XCTAssertEqual(model.address, "http://192.168.1.22")
        XCTAssertEqual(applied, [URL(string: "http://192.168.1.22")])
    }

    /// Enter on the address already kept restarts nothing: the bridge would
    /// install, put the face away and start over for no reason.
    func testTheSameAddressAgainRestartsNothing() {
        let model = wiredModel(address: "http://192.168.1.22")

        XCTAssertTrue(model.submit("192.168.1.22"))
        XCTAssertTrue(model.submit("http://192.168.1.22"))

        XCTAssertTrue(applied.isEmpty)
    }

    /// Emptying the field is how the face is switched off; emptying it again
    /// asks for nothing more.
    func testABlankFieldSwitchesTheFaceOff() {
        let model = wiredModel(address: "http://192.168.1.22")

        XCTAssertTrue(model.submit("   "))
        XCTAssertTrue(model.submit(""))

        XCTAssertEqual(model.address, "")
        XCTAssertEqual(applied, [nil])
    }

    /// An address nobody could call doesn't replace the one that works.
    func testAnUnreadableAddressLeavesTheKeptOneAlone() {
        let model = wiredModel(address: "http://192.168.1.22")

        XCTAssertFalse(model.submit("ftp://192.168.1.22"))

        XCTAssertEqual(model.address, "http://192.168.1.22")
        XCTAssertTrue(applied.isEmpty)
    }

    /// A model nobody wired, a preview's, takes the address and asks
    /// nothing of an app that isn't there.
    func testAModelWithNoAppBehindItStillTakesTheAddress() {
        let model = UlanziStatusModel()
        model.status = .ready
        XCTAssertTrue(model.submit("192.168.1.30"))
        XCTAssertTrue(model.testTyped("192.168.1.30"))
        XCTAssertEqual(model.address, "http://192.168.1.30")
        XCTAssertEqual(model.status, .ready)
    }

    // MARK: - The Test button

    /// The address typed is kept first, then tried.
    func testTestingANewAddressKeepsItThenTries() {
        let model = wiredModel(address: "http://192.168.1.22")

        XCTAssertTrue(model.testTyped("192.168.1.30"))

        XCTAssertEqual(applied, [URL(string: "http://192.168.1.30")])
        XCTAssertEqual(tests, 1)
    }

    /// The address kept, tried as it is: nothing restarts on the way.
    func testTestingTheKeptAddressOnlyTries() {
        let model = wiredModel(address: "http://192.168.1.22")

        XCTAssertTrue(model.testTyped("http://192.168.1.22"))

        XCTAssertTrue(applied.isEmpty)
        XCTAssertEqual(tests, 1)
    }

    /// An address nobody could call is reported, and the old one is not
    /// tried in its place: the clock smiling would say the typo works.
    func testTestingAnUnreadableAddressTriesNothing() {
        let model = wiredModel(address: "http://192.168.1.22")

        XCTAssertFalse(model.testTyped("ftp://192.168.1.30"))

        XCTAssertTrue(applied.isEmpty)
        XCTAssertEqual(tests, 0)
        XCTAssertEqual(model.address, "http://192.168.1.22")
    }

    // MARK: - The status line

    /// Out of reach and in error are two different things to fix: a cable
    /// or an address, against a clock that answered no. Each says which,
    /// in the device's words rather than its JSON.
    func testTheStatusLineSaysWhatWentWrong() {
        useLanguage(.french)
        let model = UlanziStatusModel()
        let lines: [(UlanziBridge.Status, String)] = [
            (.off, "Désactivé"),
            (.installing, "Installation du visage…"),
            (.ready, "Prêt"),
            (.failed(.unreachable("Délai dépassé")), "Injoignable : Délai dépassé"),
            (.failed(.rejected(status: 503, message: "busy")), "Erreur : busy"),
            (.failed(.rejected(status: 503, message: "")), "Erreur : l'appareil a répondu 503"),
            (.failed(.scriptBroken("syntax_error: x")), "Erreur : syntax_error: x"),
        ]
        for (status, line) in lines {
            model.status = status
            XCTAssertEqual(model.statusLine, line)
        }
    }

    /// The same lines in English.
    func testTheStatusLineInEnglish() {
        useLanguage(.english)
        let model = UlanziStatusModel()
        model.status = .failed(.unreachable("Timed out"))
        XCTAssertEqual(model.statusLine, "Unreachable: Timed out")
        model.status = .failed(.scriptBroken("syntax_error: x"))
        XCTAssertEqual(model.statusLine, "Error: syntax_error: x")
    }
}
