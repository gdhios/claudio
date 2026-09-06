import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    /// The "Recent ▸" entry and its submenu: hidden while history is empty,
    /// repopulated on every open (recents change).
    private var recentsItem: NSMenuItem?
    private var recentsMenu: NSMenu?
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

        // First launch without a key: open Settings directly.
        if KeychainStore.currentAPIKey() == nil {
            settingsController.show()
        }
    }

    /// Invisible main menu (app .accessory): without an Edit menu, macOS
    /// doesn't route ⌘X/⌘C/⌘V/⌘A to text fields.
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: loc("Quitter Claudio", en: "Quit Claudio"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: loc("Édition", en: "Edit"))
        editMenu.addItem(NSMenuItem(title: loc("Annuler", en: "Undo"), action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: loc("Rétablir", en: "Redo"), action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: loc("Couper", en: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: loc("Copier", en: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: loc("Coller", en: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: loc("Tout sélectionner", en: "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    private func setupStatusItem() {
        // Claudio himself in the menu bar. Variable length: the bust is
        // wider than it is tall, a square would squash it.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = ClaudioMascot.menuBarImage()
        item.button?.setAccessibilityLabel("Claudio")

        let menu = NSMenu()

        // At the top: the single entry point, which contains all the others.
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

        // The custom instructions already launched, to relaunch with one
        // gesture on the current selection. Its content is rebuilt on open.
        let recentsMenu = NSMenu()
        recentsMenu.autoenablesItems = false
        recentsMenu.delegate = self
        let recentsItem = NSMenuItem(title: loc("Récentes", en: "Recent"),
                                     action: nil, keyEquivalent: "")
        recentsItem.submenu = recentsMenu
        menu.addItem(recentsItem)
        self.recentsMenu = recentsMenu
        self.recentsItem = recentsItem

        menu.addItem(.separator())

        let settings = NSMenuItem(title: loc("Réglages…", en: "Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: loc("Quitter Claudio", en: "Quit Claudio"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        menu.delegate = self
        item.menu = menu
        statusItem = item
        statusMenu = menu
    }

    // MARK: - History ("Recent")

    /// When the main menu opens, "Recent ▸" only appears if there's
    /// something to relaunch. When the submenu itself opens, it's
    /// repopulated: history may have changed since last time.
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === statusMenu {
            recentsItem?.isHidden = TransformHistory.shared.recents.entries.isEmpty
        } else if menu === recentsMenu {
            rebuildRecentsMenu(menu)
        }
    }

    private func rebuildRecentsMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        for entry in TransformHistory.shared.recents.entries {
            let item = NSMenuItem(title: AppDelegate.recentTitle(entry.instruction),
                                  action: #selector(recentFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = entry.instruction
            item.toolTip = entry.instruction  // the truncated label, in full on hover
            menu.addItem(item)
        }
        guard !menu.items.isEmpty else { return }
        menu.addItem(.separator())
        let clear = NSMenuItem(title: loc("Vider l'historique", en: "Clear history"),
                               action: #selector(clearRecents), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
    }

    /// The instruction for a menu row: on a single line, truncated so it
    /// doesn't stretch the menu.
    private static func recentTitle(_ instruction: String) -> String {
        let flat = instruction.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        let limit = 48
        guard flat.count > limit else { return flat }
        return String(flat.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    @objc private func recentFromMenu(_ sender: NSMenuItem) {
        guard let instruction = sender.representedObject as? String else { return }
        afterMenuCloses { $0.triggerRecent(instruction: instruction) }
    }

    @objc private func clearRecents() {
        TransformHistory.shared.clear()
    }

    private func updateMenuTitle(_ feed: UpdateChecker.Feed) -> String {
        loc("Mise à jour \(feed.version) disponible…", en: "Update \(feed.version) available…")
    }

    /// "Update X available…" item at the top of the status menu.
    private func showUpdateMenuItem(_ feed: UpdateChecker.Feed) {
        guard let menu = statusMenu else { return }
        if let existing = menu.item(withTag: updateMenuItemTag) {
            existing.title = updateMenuTitle(feed)
            existing.representedObject = feed.url
            return
        }
        let item = NSMenuItem(title: updateMenuTitle(feed),
                              action: #selector(installUpdate(_:)), keyEquivalent: "")
        item.target = self
        item.tag = updateMenuItemTag
        item.representedObject = feed.url
        menu.insertItem(item, at: 0)
        menu.insertItem(.separator(), at: 1)
    }

    /// Installs the update in place of the app then relaunches, after
    /// explicit consent: replacing the installed app isn't trivial.
    @objc private func installUpdate(_ sender: NSMenuItem) {
        guard let feed = UpdateChecker.shared.availableUpdate else { return }

        let confirm = NSAlert()
        confirm.messageText = loc("Installer Claudio \(feed.version) ?", en: "Install Claudio \(feed.version)?")
        confirm.informativeText = loc("Claudio télécharge la nouvelle version, remplace l'app installée, puis redémarre.",
                                      en: "Claudio downloads the new version, replaces the installed app, then restarts.")
        confirm.addButton(withTitle: loc("Installer et redémarrer", en: "Install and restart"))
        confirm.addButton(withTitle: loc("Annuler", en: "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        let title = sender.title
        sender.title = loc("Téléchargement de la mise à jour…", en: "Downloading the update…")
        sender.isEnabled = false
        Task { @MainActor in
            do {
                let newApp = try await UpdateInstaller.prepare(from: feed.url)
                try UpdateInstaller.installAndRelaunch(newApp)
            } catch {
                sender.title = title
                sender.isEnabled = true
                let failed = NSAlert()
                failed.messageText = loc("Mise à jour impossible", en: "Update failed")
                failed.informativeText = error.localizedDescription
                failed.addButton(withTitle: "OK")
                failed.addButton(withTitle: loc("Télécharger dans le navigateur", en: "Download in the browser"))
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

    /// Lets the menu close and the previous app regain focus before
    /// triggering: the selection capture targets the source app, not Claudio.
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
