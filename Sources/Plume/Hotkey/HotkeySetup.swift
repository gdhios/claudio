import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    // Défauts ⌃⌥C / ⌃⌥P, reconfigurables dans les Réglages.
    static let correctSelection = Self(
        "correctSelection",
        initial: .init(.c, modifiers: [.control, .option])
    )
    static let structurePrompt = Self(
        "structurePrompt",
        initial: .init(.p, modifiers: [.control, .option])
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
    }
}
