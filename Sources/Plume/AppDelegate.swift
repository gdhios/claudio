import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let coordinator = CorrectionCoordinator()
    private let settingsController = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.openSettings = { [weak self] in self?.settingsController.show() }
        setupStatusItem()
        HotkeySetup.install(coordinator: coordinator)

        // Premier lancement sans clé : ouvrir directement les Réglages.
        if KeychainStore.currentAPIKey() == nil {
            settingsController.show()
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: "Plume")

        let menu = NSMenu()
        let correct = NSMenuItem(title: "Corriger la sélection", action: #selector(correctFromMenu), keyEquivalent: "")
        correct.target = self
        menu.addItem(correct)

        let settings = NSMenuItem(title: "Réglages…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quitter Plume", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
    }

    @objc private func correctFromMenu() {
        // Laisse le menu se refermer et l'app précédente reprendre le focus.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            coordinator.trigger()
        }
    }

    @objc private func openSettings() {
        settingsController.show()
    }
}
