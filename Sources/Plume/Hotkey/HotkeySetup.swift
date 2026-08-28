import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    // Défauts ⌃⌥C / ⌃⌥P / ⌃⌥S, reconfigurables dans les Réglages.
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
}

@MainActor
enum HotkeySetup {
    static func install(coordinator: CorrectionCoordinator) {
        KeyboardShortcuts.onKeyUp(for: .correctSelection) { [weak coordinator] in
            coordinator?.trigger(action: .correct)
        }
        KeyboardShortcuts.onKeyUp(for: .structurePrompt) { [weak coordinator] in
            coordinator?.trigger(action: .makePrompt)
        }
        KeyboardShortcuts.onKeyUp(for: .expertPrompt) { [weak coordinator] in
            coordinator?.trigger(action: .expertPrompt)
        }
    }
}
