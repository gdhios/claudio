import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    // Défauts ⌃⌥ + lettre mnémotechnique, reconfigurables dans les Réglages.
    static let correctSelection = Self(
        "correctSelection",
        initial: .init(.c, modifiers: [.control, .option])
    )
    static let structurePrompt = Self(
        "structurePrompt",
        initial: .init(.p, modifiers: [.control, .option])
    )
    static let expertPrompt = Self(
        "expertPrompt",
        initial: .init(.s, modifiers: [.control, .option])
    )
    static let translateFrench = Self(
        "translateFrench",
        initial: .init(.f, modifiers: [.control, .option])
    )
    static let translateEnglish = Self(
        "translateEnglish",
        initial: .init(.e, modifiers: [.control, .option])
    )
    static let professionalTone = Self(
        "professionalTone",
        initial: .init(.t, modifiers: [.control, .option])
    )
    static let summarizeSelection = Self(
        "summarizeSelection",
        initial: .init(.r, modifiers: [.control, .option])
    )
}

extension PlumeAction {
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
        }
    }
}

@MainActor
enum HotkeySetup {
    static func install(coordinator: CorrectionCoordinator) {
        for action in PlumeAction.allCases {
            KeyboardShortcuts.onKeyUp(for: action.shortcutName) { [weak coordinator] in
                coordinator?.trigger(action: action)
            }
        }
    }
}
