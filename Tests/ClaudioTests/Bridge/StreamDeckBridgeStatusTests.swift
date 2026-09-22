import XCTest
@testable import Claudio

/// What Settings reads off the bridge. The socket itself is out of reach of
/// a test — it would open one — but the rule that turns the bridge's two
/// facts into a line on screen is a value, and it is the part Settings
/// watches.
@MainActor
final class StreamDeckBridgeStatusTests: XCTestCase {

    /// Nothing published: nothing for a plugin to find, whatever else is
    /// true.
    func testABridgeThatPublishedNothingIsOff() {
        XCTAssertEqual(StreamDeckBridge.status(published: false, clients: 0), .off)
    }

    /// The case the rule exists for: a bridge being switched off closes its
    /// last connection, which reports a count of zero on the way out. Read
    /// as "waiting for the plugin", that would flash the wrong line on
    /// screen a moment before "off".
    func testABridgeOnItsWayOffIsOffWhateverTheCount() {
        XCTAssertEqual(StreamDeckBridge.status(published: false, clients: 3), .off)
    }

    /// Everything Claudio can do is done: the plugin is the one that hasn't
    /// come.
    func testPublishedAndAloneIsWaiting() {
        XCTAssertEqual(StreamDeckBridge.status(published: true, clients: 0), .waiting)
    }

    /// The count travels: a Stream Deck and its property inspector are two.
    func testEveryConnectedPluginIsCounted() {
        XCTAssertEqual(StreamDeckBridge.status(published: true, clients: 1),
                       .connected(clients: 1))
        XCTAssertEqual(StreamDeckBridge.status(published: true, clients: 2),
                       .connected(clients: 2))
    }

    /// Built and left alone: no socket, no handshake file, nothing to show.
    func testAFreshBridgeIsOff() {
        let bridge = StreamDeckBridge(
            dispatcher: .doingNothing,
            handshake: BridgeHandshakeFile(directory: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("ClaudioTests.unused.\(UUID().uuidString)")),
            appVersion: "test")
        XCTAssertEqual(bridge.status, .off)
    }
}

private extension BridgeDispatcher {
    /// A dispatcher whose keys go nowhere: what a bridge that is never
    /// started would do with them.
    static var doingNothing: BridgeDispatcher {
        BridgeDispatcher(triggerAction: { _ in }, triggerFree: {}, triggerPalette: {},
                         dictationDown: { _, _ in }, dictationUp: {}, dictationCancel: {},
                         applyLayout: { _ in }, nextScreen: {}, openSettings: {})
    }
}
