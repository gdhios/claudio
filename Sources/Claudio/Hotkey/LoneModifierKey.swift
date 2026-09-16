import AppKit

/// A modifier key that is a dictation shortcut on its own — right ⌥ held
/// alone, as in Spokenly. Right-hand keys only: the left-hand ones are in
/// every everyday shortcut, and fn belongs to macOS.
///
/// A right-hand key is told from its left-hand twin by its key code and by
/// its own bit among the raw modifier flags, never by `.option` alone: that
/// flag stays set for as long as either ⌥ is down.
///
/// The rawValue is the storage key: add cases, never rename them.
enum LoneModifierKey: String, CaseIterable, Sendable {
    case rightOption
    case rightCommand
    case rightShift
    case rightControl

    /// The key code of its flagsChanged events (kVK_RightOption…).
    var keyCode: UInt16 {
        switch self {
        case .rightOption: 61
        case .rightCommand: 54
        case .rightShift: 60
        case .rightControl: 62
        }
    }

    /// The device-dependent bit only this key sets (NX_DEVICERALTKEYMASK…).
    var deviceFlag: UInt {
        switch self {
        case .rightOption: 0x40
        case .rightCommand: 0x10
        case .rightShift: 0x04
        case .rightControl: 0x2000
        }
    }

    /// The flag it shares with its left-hand twin.
    var modifierFlag: NSEvent.ModifierFlags {
        switch self {
        case .rightOption: .option
        case .rightCommand: .command
        case .rightShift: .shift
        case .rightControl: .control
        }
    }

    /// What the shortcut field in Settings shows.
    var title: String {
        switch self {
        case .rightOption: loc("⌥ droite", en: "Right ⌥")
        case .rightCommand: loc("⌘ droite", en: "Right ⌘")
        case .rightShift: loc("⇧ droite", en: "Right ⇧")
        case .rightControl: loc("⌃ droite", en: "Right ⌃")
        }
    }

    init?(keyCode: UInt16) {
        guard let key = Self.allCases.first(where: { $0.keyCode == keyCode }) else { return nil }
        self = key
    }

    // MARK: - Reading the raw flags

    /// Every left- and right-hand ⌃ ⇧ ⌘ ⌥ bit (NX_DEVICE…KEYMASK).
    private static let deviceModifiers: UInt = 0x207F
    /// The shared flags that make a combination. Caps lock, fn and the
    /// numeric pad are left out: noise arrow keys and a lit caps lock add.
    private static let combiningFlags = NSEvent.ModifierFlags([.shift, .control, .option, .command]).rawValue

    /// Whether this very key is down, whatever its twin does.
    func isDown(in flags: UInt) -> Bool {
        flags & deviceFlag != 0
    }

    /// Whether no key of its pair is down: the shared flag is gone too.
    func pairIsUp(in flags: UInt) -> Bool {
        flags & modifierFlag.rawValue == 0
    }

    /// Whether any other modifier is down: another key's own bit, or another
    /// pair's shared flag.
    func othersAreDown(in flags: UInt) -> Bool {
        flags & Self.deviceModifiers & ~deviceFlag != 0
            || flags & Self.combiningFlags & ~modifierFlag.rawValue != 0
    }
}
