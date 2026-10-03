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
    private let artwork: ArtworkSource
    private let facts: FactsSource
    private let remoteArtwork: RemoteArtworkSource
    /// The Music tab's settings, read at each read of the player.
    private let preferences: () -> ListeningPreferences
    /// The model the notes come from, asked at each trigger: a setting
    /// since the Models tab, a fixed value in a test.
    private let model: () -> ModelChoice
    /// The long text's own model, asked at each pill.
    private let essayModel: () -> ModelChoice
    /// Hands a link to the system: "Search in Claude".
    private let openLink: @MainActor (URL) -> Void
    /// Whether Claude Desktop is on this Mac, asked at each click.
    private let claudeDesktop: @MainActor () -> Bool
    /// Brings the player forward, by bundle id: "Open Spotify".
    private let activatePlayer: @MainActor (String) -> Void

    private var panel: ResultPanel?
    /// The listening under way, `nil` between two.
    private(set) var session: ListeningSession?
    /// Reads the player, then streams the notes: cancelled by Esc, by the
    /// next trigger, and by a retry.
    private(set) var cycle: Task<Void, Never>?
    /// Fetches the cover beside the cycle, never holding it up: cancelled
    /// with it.
    private var coverFetch: Task<Void, Never>?
    private var factsFetch: Task<Void, Never>?
    /// The archive is asked for a cover once the player has given none and
    /// the facts name a release group, whichever comes last — and once.
    private var playerCoverSettled = false
    private var archiveAsked = false

    init(source: NowPlayingSource = .system,
         client: @escaping DictationCoordinator.ClientFactory = TextStreamClientFactory.make(for:),
         panel: @escaping PanelMaker = ListeningCoordinator.systemPanel,
         durations: DictationCoordinator.MessageDurations = .standard,
         galette: GaletteService = .system,
         artwork: ArtworkSource = .system,
         facts: FactsSource = .system,
         remoteArtwork: RemoteArtworkSource = .system,
         preferences: @escaping () -> ListeningPreferences = { .current() },
         model: @escaping () -> ModelChoice = { AppSettings.listeningModel() },
         essayModel: @escaping () -> ModelChoice = { AppSettings.essayModel() },
         openLink: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) },
         claudeDesktop: @escaping @MainActor () -> Bool = ClaudeSearch.desktopInstalled,
         activatePlayer: @escaping @MainActor (String) -> Void = ListeningCoordinator.activateApp) {
        self.source = source
        self.client = client
        self.makePanel = panel
        self.durations = durations
        self.galette = galette
        self.artwork = artwork
        self.facts = facts
        self.remoteArtwork = remoteArtwork
        self.preferences = preferences
        self.model = model
        self.essayModel = essayModel
        self.openLink = openLink
        self.claudeDesktop = claudeDesktop
        self.activatePlayer = activatePlayer
    }

    // MARK: - The cycle

    /// Menu or shortcut: the panel opens at once, on its header alone, and
    /// the player is read behind it.
    func trigger() {
        dismiss()  // idempotent: a shortcut while the panel is up starts fresh
        // Before this session exists: closing another panel may call back
        // into `dismiss()`, which must then find nothing of this one to close.
        onOpen?()
        let session = ListeningSession(model: model())
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
        // A retry that finds another track drops the old cover and facts;
        // the same track keeps them rather than blink.
        if session.track != track {
            session.artwork = nil
            session.facts = nil
        }
        session.track = track
        guard let track else {
            session.phase = .nothing
            closeAfter(durations.empty, session: session)
            return
        }
        let preferences = preferences()
        // Facts already known go to Claude with the first request.
        let known = preferences.musicBrainz ? facts.cached(track) : nil
        session.facts = known
        playerCoverSettled = false
        archiveAsked = false
        if preferences.showsArtwork {
            fetchCover(of: track, for: session)
        }
        if preferences.musicBrainz, known == nil {
            fetchFacts(of: track, for: session, preferences: preferences)
        } else {
            considerArchiveCover(for: session, preferences: preferences)
        }
        await tell(about: track, facts: known, detail: preferences.detail, session: session)
    }

    /// The cover goes its own way: the card is up, Claude is being asked,
    /// and the image takes its place whenever it arrives — if this is still
    /// the panel it was asked for.
    private func fetchCover(of track: NowPlayingTrack, for session: ListeningSession) {
        coverFetch?.cancel()
        coverFetch = Task { [weak self, artwork] in
            let image = await artwork.image(track)
            guard let self, self.session === session, !Task.isCancelled else { return }
            if let image { session.artwork = image }
            playerCoverSettled = true
            considerArchiveCover(for: session, preferences: preferences())
        }
    }

    /// MusicBrainz, beside the cycle and never holding it up: the facts
    /// take their place under the card when they arrive. Claude isn't
    /// asked again — his text is on screen — but they serve the cover, and
    /// the next listen of the track.
    private func fetchFacts(of track: NowPlayingTrack, for session: ListeningSession,
                            preferences: ListeningPreferences) {
        factsFetch?.cancel()
        factsFetch = Task { [weak self, facts] in
            let found = await facts.fetch(track)
            guard let self, self.session === session, !Task.isCancelled else { return }
            session.facts = found
            considerArchiveCover(for: session, preferences: preferences)
        }
    }

    /// The archive's cover, once: when the player has given none, the
    /// facts name a release group, and the cover is wanted at all.
    private func considerArchiveCover(for session: ListeningSession, preferences: ListeningPreferences) {
        guard preferences.showsArtwork, preferences.musicBrainz, !archiveAsked,
              playerCoverSettled || !preferences.showsArtwork,
              session.artwork == nil,
              let facts = session.facts, facts.releaseGroupID != nil else { return }
        archiveAsked = true
        Task { [weak self, remoteArtwork] in
            let image = await remoteArtwork.image(facts)
            guard let self, self.session === session, session.artwork == nil else { return }
            session.artwork = image
        }
    }

    /// The card is up by now, and worth something without Claude: whatever
    /// happens from here, it stays.
    private func tell(about track: NowPlayingTrack, facts: TrackFacts?, detail: ListeningDetail,
                      session: ListeningSession) async {
        guard let client = client(session.model) else {
            session.phase = .missingKey
            return
        }
        session.beginStreaming()
        do {
            let result = try await client.streamCompletion(
                of: ListeningNotes.userMessage(for: track, facts: facts),
                system: ListeningNotes.system(detail: detail),
                maxTokens: detail.maxTokens
            ) { @MainActor piece in
                session.appendNotes(piece)
            }
            guard self.session === session, !Task.isCancelled else { return }
            CostLedger.shared.record(model: session.model,
                                     inputTokens: result.inputTokens,
                                     outputTokens: result.outputTokens)
            // Nothing is an answer too, and a wrong one: said as such,
            // with what the stream held, rather than "Ready" over a blank.
            if result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                session.phase = .error(Self.emptyAnswerMessage(model: session.model, result: result))
                return
            }
            session.finish(with: result.text)
        } catch is CancellationError {
            // Esc during the stream: nothing to do
        } catch let error as URLError where error.code == .cancelled {
            // same thing, URLSession reports cancellation this way
        } catch {
            guard self.session === session, !Task.isCancelled else { return }
            session.phase = .error(error.localizedDescription)
        }
    }

    // MARK: - "Tell me more"

    /// A pill on the card: the notes make way for a long text about the
    /// album or the artist. Whatever the notes were doing stops; they stay
    /// as they are for the way back.
    func elaborate(on subject: MusicSubject) {
        guard let session else { return }
        cycle?.cancel()
        session.beginEssay(on: subject, model: essayModel())
        cycle = Task { [weak self] in
            await self?.write(about: subject, session: session)
        }
    }

    /// "Back": the notes again, as they were.
    func back() {
        guard let session, session.essaySubject != nil else { return }
        cycle?.cancel()
        cycle = nil
        session.closeEssay()
    }

    /// A `claudio://music` link from Galette: the panel opens on the
    /// subject's card, nothing is read from the player, and the long text
    /// streams at once. The album's facts come with the link: the archive
    /// is asked for its cover like a listening would.
    func open(_ subject: MusicSubject) {
        dismiss()
        onOpen?()
        let session = ListeningSession(model: model())
        session.galette = galette.find()
        session.cameFromLink = true
        session.track = subject.card
        session.facts = subject.facts
        self.session = session
        panel = makePanel(session, self)
        let preferences = preferences()
        playerCoverSettled = true
        archiveAsked = false
        considerArchiveCover(for: session, preferences: preferences)
        elaborate(on: subject)
    }

    /// The artist's facts first — the text waits for them, the panel shows
    /// it coming meanwhile — then Claude, with the discography in hand.
    private func write(about subject: MusicSubject, session: ListeningSession) async {
        guard let client = client(session.model) else {
            session.phase = .missingKey
            return
        }
        let artist = preferences().musicBrainz ? await facts.artist(subject) : nil
        guard self.session === session, !Task.isCancelled, session.essaySubject == subject else { return }
        session.artistFacts = artist
        do {
            let result = try await client.streamCompletion(
                of: ListeningEssay.userMessage(for: subject, artist: artist),
                system: ListeningEssay.system(),
                maxTokens: ListeningEssay.maxTokens
            ) { @MainActor piece in
                session.appendEssay(piece)
            }
            guard self.session === session, !Task.isCancelled, session.essaySubject == subject else { return }
            CostLedger.shared.record(model: session.model,
                                     inputTokens: result.inputTokens,
                                     outputTokens: result.outputTokens)
            if result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                session.phase = .error(Self.emptyAnswerMessage(model: session.model, result: result))
                return
            }
            session.finishEssay(with: result.text)
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            guard self.session === session, !Task.isCancelled else { return }
            session.phase = .error(error.localizedDescription)
        }
    }

    /// "Search in Claude": the subject goes to Claude — the desktop app
    /// when it is on this Mac, the browser otherwise — with the artist's
    /// facts when the long text got them, and the panel closes, its job
    /// done.
    func search(_ subject: MusicSubject) {
        guard let session else { return }
        let artist = session.essaySubject == subject ? session.artistFacts : nil
        openLink(ClaudeSearch.url(for: subject, artist: artist, desktop: claudeDesktop()))
        dismiss()
    }

    /// "Open Spotify": back to the player the track came from, where the
    /// favourite button is if there is one (Guillaume, 2026-10-03). The
    /// panel closes, the listener gone back to it.
    func openPlayer() {
        guard let session, let bundleID = session.track?.bundleID else { return }
        activatePlayer(bundleID)
        dismiss()
    }

    /// Brings an installed app forward by its bundle id; nothing happens
    /// for an app this Mac doesn't have.
    static func activateApp(_ bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    /// The line under the card when the model sent nothing: which model,
    /// how the stream ended, what it carried. Enough to tell a refusal
    /// from a thinking-only answer from a cut connection.
    static func emptyAnswerMessage(model: ModelChoice, result: StreamResult) -> String {
        loc("Réponse vide de \(model.shortName) (\(result.emptyAnswerDescription)).",
            en: "Empty answer from \(model.shortName) (\(result.emptyAnswerDescription)).")
    }

    // MARK: - Panel actions

    /// "Try again", once Claude has failed: the player is read again — the
    /// track may have changed since — then Claude is asked again. The card
    /// stays up while the player answers.
    func retry() {
        guard let session, case .error = session.phase else { return }
        cycle?.cancel()
        // The long text failed: it is asked again, the card as it is.
        if let subject = session.essaySubject {
            session.beginEssay(on: subject, model: essayModel())
            cycle = Task { [weak self] in
                await self?.write(about: subject, session: session)
            }
            return
        }
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
        coverFetch?.cancel()
        coverFetch = nil
        factsFetch?.cancel()
        factsFetch = nil
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
            onClose: { [weak coordinator] in coordinator?.dismiss() },
            onOpenInGalette: { [weak coordinator] link in coordinator?.openInGalette(link) },
            onElaborate: { [weak coordinator] subject in coordinator?.elaborate(on: subject) },
            onBack: { [weak coordinator] in coordinator?.back() },
            onSearch: { [weak coordinator] subject in coordinator?.search(subject) },
            onOpenPlayer: { [weak coordinator] in coordinator?.openPlayer() }
        )
        panel.onEscape = { [weak coordinator] in coordinator?.dismiss() }
        panel.onCopyShortcut = { [weak coordinator] in coordinator?.copyTrack() }
        panel.present()
        return panel
    }
}
