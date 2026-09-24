import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    /// The "Recent ▸" entry and its submenu: hidden while history is empty,
    /// repopulated on every open (recents change).
    private var recentsItem: NSMenuItem?
    private var recentsMenu: NSMenu?
    /// "Recent dictations ▸", on the same terms: hidden while no dictation
    /// was made, repopulated on every open.
    private var recentDictationsItem: NSMenuItem?
    private var recentDictationsMenu: NSMenu?
    private let updateMenuItemTag = 777
    private let coordinator = CorrectionCoordinator()
    /// Dictation's own coordinator, on Apple's engine. Built here and kept
    /// for the life of the app: the hold shortcuts hold a weak reference to
    /// it, and the microphone only opens on a press.
    ///
    /// Its panel takes the listening one off the screen first: every panel
    /// opens in the same spot, and the one that is key takes the keyboard.
    private lazy var dictation = DictationCoordinator(
        engine: AppleSpeechEngine(),
        panel: { [weak self] session, coordinator in
            self?.listening.dismiss()
            return DictationCoordinator.systemPanel(for: session, coordinator: coordinator)
        }
    )
    /// "What's playing?": the player read through `osascript`, Claude's
    /// notes in a panel of its own. Nothing is captured, so no Accessibility.
    private let listening = ListeningCoordinator()
    /// The free action's own microphone: its shortcut held speaks the
    /// instruction instead of typing it. Its own engine, because a dictation
    /// and an instruction are two microphones that never open together.
    private lazy var spokenInstruction = SpokenInstructionCoordinator(
        engine: AppleSpeechEngine(),
        panel: .freeAction(coordinator)
    )
    private let settingsController = SettingsWindowController()
    /// The Stream Deck bridge, and the one place a key press becomes a
    /// gesture. Only ever started when the plugin is there, or when Settings
    /// asks for it: a Mac with neither never opens a socket.
    private lazy var streamDeck = StreamDeckBridge(dispatcher: BridgeDispatcher(
        triggerAction: { [weak self] action in self?.coordinator.trigger(action: action) },
        triggerFree: { [weak self] in self?.coordinator.triggerFreeAction() },
        triggerPalette: { [weak self] in self?.coordinator.triggerPalette() },
        triggerWhatsPlaying: { [weak self] in self?.listening.trigger() },
        dictationDown: { [weak self] language, output in
            // The plugin names one of the two shortcuts, not a locale: the
            // key dictates in whatever Settings has for that one, and
            // changing the language there changes what the key does.
            let shortcut: DictationShortcut = switch language {
            case .primary: .dictate
            case .secondary: .dictateOtherLanguage
            }
            self?.dictation.keyDown(language: shortcut.language, output: output)
        },
        dictationUp: { [weak self] in self?.dictation.keyUp() },
        dictationCancel: { [weak self] in self?.dictation.escape() },
        applyLayout: { WindowMover.apply($0) },
        nextScreen: { WindowMover.moveToNextScreen() },
        openSettings: { [weak self] in self?.settingsController.show(initialSection: .streamDeck) }
    ))

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.openSettings = { [weak self] in self?.settingsController.show() }
        // A panel gone is a microphone that has nothing left to listen for:
        // Esc, another shortcut or a paste all end a spoken instruction.
        // Every correction also starts with this dismissal, which is what
        // takes the listening panel away before the selection is captured:
        // left key, it would catch the simulated ⌘C.
        coordinator.onDismiss = { [weak self] in
            self?.spokenInstruction.cancel()
            self?.listening.dismiss()
        }
        listening.openSettings = { [weak self] in self?.settingsController.show() }
        // One panel on screen, the other way round.
        listening.onOpen = { [weak self] in
            self?.coordinator.dismiss()
            self?.dictation.dismiss()
        }
        // The palette's "What's playing?" row. Its own panel closes the
        // palette's through `onOpen` above, before the new session exists:
        // the `onDismiss` that follows finds nothing of it to take away.
        coordinator.openWhatsPlaying = { [weak self] in self?.listening.trigger() }
        setupMainMenu()
        setupStatusItem()
        HotkeySetup.install(coordinator: coordinator)
        HotkeySetup.installFreeAction(coordinator: spokenInstruction)
        HotkeySetup.installDictation(coordinator: dictation)
        HotkeySetup.installListening(coordinator: listening)
        // The Stream Deck keys, which are shortcuts by another road. Hooked
        // up whether or not the bridge runs, so Settings can switch it on
        // later without anything else to arrange; the plugin sitting in its
        // folder is what opens the socket on a fresh launch.
        streamDeck.attach(correction: coordinator, dictation: dictation)
        wireStreamDeckSettings()
        if AppSettings.streamDeckBridgeEnabled(
            pluginInstalled: StreamDeckPluginLocator().isInstalled) {
            streamDeck.start()
        }
        // Earlier builds muted the other apps with a tap that outlives a
        // crash, and every app with it: a launch gives the sound back.
        LeftoverMuteTaps.remove()

        UpdateChecker.shared.onUpdateFound = { [weak self] feed in
            self?.showUpdateMenuItem(feed)
        }
        UpdateChecker.shared.startPeriodicChecks()

        // First launch without a key: open Settings directly.
        if KeychainStore.currentAPIKey() == nil {
            settingsController.show()
        }
    }

    /// Quitting mid-dictation — easy once a tap has locked it: the music
    /// Claudio paused resumes with the app gone, rather than staying off.
    func applicationWillTerminate(_ notification: Notification) {
        dictation.dismiss()
        spokenInstruction.cancel()
        // And the handshake file goes with the app: one left behind points
        // the plugin at a port nobody answers.
        streamDeck.stop()
    }

    /// The `claudio://` links: how the plugin, and the download page, send
    /// someone straight to the tab that matters instead of describing where
    /// it hides. The scheme is declared in the built app's Info.plist, so a
    /// `swift run` never receives one; what a link means is decided by the
    /// parser, and a link Claudio doesn't understand opens nothing.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            switch ClaudioURL.parse(url) {
            case .settings(let section):
                settingsController.show(initialSection: section)
            case nil:
                continue
            }
        }
    }

    // MARK: - The Stream Deck tab

    /// Settings' Stream Deck tab, hooked to the real bridge: it shows what
    /// the bridge reports and gets to switch it on or off. Hooked whether or
    /// not the bridge runs — the tab is where a stopped bridge is started.
    private func wireStreamDeckSettings() {
        let model = StreamDeckStatusModel.shared
        streamDeck.onStatusChange = { status in model.status = status }
        model.refresh = { [weak self] in self?.refreshStreamDeckSettings() }
        // A window that never closed shows a tab that never reappears: the
        // look for the plugin is taken again every time Settings comes up,
        // not only when the tab is built.
        settingsController.selection.onShown = { [weak self] in self?.refreshStreamDeckSettings() }
        model.applyChoice = { [weak self] choice in self?.applyStreamDeckChoice(choice) }
        refreshStreamDeckSettings()
    }

    /// What the tab reads every time it opens: the plugin may have been
    /// installed — or removed — since launch, and the bridge may have given
    /// up on its own meanwhile.
    private func refreshStreamDeckSettings() {
        let model = StreamDeckStatusModel.shared
        model.pluginInstalled = StreamDeckPluginLocator().isInstalled
        model.choice = AppSettings.streamDeckBridgeChoice()
        model.status = streamDeck.status
    }

    /// The switch, applied for real: the choice is written down, then the
    /// bridge is brought in line with it. Back to automatic included, where
    /// the plugin's presence decides again — and may close the socket.
    private func applyStreamDeckChoice(_ choice: Bool?) {
        let model = StreamDeckStatusModel.shared
        AppSettings.setStreamDeckBridgeChoice(choice)
        let installed = StreamDeckPluginLocator().isInstalled
        model.pluginInstalled = installed
        if AppSettings.streamDeckBridgeEnabled(pluginInstalled: installed) {
            streamDeck.start()
        } else {
            streamDeck.stop()
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

        // Not a transformation of the selection: it reads what plays, and
        // Claude says a few words about it.
        let whatsPlaying = NSMenuItem(title: ListeningSession.menuTitle,
                                      action: #selector(whatsPlayingFromMenu), keyEquivalent: "")
        whatsPlaying.target = self
        menu.addItem(whatsPlaying)

        // No dictation entry: this menu lists titles without their
        // shortcuts, and dictation is a key held down — a click could only
        // ever open the microphone without a way to close it. Its shortcuts
        // and its history live in Settings ▸ Dictation.

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

        // The last few dictations, to paste one again at the cursor when its
        // first paste landed in the wrong place: a way back to a text, not a
        // way to dictate. Also rebuilt on open.
        let dictationsMenu = NSMenu()
        dictationsMenu.autoenablesItems = false
        dictationsMenu.delegate = self
        let dictationsItem = NSMenuItem(title: RecentDictationsMenu.menuTitle,
                                        action: nil, keyEquivalent: "")
        dictationsItem.submenu = dictationsMenu
        menu.addItem(dictationsItem)
        self.recentDictationsMenu = dictationsMenu
        self.recentDictationsItem = dictationsItem

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

    /// When the main menu opens, "Recent ▸" and "Recent dictations ▸" only
    /// appear if there's something in them. When a submenu itself opens,
    /// it's repopulated: its history may have changed since last time.
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === statusMenu {
            recentsItem?.isHidden = TransformHistory.shared.recents.entries.isEmpty
            recentDictationsItem?.isHidden = DictationHistory.shared.recents.entries.isEmpty
        } else if menu === recentsMenu {
            rebuildRecentsMenu(menu)
        } else if menu === recentDictationsMenu {
            rebuildRecentDictationsMenu(menu)
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

    // MARK: - Dictations ("Recent dictations")

    /// Which dictations and under which titles is `RecentDictationsMenu`'s
    /// call; this only makes the rows. No "Clear" here: Settings has it.
    private func rebuildRecentDictationsMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        for row in RecentDictationsMenu(DictationHistory.shared.recents).items {
            let item = NSMenuItem(title: row.title,
                                  action: #selector(recentDictationFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = row.text
            item.toolTip = row.text  // the truncated title, in full on hover
            menu.addItem(item)
        }
    }

    /// Pastes the dictation again at the cursor of the app in front, or
    /// copies it when that app is Claudio. Any panel still on screen has the
    /// keyboard, so they all close before the keystroke.
    @objc private func recentDictationFromMenu(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        let paster = RecentDictationPaster(closePanels: { [weak self] in
            self?.coordinator.dismiss()
            self?.dictation.dismiss()
            self?.listening.dismiss()
        })
        Task { await paster.paste(text) }
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

    /// Nothing to capture here, but the same beat all the same: the panel
    /// takes the keyboard once the menu is gone and the app in front is
    /// back, exactly as it does from the shortcut.
    @objc private func whatsPlayingFromMenu() {
        afterMenuCloses { [weak self] _ in self?.listening.trigger() }
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
