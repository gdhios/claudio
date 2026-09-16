import AppKit
import XCTest
@testable import Claudio

/// A modifier key held alone as a dictation shortcut, told apart from the
/// same key starting a combination: on AZERTY, ⌥⇧L types "|" and ⌥( types
/// "{". At stake both ways round: a dictation that never starts, or music
/// paused and a panel flashing for a character typed. The keyboard is
/// simulated, the arming delay runs out when the test says so, and what the
/// dictation is told is a list of intents.
@MainActor
final class LoneKeyGestureTests: XCTestCase {

    // MARK: - Held and tapped

    /// Held past the arming delay: the dictation starts when the delay runs
    /// out, and finishes on the release.
    func testALonePressHeldPastTheDelayListensUntilReleased() {
        let bench = Bench()
        bench.press(.rightOption)
        XCTAssertEqual(bench.intents, [])
        XCTAssertEqual(bench.delays, [0.15])

        bench.waitOutTheDelay()
        XCTAssertEqual(bench.intents, [.press(.rightOption)])

        bench.release(.rightOption)
        XCTAssertEqual(bench.intents, [.press(.rightOption), .release])
    }

    /// Released within the delay, nothing else pressed: a tap. Press and
    /// release go out together, which the coordinator reads as hands-free.
    func testATapWithinTheDelayPressesAndReleasesAtOnce() {
        let bench = Bench()
        bench.press(.rightOption)
        bench.release(.rightOption)
        XCTAssertEqual(bench.intents, [.press(.rightOption), .release])

        // The delay belonged to that press: running out now starts nothing.
        bench.waitOutTheDelay()
        XCTAssertEqual(bench.intents, [.press(.rightOption), .release])
    }

    /// Hands-free, the key is up: what is typed or clicked next is typing,
    /// not a combination, and cancels nothing.
    func testAfterATapKeysAndClicksCancelNothing() {
        let bench = Bench()
        bench.press(.rightOption)
        bench.release(.rightOption)

        bench.typeAKey()
        bench.click()
        bench.press(.leftShift)
        bench.release(.leftShift)
        XCTAssertEqual(bench.intents, [.press(.rightOption), .release])
    }

    /// Every right-hand modifier works alone, and says which one it was.
    func testEachRightHandModifierWorksAlone() {
        let pairs: [(PhysicalModifier, LoneModifierKey)] = [
            (.rightOption, .rightOption), (.rightCommand, .rightCommand),
            (.rightShift, .rightShift), (.rightControl, .rightControl),
        ]
        for (physical, key) in pairs {
            let bench = Bench(keys: Set(LoneModifierKey.allCases))
            bench.press(physical)
            bench.waitOutTheDelay()
            bench.release(physical)
            XCTAssertEqual(bench.intents, [.press(key), .release], key.rawValue)
        }
    }

    // MARK: - Combinations

    /// ⌥( : the key comes within the delay. Nothing at all goes out — no
    /// press, so no panel, no microphone, and the music untouched.
    func testAKeyWithinTheDelayDropsThePressSilently() {
        let bench = Bench()
        bench.press(.rightOption)
        bench.typeAKey()
        bench.waitOutTheDelay()
        bench.release(.rightOption)
        XCTAssertEqual(bench.intents, [])
    }

    /// ⌥⇧L: another modifier joins within the delay, then the letter.
    func testAnotherModifierWithinTheDelayDropsThePressSilently() {
        let bench = Bench()
        bench.press(.rightOption)
        bench.press(.leftShift)
        bench.typeAKey()
        bench.waitOutTheDelay()
        bench.release(.leftShift)
        bench.release(.rightOption)
        XCTAssertEqual(bench.intents, [])
    }

    /// ⌥-click, within the delay.
    func testAClickWithinTheDelayDropsThePressSilently() {
        let bench = Bench()
        bench.press(.rightOption)
        bench.click()
        bench.waitOutTheDelay()
        bench.release(.rightOption)
        XCTAssertEqual(bench.intents, [])
    }

    /// A key after the delay: the dictation had started, so it is cancelled
    /// — once, however many keys follow — and the release that comes after
    /// must not paste anything.
    func testAKeyAfterTheDelayCancelsAndTheReleaseIsIgnored() {
        let bench = Bench()
        bench.press(.rightOption)
        bench.waitOutTheDelay()
        bench.typeAKey()
        bench.typeAKey()
        XCTAssertEqual(bench.intents, [.press(.rightOption), .cancel])

        bench.release(.rightOption)
        XCTAssertEqual(bench.intents, [.press(.rightOption), .cancel])
    }

    /// ⌥⇧L typed slowly: ⇧ joins after the delay.
    func testAnotherModifierAfterTheDelayCancels() {
        let bench = Bench()
        bench.press(.rightOption)
        bench.waitOutTheDelay()
        bench.press(.leftShift)
        bench.typeAKey()
        bench.release(.leftShift)
        bench.release(.rightOption)
        XCTAssertEqual(bench.intents, [.press(.rightOption), .cancel])
    }

    func testAClickAfterTheDelayCancels() {
        let bench = Bench()
        bench.press(.rightOption)
        bench.waitOutTheDelay()
        bench.click()
        bench.release(.rightOption)
        XCTAssertEqual(bench.intents, [.press(.rightOption), .cancel])
    }

    /// Whatever ended the last press, the next lone one is a press again.
    func testAPressAfterACancelWorksAgain() {
        let bench = Bench()
        bench.press(.rightOption)
        bench.typeAKey()
        bench.release(.rightOption)

        bench.press(.rightOption)
        bench.waitOutTheDelay()
        bench.release(.rightOption)
        XCTAssertEqual(bench.intents, [.press(.rightOption), .release])
    }

    // MARK: - Which key, which side

    /// Left ⌥ is in every everyday shortcut: alone, it does nothing, and
    /// isn't even waited on.
    func testLeftOptionAloneDoesNothing() {
        let bench = Bench()
        bench.press(.leftOption)
        XCTAssertEqual(bench.delays, [])
        bench.waitOutTheDelay()
        bench.release(.leftOption)
        XCTAssertEqual(bench.intents, [])
    }

    /// ⇧ already down when right ⌥ goes down: a combination from the start.
    func testRightOptionWhileShiftIsAlreadyHeldDoesNothing() {
        let bench = Bench()
        bench.press(.leftShift)
        bench.press(.rightOption)
        XCTAssertEqual(bench.delays, [])
        bench.waitOutTheDelay()
        bench.release(.rightOption)
        bench.release(.leftShift)
        XCTAssertEqual(bench.intents, [])
    }

    /// Both ⌥ down: `.option` stays set while right ⌥ comes up. Its release is
    /// read from its own bit, so nothing is left believing it still held,
    /// and the next lone press works.
    func testBothOptionsHeldThenRightReleased() {
        let bench = Bench()
        bench.press(.leftOption)
        bench.press(.rightOption)
        bench.release(.rightOption)
        bench.release(.leftOption)
        XCTAssertEqual(bench.intents, [])

        bench.press(.rightOption)
        bench.waitOutTheDelay()
        bench.release(.rightOption)
        XCTAssertEqual(bench.intents, [.press(.rightOption), .release])
    }

    /// The other way round: right ⌥ held alone, left ⌥ joins — a cancel —
    /// and right ⌥ comes up first, `.option` still set. No second intent,
    /// and the next lone press is a press again.
    func testRightOptionReleasedWhileLeftIsStillHeld() {
        let bench = Bench()
        bench.press(.rightOption)
        bench.waitOutTheDelay()
        bench.press(.leftOption)
        bench.release(.rightOption)
        bench.release(.leftOption)
        XCTAssertEqual(bench.intents, [.press(.rightOption), .cancel])

        bench.press(.rightOption)
        bench.release(.rightOption)
        XCTAssertEqual(bench.intents, [.press(.rightOption), .cancel, .press(.rightOption), .release])
    }

    /// Only the key a shortcut is set to counts.
    func testAKeyNoShortcutIsSetToDoesNothing() {
        let bench = Bench(keys: [.rightOption])
        bench.press(.rightCommand)
        bench.waitOutTheDelay()
        bench.release(.rightCommand)
        XCTAssertEqual(bench.delays, [])
        XCTAssertEqual(bench.intents, [])
    }

    /// Caps lock on, fn held, the numeric-pad flag: noise, which spoils
    /// neither the press nor its release.
    func testCapsLockFnAndTheNumericPadFlagSpoilNothing() {
        let bench = Bench()
        bench.keyboard.background |= NSEvent.ModifierFlags([.capsLock, .numericPad]).rawValue
        bench.press(.function)
        bench.press(.rightOption)
        bench.waitOutTheDelay()
        bench.release(.rightOption)
        XCTAssertEqual(bench.intents, [.press(.rightOption), .release])
    }

    /// `.option` without right ⌥'s own bit says nothing about which side is
    /// down, so it is no right ⌥.
    func testTheSharedFlagWithoutTheDeviceBitIsNoPress() {
        let bench = Bench()
        bench.gesture.handle(.modifiersChanged(keyCode: 61,
                                               flags: NSEvent.ModifierFlags.option.rawValue))
        XCTAssertEqual(bench.delays, [])
        XCTAssertEqual(bench.intents, [])
    }

    // MARK: - When the key is not listened to at all

    /// Without Accessibility, keys typed in other apps never reach Claudio:
    /// every combination would look like a lone press.
    func testNothingWithoutAccessibility() {
        let bench = Bench()
        bench.trusted = false
        bench.pressHoldAndRelease(.rightOption)
        XCTAssertEqual(bench.delays, [])
        XCTAssertEqual(bench.intents, [])
    }

    /// A password field hides the keystrokes the same way.
    func testNothingUnderSecureInput() {
        let bench = Bench()
        bench.secureInput = true
        bench.pressHoldAndRelease(.rightOption)
        XCTAssertEqual(bench.delays, [])
        XCTAssertEqual(bench.intents, [])
    }

    /// Recording a shortcut in Settings: the key is being recorded, not used.
    func testNothingWhileAShortcutIsBeingRecorded() {
        let bench = Bench()
        bench.recording = true
        bench.pressHoldAndRelease(.rightOption)
        XCTAssertEqual(bench.delays, [])
        XCTAssertEqual(bench.intents, [])
    }

    /// The guards are read for each press: once lifted, the key works.
    func testTheGuardsAreReadOnEachPress() {
        let bench = Bench()
        bench.secureInput = true
        bench.pressHoldAndRelease(.rightOption)
        bench.secureInput = false
        bench.pressHoldAndRelease(.rightOption)
        XCTAssertEqual(bench.intents, [.press(.rightOption), .release])
    }
}

// MARK: - The bench

/// One gesture, a simulated keyboard to drive it, and everything it asked
/// for: the delays it scheduled, and the intents it sent.
@MainActor
private final class Bench {
    var trusted = true
    var secureInput = false
    var recording = false
    var keyboard = FakeModifierKeyboard()

    private(set) var intents: [LoneKeyGesture.Intent] = []
    /// Every delay asked for, in seconds, cancelled or not.
    private(set) var delays: [TimeInterval] = []
    /// The work still scheduled: cancelling removes it, so running out the
    /// delay only runs what the gesture still wants.
    private var pending: [Int: @MainActor () -> Void] = [:]
    private var nextID = 0

    private(set) var gesture: LoneKeyGesture!

    init(keys: Set<LoneModifierKey> = [.rightOption]) {
        gesture = LoneKeyGesture(
            keys: keys,
            guards: LoneKeyGesture.Guards(
                isTrusted: { [unowned self] in trusted },
                isSecureInputOn: { [unowned self] in secureInput },
                isRecordingShortcut: { [unowned self] in recording }
            ),
            schedule: { [unowned self] delay, work in
                delays.append(delay)
                let id = nextID
                nextID += 1
                pending[id] = work
                return { [weak self] in self?.pending[id] = nil }
            },
            emit: { [unowned self] intent in intents.append(intent) }
        )
    }

    func press(_ key: PhysicalModifier) {
        let event = keyboard.down(key)
        gesture.handle(.modifiersChanged(keyCode: event.keyCode, flags: event.flags))
    }

    func release(_ key: PhysicalModifier) {
        let event = keyboard.up(key)
        gesture.handle(.modifiersChanged(keyCode: event.keyCode, flags: event.flags))
    }

    func typeAKey() { gesture.handle(.keyDown) }

    func click() { gesture.handle(.mouseDown) }

    /// The arming delay runs out: whatever is still scheduled runs.
    func waitOutTheDelay() {
        let due = pending.sorted { $0.key < $1.key }.map(\.value)
        pending = [:]
        for work in due { work() }
    }

    func pressHoldAndRelease(_ key: PhysicalModifier) {
        press(key)
        waitOutTheDelay()
        release(key)
    }
}
