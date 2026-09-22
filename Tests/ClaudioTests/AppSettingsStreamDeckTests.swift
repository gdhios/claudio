import XCTest
@testable import Claudio

/// Whether the Stream Deck bridge runs. Three states, not two: with nothing
/// stored the bridge follows the plugin, which is what makes installing the
/// plugin the whole setup. An explicit choice then outranks the plugin, in
/// both directions. Each test writes to a throwaway suite, never to this
/// Mac's preferences.
final class AppSettingsStreamDeckTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ClaudioTests.streamDeck.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    /// Nothing stored: the plugin's presence decides. Installing it is what
    /// switches the bridge on, and removing it is what switches it off.
    func testWithNoChoiceThePluginDecides() {
        XCTAssertNil(AppSettings.streamDeckBridgeChoice(defaults: defaults))
        XCTAssertTrue(AppSettings.streamDeckBridgeEnabled(pluginInstalled: true, defaults: defaults))
        XCTAssertFalse(AppSettings.streamDeckBridgeEnabled(pluginInstalled: false, defaults: defaults))
    }

    /// Switched off by hand with the plugin sitting there: the bridge stays
    /// off. Someone who says no to a listening socket is not asked twice.
    func testAnExplicitNoOutranksAnInstalledPlugin() {
        AppSettings.setStreamDeckBridgeChoice(false, defaults: defaults)
        XCTAssertEqual(AppSettings.streamDeckBridgeChoice(defaults: defaults), false)
        XCTAssertFalse(AppSettings.streamDeckBridgeEnabled(pluginInstalled: true, defaults: defaults))
    }

    /// Switched on by hand without the plugin: the bridge listens all the
    /// same, which is what a plugin installed somewhere unusual needs.
    func testAnExplicitYesOutranksAMissingPlugin() {
        AppSettings.setStreamDeckBridgeChoice(true, defaults: defaults)
        XCTAssertEqual(AppSettings.streamDeckBridgeChoice(defaults: defaults), true)
        XCTAssertTrue(AppSettings.streamDeckBridgeEnabled(pluginInstalled: false, defaults: defaults))
    }

    /// Back to automatic: the key goes, rather than being stored as a third
    /// value. A `false` left behind would keep the bridge off forever.
    func testGoingBackToAutomaticRemovesTheKey() {
        AppSettings.setStreamDeckBridgeChoice(false, defaults: defaults)
        AppSettings.setStreamDeckBridgeChoice(nil, defaults: defaults)

        XCTAssertNil(defaults.object(forKey: AppSettings.streamDeckBridgeKey))
        XCTAssertNil(AppSettings.streamDeckBridgeChoice(defaults: defaults))
        XCTAssertTrue(AppSettings.streamDeckBridgeEnabled(pluginInstalled: true, defaults: defaults))
    }

    /// The storage key is part of the contract: renaming it would forget
    /// every explicit choice made so far.
    func testItIsStoredUnderItsOwnKey() {
        XCTAssertEqual(AppSettings.streamDeckBridgeKey, "streamDeckBridgeEnabled")
        AppSettings.setStreamDeckBridgeChoice(false, defaults: defaults)
        XCTAssertEqual(defaults.object(forKey: "streamDeckBridgeEnabled") as? Bool, false)
    }
}
