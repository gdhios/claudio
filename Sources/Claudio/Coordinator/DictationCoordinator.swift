import AppKit

/// The dictation cycle: hold the shortcut, speak, release, and the text
/// lands where the cursor was. `CorrectionCoordinator`'s counterpart — same
/// panel, same paste path — except the material comes from a microphone
/// instead of a selection.
///
/// Everything that touches the outside world arrives through `init`: the
/// engine, the model behind the cleanup, the paste, the panel, the clock.
/// The whole cycle is then playable without a microphone, a network, a
/// pasteboard or a screen.
@MainActor
final class DictationCoordinator {
    /// A press shorter than this isn't speech: a slip of the finger, or a
    /// shortcut meant for something else. Nothing is pasted.
    static let shortPressThreshold: TimeInterval = 0.3
    /// How long "Nothing heard" stays on screen before the panel closes.
    static let emptyPanelDuration: Duration = .milliseconds(1500)

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
    private let now: @MainActor () -> Date

    private var panel: ResultPanel?
    private var target: PasteTarget?
    private var pressedAt = Date.distantPast

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
         now: @escaping @MainActor () -> Date = Date.init) {
        self.engine = engine
        self.model = model
        self.client = client
        self.pasting = pasting
        self.microphone = microphone
        self.makePanel = panel
        self.history = history
        self.now = now
    }

    // MARK: - The gesture

    /// Key down: the microphone opens and the panel shows what it hears.
    func keyDown(language: DictationLanguage) {
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
            guard let self, await !microphone.request() else { return }
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
        cycle = Task { [weak self] in
            await self?.listen(session: session)
        }
    }

    /// Key up: the microphone closes and the engine gets to say its last
    /// word. Too short a press, and the whole thing is dropped.
    func keyUp() {
        guard let session, session.phase == .listening else { return }
        guard now().timeIntervalSince(pressedAt) >= Self.shortPressThreshold else {
            dismiss()
            return
        }
        session.phase = .finishing
        engine.stop()
    }

    /// Esc, at any phase: the microphone is cancelled, the cycle dropped,
    /// nothing pasted. Nothing was written to the clipboard either — only
    /// the paste writes it, and it never ran.
    func escape() { dismiss() }

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
            case .failed(let error):
                session.phase = .error(error.localizedDescription)
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
        let raw = session.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            // A silence, a press on nothing: said rather than pasted.
            session.phase = .empty
            closeAfterNothingHeard(session)
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

        session.phase = .pasting
        let landed = await pasting.paste(cleaned ?? raw, target ?? PasteTarget())
        guard self.session === session else { return }
        guard landed else {
            // Nowhere to paste: the panel stays open with Copy rather than
            // dropping the text into nothing.
            session.phase = .done
            return
        }
        dismiss()
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

    /// "Nothing heard" is read in a second, then the panel takes itself off
    /// the screen.
    private func closeAfterNothingHeard(_ session: DictationSession) {
        Task { [weak self] in
            try? await Task.sleep(for: Self.emptyPanelDuration)
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
        // Only a dictation under way has a microphone to close.
        if session != nil { engine.cancel() }
        panel?.orderOut(nil)
        panel = nil
        session = nil
        target = nil
    }
}
