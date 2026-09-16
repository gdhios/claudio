import KeyboardShortcuts

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

extension ClaudioAction {
    /// Global shortcut associated with the action.
    var shortcutName: KeyboardShortcuts.Name {
        switch self {
        case .correct: .correctSelection
        case .makePrompt: .structurePrompt
        case .expertPrompt: .expertPrompt
        case .translateFR: .translateFrench
        case .translateEN: .translateEnglish
        case .professionalTone: .professionalTone
        case .summarize: .summarizeSelection
        case .simplify: .simplifyExplanation
        }
    }

    /// Shortcut as currently configured, to display in the palette. Empty if
    /// the user cleared it: the row then launches on ⏎ or its digit, like
    /// the others.
    @MainActor
    var shortcutDescription: String {
        KeyboardShortcuts.getShortcut(for: shortcutName)?.description ?? ""
    }
}

extension DictationShortcut {
    /// Its key combination, when it isn't set to a lone key.
    var name: KeyboardShortcuts.Name {
        switch self {
        case .dictate: .dictate
        case .dictateOtherLanguage: .dictateOtherLanguage
        }
    }
}

extension ClaudioRequest {
    /// Same for the free action, which isn't a catalog entry.
    @MainActor
    static var freeShortcutDescription: String {
        KeyboardShortcuts.getShortcut(for: .freeAction)?.description ?? ""
    }
}

extension WindowLayout {
    /// Global shortcut that snaps the frontmost window to this layout.
    var shortcutName: KeyboardShortcuts.Name {
        switch self {
        case .leftHalf: .windowLeftHalf
        case .rightHalf: .windowRightHalf
        case .topHalf: .windowTopHalf
        case .bottomHalf: .windowBottomHalf
        case .topLeft: .windowTopLeft
        case .topRight: .windowTopRight
        case .bottomLeft: .windowBottomLeft
        case .bottomRight: .windowBottomRight
        case .maximize: .windowMaximize
        case .center: .windowCenter
        }
    }
}

@MainActor
enum HotkeySetup {
    /// Fixed numeric-keypad duplicates of the corner and center shortcuts. The
    /// keypad sends different key codes from the top-row digits, so these bind
    /// ⌃⌥⌘ + keypad keys to the same layouts. Not shown in Settings.
    private static let keypadLayouts: [(KeyboardShortcuts.Name, WindowLayout)] = [
        (.windowTopLeftKeypad, .topLeft),
        (.windowTopRightKeypad, .topRight),
        (.windowBottomLeftKeypad, .bottomLeft),
        (.windowBottomRightKeypad, .bottomRight),
        (.windowCenterKeypad, .center),
    ]

    /// Every window shortcut the master switch turns on or off: the ten
    /// layouts, the next-display one, and the fixed keypad duplicates.
    private static var windowShortcutNames: [KeyboardShortcuts.Name] {
        WindowLayout.allCases.map(\.shortcutName) + keypadLayouts.map(\.0) + [.windowNextScreen]
    }

    static func install(coordinator: CorrectionCoordinator) {
        for action in ClaudioAction.allCases {
            KeyboardShortcuts.onKeyUp(for: action.shortcutName) { [weak coordinator] in
                coordinator?.trigger(action: action)
            }
        }
        KeyboardShortcuts.onKeyUp(for: .actionPalette) { [weak coordinator] in
            coordinator?.triggerPalette()
        }
        for layout in WindowLayout.allCases {
            KeyboardShortcuts.onKeyUp(for: layout.shortcutName) {
                WindowMover.apply(layout)
            }
        }
        for (name, layout) in keypadLayouts {
            KeyboardShortcuts.onKeyUp(for: name) {
                WindowMover.apply(layout)
            }
        }
        KeyboardShortcuts.onKeyUp(for: .windowNextScreen) {
            WindowMover.moveToNextScreen()
        }
        // Apply the stored on/off state: the handlers above are live by
        // default, so a window feature turned off in a past session must be
        // unregistered now.
        setWindowShortcutsEnabled(AppSettings.windowShortcutsEnabled)
    }

    /// The free action, which acts on the key going down as well as coming
    /// up: tapped it opens the field where the instruction is typed, held it
    /// opens the microphone and the instruction is spoken. Only the
    /// coordinator can tell the two gestures apart, so both go to it.
    static func installFreeAction(coordinator: SpokenInstructionCoordinator) {
        KeyboardShortcuts.onKeyDown(for: .freeAction) { [weak coordinator] in
            coordinator?.keyDown()
        }
        KeyboardShortcuts.onKeyUp(for: .freeAction) { [weak coordinator] in
            coordinator?.keyUp()
        }
    }

    /// Listens for the dictation shortcuts set to a lone key. Kept for the
    /// life of the app, like the handlers the library keeps.
    private static var loneKeyMonitor: LoneKeyMonitor?

    /// Dictation: the other shortcuts that act on the key going down as well
    /// as coming up — pressed is "listen", released is "paste what I said".
    /// Installed apart from the actions above because it drives its own
    /// coordinator, and because the two shortcuts differ only by what they
    /// are set to: the language they listen in, and what they turn it into.
    /// Both are read on the press, never mid-dictation.
    static func installDictation(coordinator: DictationCoordinator) {
        for shortcut in DictationShortcut.allCases {
            KeyboardShortcuts.onKeyDown(for: shortcut.name) { [weak coordinator] in
                coordinator?.keyDown(language: shortcut.language, output: shortcut.output)
            }
            KeyboardShortcuts.onKeyUp(for: shortcut.name) { [weak coordinator] in
                coordinator?.keyUp()
            }
        }
        // The same two on a modifier key held alone, which the library can't
        // register: the key is watched instead, and only while one is set.
        loneKeyMonitor = LoneKeyMonitor(coordinator: coordinator)
    }

    /// Registers or unregisters the window shortcuts as a group and persists
    /// the choice. Disabling truly releases the keys, so another tool can take
    /// them back; enabling re-registers them with their configured shortcut.
    static func setWindowShortcutsEnabled(_ enabled: Bool) {
        AppSettings.windowShortcutsEnabled = enabled
        if enabled {
            KeyboardShortcuts.enable(windowShortcutNames)
        } else {
            KeyboardShortcuts.disable(windowShortcutNames)
        }
    }
}
