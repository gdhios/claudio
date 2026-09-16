import AppKit
import XCTest
@testable import Claudio

/// Recording a lone key in the Settings field: a modifier pressed and
/// released with nothing else in between. A right-hand one becomes the
/// shortcut; a left-hand one or fn is refused with a beep, like a combination
/// the recorder can't use. At stake: a combination being typed into the
/// field must never be stored as the lone key it started with.
final class LoneKeyRecordingTests: XCTestCase {

    private var keyboard = FakeModifierKeyboard()
    private var recording = LoneKeyRecording()

    func testARightHandModifierPressedAndReleasedAloneIsRecorded() {
        let pairs: [(PhysicalModifier, LoneModifierKey)] = [
            (.rightOption, .rightOption), (.rightCommand, .rightCommand),
            (.rightShift, .rightShift), (.rightControl, .rightControl),
        ]
        for (physical, key) in pairs {
            XCTAssertNil(press(physical), key.rawValue)
            XCTAssertEqual(release(physical), .recorded(key), key.rawValue)
        }
    }

    /// Left-hand keys are in every everyday shortcut, and fn belongs to macOS.
    func testALeftHandModifierOrFnAloneIsRefused() {
        for physical: PhysicalModifier in [.leftOption, .leftCommand, .leftShift, .leftControl, .function] {
            XCTAssertNil(press(physical), "\(physical)")
            XCTAssertEqual(release(physical), .refused, "\(physical)")
        }
    }

    /// ⌥K: the recorder records the combination, and the ⌥ that follows it
    /// up is no lone key.
    func testAKeyInBetweenMakesItACombination() {
        _ = press(.rightOption)
        recording.keyDown()
        XCTAssertNil(release(.rightOption))
    }

    /// ⌥⇧, whichever comes up first.
    func testAnotherModifierInBetweenMakesItACombination() {
        _ = press(.rightOption)
        XCTAssertNil(press(.leftShift))
        XCTAssertNil(release(.leftShift))
        XCTAssertNil(release(.rightOption))

        _ = press(.rightOption)
        _ = press(.rightShift)
        XCTAssertNil(release(.rightOption))
        XCTAssertNil(release(.rightShift))
    }

    /// ⇧ already down: right ⌥ never went down alone.
    func testAModifierAlreadyHeldMakesItACombination() {
        _ = press(.leftShift)
        XCTAssertNil(press(.rightOption))
        XCTAssertNil(release(.rightOption))
        XCTAssertNil(release(.leftShift))
    }

    /// A combination abandoned leaves nothing behind: the next lone press
    /// records.
    func testAfterACombinationTheNextLonePressRecords() {
        _ = press(.rightOption)
        recording.keyDown()
        _ = release(.rightOption)

        _ = press(.rightOption)
        XCTAssertEqual(release(.rightOption), .recorded(.rightOption))
    }

    /// Caps lock toggles rather than being held: pressed, it records and
    /// refuses nothing; lit, it spoils nothing.
    func testCapsLockIsNeitherAKeyNorNoise() {
        let capsLock = NSEvent.ModifierFlags.capsLock.rawValue
        XCTAssertNil(recording.modifiersChanged(keyCode: 57, flags: capsLock | 0x100))

        keyboard.background |= capsLock
        _ = press(.rightCommand)
        XCTAssertEqual(release(.rightCommand), .recorded(.rightCommand))
    }

    private func press(_ key: PhysicalModifier) -> LoneKeyRecording.Outcome? {
        let event = keyboard.down(key)
        return recording.modifiersChanged(keyCode: event.keyCode, flags: event.flags)
    }

    private func release(_ key: PhysicalModifier) -> LoneKeyRecording.Outcome? {
        let event = keyboard.up(key)
        return recording.modifiersChanged(keyCode: event.keyCode, flags: event.flags)
    }
}
