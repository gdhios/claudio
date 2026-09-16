import AppKit
import XCTest
@testable import Claudio

/// The modifier keys a dictation shortcut can be on its own. The rawValues
/// are storage keys, and the key codes and device bits are what tells a
/// right-hand key from its left-hand twin: a wrong one here is a shortcut
/// that never fires, or one that fires on every ⌥ typed.
final class LoneModifierKeyTests: XCTestCase {

    private var previousLanguage: AppLanguage = .system

    override func setUp() {
        super.setUp()
        previousLanguage = AppSettings.language
    }

    override func tearDown() {
        AppSettings.language = previousLanguage
        super.tearDown()
    }

    /// Written to the preferences: added to, never renamed.
    func testTheRawValuesAreTheStorageKeys() {
        XCTAssertEqual(LoneModifierKey.allCases.map(\.rawValue),
                       ["rightOption", "rightCommand", "rightShift", "rightControl"])
    }

    /// kVK_RightOption, kVK_RightCommand, kVK_RightShift, kVK_RightControl.
    func testEachKeyHasItsRightHandKeyCode() {
        XCTAssertEqual(LoneModifierKey.allCases.map(\.keyCode), [61, 54, 60, 62])
        for key in LoneModifierKey.allCases {
            XCTAssertEqual(LoneModifierKey(keyCode: key.keyCode), key, key.rawValue)
        }
    }

    /// The left-hand keys (⌘ 55, ⇧ 56, ⌥ 58, ⌃ 59), caps lock (57) and fn
    /// (63) are no lone key.
    func testLeftHandKeysCapsLockAndFnAreNone() {
        for keyCode: UInt16 in [55, 56, 57, 58, 59, 63] {
            XCTAssertNil(LoneModifierKey(keyCode: keyCode), "\(keyCode)")
        }
    }

    /// NX_DEVICERALTKEYMASK and its siblings: the bit only the right-hand
    /// key sets, next to the flag both keys of the pair share.
    func testEachKeyHasItsOwnDeviceBitAndSharedFlag() {
        XCTAssertEqual(LoneModifierKey.allCases.map(\.deviceFlag), [0x40, 0x10, 0x04, 0x2000])
        XCTAssertEqual(LoneModifierKey.allCases.map(\.modifierFlag),
                       [.option, .command, .shift, .control])
    }

    /// What the Settings field shows once the key is recorded.
    func testTheNamesShownInSettings() {
        AppSettings.language = .french
        XCTAssertEqual(LoneModifierKey.allCases.map(\.title),
                       ["⌥ droite", "⌘ droite", "⇧ droite", "⌃ droite"])
        AppSettings.language = .english
        XCTAssertEqual(LoneModifierKey.allCases.map(\.title),
                       ["Right ⌥", "Right ⌘", "Right ⇧", "Right ⌃"])
    }
}
