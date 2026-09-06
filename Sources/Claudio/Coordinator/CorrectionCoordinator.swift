import AppKit
import SwiftUI

/// Orchestrates the full cycle: capture, stream, panel, paste.
@MainActor
final class CorrectionCoordinator {
    var openSettings: (() -> Void)?

    private var panel: ResultPanel?
    private var session: CorrectionSession?
    private var streamTask: Task<Void, Never>?
    private var previousApp: NSRunningApplication?
    private var clipboardSnapshot: PasteboardSnapshot?

    // MARK: - Triggering

    /// Catalog entry: global shortcut or menu item.
    func trigger(action: ClaudioAction) {
        trigger(action.request)
    }

    /// Custom action: same cycle, with a stop to type the instruction between
    /// capturing the selection and calling the API.
    func triggerFreeAction() {
        trigger(.awaitingInstruction)
    }

    /// Palette: the selection is captured first, the action is chosen
    /// afterward in the panel. The starting request is just filler.
    func triggerPalette() {
        trigger(.awaitingChoice, opensPalette: true)
    }

    /// Instruction relaunched from history: same cycle as a custom action,
    /// but the instruction is already known, so no stop to type it: the
    /// capture targets the current selection and the stream starts right away.
    func triggerRecent(instruction: String) {
        trigger(.free(instruction: instruction))
    }

    func trigger(_ request: ClaudioRequest, opensPalette: Bool = false) {
        dismiss()  // idempotent: a shortcut while a panel is open starts fresh

        guard AccessibilityPermission.isGranted else {
            AccessibilityPermission.request()
            AccessibilityPermission.showExplanation()
            return
        }

        // Captured BEFORE showing anything.
        let frontmost = NSWorkspace.shared.frontmostApplication
        previousApp = (frontmost?.bundleIdentifier == Bundle.main.bundleIdentifier) ? nil : frontmost
        clipboardSnapshot = PasteboardSnapshot.capture()

        let session = CorrectionSession(request: request, opensPalette: opensPalette)
        self.session = session

        streamTask = Task { [weak self] in
            await self?.runCorrection(session: session)
        }
    }

    private func runCorrection(session: CorrectionSession) async {
        // Capture BEFORE showing the panel: once key, the panel would
        // intercept the simulated ⌘C meant for the source app.
        let text = await SelectionCapture.capture()
        guard self.session === session else { return }  // re-triggered/closed in the meantime
        showPanel(for: session)

        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            session.phase = .noSelection
            return
        }
        session.originalText = text

        // Palette: nothing to send until a row is picked.
        // The rest resumes from `launchPaletteRow(at:)`.
        guard !session.opensPalette else {
            session.phase = .choosingAction
            return
        }

        // Custom action: nothing to send until the instruction is typed.
        // The rest resumes from `submitInstruction()`.
        guard !session.request.needsInstruction else {
            session.phase = .askingInstruction
            return
        }
        await stream(session: session)
    }

    /// Instruction validated in the panel: the custom request is built here,
    /// then follows the common path.
    func submitInstruction() {
        guard let session, session.phase == .askingInstruction else { return }
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
        guard rows.indices.contains(index) else { return }
        session.paletteSelection = index
        choose(rows[index].request)
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
        case .claude(let model):
            guard let apiKey = KeychainStore.currentAPIKey() else {
                session.phase = .missingKey
                return
            }
            client = AnthropicClient(apiKey: apiKey,
                                     workspaceID: AppSettings.currentWorkspaceID(),
                                     model: model)
        case .ollama(let name):
            client = OllamaClient(baseURL: AppSettings.ollamaBaseURL, model: name)
        }
        session.beginStreaming()

        do {
            let result = try await client.streamCompletion(
                of: request.userMessage(forText: session.originalText),
                system: request.system,
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
                TransformHistory.shared.record(instruction)
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

    func retry() {
        guard let session else { return }
        if session.truncated {
            session.maxTokensMultiplier = min(session.maxTokensMultiplier * 2, 4)
        }
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            guard let self else { return }
            if session.originalText.isEmpty {
                await self.runCorrection(session: session)
            } else {
                await self.stream(session: session)
            }
        }
    }

    func copyResult() {
        guard let session, !session.correctedText.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(session.correctedText, forType: .string)
        session.justCopied = true
        clipboardSnapshot = nil  // the user wants this content: don't restore over it
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            if self?.session === session, session.justCopied {
                self?.dismiss()
            }
        }
    }

    func pasteResult() {
        guard let session, session.canPaste else { return }
        let text = session.correctedText
        let target = previousApp
        let snapshot = Constants.restoreClipboardAfterPaste ? clipboardSnapshot : nil
        dismiss()

        Task { @MainActor in
            target?.activate()
            try? await Task.sleep(nanoseconds: Constants.activationDelayNs)

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            Keystroke.simulate(virtualKey: Keystroke.keyV, flags: .maskCommand)

            if let snapshot {
                try? await Task.sleep(nanoseconds: Constants.clipboardRestoreDelayNs)
                snapshot.restore()
            }
        }
    }

    // MARK: - Panel

    private func showPanel(for session: CorrectionSession) {
        let panel = ResultPanel.make(
            session: session,
            onPaste: { [weak self] in self?.pasteResult() },
            onCopy: { [weak self] in self?.copyResult() },
            onRetry: { [weak self] in self?.retry() },
            onSubmitInstruction: { [weak self] in self?.submitInstruction() },
            onLaunchPaletteRow: { [weak self] index in self?.launchPaletteRow(at: index) },
            onOpenSettings: { [weak self] in
                self?.dismiss()
                self?.openSettings?()
            },
            onClose: { [weak self] in self?.dismiss() }
        )
        panel.onEnter = { [weak self] in self?.confirm() }
        panel.onEscape = { [weak self] in self?.dismiss() }
        panel.onCopyShortcut = { [weak self] in self?.copyResult() }
        panel.onArrow = { [weak self] delta in self?.movePaletteSelection(by: delta) ?? false }
        panel.onDigit = { [weak self] rank, withCommand in
            self?.launchPaletteRank(rank, withCommand: withCommand) ?? false
        }
        self.panel = panel
        panel.present()
    }

    func dismiss() {
        streamTask?.cancel()
        streamTask = nil
        panel?.orderOut(nil)
        panel = nil
        session = nil
        previousApp = nil
        clipboardSnapshot = nil
    }
}
