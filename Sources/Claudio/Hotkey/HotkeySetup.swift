import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// The shortcut as currently set, for display; empty when cleared.
    @MainActor
    var shortcutDescription: String {
        KeyboardShortcuts.getShortcut(for: self)?.description ?? ""
    }
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
    var shortcutDescription: String { shortcutName.shortcutDescription }
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
    static var freeShortcutDescription: String { KeyboardShortcuts.Name.freeAction.shortcutDescription }
}

extension ListeningSession {
    /// Same for "What's playing?", which isn't one either.
    @MainActor
    static var shortcutDescription: String { KeyboardShortcuts.Name.whatsPlaying.shortcutDescription }
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

    /// "What's playing?", on the key coming up like the actions: it drives
    /// its own coordinator, since it has no selection to capture.
    static func installListening(coordinator: ListeningCoordinator) {
        KeyboardShortcuts.onKeyUp(for: .whatsPlaying) { [weak coordinator] in
            coordinator?.trigger()
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
        // Apply the stored on/off state, as the window shortcuts do above:
        // the handlers are live by default, so dictation turned off in a
        // past session must be unregistered now.
        setDictationEnabled(AppSettings.dictationEnabled())
    }

    /// Registers or unregisters the two dictation shortcuts as a group and
    /// persists the choice. Disabling truly releases the keys, so another
    /// tool can take them back. The lone-key monitor is left in place: it
    /// only watches events and consumes none, so unhooking it would free
    /// nothing — what stops it dictating is the coordinator, which refuses
    /// every press while the switch is off.
    static func setDictationEnabled(_ enabled: Bool) {
        AppSettings.setDictationEnabled(enabled)
        setRegistered(DictationShortcut.allCases.map(\.name), enabled)
    }

    /// Registers or unregisters the window shortcuts as a group and persists
    /// the choice. Disabling truly releases the keys, so another tool can take
    /// them back; enabling re-registers them with their configured shortcut.
    static func setWindowShortcutsEnabled(_ enabled: Bool) {
        AppSettings.windowShortcutsEnabled = enabled
        setRegistered(windowShortcutNames, enabled)
    }

    private static func setRegistered(_ names: [KeyboardShortcuts.Name], _ registered: Bool) {
        if registered {
            KeyboardShortcuts.enable(names)
        } else {
            KeyboardShortcuts.disable(names)
        }
    }
}
