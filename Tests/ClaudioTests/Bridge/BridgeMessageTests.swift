import XCTest
@testable import Claudio

/// The wire format, frame by frame, against the fixtures the plugin reads
/// too. Nothing here opens a socket: a frame is a value, and this is the
/// whole of what the bridge has to agree on.
final class BridgeMessageTests: XCTestCase {

    private func decoded(_ fixture: String) throws -> BridgeInbound {
        try BridgeFixtures.decode(BridgeInbound.self, from: fixture)
    }

    /// A frame the app cannot make sense of is refused, never guessed at:
    /// the connection is what the server closes on it.
    private func assertRejects(_ json: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        let data = Data(json.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(BridgeInbound.self, from: data),
                             json, file: file, line: line) { error in
            XCTAssertTrue(error is DecodingError,
                          "\(json) threw \(error)", file: file, line: line)
        }
    }

    // MARK: - The handshake

    func testHelloCarriesTheVersionTheTokenAndThePluginVersion() throws {
        XCTAssertEqual(try decoded("hello"),
                       .hello(version: 1,
                              token: "3f9a1c0e7b2d4f6a8c1e3b5d7f9a2c4e6b8d0f1a3c5e7b9d2f4a6c8e0b1d3f5a",
                              plugin: "1.13.0"))
    }

    func testTheProtocolVersionIsTheOneTheFixtureAnnounces() throws {
        let hello = try BridgeFixtures.object("hello")
        XCTAssertEqual(hello["v"] as? Int, BridgeProtocol.version)
        XCTAssertEqual(BridgeProtocol.version, 1)
    }

    // MARK: - Actions

    func testACatalogActionArrivesByItsOwnIdentifier() throws {
        XCTAssertEqual(try decoded("action-correct"), .action(.catalog(.correct)))
    }

    /// Every catalog entry is reachable from a key, not just the one with a
    /// fixture: the identifier on the wire is the action's own rawValue.
    func testEveryCatalogActionIsReachable() throws {
        for action in ClaudioAction.allCases {
            let json = Data(#"{"type":"action","id":"\#(action.rawValue)"}"#.utf8)
            XCTAssertEqual(try JSONDecoder().decode(BridgeInbound.self, from: json),
                           .action(.catalog(action)), action.rawValue)
        }
    }

    func testTheFreeActionIsNotACatalogEntry() throws {
        XCTAssertEqual(try decoded("action-free"), .action(.free))
    }

    func testThePaletteIsNotACatalogEntryEither() throws {
        XCTAssertEqual(try decoded("action-palette"), .action(.palette))
    }

    /// "What's playing?" reads the player, not the selection: it is no
    /// catalog entry, and it rides the Action key's frame all the same.
    func testWhatsPlayingIsNoCatalogEntryAndArrivesByItsOwnName() throws {
        XCTAssertEqual(try decoded("action-whats-playing"), .action(.whatsPlaying))
    }

    // MARK: - Dictation

    /// The key going down carries what the dictation will be: the language
    /// it is spoken in and what it becomes. Both belong to the key, as they
    /// belong to a shortcut, which is why they travel with the press.
    func testTheKeyGoingDownCarriesTheLanguageAndTheOutput() throws {
        XCTAssertEqual(try decoded("dictation-down"),
                       .dictationDown(language: .primary, output: .cleanup))
        XCTAssertEqual(try decoded("dictation-down-secondary"),
                       .dictationDown(language: .secondary, output: .cleanup))
        XCTAssertEqual(try decoded("dictation-down-translate"),
                       .dictationDown(language: .primary, output: .translateEN))
    }

    func testTheKeyComingUpCarriesNothingElse() throws {
        XCTAssertEqual(try decoded("dictation-up"), .dictationUp)
    }

    func testACancelledDictationCarriesNothingElseEither() throws {
        XCTAssertEqual(try decoded("dictation-cancel"), .dictationCancel)
    }

    // MARK: - Windows

    func testALayoutArrivesByItsWireName() throws {
        XCTAssertEqual(try decoded("window-top-left"), .window(.layout(.topLeft)))
    }

    /// The next display is no layout: it moves the window, it doesn't
    /// reshape it. It shares the field because it shares the key.
    func testTheNextDisplayIsALayoutsNeighbourNotALayout() throws {
        XCTAssertEqual(try decoded("window-next-screen"), .window(.nextScreen))
    }

    // MARK: - Opening Claudio

    func testOpeningTheSettings() throws {
        XCTAssertEqual(try decoded("open-settings"), .openSettings)
    }

    // MARK: - What is refused

    func testAnUnknownTypeIsRefused() {
        assertRejects(#"{"type":"explode"}"#)
        assertRejects(#"{"id":"correct"}"#)
    }

    func testAnUnknownActionIsRefused() {
        assertRejects(#"{"type":"action","id":"rewriteInLatin"}"#)
        // The fixture's file name is not the wire name.
        assertRejects(#"{"type":"action","id":"whats-playing"}"#)
    }

    func testAnUnknownLayoutIsRefused() {
        assertRejects(#"{"type":"window","layout":"thirdOfTheWay"}"#)
    }

    func testAnUnknownDictationEventLanguageOrOutputIsRefused() {
        assertRejects(#"{"type":"dictation","event":"hum"}"#)
        assertRejects(#"{"type":"dictation","event":"down","language":"third","output":"cleanup"}"#)
        assertRejects(#"{"type":"dictation","event":"down","language":"primary","output":"haiku"}"#)
    }

    /// The press is where the language and the output are decided: a `down`
    /// without them is a plugin from another version, not a default.
    func testADownWithoutItsLanguageOrItsOutputIsRefused() {
        assertRejects(#"{"type":"dictation","event":"down","language":"primary"}"#)
        assertRejects(#"{"type":"dictation","event":"down","output":"cleanup"}"#)
    }

    /// The version is a number. A plugin sending "1" doesn't get the benefit
    /// of the doubt: the handshake is the one frame that must not be guessed.
    func testAVersionThatIsNotANumberIsRefused() {
        assertRejects(#"{"type":"hello","v":"1","token":"ab","plugin":"1.13.0"}"#)
        assertRejects(#"{"type":"hello","token":"ab","plugin":"1.13.0"}"#)
    }

    func testAnUnknownOpenTargetIsRefused() {
        assertRejects(#"{"type":"open","target":"history"}"#)
    }

    // MARK: - What the app answers

    func testTheWelcomeCarriesTheVersionTheAppVersionAndTheState() throws {
        try BridgeFixtures.assertEncoding(
            BridgeOutbound.welcome(version: 1, app: "1.13.0", state: .idle),
            matches: "welcome")
    }

    func testTheIdleState() throws {
        try BridgeFixtures.assertEncoding(BridgeOutbound.state(.idle), matches: "state-idle")
    }

    /// The label is the fixture's own wire data, quoted verbatim — not a
    /// string this test displays, so it goes through no `loc`. The app's
    /// language never enters into it: both sides of the comparison are fixed.
    func testAStreamingCorrection() throws {
        let state = BridgeState(gaze: .veille, activity: .correction,
                                phase: "streaming", label: "Correction…", locked: false)
        try BridgeFixtures.assertEncoding(BridgeOutbound.state(state),
                                          matches: "state-correction-streaming")
    }

    func testACorrectionWithNothingSelected() throws {
        let state = BridgeState(gaze: .vide, activity: .correction,
                                phase: "noSelection", label: nil, locked: false)
        try BridgeFixtures.assertEncoding(BridgeOutbound.state(state),
                                          matches: "state-correction-no-selection")
    }

    func testAListeningDictation() throws {
        let state = BridgeState(gaze: .repos, activity: .dictation,
                                phase: "listening", label: nil, locked: false)
        try BridgeFixtures.assertEncoding(BridgeOutbound.state(state),
                                          matches: "state-dictation-listening")
    }

    /// Same here: the label is the fixture's wire data, quoted verbatim.
    func testALockedDictationBeingCleanedUp() throws {
        let state = BridgeState(gaze: .veille, activity: .dictation,
                                phase: "cleaning", label: "Nettoyage…", locked: true)
        try BridgeFixtures.assertEncoding(BridgeOutbound.state(state),
                                          matches: "state-dictation-cleaning-locked")
    }

    func testADictationThatIsOver() throws {
        let state = BridgeState(gaze: .fait, activity: .dictation,
                                phase: "done", label: nil, locked: false)
        try BridgeFixtures.assertEncoding(BridgeOutbound.state(state),
                                          matches: "state-dictation-done")
    }

    /// The keys stay, empty: a plugin reading `phase` on a frame that lost
    /// the field would see a state from another version rather than an idle
    /// Claudio.
    func testAnEmptyPhaseAndLabelGoOutAsNullRatherThanVanishing() throws {
        let encoded = try JSONEncoder().encode(BridgeOutbound.state(.idle))
        let object = try BridgeFixtures.object(in: encoded)
        XCTAssertTrue(object["phase"] is NSNull)
        XCTAssertTrue(object["label"] is NSNull)
    }

    /// The state reads back out of the frame it was written into, flat keys
    /// and all: what the plugin's own parser goes looking for is there. The
    /// label, again, is the fixture's wire data quoted verbatim.
    func testAStateFrameReadsBackAsTheStateItCarries() throws {
        XCTAssertEqual(try BridgeFixtures.decode(BridgeState.self, from: "state-idle"), .idle)
        XCTAssertEqual(
            try BridgeFixtures.decode(BridgeState.self, from: "state-dictation-cleaning-locked"),
            BridgeState(gaze: .veille, activity: .dictation,
                        phase: "cleaning", label: "Nettoyage…", locked: true))
    }

    func testTheMicrophoneLevel() throws {
        try BridgeFixtures.assertEncoding(BridgeOutbound.level(0.42), matches: "level")
    }

    func testTheGoodbye() throws {
        try BridgeFixtures.assertEncoding(BridgeOutbound.bye, matches: "bye")
    }

    func testAnUnsupportedVersionIsAnError() throws {
        try BridgeFixtures.assertEncoding(
            BridgeOutbound.error(code: .version, message: "Unsupported protocol version"),
            matches: "error-version")
    }

    /// The other refusal the server has: a token that doesn't match the
    /// handshake file.
    func testAnErrorCodeIsOneOfTwoWireNames() {
        XCTAssertEqual(BridgeErrorCode.version.rawValue, "version")
        XCTAssertEqual(BridgeErrorCode.token.rawValue, "token")
    }
}
