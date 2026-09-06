import CoreGraphics

enum Keystroke {
    // Physical keycodes: same positions on QWERTY and AZERTY
    // (known limitation: Dvorak/Bépo).
    static let keyC: CGKeyCode = 0x08   // kVK_ANSI_C
    static let keyV: CGKeyCode = 0x09   // kVK_ANSI_V

    static func simulate(virtualKey: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
