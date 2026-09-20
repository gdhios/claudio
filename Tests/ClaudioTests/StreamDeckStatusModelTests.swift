import XCTest
@testable import Claudio

/// What the Stream Deck tab shows and what flipping its switch means. Three
/// states, not two: left alone, the switch follows the plugin's presence;
/// touched, it holds an explicit choice that outranks it, until it is handed
/// back to the automatic. The model knows nothing of preferences or sockets —
/// the app applies the choice — so these tests store nothing on this Mac.
@MainActor
final class StreamDeckStatusModelTests: XCTestCase {

    /// The state a fresh install is in: nobody chose, so the plugin decides
    /// and the switch shows what it decided.
    func testWithNoChoiceTheSwitchFollowsThePlugin() {
        let model = StreamDeckStatusModel()
        model.pluginInstalled = true
        XCTAssertTrue(model.isAutomatic)
        XCTAssertTrue(model.isOn)

        model.pluginInstalled = false
        XCTAssertTrue(model.isAutomatic)
        XCTAssertFalse(model.isOn)
    }

    /// Flipping the switch is a choice, and a choice outranks the plugin:
    /// the tab stops following it and the app is told what to apply.
    func testFlippingTheSwitchMakesAnExplicitChoice() {
        let model = StreamDeckStatusModel()
        model.pluginInstalled = true
        var applied: [Bool?] = []
        model.applyChoice = { applied.append($0) }

        model.setOn(false)
        XCTAssertFalse(model.isAutomatic)
        XCTAssertFalse(model.isOn)
        XCTAssertEqual(model.choice, false)
        XCTAssertEqual(applied.count, 1)
        XCTAssertEqual(applied.first, false)
    }

    /// The other direction, which is what the choice is for: a plugin kept
    /// somewhere Claudio can't see still gets a socket.
    func testSwitchingItOnWithoutThePluginIsAChoiceToo() {
        let model = StreamDeckStatusModel()
        model.pluginInstalled = false
        var applied: [Bool?] = []
        model.applyChoice = { applied.append($0) }

        model.setOn(true)
        XCTAssertFalse(model.isAutomatic)
        XCTAssertTrue(model.isOn)
        XCTAssertEqual(applied.first, true)
    }

    /// Back to automatic: the choice is forgotten, the plugin decides again,
    /// and the app hears `nil` rather than the value that was showing.
    func testBackToAutomaticForgetsTheChoice() {
        let model = StreamDeckStatusModel()
        model.pluginInstalled = true
        model.setOn(false)
        var applied: [Bool?] = []
        model.applyChoice = { applied.append($0) }

        model.backToAutomatic()
        XCTAssertTrue(model.isAutomatic)
        XCTAssertNil(model.choice)
        XCTAssertTrue(model.isOn)
        XCTAssertEqual(applied.count, 1)
        XCTAssertEqual(applied.first, Bool?.none)
    }

    /// A model nobody wired — a preview — changes its own state and asks
    /// nothing of an app that isn't there.
    func testAModelWithNoAppBehindItStillHoldsItsState() {
        let model = StreamDeckStatusModel()
        model.status = .waiting
        model.setOn(true)
        XCTAssertEqual(model.status, .waiting)
        XCTAssertEqual(model.choice, true)
    }

    /// The tab reads its line off the bridge, and only the bridge: a model
    /// built and left alone says the bridge is off.
    func testAFreshModelReportsTheBridgeOff() {
        XCTAssertEqual(StreamDeckStatusModel().status, .off)
    }
}
