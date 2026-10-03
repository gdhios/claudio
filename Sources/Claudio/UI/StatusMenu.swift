import AppKit

/// What the status menu's rows do. The app delegate answers: the menu only
/// knows how to show them.
struct StatusMenuActions {
    var palette: @MainActor () -> Void
    var action: @MainActor (ClaudioAction) -> Void
    var freeAction: @MainActor () -> Void
    var whatsPlaying: @MainActor () -> Void
    var recent: @MainActor (_ instruction: String) -> Void
    var recentDictation: @MainActor (_ text: String) -> Void
    var openSettings: @MainActor () -> Void
}

/// Claudio in the menu bar, and the menu under it.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let actions: StatusMenuActions
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    /// The "Recent ▸" entry and its submenu: hidden while history is empty,
    /// repopulated on every open (recents change).
    private let recentsItem = NSMenuItem()
    private let recentsMenu = NSMenu()
    /// "Recent dictations ▸", on the same terms: hidden while no dictation
    /// was made, repopulated on every open.
    private let recentDictationsItem = NSMenuItem()
    private let recentDictationsMenu = NSMenu()
    private var updateItem: NSMenuItem?
    /// The rows built once, each with the way to say its title: the
    /// interface language can change while the app runs, and they are
    /// named again every time the menu opens.
    private var fixedRows: [(item: NSMenuItem, title: @MainActor () -> String)] = []

    init(actions: StatusMenuActions) {
        self.actions = actions
        // Claudio himself in the menu bar. Variable length: the bust is
        // wider than it is tall, a square would squash it.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.button?.image = ClaudioMascot.menuBarImage()
        statusItem.button?.setAccessibilityLabel("Claudio")
        build()
        statusItem.menu = menu
    }

    private func build() {
        // At the top: the single entry point, which contains all the others.
        addFixed({ PaletteCatalog.menuTitle }, #selector(paletteFromMenu))
        menu.addItem(.separator())

        for action in ClaudioAction.allCases {
            addFixed({ action.menuTitle }, #selector(actionFromMenu(_:))).representedObject = action
        }
        addFixed({ ClaudioRequest.freeMenuTitle }, #selector(freeActionFromMenu))
        // Not a transformation of the selection: it reads what plays, and
        // Claude says a few words about it.
        addFixed({ ListeningSession.menuTitle }, #selector(whatsPlayingFromMenu))

        // No dictation entry: this menu lists titles without their
        // shortcuts, and dictation is a key held down — a click could only
        // ever open the microphone without a way to close it. Its shortcuts
        // and its history live in Settings ▸ Dictation.

        // The custom instructions already launched, to relaunch with one
        // gesture on the current selection; and the last few dictations, to
        // paste one again at the cursor when its first paste landed in the
        // wrong place. Both are rebuilt on open.
        let submenus: [(NSMenuItem, NSMenu, @MainActor () -> String)] = [
            (recentsItem, recentsMenu, { loc("Récentes", en: "Recent") }),
            (recentDictationsItem, recentDictationsMenu, { RecentDictationsMenu.menuTitle }),
        ]
        for (item, submenu, title) in submenus {
            submenu.autoenablesItems = false
            submenu.delegate = self
            item.submenu = submenu
            keepNamed(item, title)
            menu.addItem(item)
        }

        menu.addItem(.separator())
        addFixed({ loc("Réglages…", en: "Settings…") }, #selector(openSettings), key: ",")
        menu.addItem(.separator())
        // NSApp's to answer, not this menu's: no target.
        let quit = NSMenuItem(title: "", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        keepNamed(quit, { loc("Quitter Claudio", en: "Quit Claudio") })
        menu.addItem(quit)
        menu.delegate = self
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector, key: String = "", to menu: NSMenu? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        (menu ?? self.menu).addItem(item)
        return item
    }

    /// A row of the menu itself: `add`, then `keepNamed`.
    @discardableResult
    private func addFixed(_ title: @escaping @MainActor () -> String, _ action: Selector,
                          key: String = "") -> NSMenuItem {
        let item = add("", action, key: key)
        keepNamed(item, title)
        return item
    }

    /// Names the row now, and again in the current language every time the
    /// menu opens.
    private func keepNamed(_ item: NSMenuItem, _ title: @escaping @MainActor () -> String) {
        item.title = title()
        fixedRows.append((item, title))
    }

    // MARK: - History submenus

    /// When the main menu opens, its rows are named in the current language,
    /// and "Recent ▸" and "Recent dictations ▸" only appear if there's
    /// something in them. When a submenu itself opens, it's repopulated: its
    /// history may have changed since last time.
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === self.menu {
            for (item, title) in fixedRows { item.title = title() }
            recentsItem.isHidden = TransformHistory.shared.recents.entries.isEmpty
            recentDictationsItem.isHidden = DictationHistory.shared.recents.entries.isEmpty
        } else if menu === recentsMenu {
            rebuildRecents()
        } else if menu === recentDictationsMenu {
            rebuildRecentDictations()
        }
    }

    private func rebuildRecents() {
        recentsMenu.removeAllItems()
        for entry in TransformHistory.shared.recents.entries {
            let item = add(entry.instruction.menuRowTitle(length: Self.recentTitleLength),
                           #selector(recentFromMenu(_:)), to: recentsMenu)
            item.representedObject = entry.instruction
            item.toolTip = entry.instruction  // the truncated label, in full on hover
        }
        guard !recentsMenu.items.isEmpty else { return }
        recentsMenu.addItem(.separator())
        add(loc("Vider l'historique", en: "Clear history"), #selector(clearRecents), to: recentsMenu)
    }

    /// Which dictations and under which titles is `RecentDictationsMenu`'s
    /// call; this only makes the rows. No "Clear" here: Settings has it.
    private func rebuildRecentDictations() {
        recentDictationsMenu.removeAllItems()
        for row in RecentDictationsMenu(DictationHistory.shared.recents).items {
            let item = add(row.title, #selector(recentDictationFromMenu(_:)), to: recentDictationsMenu)
            item.representedObject = row.text
            item.toolTip = row.text  // the truncated title, in full on hover
        }
    }

    /// Characters in a recent instruction's row, "…" included.
    private static let recentTitleLength = 48

    // MARK: - Update

    /// "Update X available…" item at the top of the menu.
    func showUpdate(_ feed: UpdateChecker.Feed) {
        let title = loc("Mise à jour \(feed.version) disponible…", en: "Update \(feed.version) available…")
        if let updateItem {
            updateItem.title = title
            return
        }
        let item = NSMenuItem(title: title, action: #selector(installUpdate(_:)), keyEquivalent: "")
        item.target = self
        menu.insertItem(item, at: 0)
        menu.insertItem(.separator(), at: 1)
        updateItem = item
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
        Task {
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

    // MARK: - Rows

    @objc private func paletteFromMenu() { afterMenuCloses(actions.palette) }

    @objc private func actionFromMenu(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? ClaudioAction else { return }
        afterMenuCloses { [actions] in actions.action(action) }
    }

    @objc private func freeActionFromMenu() { afterMenuCloses(actions.freeAction) }

    /// Nothing to capture here, but the same beat all the same: the panel
    /// takes the keyboard once the menu is gone and the app in front is
    /// back, exactly as it does from the shortcut.
    @objc private func whatsPlayingFromMenu() { afterMenuCloses(actions.whatsPlaying) }

    @objc private func recentFromMenu(_ sender: NSMenuItem) {
        guard let instruction = sender.representedObject as? String else { return }
        afterMenuCloses { [actions] in actions.recent(instruction) }
    }

    @objc private func clearRecents() { TransformHistory.shared.clear() }

    /// Waits for the menu itself (`RecentDictationPaster`), since a panel or
    /// a permission alert may come first.
    @objc private func recentDictationFromMenu(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        actions.recentDictation(text)
    }

    @objc private func openSettings() { actions.openSettings() }

    /// Lets the menu close and the previous app regain focus before
    /// triggering: the selection capture targets the source app, not Claudio.
    private func afterMenuCloses(_ run: @escaping @MainActor () -> Void) {
        Task {
            try? await Task.sleep(for: Constants.menuCloseDelay)
            run()
        }
    }
}

/// Invisible main menu (app .accessory): without an Edit menu, macOS
/// doesn't route ⌘X/⌘C/⌘V/⌘A to text fields.
enum MainMenu {
    @MainActor
    static func make() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: loc("Quitter Claudio", en: "Quit Claudio"),
                                   action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let editMenu = NSMenu(title: loc("Édition", en: "Edit"))
        let rows: [(String, Selector?, String)] = [
            (loc("Annuler", en: "Undo"), Selector(("undo:")), "z"),
            (loc("Rétablir", en: "Redo"), Selector(("redo:")), "Z"),
            ("", nil, ""),
            (loc("Couper", en: "Cut"), #selector(NSText.cut(_:)), "x"),
            (loc("Copier", en: "Copy"), #selector(NSText.copy(_:)), "c"),
            (loc("Coller", en: "Paste"), #selector(NSText.paste(_:)), "v"),
            (loc("Tout sélectionner", en: "Select All"), #selector(NSText.selectAll(_:)), "a"),
        ]
        for (title, action, key) in rows {
            editMenu.addItem(action.map { NSMenuItem(title: title, action: $0, keyEquivalent: key) } ?? .separator())
        }

        for submenu in [appMenu, editMenu] {
            let item = NSMenuItem()
            item.submenu = submenu
            mainMenu.addItem(item)
        }
        return mainMenu
    }
}
