import AppKit

/// Recording a lone modifier key in a Settings field. Decided on the release
/// only: a modifier going down is also how every combination starts, so the
/// key has to go down with no other modifier and come back up with nothing
/// pressed in between.
struct LoneKeyRecording {
    enum Outcome: Equatable {
        /// A right-hand modifier: the shortcut is that key.
        case recorded(LoneModifierKey)
        /// A left-hand modifier or fn: refused with a beep, the way the
        /// recorder refuses a combination it can't use.
        case refused
    }

    /// Every modifier key held rather than toggled, by key code, with the bit
    /// that says it is down: its device-dependent bit, the fn flag for fn.
    /// Caps lock toggles, and is none of them.
    private static let downBits: [UInt16: UInt] = [
        59: 0x01, 56: 0x02, 60: 0x04, 55: 0x08, 54: 0x10, 58: 0x20, 61: 0x40, 62: 0x2000,
        63: NSEvent.ModifierFlags.function.rawValue,
    ]
    private static let anyDown = downBits.values.reduce(0, |)

    /// The key code of the modifier that went down alone, until anything
    /// else happens.
    private var pressed: UInt16?

    mutating func modifiersChanged(keyCode: UInt16, flags: UInt) -> Outcome? {
        let down = flags & Self.anyDown
        guard let pressed else {
            if let bit = Self.downBits[keyCode], down == bit { self.pressed = keyCode }
            return nil
        }
        self.pressed = nil
        // Anything but that same key coming up with every modifier up: part
        // of a combination.
        guard keyCode == pressed, down == 0 else { return nil }
        return LoneModifierKey(keyCode: keyCode).map(Outcome.recorded) ?? .refused
    }

    /// A key went down: whatever modifier is down is part of a combination.
    mutating func keyDown() {
        pressed = nil
    }
}
