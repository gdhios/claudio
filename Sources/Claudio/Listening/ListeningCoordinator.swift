import AppKit

/// "What's playing?": read the player, put the track on screen, and let
/// Claude say two or three things about it. The other coordinators'
/// counterpart, in the same panel — except nothing is captured and nothing
/// is pasted: no selection, no Accessibility, a card and a text.
///
/// Everything that touches the outside world arrives through `init`: the
/// player, the model, the panel, how long a message stays up, Galette. The
/// whole cycle is then playable without `osascript`, a network or a screen.
@MainActor
final class ListeningCoordinator {
    /// Puts the session on screen and hands back the panel to keep. `nil`
    /// when there is no screen to put it on.
    typealias PanelMaker = @MainActor (ListeningSession, ListeningCoordinator) -> ResultPanel?

    /// Opens Settings: the missing-key message's way out.
    var openSettings: (() -> Void)?
    /// Called as the panel is about to open. Every panel opens in the same
    /// spot, and the one that is key takes the keyboard: the app hangs the
    /// closing of the correction and dictation panels on this.
    var onOpen: (() -> Void)?

    private let source: NowPlayingSource
    private let client: DictationCoordinator.ClientFactory
    private let makePanel: PanelMaker
    private let durations: DictationCoordinator.MessageDurations
    private let galette: GaletteService

    private var panel: ResultPanel?
    /// The listening under way, `nil` between two.
    private(set) var session: ListeningSession?
    /// Reads the player, then streams the notes: cancelled by Esc, by the
    /// next trigger, and by a retry.
    private(set) var cycle: Task<Void, Never>?

    init(source: NowPlayingSource = .system,
         client: @escaping DictationCoordinator.ClientFactory = TextStreamClientFactory.make(for:),
         panel: @escaping PanelMaker = ListeningCoordinator.systemPanel,
         durations: DictationCoordinator.MessageDurations = .standard,
         galette: GaletteService = .system) {
        self.source = source
        self.client = client
        self.makePanel = panel
        self.durations = durations
        self.galette = galette
    }

    // MARK: - The cycle

    /// Menu or shortcut: the panel opens at once, on its header alone, and
    /// the player is read behind it.
    func trigger() {
        dismiss()  // idempotent: a shortcut while the panel is up starts fresh
        // Before this session exists: closing another panel may call back
        // into `dismiss()`, which must then find nothing of this one to close.
        onOpen?()
        let session = ListeningSession()
        // Looked for with each panel: the card only offers what this Mac has.
        session.galette = galette.find()
        self.session = session
        panel = makePanel(session, self)
        cycle = Task { [weak self] in
            await self?.read(session)
        }
    }

    /// Asks the player what it plays, then Claude about it.
    private func read(_ session: ListeningSession) async {
        let track = await source.current()
        // Esc or another trigger while the player was answering: its answer
        // belongs to a panel that is gone.
        guard self.session === session, !Task.isCancelled else { return }
        session.track = track
        guard let track else {
            session.phase = .nothing
            closeAfter(durations.empty, session: session)
            return
        }
        await tell(about: track, session: session)
    }

    /// The card is up by now, and worth something without Claude: whatever
    /// happens from here, it stays.
    private func tell(about track: NowPlayingTrack, session: ListeningSession) async {
        guard let client = client(session.model) else {
            session.phase = .missingKey
            return
        }
        session.beginStreaming()
        do {
            let result = try await client.streamCompletion(
                of: ListeningNotes.userMessage(for: track),
                system: ListeningNotes.system(),
                maxTokens: ListeningNotes.maxTokens
            ) { @MainActor piece in
                session.appendNotes(piece)
            }
            guard self.session === session, !Task.isCancelled else { return }
            session.finish(with: result.text)
            CostLedger.shared.record(model: session.model,
                                     inputTokens: result.inputTokens,
                                     outputTokens: result.outputTokens)
        } catch is CancellationError {
            // Esc during the stream: nothing to do
        } catch let error as URLError where error.code == .cancelled {
            // same thing, URLSession reports cancellation this way
        } catch {
            guard self.session === session, !Task.isCancelled else { return }
            session.phase = .error(error.localizedDescription)
        }
    }

    // MARK: - Panel actions

    /// "Try again", once Claude has failed: the player is read again — the
    /// track may have changed since — then Claude is asked again. The card
    /// stays up while the player answers.
    func retry() {
        guard let session, case .error = session.phase else { return }
        cycle?.cancel()
        session.phase = .reading
        cycle = Task { [weak self] in
            await self?.read(session)
        }
    }

    /// ⌘C or the Copy button: the track the way one would write it to
    /// someone, as soon as the card is up, whatever Claude is doing. Then
    /// the panel goes, as the other panels do after a copy.
    func copyTrack() {
        guard let session, let track = session.track else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(track.copyLine, forType: .string)
        session.justCopied = true
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard self?.session === session, session.justCopied else { return }
            self?.dismiss()
        }
    }

    /// A Galette button on the card: the track goes to Galette, and the
    /// panel, its job done, closes.
    func openInGalette(_ link: GaletteLink) {
        guard session != nil else { return }
        galette.open(link.url)
        dismiss()
    }

    /// "Nothing playing" has said its piece and takes itself off the screen.
    /// Esc and the next trigger cut it short: both call `dismiss()`, and the
    /// session no longer being this one is what makes the sleeping task
    /// harmless. The phase is held too, so it only ever closes that message.
    private func closeAfter(_ delay: Duration, session: ListeningSession) {
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, self.session === session, session.phase == .nothing else { return }
            dismiss()
        }
    }

    /// Esc, the close button, another panel opening: whatever was being read
    /// or streamed is dropped. Idempotent.
    func dismiss() {
        cycle?.cancel()
        cycle = nil
        panel?.orderOut(nil)
        panel = nil
        session = nil
    }

    // MARK: - The panel

    /// The real panel, wired to this coordinator: Esc and ⌘C reach it, and
    /// closing it drops the cycle.
    static func systemPanel(for session: ListeningSession,
                            coordinator: ListeningCoordinator) -> ResultPanel? {
        let panel = ResultPanel.make(
            session: session,
            onCopy: { [weak coordinator] in coordinator?.copyTrack() },
            onRetry: { [weak coordinator] in coordinator?.retry() },
            onOpenSettings: { [weak coordinator] in
                coordinator?.dismiss()
                coordinator?.openSettings?()
            },
            onClose: { [weak coordinator] in coordinator?.dismiss() }
        )
        panel.onEscape = { [weak coordinator] in coordinator?.dismiss() }
        panel.onCopyShortcut = { [weak coordinator] in coordinator?.copyTrack() }
        panel.present()
        return panel
    }
}
