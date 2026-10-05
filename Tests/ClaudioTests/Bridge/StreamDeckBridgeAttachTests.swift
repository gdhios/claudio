import XCTest
@testable import Claudio

/// Each coordinator takes one observer, and two bridges watch them, the
/// Stream Deck's and the Ulanzi's: the app sets the hooks once and tells
/// both. Attaching the Stream Deck bridge must leave those hooks alone; it
/// only keeps the coordinators, to read what is under way when it comes on.
@MainActor
final class StreamDeckBridgeAttachTests: XCTestCase {

    /// The hooks the app set are still the ones called after the bridge is
    /// attached: the Ulanzi keeps hearing about sessions.
    func testAttachingLeavesTheAppsHooksInPlace() {
        let correction = CorrectionCoordinator()
        let dictation = DictationCoordinator(engine: FakeSpeechEngine([]))
        var heard: [String] = []
        correction.onSessionChange = { _ in heard.append("correction") }
        dictation.onSessionChange = { _ in heard.append("dictation") }

        let bridge = StreamDeckBridge(
            dispatcher: .doingNothing,
            handshake: BridgeHandshakeFile(directory: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("ClaudioTests.unused.\(UUID().uuidString)")),
            appVersion: "test")
        bridge.attach(correction: correction, dictation: dictation)
        correction.onSessionChange?(nil)
        dictation.onSessionChange?(nil)

        XCTAssertEqual(heard, ["correction", "dictation"])
    }

    /// Off, the bridge has nobody to tell: what the app relays goes nowhere,
    /// and opens nothing.
    func testAStoppedBridgeTakesTheRelaysAndStaysOff() {
        let bridge = StreamDeckBridge(
            dispatcher: .doingNothing,
            handshake: BridgeHandshakeFile(directory: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("ClaudioTests.unused.\(UUID().uuidString)")),
            appVersion: "test")
        bridge.correctionSessionChanged(CorrectionSession(request: ClaudioAction.correct.request))
        bridge.dictationSessionChanged(DictationSession(language: .frFR, model: .raw))

        XCTAssertEqual(bridge.status, .off)
    }
}
