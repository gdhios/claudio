import AppKit
import KeyboardShortcuts

/// What the status menu's rows do. The app delegate answers: the menu only
/// knows how to show them.
struct StatusMenuActions {
    var palette: @MainActor () -> Void
    var action: @MainActor (ClaudioAction) -> Void
    var freeAction: @MainActor () -> Void
    var whatsPlaying: @MainActor () -> Void
    var recent: @MainActor (_ instruction: String) -> Void
    var recentDictation: @MainActor (_ text: String) -> Void
    /// "Settings…": Settings where they were left.
    var openSettings: @MainActor () -> Void
    /// Settings on a named tab: the status lines, the dictation history,
    /// the tip and About.
    var openSettingsSection: @MainActor (SettingsSection) -> Void
}

/// Claudio in the menu bar, and the menu under it: the rows `StatusMenuRows`
/// lists, made into menu items again every time it opens.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let actions: StatusMenuActions
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    /// The submenus of "Recent ▸" and "Recent dictations ▸", repopulated
    /// every time one opens: their histories change.
    private let recentsMenu = NSMenu()
    private let recentDictationsMenu = NSMenu()
    private lazy var items = StatusMenuItems(
        target: self, action: #selector(rowClicked(_:)),
        submenus: [.recents: recentsMenu, .recentDictations: recentDictationsMenu])
    /// The update the daily check found, until it's installed.
    private var update: StatusMenuRows.PendingUpdate?

    init(actions: StatusMenuActions) {
        self.actions = actions
        // Claudio himself in the menu bar. Variable length: the bust is
        // wider than it is tall, a square would squash it.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.button?.image = ClaudioMascot.menuBarImage()
        statusItem.button?.setAccessibilityLabel("Claudio")
        // A row says itself whether it takes a click: only an update already
        // downloading doesn't.
        for each in [menu, recentsMenu, recentDictationsMenu] {
            each.autoenablesItems = false
            each.delegate = self
        }
        rebuild()
        statusItem.menu = menu
    }

    // MARK: - Opening

    /// While the main menu is open, the global shortcuts step aside: the
    /// library would otherwise take a shortcut typed over the menu for
    /// itself and fire the action under the still-open menu, where the
    /// selection capture finds nothing. Left to the menu, the keystroke
    /// runs the row it is shown on, after the menu closes, like a click.
    func menuWillOpen(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        KeyboardShortcuts.isEnabled = false
    }

    func menuDidClose(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        KeyboardShortcuts.isEnabled = true
    }

    /// The main menu is made again from its rows, in the current language,
    /// with the histories and the status lines as they stand. A submenu is
    /// repopulated from its history.
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === self.menu {
            rebuild()
        } else if menu === recentsMenu {
            rebuildRecents()
        } else if menu === recentDictationsMenu {
            rebuildRecentDictations()
        }
    }

    private func rebuild() {
        items.fill(menu, with: StatusMenuRows.build(
            update: update,
            hasRecents: !TransformHistory.shared.recents.entries.isEmpty,
            hasRecentDictations: !DictationHistory.shared.recents.entries.isEmpty,
            lines: currentLines()))
    }

    /// Where dictation, the clocks and the Stream Deck stand right now: the
    /// settings as stored, and the models the app keeps current.
    private func currentLines() -> StatusMenuLines {
        let keys = DictationShortcut.allCases.map { shortcut in
            (loneKey: AppSettings.dictationLoneKey(for: shortcut)?.title,
             combination: shortcut.name.shortcutDescription)
        }
        let streamDeck = StreamDeckStatusModel.shared
        return StatusMenuLines(
            dictation: StatusMenuLines.dictation(enabled: AppSettings.dictationEnabled(),
                                                 key: StatusMenuLines.dictationKey(keys)),
            ulanzi: StatusMenuLines.ulanzi(UlanziStatusModel.shared.clocks),
            streamDeck: StatusMenuLines.streamDeck(status: streamDeck.status,
                                                   pluginInstalled: streamDeck.pluginInstalled,
                                                   choice: streamDeck.choice))
    }

    // MARK: - History submenus

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
    /// call; this only makes the rows. The whole history, and its Clear,
    /// are one more click away in Settings.
    private func rebuildRecentDictations() {
        recentDictationsMenu.removeAllItems()
        for row in RecentDictationsMenu(DictationHistory.shared.recents).items {
            let item = add(row.title, #selector(recentDictationFromMenu(_:)), to: recentDictationsMenu)
            item.representedObject = row.text
            item.toolTip = row.text  // the truncated title, in full on hover
        }
        recentDictationsMenu.addItem(.separator())
        add(StatusMenuRows.dictationHistoryTitle, #selector(openDictationHistory), to: recentDictationsMenu)
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector, to submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        submenu.addItem(item)
        return item
    }

    /// Characters in a recent instruction's row, "…" included.
    private static let recentTitleLength = 48

    // MARK: - Update

    /// "Update X available…" at the top of the menu, from its next opening.
    /// The same version found again leaves a download running alone.
    func showUpdate(_ feed: UpdateChecker.Feed) {
        guard update?.version != feed.version else { return }
        update = StatusMenuRows.PendingUpdate(version: feed.version)
    }

    /// Installs the update in place of the app then relaunches, after
    /// explicit consent: replacing the installed app isn't trivial.
    private func installUpdate() {
        guard let feed = UpdateChecker.shared.availableUpdate else { return }

        let confirm = NSAlert()
        confirm.messageText = loc("Installer Claudio \(feed.version) ?", en: "Install Claudio \(feed.version)?")
        confirm.informativeText = loc("Claudio télécharge la nouvelle version, remplace l'app installée, puis redémarre.",
                                      en: "Claudio downloads the new version, replaces the installed app, then restarts.")
        confirm.addButton(withTitle: loc("Installer et redémarrer", en: "Install and restart"))
        confirm.addButton(withTitle: loc("Annuler", en: "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        update?.isDownloading = true
        Task {
            do {
                let newApp = try await UpdateInstaller.prepare(from: feed.url)
                try UpdateInstaller.installAndRelaunch(newApp)
            } catch {
                update?.isDownloading = false
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

    @objc private func rowClicked(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? StatusMenuCommand else { return }
        switch command {
        case .installUpdate: installUpdate()
        case .palette: afterMenuCloses(actions.palette)
        case .action(let action): afterMenuCloses { [actions] in actions.action(action) }
        case .freeAction: afterMenuCloses(actions.freeAction)
        // Nothing to capture here, but the same beat all the same: the panel
        // takes the keyboard once the menu is gone and the app in front is
        // back, exactly as it does from the shortcut.
        case .whatsPlaying: afterMenuCloses(actions.whatsPlaying)
        case .settings: actions.openSettings()
        case .settingsSection(let section): actions.openSettingsSection(section)
        case .quit: NSApp.terminate(nil)
        }
    }

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

    @objc private func openDictationHistory() { actions.openSettingsSection(.dictation) }

    /// Lets the menu close and the previous app regain focus before
    /// triggering: the selection capture targets the source app, not Claudio.
    private func afterMenuCloses(_ run: @escaping @MainActor () -> Void) {
        Task {
            try? await Task.sleep(for: Constants.menuCloseDelay)
            run()
        }
    }
}
