import AppKit
@testable import Claudio

/// The modifier keys of a real keyboard, both hands, with what macOS reports
/// for each in a flagsChanged event: its key code, the flag the pair shares,
/// and the device-dependent bit only this key sets.
enum PhysicalModifier: CaseIterable {
    case leftControl, leftShift, rightShift, leftCommand, rightCommand
    case leftOption, rightOption, rightControl, function

    var keyCode: UInt16 {
        switch self {
        case .leftControl: 59
        case .leftShift: 56
        case .rightShift: 60
        case .leftCommand: 55
        case .rightCommand: 54
        case .leftOption: 58
        case .rightOption: 61
        case .rightControl: 62
        case .function: 63
        }
    }

    /// NSEvent.ModifierFlags, then NX_DEVICE…KEYMASK from IOLLEvent.h. fn has
    /// no device bit of its own.
    var flags: UInt {
        switch self {
        case .leftControl: NSEvent.ModifierFlags.control.rawValue | 0x01
        case .leftShift: NSEvent.ModifierFlags.shift.rawValue | 0x02
        case .rightShift: NSEvent.ModifierFlags.shift.rawValue | 0x04
        case .leftCommand: NSEvent.ModifierFlags.command.rawValue | 0x08
        case .rightCommand: NSEvent.ModifierFlags.command.rawValue | 0x10
        case .leftOption: NSEvent.ModifierFlags.option.rawValue | 0x20
        case .rightOption: NSEvent.ModifierFlags.option.rawValue | 0x40
        case .rightControl: NSEvent.ModifierFlags.control.rawValue | 0x2000
        case .function: NSEvent.ModifierFlags.function.rawValue
        }
    }
}

/// Holds modifier keys down and lets them go, and says what macOS would
/// report after each change: the key that changed, and every flag then set.
struct FakeModifierKeyboard {
    /// Set on every real event (NX_NONCOALSESCEDMASK), plus whatever noise a
    /// test adds: caps lock on, the numeric-pad flag.
    var background: UInt = 0x100
    private(set) var held: [PhysicalModifier] = []

    var flags: UInt { held.reduce(background) { $0 | $1.flags } }

    mutating func down(_ key: PhysicalModifier) -> (keyCode: UInt16, flags: UInt) {
        held.append(key)
        return (key.keyCode, flags)
    }

    mutating func up(_ key: PhysicalModifier) -> (keyCode: UInt16, flags: UInt) {
        held.removeAll { $0 == key }
        return (key.keyCode, flags)
    }
}
