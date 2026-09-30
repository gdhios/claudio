import XCTest
@testable import Claudio

/// The master switch for dictation. At stake: someone who never dictates
/// gets their keys back, and someone who never opens Settings keeps
/// dictating. Each test writes to throwaway defaults held in memory, never
/// to this Mac's preferences.
final class AppSettingsDictationEnabledTests: XCTestCase {

    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = InMemoryDefaults()
    }

    override func tearDown() {
        defaults = nil
        super.tearDown()
    }

    /// Nothing stored: dictation works, as it did before there was a switch.
    func testDictationIsOnWithNothingStored() {
        XCTAssertTrue(AppSettings.dictationEnabled(in: defaults))
    }

    /// Switched off, it stays off — the whole point of the switch.
    func testSwitchingItOffIsRemembered() {
        AppSettings.setDictationEnabled(false, in: defaults)
        XCTAssertFalse(AppSettings.dictationEnabled(in: defaults))

        AppSettings.setDictationEnabled(true, in: defaults)
        XCTAssertTrue(AppSettings.dictationEnabled(in: defaults))
    }

    /// The storage key is part of the contract: renaming it would switch
    /// dictation back on under everyone who had turned it off.
    func testItIsStoredUnderItsOwnKey() {
        AppSettings.setDictationEnabled(false, in: defaults)
        XCTAssertEqual(defaults.object(forKey: "dictationEnabled") as? Bool, false)
    }
}
