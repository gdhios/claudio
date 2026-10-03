import KeyboardShortcuts

// The names are the library's storage keys: never renamed.
extension KeyboardShortcuts.Name {
    // Defaults ⌃⌥⌘ + a mnemonic key, reconfigurable in Settings.
    // ⌃⌥⌘ avoids collisions with the ⌃⌥ shortcuts of common apps.
    static let correctSelection = Self(
        "correctSelection",
        initial: .init(.i, modifiers: [.control, .option, .command])
    )
    static let structurePrompt = Self(
        "structurePrompt",
        initial: .init(.p, modifiers: [.control, .option, .command])
    )
    static let expertPrompt = Self(
        "expertPrompt",
        initial: .init(.leftBracket, modifiers: [.control, .option, .command])
    )
    static let translateFrench = Self(
        "translateFrench",
        initial: .init(.f, modifiers: [.control, .option, .command])
    )
    static let translateEnglish = Self(
        "translateEnglish",
        initial: .init(.e, modifiers: [.control, .option, .command])
    )
    static let professionalTone = Self(
        "professionalTone",
        initial: .init(.t, modifiers: [.control, .option, .command])
    )
    static let summarizeSelection = Self(
        "summarizeSelection",
        initial: .init(.r, modifiers: [.control, .option, .command])
    )
    static let simplifyExplanation = Self(
        "simplifyExplanation",
        initial: .init(.l, modifiers: [.control, .option, .command])
    )
    /// Free action: D as in "demande" (request). Carbon registers shortcuts
    /// by physical position, and D sits at the same one on AZERTY as on
    /// QWERTY (unlike A, Z and M): the key pressed really is the one shown.
    static let freeAction = Self(
        "freeAction",
        initial: .init(.d, modifiers: [.control, .option, .command])
    )
    /// Action palette: K as in "kommande" (command), and above all a key at
    /// the same physical position on AZERTY and QWERTY, like D above.
    static let actionPalette = Self(
        "actionPalette",
        initial: .init(.k, modifiers: [.control, .option, .command])
    )
    /// "What's playing?": S as in "son" (sound), in the actions' family, on
    /// a letter none of them takes and at the same physical position on
    /// AZERTY and QWERTY. The name is a storage key: it stays.
    static let whatsPlaying = Self(
        "whatsPlaying",
        initial: .init(.s, modifiers: [.control, .option, .command])
    )

    /// Dictation, held down: the space bar, the one key a thumb finds without
    /// looking — which is what a push-to-talk shortcut is. It also keeps the
    /// same physical position on every layout, unlike a letter: Carbon binds
    /// by position, and M (the mnemonic for "micro") is labelled "," on
    /// AZERTY. Settings shows the key really bound and it is reconfigurable
    /// there.
    static let dictate = Self(
        "dictate",
        initial: .init(.space, modifiers: [.control, .option, .command])
    )
    /// Same gesture in the other language. No default: a second dictation
    /// shortcut is worth a key only to whoever actually speaks two languages,
    /// and they pick it themselves in Settings.
    static let dictateOtherLanguage = Self("dictateOtherLanguage")

    // Window snapping, all on ⌃⌥⌘ so they don't collide with the actions
    // above (which use ⌃⌥⌘ + a letter). Arrows for halves, ↩ to maximize,
    // digits 7/9/1/3 for the four corners and 5 to center — the numeric-keypad
    // arrangement — and ⇟ to send the window to the next display. Digits,
    // arrows and ⇟ keep the same physical position on AZERTY and QWERTY, so
    // the key pressed is the one shown.
    static let windowLeftHalf = Self(
        "windowLeftHalf",
        initial: .init(.leftArrow, modifiers: [.control, .option, .command])
    )
    static let windowRightHalf = Self(
        "windowRightHalf",
        initial: .init(.rightArrow, modifiers: [.control, .option, .command])
    )
    static let windowTopHalf = Self(
        "windowTopHalf",
        initial: .init(.upArrow, modifiers: [.control, .option, .command])
    )
    static let windowBottomHalf = Self(
        "windowBottomHalf",
        initial: .init(.downArrow, modifiers: [.control, .option, .command])
    )
    static let windowTopLeft = Self(
        "windowTopLeft",
        initial: .init(.seven, modifiers: [.control, .option, .command])
    )
    static let windowTopRight = Self(
        "windowTopRight",
        initial: .init(.nine, modifiers: [.control, .option, .command])
    )
    static let windowBottomLeft = Self(
        "windowBottomLeft",
        initial: .init(.one, modifiers: [.control, .option, .command])
    )
    static let windowBottomRight = Self(
        "windowBottomRight",
        initial: .init(.three, modifiers: [.control, .option, .command])
    )
    static let windowMaximize = Self(
        "windowMaximize",
        initial: .init(.return, modifiers: [.control, .option, .command])
    )
    static let windowCenter = Self(
        "windowCenter",
        initial: .init(.five, modifiers: [.control, .option, .command])
    )

    /// Not a layout: moves the window to the next display, keeping its
    /// placement. ⇟ sits right next to the arrows on a full keyboard, and is
    /// fn + ↓ on a MacBook, which has no such key.
    static let windowNextScreen = Self(
        "windowNextScreen",
        initial: .init(.pageDown, modifiers: [.control, .option, .command])
    )

    // The numeric keypad sends different key codes from the top-row digits,
    // so the corner and center shortcuts above miss it. These fixed duplicates
    // on ⌃⌥⌘ + keypad 7/9/1/3/5 trigger the same layouts. They aren't shown in
    // Settings and follow the same on/off master switch as the rest.
    static let windowTopLeftKeypad = Self(
        "windowTopLeftKeypad",
        initial: .init(.keypad7, modifiers: [.control, .option, .command])
    )
    static let windowTopRightKeypad = Self(
        "windowTopRightKeypad",
        initial: .init(.keypad9, modifiers: [.control, .option, .command])
    )
    static let windowBottomLeftKeypad = Self(
        "windowBottomLeftKeypad",
        initial: .init(.keypad1, modifiers: [.control, .option, .command])
    )
    static let windowBottomRightKeypad = Self(
        "windowBottomRightKeypad",
        initial: .init(.keypad3, modifiers: [.control, .option, .command])
    )
    static let windowCenterKeypad = Self(
        "windowCenterKeypad",
        initial: .init(.keypad5, modifiers: [.control, .option, .command])
    )
}
