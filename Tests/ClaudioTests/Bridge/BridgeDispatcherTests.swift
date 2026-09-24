import XCTest
@testable import Claudio

/// One frame in, one gesture out. The dispatcher is the whole of the bridge's
/// routing: it owns no coordinator, so every command is proved here without a
/// panel, a microphone or a window.
@MainActor
final class BridgeDispatcherTests: XCTestCase {

    /// What the dispatcher asked for, in order. Anything else than exactly
    /// one entry is a routing bug: a key doing two things, or nothing.
    private enum Call: Equatable {
        case action(ClaudioAction)
        case free
        case palette
        case whatsPlaying
        case dictationDown(BridgeDictationLanguage, DictationOutput)
        case dictationUp
        case dictationCancel
        case layout(WindowLayout)
        case nextScreen
        case settings
    }

    private var calls: [Call] = []

    private lazy var dispatcher = BridgeDispatcher(
        triggerAction: { [unowned self] in calls.append(.action($0)) },
        triggerFree: { [unowned self] in calls.append(.free) },
        triggerPalette: { [unowned self] in calls.append(.palette) },
        triggerWhatsPlaying: { [unowned self] in calls.append(.whatsPlaying) },
        dictationDown: { [unowned self] in calls.append(.dictationDown($0, $1)) },
        dictationUp: { [unowned self] in calls.append(.dictationUp) },
        dictationCancel: { [unowned self] in calls.append(.dictationCancel) },
        applyLayout: { [unowned self] in calls.append(.layout($0)) },
        nextScreen: { [unowned self] in calls.append(.nextScreen) },
        openSettings: { [unowned self] in calls.append(.settings) }
    )

    /// Dispatching `message` runs `expected` and nothing else.
    private func assertDispatch(_ message: BridgeInbound, calls expected: [Call],
                                file: StaticString = #filePath, line: UInt = #line) {
        calls = []
        XCTAssertTrue(dispatcher.dispatch(message), "\(message)", file: file, line: line)
        XCTAssertEqual(calls, expected, "\(message)", file: file, line: line)
    }

    // MARK: - Actions

    func testEveryCatalogActionReachesTheCoordinator() {
        for action in ClaudioAction.allCases {
            assertDispatch(.action(.catalog(action)), calls: [.action(action)])
        }
    }

    func testTheCustomActionAndThePaletteAreNotCatalogEntries() {
        assertDispatch(.action(.free), calls: [.free])
        assertDispatch(.action(.palette), calls: [.palette])
    }

    /// The listening panel, not a correction: the key reaches the listening
    /// coordinator and asks nothing of the selection.
    func testWhatsPlayingOpensTheListeningPanel() {
        assertDispatch(.action(.whatsPlaying), calls: [.whatsPlaying])
    }

    // MARK: - Dictation

    /// The key going down carries what it dictates: the dispatcher hands the
    /// two along rather than reading the settings behind the key's back.
    func testTheKeyGoingDownHandsOnItsLanguageAndItsOutput() {
        assertDispatch(.dictationDown(language: .secondary, output: .translateEN),
                       calls: [.dictationDown(.secondary, .translateEN)])
        assertDispatch(.dictationDown(language: .primary, output: .cleanup),
                       calls: [.dictationDown(.primary, .cleanup)])
    }

    func testTheKeyComingUpAndTheCancelAreTwoDifferentThings() {
        assertDispatch(.dictationUp, calls: [.dictationUp])
        assertDispatch(.dictationCancel, calls: [.dictationCancel])
    }

    // MARK: - Windows

    func testEveryLayoutReachesTheMover() {
        for layout in WindowLayout.allCases {
            assertDispatch(.window(.layout(layout)), calls: [.layout(layout)])
        }
    }

    func testTheNextDisplayIsItsOwnGesture() {
        assertDispatch(.window(.nextScreen), calls: [.nextScreen])
    }

    // MARK: - Settings

    func testOpeningTheSettings() {
        assertDispatch(.openSettings, calls: [.settings])
    }

    // MARK: - The handshake

    /// `hello` is no command: the server answers it, and a dispatcher that
    /// pressed a key on it would run a gesture nobody asked for.
    func testTheHandshakeIsNoCommandAndTouchesNothing() {
        XCTAssertFalse(dispatcher.dispatch(.hello(version: 1, token: "ab", plugin: "1.13.0")))
        XCTAssertEqual(calls, [])
    }
}
