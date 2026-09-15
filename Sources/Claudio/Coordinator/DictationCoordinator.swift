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
    /// otherwise keep the microphone open, and the other apps quiet, for as
    /// long as Claudio runs.
    nonisolated static let longestLockedDictation: Duration = .seconds(5 * 60)

    /// How long a panel that has nothing left to do but speak stays on
    /// screen. Injected so a test can watch one close itself without waiting
    /// four seconds for it.
    struct MessageDurations: Sendable {
        /// "Nothing heard": a glance is enough.
        var empty: Duration = .milliseconds(1500)
        /// A failure: long enough to read a sentence and reach the button it
        /// may carry, short enough that the panel doesn't outlive the
        /// dictation. Esc and the next press still cut it short.
        var failure: Duration = .seconds(4)

        static let standard = MessageDurations()
    }

    /// Builds the client that answers for a model, `nil` when none can: the
    /// Claude key is missing, or the choice names no model at all.
    typealias ClientFactory = @MainActor (ModelChoice) -> TextStreamClient?
    /// Puts the session on screen and hands back the panel to keep. `nil`
    /// when there is no screen to put it on.
    typealias PanelMaker = @MainActor (DictationSession, DictationCoordinator) -> ResultPanel?

    private let engine: SpeechEngine
    private let model: @MainActor () -> ModelChoice
    private let client: ClientFactory
    private let pasting: PasteService
    private let microphone: MicrophoneGate
    private let makePanel: PanelMaker
    private let history: DictationHistory
    private let silencer: OutputSilencer
    private let mutesOutput: @MainActor () -> Bool
    private let durations: MessageDurations
    /// `longestLockedDictation`, unless a test can't wait five minutes.
    private let lockedLimit: Duration
    private let now: @MainActor () -> Date

    private var panel: ResultPanel?
    private var target: PasteTarget?
    private var pressedAt = Date.distantPast
    /// Finishes a locked dictation at its limit. Runs from the tap, and is
    /// cancelled by whatever ends the dictation first.
    private var lockTimer: Task<Void, Never>?

    /// The dictation under way, `nil` between two.
    private(set) var session: DictationSession?
    /// The task that listens then finishes: cancelled by Esc and by the next
    /// press.
    private(set) var cycle: Task<Void, Never>?
    /// The task asking for the microphone, on the first press only. `nil`
    /// whenever the permissions are already there.
    private(set) var permission: Task<Void, Never>?

    init(engine: SpeechEngine,
         model: @escaping @MainActor () -> ModelChoice = { AppSettings.dictationModel },
         client: @escaping ClientFactory = TextStreamClientFactory.make(for:),
         pasting: PasteService = .system,
         microphone: MicrophoneGate = .system,
         panel: @escaping PanelMaker = DictationCoordinator.systemPanel,
         history: DictationHistory = .shared,
         silencer: OutputSilencer = .system,
         mutesOutput: @escaping @MainActor () -> Bool = { AppSettings.dictationMutesOutput },
         durations: MessageDurations = .standard,
         lockedLimit: Duration = DictationCoordinator.longestLockedDictation,
         now: @escaping @MainActor () -> Date = Date.init) {
        self.engine = engine
        self.model = model
        self.client = client
        self.pasting = pasting
        self.microphone = microphone
        self.makePanel = panel
        self.history = history
        self.silencer = silencer
        self.mutesOutput = mutesOutput
        self.durations = durations
        self.lockedLimit = lockedLimit
        self.now = now
    }

    // MARK: - The gesture

    /// Key down: the microphone opens and the panel shows what it hears. On
    /// a dictation locked by a tap, it's the press that finishes it.
    func keyDown(language: DictationLanguage) {
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
        guard microphone.isGranted() else {
            askForTheMicrophone()
            return
        }
        beginListening(language: language)
    }

    /// The first press, on a machine that hasn't been asked yet: the two
    /// system prompts, then the explanation if either is refused. Nothing is
    /// listened to here — the prompts are modal and the key is long released
    /// by the time they are answered, so this press asks and the next one
    /// dictates. Same bargain as the Accessibility gate.
    private func askForTheMicrophone() {
        permission = Task { [weak self] in
            // Cancelled between the press and the first turn of the loop:
            // a newer press owns the prompts, and this one asks nothing.
            guard let self, !Task.isCancelled else { return }
            let granted = await microphone.request()
            // The prompts are modal, so a second press lands here long
            // before the answer does. Only the last chain explains itself:
            // two alerts stacked on the same refusal is what `dismiss()`
            // cancelling this task is for.
            guard !Task.isCancelled, !granted else { return }
            microphone.showExplanation()
        }
    }

    /// Opens the microphone and puts the panel on screen.
    private func beginListening(language: DictationLanguage) {
        pressedAt = now()
        // Captured BEFORE showing anything, while the app being dictated
        // into is still the frontmost one.
        target = pasting.capture()

        let session = DictationSession(language: language, model: model())
        self.session = session
        panel = makePanel(session, self)
        // Music talking over the voice is what makes dictation hard: the
        // other apps go quiet for as long as the microphone listens.
        if mutesOutput() { silencer.silence() }
        cycle = Task { [weak self] in
            await self?.listen(session: session)
        }
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
    /// the paste writes it, and it never ran.
    func escape() { dismiss() }

    /// A tap rather than a hold: holding a key through a long dictation is
    /// the hard part, so the microphone stays open without it. The words
    /// keep coming and the other apps stay quiet; the next press finishes,
    /// Esc cancels, and the limit finishes it if neither comes.
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
        // After the microphone has closed, so the returning sound is never
        // heard as speech. The cleanup doesn't need silence.
        silencer.restore()
    }

    // MARK: - The cycle

    private func listen(session: DictationSession) async {
        // Cancelled between the press and the first turn of the loop: the
        // microphone must not even open.
        guard self.session === session else { return }

        for await event in engine.start(locale: session.language.locale) {
            guard self.session === session else { return }
            switch event {
            case .partial(let text), .final(let text):
                session.transcript = text
            case .level(let level):
                session.levels = session.levels.adding(level)
            case .failed(let error):
                // The message is read, not acted on: nothing was heard, so
                // the panel says why and closes itself like an empty one.
                session.fail(with: error)
                // The panel stays up to be read; the sound doesn't wait for it.
                silencer.restore()
                closeAfter(durations.failure, session: session)
                return
            }
        }
        // The stream ends after the final, and on a cancellation: only the
        // first of the two still has a session to finish.
        guard self.session === session, !Task.isCancelled else { return }
        await finish(session: session)
    }

    /// From the final transcript to the pasted text: clean up, remember,
    /// paste.
    private func finish(session: DictationSession) async {
        // The stream is over, so is the microphone. A release or a press
        // gave the sound back already; an engine that stopped by itself —
        // likelier minutes into a locked dictation — didn't, and the panel
        // may stay up with a text that has nowhere to go.
        silencer.restore()
        let raw = session.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            // A silence, a press on nothing: said rather than pasted.
            session.phase = .empty
            closeAfter(durations.empty, session: session)
            return
        }
        session.transcript = raw

        var cleaned: String?
        if session.model != .raw {
            session.phase = .cleaning
            cleaned = await cleanUp(raw, session: session)
            guard self.session === session, !Task.isCancelled else { return }
        }

        // Recorded before the paste: whether or not the text made it into
        // the app, it was said, and the history keeps it.
        history.record(raw: raw, cleaned: cleaned, language: session.language)

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
            _ = await self?.pasting.paste(text, target)
        }.value
    }

    /// Runs the cleanup pass and returns its text, `nil` when there was
    /// none: the transcript is then what gets pasted, and the panel says why.
    private func cleanUp(_ raw: String, session: DictationSession) async -> String? {
        guard let client = client(session.model) else {
            session.note = pastedWithoutCleanup(loc("clé API manquante", en: "no API key"))
            return nil
        }
        do {
            let result = try await client.streamCompletion(
                of: raw,
                system: DictationCleanup.systemPrompt,
                maxTokens: DictationCleanup.maxTokens(forRawLength: raw.count)
            ) { @MainActor piece in
                session.appendCleaned(piece)
            }
            guard !Task.isCancelled else { return nil }
            CostLedger.shared.record(model: session.model,
                                     inputTokens: result.inputTokens,
                                     outputTokens: result.outputTokens)
            let cleaned = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else {
                session.cleanedText = ""
                session.note = pastedWithoutCleanup(loc("réponse vide du modèle",
                                                        en: "the model answered nothing"))
                return nil
            }
            session.cleanedText = cleaned
            return cleaned
        } catch is CancellationError {
            return nil
        } catch let error as URLError where error.code == .cancelled {
            return nil
        } catch {
            guard !Task.isCancelled else { return nil }
            // The dictation is never lost: the cleanup is what failed.
            session.cleanedText = ""
            session.note = pastedWithoutCleanup(error.localizedDescription)
            return nil
        }
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
        let panel = ResultPanel.make(
            session: session,
            onCopy: { [weak coordinator] in coordinator?.copyText() },
            onClose: { [weak coordinator] in coordinator?.escape() }
        )
        panel.onEscape = { [weak coordinator] in coordinator?.escape() }
        panel.onCopyShortcut = { [weak coordinator] in coordinator?.copyText() }
        panel.present()
        return panel
    }

    /// Copies what the panel shows: the way out when the paste had nowhere
    /// to go.
    func copyText() {
        guard let session, !session.finalText.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(session.finalText, forType: .string)
        session.justCopied = true
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard self?.session === session, session.justCopied else { return }
            self?.dismiss()
        }
    }

    /// Closes the panel and drops the cycle. Idempotent: cancelling a
    /// finished engine does nothing.
    func dismiss() {
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
        // Every way out of a dictation ends here or in `finishListening(_:)`:
        // the sound comes back whatever happened. Harmless when nothing was
        // silenced.
        silencer.restore()
        panel?.orderOut(nil)
        panel = nil
        session = nil
        target = nil
    }
}
