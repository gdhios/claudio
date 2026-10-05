import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusMenu: StatusMenu?
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
    /// instruction instead of typing it. Its own engine, so a dictation
    /// still listening never shares one with it.
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
    /// Claudio's face on every Ulanzi clock that has it ticked. Only ever
    /// started for the clocks Settings holds: a Mac without one never calls
    /// anything.
    private let fleet = UlanziFaceFleet()
    /// The Claude Code sessions on every clock that has the flags ticked:
    /// their flags, the alerts held while they wait, and the middle button
    /// back to the conversation. Listening only while one clock has them.
    private let hub = ClaudeCodeHub()
    /// The relay this app ships, hooked into Claude Code from Settings.
    private let hookInstaller = ClaudeCodeHookInstaller()

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
        // One panel on screen: a correction or a spoken instruction ends a
        // dictation left listening hands-free. What it heard is kept in
        // "Recent dictations" and the music resumes, as for "What's playing?".
        coordinator.onOpen = { [weak self] in self?.dictation.dismiss() }
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
        NSApp.mainMenu = MainMenu.make()
        statusMenu = StatusMenu(actions: statusMenuActions)
        HotkeySetup.install(coordinator: coordinator)
        HotkeySetup.installFreeAction(coordinator: spokenInstruction)
        HotkeySetup.installDictation(coordinator: dictation)
        HotkeySetup.installListening(coordinator: listening)
        // The Stream Deck keys, which are shortcuts by another road, and the
        // Ulanzi faces both follow the two sessions. Each coordinator takes
        // one observer: the hooks are set here, once, and tell the bridge
        // and the fleet. Set whether or not either runs, so Settings can
        // switch one on later without anything else to arrange. The plugin
        // sitting in its folder is what opens the socket on a fresh launch,
        // through the first look the tab's wiring takes; the clocks stored
        // are what start the Ulanzi's.
        coordinator.onSessionChange = { [weak self] session in
            self?.streamDeck.correctionSessionChanged(session)
            self?.fleet.correctionSessionChanged(session)
        }
        dictation.onSessionChange = { [weak self] session in
            self?.streamDeck.dictationSessionChanged(session)
            self?.fleet.dictationSessionChanged(session)
        }
        streamDeck.attach(correction: coordinator, dictation: dictation)
        wireStreamDeckSettings()
        wireUlanziSettings()

        UpdateChecker.shared.onUpdateFound = { [weak self] feed in
            self?.statusMenu?.showUpdate(feed)
        }
        UpdateChecker.shared.startPeriodicChecks()

        // First launch without a key: open Settings directly, on the tab
        // where the key goes.
        if KeychainStore.currentAPIKey() == nil {
            settingsController.show(initialSection: .apiKey)
        }
    }

    /// Quitting mid-dictation — easy once a tap has locked it: the music
    /// Claudio paused resumes with the app gone, rather than staying off.
    func applicationWillTerminate(_ notification: Notification) {
        dictation.dismiss()
        spokenInstruction.cancel()
        // And the handshake files go with the app: one left behind points
        // the plugin, or the Claude Code relay, at a port nobody answers.
        streamDeck.stop()
        hub.stop()
        // The clocks' faces too, if they may be up: the app waits for the
        // clocks to answer, a second at most for them all.
        fleet.prepareToQuit(within: 1)
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
            case .music(let subject):
                listening.open(subject)
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
        settingsController.selection.onShown = { [weak self] in self?.settingsShown() }
        model.applyChoice = { [weak self] choice in self?.applyStreamDeckChoice(choice) }
        refreshStreamDeckSettings()
    }

    /// Settings coming up: what the tabs show of this Mac is read again,
    /// the plugin's folder and Claude Code's settings, either of which may
    /// have changed since, a failure of an earlier try forgotten with it.
    private func settingsShown() {
        refreshStreamDeckSettings()
        UlanziStatusModel.shared.hookRead(hookInstaller.state())
    }

    /// What the tab reads every time it opens: the plugin may have been
    /// installed — or removed — since launch, and the bridge may have given
    /// up on its own meanwhile. The bridge follows the look: a plugin that
    /// arrived since launch opens the socket now, as "Set automatically:
    /// plugin detected" says it does, not at the next launch.
    private func refreshStreamDeckSettings() {
        let model = StreamDeckStatusModel.shared
        model.pluginInstalled = syncStreamDeckBridge()
        model.choice = AppSettings.streamDeckBridgeChoice()
        model.status = streamDeck.status
    }

    /// The switch, applied for real: the choice is written down, then the
    /// bridge is brought in line with it. Back to automatic included, where
    /// the plugin's presence decides again — and may close the socket.
    private func applyStreamDeckChoice(_ choice: Bool?) {
        let model = StreamDeckStatusModel.shared
        AppSettings.setStreamDeckBridgeChoice(choice)
        model.pluginInstalled = syncStreamDeckBridge()
    }

    /// Opens or closes the socket as the setting and the plugin's presence
    /// say, and reports whether the plugin is there. Opening an open socket
    /// is nothing: `start()` returns at once.
    private func syncStreamDeckBridge() -> Bool {
        let installed = StreamDeckPluginLocator().isInstalled
        if AppSettings.streamDeckBridgeEnabled(pluginInstalled: installed) {
            streamDeck.start()
        } else {
            streamDeck.stop()
        }
        return installed
    }

    // MARK: - The Ulanzi tab

    /// Settings' Ulanzi tab, hooked to the real fleet and hub: it shows
    /// what they report, clock by clock, and hands them a new list or a
    /// test, and the hook to install or remove. The clocks stored start
    /// both at launch, the rows shown first so that every status lands on
    /// one.
    private func wireUlanziSettings() {
        let model = UlanziStatusModel.shared
        fleet.onStatusChange = { id, status in model.faceStatusChanged(status, of: id) }
        hub.onStatusChange = { status in model.hub = status }
        hub.onClockStatusChange = { id, status in model.alertsStatusChanged(status, of: id) }
        model.applyClocks = { [weak self] clocks in self?.applyUlanziClocks(clocks) }
        model.test = { [weak self] id in self?.fleet.test(id) }
        model.installHook = { [weak self] in self?.changeHook { try $0.install() } }
        model.removeHook = { [weak self] in self?.changeHook { try $0.remove() } }
        let clocks = AppSettings.ulanziClocks()
        model.show(clocks)
        fleet.apply(clocks)
        hub.apply(clocks)
        // An update of the app may ship another relay: the hook installed
        // runs the new one from now on. A copy that can't be written
        // leaves the one there as it was.
        try? hookInstaller.refreshRelay()
        refreshHookState()
    }

    /// A new list, applied for real: written down, then the faces and the
    /// flags brought in line with it. Each starts only what came or moved,
    /// and stops only what went.
    private func applyUlanziClocks(_ clocks: [UlanziClock]) {
        AppSettings.setUlanziClocks(clocks)
        fleet.apply(clocks)
        hub.apply(clocks)
    }

    /// Installs or removes the hook, then reads where it stands. What the
    /// state can't say, a file that couldn't be written, is said apart.
    private func changeHook(_ change: (ClaudeCodeHookInstaller) throws -> Void) {
        let model = UlanziStatusModel.shared
        do {
            try change(hookInstaller)
            model.hookFailure = nil
        } catch is ClaudeCodeHookInstaller.Failure {
            model.hookFailure = nil
        } catch {
            model.hookFailure = error.localizedDescription
        }
        refreshHookState()
    }

    /// Claude Code's settings may have changed by hand since the last look.
    private func refreshHookState() {
        UlanziStatusModel.shared.hook = hookInstaller.state()
    }

    // MARK: - The status menu

    private var statusMenuActions: StatusMenuActions {
        StatusMenuActions(
            palette: { [weak self] in self?.coordinator.triggerPalette() },
            action: { [weak self] action in self?.coordinator.trigger(action: action) },
            freeAction: { [weak self] in self?.coordinator.triggerFreeAction() },
            whatsPlaying: { [weak self] in self?.listening.trigger() },
            recent: { [weak self] instruction in self?.coordinator.triggerRecent(instruction: instruction) },
            recentDictation: { [weak self] text in self?.pasteAgain(text) },
            openSettings: { [weak self] in self?.settingsController.show() }
        )
    }

    /// Pastes the dictation again at the cursor of the app in front, or
    /// copies it when that app is Claudio. Any panel still on screen has the
    /// keyboard, so they all close before the keystroke.
    private func pasteAgain(_ text: String) {
        let paster = RecentDictationPaster(closePanels: { [weak self] in
            self?.coordinator.dismiss()
            self?.dictation.dismiss()
            self?.listening.dismiss()
        })
        Task { await paster.paste(text) }
    }
}
