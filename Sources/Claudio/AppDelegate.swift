import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private let updateMenuItemTag = 777
    private let coordinator = CorrectionCoordinator()
    private let settingsController = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.openSettings = { [weak self] in self?.settingsController.show() }
        setupMainMenu()
        setupStatusItem()
        HotkeySetup.install(coordinator: coordinator)

        UpdateChecker.shared.onUpdateFound = { [weak self] feed in
            self?.showUpdateMenuItem(feed)
        }
        UpdateChecker.shared.startPeriodicChecks()

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
        appMenu.addItem(NSMenuItem(title: "Quitter Claudio", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
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
        item.button?.image = NSImage(systemSymbolName: "mustache.fill", accessibilityDescription: "Claudio")

        let menu = NSMenu()

        // En tête : la porte d'entrée unique, qui contient toutes les autres.
        let palette = NSMenuItem(title: PaletteCatalog.menuTitle,
                                 action: #selector(paletteFromMenu), keyEquivalent: "")
        palette.target = self
        menu.addItem(palette)
        menu.addItem(.separator())

        for action in ClaudioAction.allCases {
            let item = NSMenuItem(title: action.menuTitle, action: #selector(actionFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action.rawValue
            menu.addItem(item)
        }

        let free = NSMenuItem(title: ClaudioRequest.freeMenuTitle,
                              action: #selector(freeActionFromMenu), keyEquivalent: "")
        free.target = self
        menu.addItem(free)
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Réglages…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quitter Claudio", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
        statusMenu = menu
    }

    /// Item « Mise à jour X disponible… » en tête du menu status.
    private func showUpdateMenuItem(_ feed: UpdateChecker.Feed) {
        guard let menu = statusMenu else { return }
        if let existing = menu.item(withTag: updateMenuItemTag) {
            existing.title = "Mise à jour \(feed.version) disponible…"
            existing.representedObject = feed.url
            return
        }
        let item = NSMenuItem(title: "Mise à jour \(feed.version) disponible…",
                              action: #selector(installUpdate(_:)), keyEquivalent: "")
        item.target = self
        item.tag = updateMenuItemTag
        item.representedObject = feed.url
        menu.insertItem(item, at: 0)
        menu.insertItem(.separator(), at: 1)
    }

    /// Installe la mise à jour à la place de l'app puis relance, après accord
    /// explicite : remplacer l'app installée n'est pas anodin.
    @objc private func installUpdate(_ sender: NSMenuItem) {
        guard let feed = UpdateChecker.shared.availableUpdate else { return }

        let confirm = NSAlert()
        confirm.messageText = "Installer Claudio \(feed.version) ?"
        confirm.informativeText = "Claudio télécharge la nouvelle version, remplace l'app installée, puis redémarre."
        confirm.addButton(withTitle: "Installer et redémarrer")
        confirm.addButton(withTitle: "Annuler")
        NSApp.activate(ignoringOtherApps: true)
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        let title = sender.title
        sender.title = "Téléchargement de la mise à jour…"
        sender.isEnabled = false
        Task { @MainActor in
            do {
                let newApp = try await UpdateInstaller.prepare(from: feed.url)
                try UpdateInstaller.installAndRelaunch(newApp)
            } catch {
                sender.title = title
                sender.isEnabled = true
                let failed = NSAlert()
                failed.messageText = "Mise à jour impossible"
                failed.informativeText = error.localizedDescription
                failed.addButton(withTitle: "OK")
                failed.addButton(withTitle: "Télécharger dans le navigateur")
                NSApp.activate(ignoringOtherApps: true)
                if failed.runModal() == .alertSecondButtonReturn {
                    NSWorkspace.shared.open(feed.url)
                }
            }
        }
    }

    @objc private func actionFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let action = ClaudioAction(rawValue: raw) else { return }
        afterMenuCloses { $0.trigger(action: action) }
    }

    @objc private func freeActionFromMenu() {
        afterMenuCloses { $0.triggerFreeAction() }
    }

    @objc private func paletteFromMenu() {
        afterMenuCloses { $0.triggerPalette() }
    }

    /// Laisse le menu se refermer et l'app précédente reprendre le focus avant
    /// de déclencher : la capture de sélection vise l'app source, pas Claudio.
    private func afterMenuCloses(_ trigger: @escaping @MainActor (CorrectionCoordinator) -> Void) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self else { return }
            trigger(self.coordinator)
        }
    }

    @objc private func openSettings() {
        settingsController.show()
    }
}
