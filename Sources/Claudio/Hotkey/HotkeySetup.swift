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

extension ClaudioRequest {
    /// Same for the free action, which isn't a catalog entry.
    @MainActor
    static var freeShortcutDescription: String {
        KeyboardShortcuts.getShortcut(for: .freeAction)?.description ?? ""
    }
}

@MainActor
enum HotkeySetup {
    static func install(coordinator: CorrectionCoordinator) {
        for action in ClaudioAction.allCases {
            KeyboardShortcuts.onKeyUp(for: action.shortcutName) { [weak coordinator] in
                coordinator?.trigger(action: action)
            }
        }
        KeyboardShortcuts.onKeyUp(for: .freeAction) { [weak coordinator] in
            coordinator?.triggerFreeAction()
        }
        KeyboardShortcuts.onKeyUp(for: .actionPalette) { [weak coordinator] in
            coordinator?.triggerPalette()
        }
    }
}
