import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    // ⌃⌥C par défaut, reconfigurable dans les Réglages.
    static let correctSelection = Self(
        "correctSelection",
        initial: .init(.c, modifiers: [.control, .option])
    )
}

@MainActor
enum HotkeySetup {
    static func install(coordinator: CorrectionCoordinator) {
        KeyboardShortcuts.onKeyUp(for: .correctSelection) { [weak coordinator] in
            coordinator?.trigger()
        }
    }
}
