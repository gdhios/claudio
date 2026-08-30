import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    // Défauts ⌃⌥⌘ + touche mnémotechnique, reconfigurables dans les Réglages.
    // ⌃⌥⌘ évite les collisions avec les raccourcis ⌃⌥ des apps courantes.
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
    /// Action libre : D comme « demande ». Carbon enregistre les raccourcis par
    /// position physique, et D occupe la même sur AZERTY que sur QWERTY (au
    /// contraire de A, Z et M) : la touche pressée est bien celle affichée.
    static let freeAction = Self(
        "freeAction",
        initial: .init(.d, modifiers: [.control, .option, .command])
    )
    /// Palette d'actions : K comme « kommande », et surtout une touche à la
    /// même position physique sur AZERTY et sur QWERTY, comme D plus haut.
    static let actionPalette = Self(
        "actionPalette",
        initial: .init(.k, modifiers: [.control, .option, .command])
    )
}

extension ClaudioAction {
    /// Raccourci global associé à l'action.
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

    /// Raccourci tel qu'il est configuré, pour l'afficher dans la palette.
    /// Vide si l'utilisateur l'a effacé : la ligne se lance alors au ⏎ ou au
    /// chiffre, comme les autres.
    @MainActor
    var shortcutDescription: String {
        KeyboardShortcuts.getShortcut(for: shortcutName)?.description ?? ""
    }
}

extension ClaudioRequest {
    /// Idem pour l'action libre, qui n'est pas une entrée du catalogue.
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
