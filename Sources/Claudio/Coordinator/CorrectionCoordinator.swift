import AppKit
import SwiftUI

/// Orchestrates the full cycle: capture, stream, panel, paste.
///
/// Everything that touches the outside world arrives through `init`: the
/// permission and the paste, the selection, the model, the panel, the
/// history. The whole cycle is then playable without Accessibility, a
/// pasteboard, a network or a screen.
@MainActor
final class CorrectionCoordinator {
    /// Puts the session on screen and hands back the panel to keep. `nil`
    /// when there is no screen to put it on.
    typealias PanelMaker = @MainActor (CorrectionSession, CorrectionCoordinator) -> ResultPanel?

    var openSettings: (() -> Void)?
    /// The palette's "What's playing?" row. Not a request about the
    /// selection: it opens a panel of its own, which is the one to take this
    /// panel off the screen — the app hangs `ListeningCoordinator.trigger()`
    /// here.
    var openWhatsPlaying: (() -> Void)?
    /// Called whenever the panel leaves the screen, for whatever reason:
    /// Esc, another shortcut, a paste. A spoken instruction hangs its own
    /// ending on it — a microphone left open behind a closed panel would go
    /// on listening, and the other apps would stay quiet.
    var onDismiss: (() -> Void)?
    /// Called when the correction under way changes, the end of one included.
    /// What watches from outside — the Stream Deck bridge — can't poll for a
    /// panel, and reads the session through this.
    ///
    /// A broadcast, and nothing more: it fires mid-mutation — before
    /// `streamTask` is assigned, before `onDismiss` runs — so the callback
    /// must never synchronously call back into the coordinator. It reports
    /// identity alone: a phase moving inside a session that is still the same
    /// one doesn't fire it, and whoever needs that observes the session's own
    /// `@Published` properties.
    var onSessionChange: ((CorrectionSession?) -> Void)?

    private var panel: ResultPanel?
    private(set) var session: CorrectionSession? {
        didSet {
            guard oldValue !== session else { return }  // a dismissal over nothing says nothing
            onSessionChange?(session)
        }
    }
    /// Captures, then streams: cancelled by Esc, by the next shortcut, and
    /// by whatever sends the request again.
    private(set) var streamTask: Task<Void, Never>?
    /// Where the result goes back to: the app in front and the clipboard, as
    /// they were when the shortcut was pressed.
    private var target: PasteTarget?
    /// How long a panel that has nothing left to say stays up. Injected so a
    /// test can watch one close itself without waiting a second and a half.
    private let durations: DictationCoordinator.MessageDurations
    private let pasting: PasteService
    private let captureSelection: @MainActor () async -> String?
    private let makeClient: DictationCoordinator.ClientFactory
    private let makePanel: PanelMaker
    private let history: TransformHistory

    init(durations: DictationCoordinator.MessageDurations = .standard,
         pasting: PasteService = .system,
         selection: @escaping @MainActor () async -> String? = SelectionCapture.capture,
         client: @escaping DictationCoordinator.ClientFactory = TextStreamClientFactory.make(for:),
         panel: @escaping PanelMaker = CorrectionCoordinator.systemPanel,
         history: TransformHistory = .shared) {
        self.durations = durations
        self.pasting = pasting
        self.captureSelection = selection
        self.makeClient = client
        self.makePanel = panel
        self.history = history
    }

    // MARK: - Triggering

    /// Catalog entry: global shortcut or menu item.
    func trigger(action: ClaudioAction) {
        trigger(action.request)
    }

    /// Custom action: same cycle, with a stop to type the instruction between
    /// capturing the selection and calling the API. With nothing selected
    /// the same stop comes, and the instruction goes out as a request that
    /// Claude answers.
    func triggerFreeAction() {
        trigger(.awaitingInstruction)
    }

    /// Same custom action, with its instruction about to be spoken rather
    /// than typed: same capture, same panel, except it opens listening —
    /// over a selection or over nothing, as when it's typed. Hands back the
    /// session the words land in, `nil` when nothing opened.
    func beginSpokenInstruction() -> CorrectionSession? {
        trigger(.awaitingInstruction, listening: true)
    }

    /// Palette: the selection is captured first, the action is chosen
    /// afterward in the panel. The starting request is just filler.
    func triggerPalette() {
        trigger(.awaitingChoice, opensPalette: true)
    }

    /// Instruction relaunched from history: same cycle as a custom action,
    /// but the instruction is already known, so no stop to type it: the
    /// capture targets the current selection and the stream starts right
    /// away — as a request, when nothing is selected.
    func triggerRecent(instruction: String) {
        trigger(.free(instruction: instruction))
    }

    /// `listening` is the custom action whose instruction is being spoken:
    /// the panel opens on the waveform instead of the field.
    @discardableResult
    func trigger(_ request: ClaudioRequest,
                 opensPalette: Bool = false,
                 listening: Bool = false) -> CorrectionSession? {
        dismiss()  // idempotent: a shortcut while a panel is open starts fresh

        // Asks for Accessibility, and explains itself, when it's missing:
        // without it nothing can be read, nor pasted back.
        guard pasting.isAllowed() else { return nil }

        // Captured BEFORE showing anything.
        target = pasting.capture()

        let session = CorrectionSession(request: request, opensPalette: opensPalette)
        if listening { session.phase = .listeningInstruction }
        self.session = session

        streamTask = Task { [weak self] in
            await self?.runCorrection(session: session)
        }
        return session
    }

    private func runCorrection(session: CorrectionSession) async {
        // Capture BEFORE showing the panel: once key, the panel would
        // intercept the simulated ⌘C meant for the source app.
        let text = await captureSelection()
        guard self.session === session else { return }  // re-triggered/closed in the meantime
        panel = makePanel(session, self)

        // Blank is nothing selected. The custom action carries on all the
        // same: its instruction becomes a request made to Claudio.
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            session.originalText = text
        }

        // Something to wait for before sending: "No selection found", which
        // closes itself; a palette row, whose launch resumes from
        // `launchPaletteRow(at:)`; the custom action's instruction, from
        // `submitInstruction()`. A spoken one is already being listened to.
        if let phase = session.phaseAfterCapture {
            if session.phase != phase { session.phase = phase }
            autoDismiss(session)
            return
        }
        await stream(session: session)
    }

    /// The instruction was spoken rather than typed: it lands in the session
    /// as if it had been, and the custom action carries on in the same panel.
    func runSpokenInstruction(_ instruction: String) {
        guard let session, session.phase == .listeningInstruction else { return }
        session.instruction = instruction
        submitInstruction()
    }

    /// Instruction validated in the panel: the custom request is built here,
    /// then follows the common path.
    func submitInstruction() {
        guard let session, session.isEnteringInstruction else { return }
        let instruction = session.trimmedInstruction
        guard !instruction.isEmpty else { return }

        session.adopt(.free(instruction: instruction))
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            await self?.stream(session: session)
        }
    }

    // MARK: - Palette

    /// Row picked in the palette: its request becomes the session's own.
    /// A custom action with no instruction stops at the text field instead
    /// of launching with an empty instruction.
    private func choose(_ request: ClaudioRequest) {
        guard let session, session.phase == .choosingAction else { return }
        session.adopt(request)

        guard !request.needsInstruction else {
            session.phase = .askingInstruction
            return
        }
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            await self?.stream(session: session)
        }
    }

    func launchPaletteRow(at index: Int) {
        guard let session, session.phase == .choosingAction else { return }
        let rows = session.paletteRows
        // The custom action's row is always there, whatever was typed: this
        // only keeps a stale index from launching anything.
        guard rows.indices.contains(index) else { return }
        session.paletteSelection = index
        switch rows[index].kind {
        case .request(let origin):
            choose(PaletteRow.request(for: origin))
        case .whatsPlaying:
            // This session ends here, closed by the panel that takes over:
            // nothing of it is touched past this call.
            openWhatsPlaying?()
        }
    }

    /// Arrows: only consumes the key when the palette is open, otherwise
    /// it keeps going and scrolls a long result.
    private func movePaletteSelection(by delta: Int) -> Bool {
        guard let session, session.phase == .choosingAction else { return false }
        session.movePaletteSelection(by: delta)
        return true
    }

    /// Digits: launches the row at that rank when the keystroke actually names it.
    private func launchPaletteRank(_ rank: Int, withCommand: Bool) -> Bool {
        guard let session,
              let index = session.paletteIndex(forRank: rank, withCommand: withCommand)
        else { return false }
        launchPaletteRow(at: index)
        return true
    }

    private func stream(session: CorrectionSession) async {
        let request = session.request

        // The action's engine decides the client. The API key is only
        // missing for Claude: an action set to local works without a key.
        let client: TextStreamClient
        switch request.model {
        case .claude, .ollama:
            guard let made = makeClient(request.model) else {
                session.phase = .missingKey
                return
            }
            client = made
        case .raw:
            // "Raw" means "no cleanup pass" and only dictation offers it: a
            // transform has nothing to answer with. Only a hand-edited
            // setting can land here.
            session.phase = .error(loc("« Brut » ne s'applique qu'à la dictée : choisis un modèle pour cette action.",
                                       en: "“Raw” only applies to dictation: pick a model for this action."))
            return
        }
        // With nothing selected, the custom action is answered rather than
        // applied: the request's own prompt, the instruction in place of a text.
        let prompt = request.prompt(forText: session.originalText)
        session.beginStreaming()

        do {
            let result = try await client.streamCompletion(
                of: prompt.userMessage,
                system: prompt.system,
                maxTokens: request.maxTokens(forText: session.originalText,
                                             multiplier: session.maxTokensMultiplier)
            ) { @MainActor piece in
                session.appendStreamed(piece)
            }
            guard !Task.isCancelled else { return }
            session.finishStreaming(with: result.text, truncated: result.truncated)
            // A custom action that succeeds enters the history: its
            // instruction can be relaunched with one gesture from the menu bar.
            if case .free(let instruction) = request.origin {
                history.record(instruction)
            }
            CostLedger.shared.record(model: request.model,
                                     inputTokens: result.inputTokens,
                                     outputTokens: result.outputTokens)
        } catch is CancellationError {
            // Esc during the stream: nothing to do
        } catch let error as URLError where error.code == .cancelled {
            // same thing, URLSession reports cancellation this way
        } catch {
            guard !Task.isCancelled else { return }
            session.phase = .error(error.localizedDescription)
        }
    }

    // MARK: - Panel actions

    /// Enter: launches the row picked in the palette, validates the
    /// instruction while it's being typed, pastes the result otherwise.
    func confirm() {
        switch session?.phase {
        case .choosingAction:
            launchPaletteRow(at: session?.paletteSelection ?? 0)
        case .askingInstruction:
            submitInstruction()
        default:
            pasteResult()
        }
    }

    /// "Try again", or "Try again +" once an answer was cut short: the same
    /// request goes out again, with twice the room in the second case.
    ///
    /// Never a second capture: the panel is up and key by now, and the
    /// simulated ⌘C would land in it. The selection was read once, before
    /// the panel opened — and with nothing selected there is nothing to read.
    func retry() {
        guard let session else { return }
        if session.truncated {
            session.maxTokensMultiplier = min(session.maxTokensMultiplier * 2, 4)
        }
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            await self?.stream(session: session)
        }
    }

    func copyResult() {
        guard let session, !session.correctedText.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(session.correctedText, forType: .string)
        session.justCopied = true
        target?.clipboard = nil  // the user wants this content: don't restore over it
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            if self?.session === session, session.justCopied {
                self?.dismiss()
            }
        }
    }

    func pasteResult() {
        // The target is captured with the session, and goes with it.
        guard let session, session.canPaste, let target else { return }
        let text = session.correctedText
        dismiss()

        Task { @MainActor [pasting] in
            _ = await pasting.paste(text, target)
        }
    }

    // MARK: - Panel

    /// The real panel, wired to this coordinator: the keyboard reaches it,
    /// and each of its buttons lands here.
    static func systemPanel(for session: CorrectionSession,
                            coordinator: CorrectionCoordinator) -> ResultPanel? {
        let panel = ResultPanel.make(
            session: session,
            onPaste: { [weak coordinator] in coordinator?.pasteResult() },
            onCopy: { [weak coordinator] in coordinator?.copyResult() },
            onRetry: { [weak coordinator] in coordinator?.retry() },
            onSubmitInstruction: { [weak coordinator] in coordinator?.submitInstruction() },
            onLaunchPaletteRow: { [weak coordinator] index in coordinator?.launchPaletteRow(at: index) },
            onOpenSettings: { [weak coordinator] in
                coordinator?.dismiss()
                coordinator?.openSettings?()
            },
            onClose: { [weak coordinator] in coordinator?.dismiss() }
        )
        panel.onEnter = { [weak coordinator] in coordinator?.confirm() }
        panel.onEscape = { [weak coordinator] in coordinator?.dismiss() }
        panel.onCopyShortcut = { [weak coordinator] in coordinator?.copyResult() }
        panel.onArrow = { [weak coordinator] delta in coordinator?.movePaletteSelection(by: delta) ?? false }
        panel.onDigit = { [weak coordinator] rank, withCommand in
            coordinator?.launchPaletteRank(rank, withCommand: withCommand) ?? false
        }
        panel.present()
        return panel
    }

    /// The panel has said all it had to say — "No selection found", so far —
    /// and takes itself off the screen after a beat. Esc and the next
    /// shortcut still cut it short: both go through `dismiss()`, and the
    /// guards here are what make the sleeping task harmless afterwards.
    ///
    /// The phase is held as well as the session: `retry()` and the palette
    /// carry on inside the same session, so a close armed in an earlier phase
    /// would take away a panel that is streaming by the time it fires.
    private func autoDismiss(_ session: CorrectionSession) {
        guard let delay = session.phase.autoDismissDelay(durations) else { return }
        let phase = session.phase
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, self.session === session, session.phase == phase else { return }
            self.dismiss()
        }
    }

    func dismiss() {
        streamTask?.cancel()
        streamTask = nil
        panel?.orderOut(nil)
        panel = nil
        session = nil
        target = nil
        onDismiss?()
    }
}
