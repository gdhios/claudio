import XCTest
@testable import Claudio

/// Which lone modifier key each dictation shortcut is set to: one storage
/// key per shortcut, holding the key's rawValue, absent for none. At stake:
/// a key set today still dictates after an update, and one key never ends up
/// on both shortcuts. Each test writes to a throwaway suite, never to this
/// Mac's preferences.
final class AppSettingsLoneKeyTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ClaudioTests.loneKeys.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    /// Nothing stored: both shortcuts are key combinations, as before.
    func testNoLoneKeyWithNothingStored() {
        for shortcut in DictationShortcut.allCases {
            XCTAssertNil(AppSettings.dictationLoneKey(for: shortcut, in: defaults))
        }
    }

    func testEachShortcutKeepsItsKeyUnderItsOwnStorageKey() {
        AppSettings.setDictationLoneKey(.rightOption, for: .dictate, in: defaults)
        AppSettings.setDictationLoneKey(.rightCommand, for: .dictateOtherLanguage, in: defaults)

        XCTAssertEqual(defaults.string(forKey: "dictationLoneKey"), "rightOption")
        XCTAssertEqual(defaults.string(forKey: "dictationSecondaryLoneKey"), "rightCommand")
        XCTAssertEqual(AppSettings.dictationLoneKey(for: .dictate, in: defaults), .rightOption)
        XCTAssertEqual(AppSettings.dictationLoneKey(for: .dictateOtherLanguage, in: defaults), .rightCommand)
    }

    /// One key can't dictate in two languages at once: given to one
    /// shortcut, it is taken from the other.
    func testALoneKeyServesOneShortcutOnly() {
        AppSettings.setDictationLoneKey(.rightOption, for: .dictate, in: defaults)
        AppSettings.setDictationLoneKey(.rightOption, for: .dictateOtherLanguage, in: defaults)

        XCTAssertNil(defaults.object(forKey: "dictationLoneKey"))
        XCTAssertNil(AppSettings.dictationLoneKey(for: .dictate, in: defaults))
        XCTAssertEqual(AppSettings.dictationLoneKey(for: .dictateOtherLanguage, in: defaults), .rightOption)
    }

    /// Cleared, the storage key goes: absent is what "no lone key" means.
    func testClearingRemovesTheStorageKey() {
        AppSettings.setDictationLoneKey(.rightShift, for: .dictate, in: defaults)
        AppSettings.setDictationLoneKey(nil, for: .dictate, in: defaults)

        XCTAssertNil(defaults.object(forKey: "dictationLoneKey"))
        XCTAssertNil(AppSettings.dictationLoneKey(for: .dictate, in: defaults))
    }

    /// A key written by a future version reads as none rather than as some
    /// other key, and clearing the field takes it away.
    func testAnUnknownValueReadsAsNone() {
        defaults.set("leftFn", forKey: "dictationLoneKey")
        XCTAssertNil(AppSettings.dictationLoneKey(for: .dictate, in: defaults))

        AppSettings.setDictationLoneKey(nil, for: .dictate, in: defaults)
        XCTAssertNil(defaults.object(forKey: "dictationLoneKey"))
    }

    /// The keyboard monitor and the Settings fields follow the change.
    func testAChangeIsAnnounced() {
        let announced = expectation(forNotification: AppSettings.dictationLoneKeysDidChange,
                                    object: defaults)
        AppSettings.setDictationLoneKey(.rightControl, for: .dictate, in: defaults)
        wait(for: [announced], timeout: 1)
    }

    /// Setting what is already set changes nothing, and says nothing.
    func testSettingTheSameKeyAgainIsNotAnnounced() {
        AppSettings.setDictationLoneKey(.rightControl, for: .dictate, in: defaults)
        let announced = expectation(forNotification: AppSettings.dictationLoneKeysDidChange,
                                    object: defaults)
        announced.isInverted = true
        AppSettings.setDictationLoneKey(.rightControl, for: .dictate, in: defaults)
        wait(for: [announced], timeout: 0.1)
    }
}
