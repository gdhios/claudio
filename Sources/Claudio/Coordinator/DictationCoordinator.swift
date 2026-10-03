import AppKit

/// The dictation cycle: hold the shortcut, speak, release — or tap it, speak,
/// press it again — and the text lands where the cursor was.
/// `CorrectionCoordinator`'s counterpart — same panel, same paste path —
/// except the material comes from a microphone instead of a selection.
///
/// Everything that touches the outside world arrives through `init`: the
/// engine, the model behind the cleanup, the paste, the panel, the clock.
/// The whole cycle is then playable without a microphone, a network, a
/// pasteboard or a screen.
@MainActor
final class DictationCoordinator {
    /// A press shorter than this isn't a hold: the key was tapped, and the
    /// microphone stays open without it until the next press.
    static let shortPressThreshold: TimeInterval = 0.3

    /// How long a dictation locked by a tap listens before finishing by
    /// itself, as the next press would have. A tap nobody follows up would
    /// otherwise keep the microphone open, and the music paused, for as long
    /// as Claudio runs.
    nonisolated static let longestLockedDictation: Duration = .seconds(5 * 60)

    /// Puts the session on screen and hands back the panel to keep. `nil`
    /// when there is no screen to put it on.
    typealias PanelMaker = @MainActor (DictationSession, DictationCoordinator) -> ResultPanel?

    private let engine: SpeechEngine
    private let model: @MainActor () -> ModelChoice
    private let vocabulary: @MainActor () -> DictationVocabulary
    private let client: TextStreamClientFactory.Maker
    private let pasting: PasteService
    private let microphone: MicrophoneGate
    private let makePanel: PanelMaker
    private let history: DictationHistory
    private let pauser: MediaPauser
    private let pausesMedia: @MainActor () -> Bool
    /// Whether dictation is switched on at all.
    private let isEnabled: @MainActor () -> Bool
    private let durations: PanelMessageDurations
    /// `longestLockedDictation`, unless a test can't wait five minutes.
    private let lockedLimit: Duration
    private let now: @MainActor () -> Date

    private var panel: ResultPanel?
    private var target: PasteTarget?
    /// When the dictation under way entered the history, `nil` until it has.
    /// Whatever ends it later — a close, a failure, the cleanup coming back —
    /// finds it there already and writes no second line.
    private var recordedAt: Date?
    private var pressedAt = Date.distantPast
    /// Finishes a locked dictation at its limit. Runs from the tap, and is
    /// cancelled by whatever ends the dictation first.
    private var lockTimer: Task<Void, Never>?

    /// Called when the dictation under way changes, the end of one included.
    /// What watches from outside — the Stream Deck bridge — can't poll for a
    /// panel, and reads the session through this.
    ///
    /// A broadcast, and nothing more: it fires mid-mutation — before the panel
    /// is made, before the cycle starts — so the callback must never
    /// synchronously call back into the coordinator. It reports identity
    /// alone: a phase moving inside a session that is still the same one
    /// doesn't fire it, and whoever needs that observes the session's own
    /// `@Published` properties.
    var onSessionChange: ((DictationSession?) -> Void)?

    /// The dictation under way, `nil` between two.
    private(set) var session: DictationSession? {
        didSet {
            guard oldValue !== session else { return }  // a dismissal over nothing says nothing
            onSessionChange?(session)
        }
    }
    /// The task that listens then finishes: cancelled by Esc and by the next
    /// press.
    private(set) var cycle: Task<Void, Never>?
    /// The task asking for the microphone, on the first press only. `nil`
    /// whenever the permissions are already there.
    private(set) var permission: Task<Void, Never>?

    init(engine: SpeechEngine,
         model: @escaping @MainActor () -> ModelChoice = { ModelSlot.dictation.current() },
         vocabulary: @escaping @MainActor () -> DictationVocabulary = {
             DictationVocabulary(parsing: AppSettings.dictationVocabulary)
         },
         client: @escaping TextStreamClientFactory.Maker = TextStreamClientFactory.make(for:),
         pasting: PasteService = .system,
         microphone: MicrophoneGate = .system,
         panel: @escaping PanelMaker = DictationCoordinator.systemPanel,
         history: DictationHistory = .shared,
         pauser: MediaPauser = MediaPauser(),
         pausesMedia: @escaping @MainActor () -> Bool = { AppSettings.dictationPausesMedia },
         isEnabled: @escaping @MainActor () -> Bool = { AppSettings.dictationEnabled() },
         durations: PanelMessageDurations = .standard,
         lockedLimit: Duration = DictationCoordinator.longestLockedDictation,
         now: @escaping @MainActor () -> Date = Date.init) {
        self.engine = engine
        self.model = model
        self.vocabulary = vocabulary
        self.client = client
        self.pasting = pasting
        self.microphone = microphone
        self.makePanel = panel
        self.history = history
        self.pauser = pauser
        self.pausesMedia = pausesMedia
        self.isEnabled = isEnabled
        self.durations = durations
        self.lockedLimit = lockedLimit
        self.now = now
    }

    // MARK: - The gesture

    /// Key down: the microphone opens and the panel shows what it hears. On
    /// a dictation locked by a tap, it's the press that finishes it.
    /// `output` is what the shortcut turns what is said into: each of the
    /// two has its own, which is why it arrives with the language rather
    /// than being read from the settings here. `heldFor` is how long the key
    /// was already down when the press reached here: a lone key arms first,
    /// and that time counts towards telling a hold from a tap.
    func keyDown(language: DictationLanguage, output: DictationOutput = .cleanup,
                 heldFor: TimeInterval = 0) {
        // Switched off in the Settings. The shortcuts are unregistered with
        // it, so this catches what still gets through: a lone key, or a
        // registration that outlived the switch.
        guard isEnabled() else { return }

        // Either shortcut ends a locked dictation, in the language it was
        // started in. The release that follows finds nothing listening.
        if let session, session.isLocked, session.phase == .listening {
            finishListening(session)
            return
        }
        dismiss()  // idempotent: a press during a cycle starts a fresh one

        // Same gate as a correction: without Accessibility nothing can be
        // pasted, so there is no point listening.
        guard pasting.isAllowed() else { return }

        // Then the microphone and speech recognition. Granted, this costs
        // nothing and the dictation starts on the press itself.
        // The first press on a machine that hasn't been asked yet only asks:
        // the prompts are modal and the key is long released by the time
        // they are answered, so the next press dictates. Same bargain as the
        // Accessibility gate.
        guard microphone.isGranted() else {
            permission = microphone.ask()
            return
        }
        beginListening(language: language, output: output, heldFor: heldFor)
    }

    /// Opens the microphone and puts the panel on screen.
    private func beginListening(language: DictationLanguage, output: DictationOutput,
                                heldFor: TimeInterval) {
        pressedAt = now() - heldFor
        // Captured BEFORE showing anything, while the app being dictated
        // into is still the frontmost one.
        target = pasting.capture()

        let session = DictationSession(language: language, model: model(), output: output,
                                       vocabulary: vocabulary())
        self.session = session
        panel = makePanel(session, self)
        cycle = Task { [weak self] in
            await self?.listen(session: session)
        }
        // Music talking over the voice is what makes dictation hard: what
        // plays pauses for as long as the microphone listens. Asked after the
        // microphone was sent on its way, which never waits for the answer.
        if pausesMedia() { pauser.pause() }
    }

    /// Key up: the microphone closes and the engine gets to say its last
    /// word. Too short a press is a tap, and the dictation locks instead.
    func keyUp() {
        // A locked dictation waits for a press, not a release; one already
        // finishing has nothing left to close.
        guard let session, session.phase == .listening, !session.isLocked else { return }
        guard now().timeIntervalSince(pressedAt) >= Self.shortPressThreshold else {
            lock(session)
            return
        }
        finishListening(session)
    }

    /// Esc, at any phase: the microphone is cancelled, the cycle dropped,
    /// nothing pasted. Nothing was written to the clipboard either — only
    /// the paste writes it, and it never ran. What was heard is kept in the
    /// history all the same: Esc means "don't paste", not "forget".
    func escape() { dismiss() }

    /// A lone modifier key held to dictate turned out to be the start of a
    /// combination: a key, another modifier or a click came while it was
    /// down (⌥( types "{"). Cancelled like Esc — nothing pasted, nothing
    /// remembered, the music back — but only while the key is what keeps the
    /// microphone open. A dictation locked hands-free, or one already
    /// finishing, was not started by this press, and carries on.
    func cancelHeld() {
        guard let session, session.phase == .listening, !session.isLocked else { return }
        dismiss()
    }

    /// A tap rather than a hold: holding a key through a long dictation is
    /// the hard part, so the microphone stays open without it. The words
    /// keep coming and the music stays paused; the next press finishes, Esc
    /// cancels, and the limit finishes it if neither comes.
    private func lock(_ session: DictationSession) {
        session.isLocked = true
        let limit = lockedLimit
        lockTimer = Task { [weak self] in
            try? await Task.sleep(for: limit)
            guard let self, !Task.isCancelled,
                  self.session === session, session.phase == .listening else { return }
            finishListening(session)
        }
    }

    /// The end of listening — a release, the press after a tap, or the
    /// limit: the microphone closes and the engine gets to say its last word.
    private func finishListening(_ session: DictationSession) {
        lockTimer?.cancel()
        lockTimer = nil
        session.phase = .finishing
        engine.stop()
        // After the microphone has closed, so the music coming back is never
        // heard as speech. The cleanup and the paste don't need silence.
        pauser.resume()
    }

    // MARK: - The cycle

    private func listen(session: DictationSession) async {
        // Cancelled between the press and the first turn of the loop: the
        // microphone must not even open.
        guard self.session === session else { return }

        for await event in engine.start(locale: session.language.locale,
                                        contextualStrings: session.vocabulary.terms) {
            guard self.session === session else { return }
            switch event {
            case .partial(let text), .final(let text):
                session.transcript = text
            case .level(let level):
                session.levels = session.levels.adding(level)
            case .failed(let error):
                // The message is read, not acted on: nothing was heard, so
                // the panel says why and closes itself like an empty one.
                keepWhatWasHeard(session)
                session.fail(with: error)
                // The panel stays up to be read; the music doesn't wait for it.
                pauser.resume()
                closeAfter(durations.failure, session: session)
                return
            }
        }
        // The stream ends after the final, and on a cancellation: only the
        // first of the two still has a session to finish.
        guard self.session === session, !Task.isCancelled else { return }
        await finish(session: session)
    }

    /// From the final transcript to the pasted text: fix the vocabulary,
    /// clean up, remember, paste.
    private func finish(session: DictationSession) async {
        // The stream is over, so is the microphone. A release or a press
        // resumed the music already; an engine that stopped by itself —
        // likelier minutes into a locked dictation — didn't, and the panel
        // may stay up with a text that has nowhere to go.
        pauser.resume()
        let heard = session.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !heard.isEmpty else {
            // A silence, a press on nothing: said rather than pasted.
            session.phase = .empty
            closeAfter(durations.empty, session: session)
            return
        }
        // The speaker's own spellings, before anything else reads the text:
        // the model cleans up what they wrote, Raw pastes it, and it is the
        // raw text the history keeps.
        let raw = session.vocabulary.applyingReplacements(to: heard)
        session.transcript = raw

        // Written down before the model is asked anything. Closing the panel
        // while the cleanup was under way used to take the whole dictation
        // with it: the words were said, they existed, and nothing had kept
        // them. The cleaned-up text joins this entry when it comes.
        guard let recordedAt = keepWhatWasHeard(session, raw: raw) else { return }

        var cleaned: String?
        if session.model != .raw {
            session.phase = .cleaning
            // Where the text is heading was captured on the press, with the
            // app itself: a Slack message, an email and a command line aren't
            // cleaned up the same way — and the last one not at all.
            cleaned = await cleanUp(raw,
                                    keeping: session.vocabulary.terms,
                                    landingIn: target.map {
                                        DictationDestination(name: $0.appName,
                                                             bundleID: $0.appBundleID)
                                    },
                                    session: session)
            guard self.session === session, !Task.isCancelled else { return }
        }

        // The other half of the entry, now that there is one. Before the
        // paste, as the transcript was: whether or not the text made it into
        // the app, it was said, and the history keeps it.
        if let cleaned { history.complete(cleaned: cleaned, at: recordedAt) }

        // Nowhere to paste: Claudio itself was frontmost when the key went
        // down — the cursor in its own prompt editor, say. The keystroke
        // isn't sent at all, since it would land in whatever has focus now:
        // the panel keeps the text instead, with Copy as the way out.
        guard let target, target.app != nil else {
            session.phase = .done
            return
        }

        session.phase = .pasting
        let text = cleaned ?? raw
        // The panel leaves the screen before the keystroke, as
        // `CorrectionCoordinator.pasteResult()` does: it is a key window
        // while it is up, and a ⌘V sent to it pastes into Claudio.
        dismiss()
        // In a task of its own, because `dismiss()` cancelled this one and a
        // cancelled task turns the paste's activation delay into no delay.
        await Task { [weak self] in
            await self?.pasting.paste(text, target)
        }.value
    }

    /// Runs the single model pass and returns its text, `nil` when there was
    /// none: the transcript is then what gets pasted, and the panel says why.
    /// What the dictation becomes — cleaned up, translated, turned into a
    /// prompt — is the session's output: one call, whichever it is.
    /// `terms` are the spellings the model is told to keep, `destination` the
    /// app the text is about to land in — its name, and whether it is a place
    /// for prose at all.
    private func cleanUp(_ raw: String,
                         keeping terms: [String],
                         landingIn destination: DictationDestination?,
                         session: DictationSession) async -> String? {
        guard let client = client(session.model) else {
            session.note = pastedWithoutCleanup(loc("clé API manquante", en: "no API key"))
            return nil
        }
        let outcome = await client.complete(
            session.output.userMessage(for: raw),
            system: session.output.systemPrompt(keeping: terms, landingIn: destination),
            maxTokens: session.output.maxTokens(forRawLength: raw.count),
            model: session.model
        ) { piece in session.appendCleaned(piece) }
        switch outcome {
        case .cancelled:
            return nil
        case .failed(let error):
            // The dictation is never lost: the cleanup is what failed.
            session.cleanedText = ""
            session.note = pastedWithoutCleanup(error.localizedDescription)
            return nil
        case .answered(let result):
            let cleaned = DictationCleanup.strippingTranscriptTags(result.text)
            guard !cleaned.isEmpty else {
                session.cleanedText = ""
                session.note = pastedWithoutCleanup(loc("réponse vide du modèle",
                                                        en: "the model answered nothing"))
                return nil
            }
            // A model that answered the dictation instead of cleaning it up:
            // what was said is pasted, not its reply.
            guard session.output != .cleanup
                    || CleanupPlausibility.isCleanup(cleaned, of: raw) else {
                session.cleanedText = ""
                session.note = pastedWithoutCleanup(loc("le modèle a répondu au lieu de nettoyer",
                                                        en: "the model answered instead of cleaning up"))
                return nil
            }
            session.cleanedText = cleaned
            return cleaned
        }
    }

    /// Writes what was heard into the history, once per dictation, without
    /// pasting it. Every end goes through here: the transcript finished, and
    /// every way a dictation stops before that — Esc, the close button, a
    /// click under a held ⌥, a new press, the engine giving up. The words on
    /// screen were said; "Recent dictations" is where they wait.
    /// `raw` is the transcript once the replacements are applied, when the
    /// caller has it already; otherwise they are applied here, once.
    /// Returns the entry's date, `nil` when nothing was heard.
    @discardableResult
    private func keepWhatWasHeard(_ session: DictationSession, raw: String? = nil) -> Date? {
        if let recordedAt { return recordedAt }
        let heard = session.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !heard.isEmpty else { return nil }
        let date = now()
        recordedAt = date
        history.record(raw: raw ?? session.vocabulary.applyingReplacements(to: heard),
                       cleaned: nil, language: session.language, at: date)
        return date
    }

    private func pastedWithoutCleanup(_ reason: String) -> String {
        loc("Collé sans nettoyage : \(reason)", en: "Pasted without cleanup: \(reason)")
    }

    /// The panel has said its piece — "Nothing heard", or why the dictation
    /// stopped — and takes itself off the screen. Esc and the next press cut
    /// it short: both call `dismiss()`, and the session no longer being this
    /// one is what makes the sleeping task harmless.
    private func closeAfter(_ delay: Duration, session: DictationSession) {
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard self?.session === session else { return }
            self?.dismiss()
        }
    }

    // MARK: - The panel

    /// The real panel, wired to this coordinator: Esc and ⌘C reach it, and
    /// closing it cancels the dictation.
    static func systemPanel(for session: DictationSession,
                            coordinator: DictationCoordinator) -> ResultPanel? {
        ResultPanel.make(
            session: session,
            onCopy: { [weak coordinator] in coordinator?.copyText() },
            onClose: { [weak coordinator] in coordinator?.escape() }
        )
    }

    /// Copies what the panel shows: the way out when the paste had nowhere
    /// to go.
    func copyText() {
        guard let session, session.canCopy else { return }
        NSPasteboard.general.setText(session.finalText)
        session.justCopied = true
        Task { [weak self] in
            try? await Task.sleep(for: Constants.closeAfterCopyDelay)
            guard self?.session === session, session.justCopied else { return }
            self?.dismiss()
        }
    }

    /// Closes the panel and drops the cycle. Idempotent: cancelling a
    /// finished engine does nothing. Nothing is pasted, and what was heard
    /// stays in the history.
    func dismiss() {
        if let session { keepWhatWasHeard(session) }
        cycle?.cancel()
        cycle = nil
        lockTimer?.cancel()
        lockTimer = nil
        // The prompts can't be taken back, but the explanation that follows
        // them can: a press that starts a new chain drops the old one rather
        // than letting two alerts pile up on the same refusal.
        permission?.cancel()
        permission = nil
        // Only a dictation under way has a microphone to close.
        if session != nil { engine.cancel() }
        // Every way out of a dictation ends here or in `finishListening(_:)`,
        // quitting included: what was paused resumes whatever happened, and
        // nothing does when nothing was.
        pauser.resume()
        panel?.orderOut(nil)
        panel = nil
        session = nil
        target = nil
        recordedAt = nil
    }
}
