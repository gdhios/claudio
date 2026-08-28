import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let coordinator = CorrectionCoordinator()
    private let settingsController = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.openSettings = { [weak self] in self?.settingsController.show() }
        setupMainMenu()
        setupStatusItem()
        HotkeySetup.install(coordinator: coordinator)

        // Premier lancement sans clé : ouvrir directement les Réglages.
        if KeychainStore.currentAPIKey() == nil {
            settingsController.show()
        }
    }

    /// Menu principal invisible (app .accessory) : sans menu Édition,
    /// macOS ne route pas ⌘X/⌘C/⌘V/⌘A vers les champs de texte.
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quitter Plume", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Édition")
        editMenu.addItem(NSMenuItem(title: "Annuler", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Rétablir", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Couper", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copier", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Coller", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Tout sélectionner", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: "Plume")

        let menu = NSMenu()
        for action in PlumeAction.allCases {
            let item = NSMenuItem(title: action.menuTitle, action: #selector(actionFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action.rawValue
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Réglages…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quitter Plume", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
    }

    @objc private func actionFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let action = PlumeAction(rawValue: raw) else { return }
        triggerFromMenu(action)
    }

    private func triggerFromMenu(_ action: PlumeAction) {
        // Laisse le menu se refermer et l'app précédente reprendre le focus.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            coordinator.trigger(action: action)
        }
    }

    @objc private func openSettings() {
        settingsController.show()
    }
}
