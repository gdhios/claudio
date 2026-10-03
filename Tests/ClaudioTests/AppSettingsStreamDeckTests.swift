import XCTest
@testable import Claudio

/// Whether the Stream Deck bridge runs. Three states, not two: with nothing
/// stored the bridge follows the plugin, which is what makes installing the
/// plugin the whole setup. An explicit choice then outranks the plugin, in
/// both directions. Each test writes to throwaway defaults held in memory,
/// never to this Mac's preferences.
final class AppSettingsStreamDeckTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = InMemoryDefaults()
    }

    override func tearDown() {
        defaults = nil
        super.tearDown()
    }

    /// Nothing stored: the plugin's presence decides. Installing it is what
    /// switches the bridge on, and removing it is what switches it off.
    func testWithNoChoiceThePluginDecides() {
        XCTAssertNil(AppSettings.streamDeckBridgeChoice(in: defaults))
        XCTAssertTrue(AppSettings.streamDeckBridgeEnabled(pluginInstalled: true, in: defaults))
        XCTAssertFalse(AppSettings.streamDeckBridgeEnabled(pluginInstalled: false, in: defaults))
    }

    /// Switched off by hand with the plugin sitting there: the bridge stays
    /// off. Someone who says no to a listening socket is not asked twice.
    func testAnExplicitNoOutranksAnInstalledPlugin() {
        AppSettings.setStreamDeckBridgeChoice(false, in: defaults)
        XCTAssertEqual(AppSettings.streamDeckBridgeChoice(in: defaults), false)
        XCTAssertFalse(AppSettings.streamDeckBridgeEnabled(pluginInstalled: true, in: defaults))
    }

    /// Switched on by hand without the plugin: the bridge listens all the
    /// same, which is what a plugin installed somewhere unusual needs.
    func testAnExplicitYesOutranksAMissingPlugin() {
        AppSettings.setStreamDeckBridgeChoice(true, in: defaults)
        XCTAssertEqual(AppSettings.streamDeckBridgeChoice(in: defaults), true)
        XCTAssertTrue(AppSettings.streamDeckBridgeEnabled(pluginInstalled: false, in: defaults))
    }

    /// Back to automatic: the key goes, rather than being stored as a third
    /// value. A `false` left behind would keep the bridge off forever.
    func testGoingBackToAutomaticRemovesTheKey() {
        AppSettings.setStreamDeckBridgeChoice(false, in: defaults)
        AppSettings.setStreamDeckBridgeChoice(nil, in: defaults)

        XCTAssertNil(defaults.object(forKey: AppSettings.streamDeckBridgeKey))
        XCTAssertNil(AppSettings.streamDeckBridgeChoice(in: defaults))
        XCTAssertTrue(AppSettings.streamDeckBridgeEnabled(pluginInstalled: true, in: defaults))
    }

    /// The storage key is part of the contract: renaming it would forget
    /// every explicit choice made so far.
    func testItIsStoredUnderItsOwnKey() {
        XCTAssertEqual(AppSettings.streamDeckBridgeKey, "streamDeckBridgeEnabled")
        AppSettings.setStreamDeckBridgeChoice(false, in: defaults)
        XCTAssertEqual(defaults.object(forKey: "streamDeckBridgeEnabled") as? Bool, false)
    }
}
