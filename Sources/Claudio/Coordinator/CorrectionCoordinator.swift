import AppKit
import SwiftUI

/// Orchestre le cycle complet : capture → stream → panneau → collage.
@MainActor
final class CorrectionCoordinator {
    var openSettings: (() -> Void)?

    private var panel: ResultPanel?
    private var session: CorrectionSession?
    private var streamTask: Task<Void, Never>?
    private var previousApp: NSRunningApplication?
    private var clipboardSnapshot: PasteboardSnapshot?

    // MARK: - Déclenchement

    /// Entrée du catalogue : raccourci global ou item de menu.
    func trigger(action: ClaudioAction) {
        trigger(action.request)
    }

    /// Action libre : même cycle, avec une escale de saisie de la consigne
    /// entre la capture de la sélection et l'appel à l'API.
    func triggerFreeAction() {
        trigger(.awaitingInstruction)
    }

    /// Palette : la sélection est capturée d'abord, l'action se choisit ensuite
    /// dans le panneau. La requête de départ n'est qu'un garnissage.
    func triggerPalette() {
        trigger(.awaitingChoice, opensPalette: true)
    }

    /// Consigne relancée depuis l'historique : même cycle qu'une action libre,
    /// mais la consigne est déjà connue, donc pas d'escale de saisie — la
    /// capture vise la sélection courante et le stream part aussitôt.
    func triggerRecent(instruction: String) {
        trigger(.free(instruction: instruction))
    }

    func trigger(_ request: ClaudioRequest, opensPalette: Bool = false) {
        dismiss()  // idempotent : un raccourci pendant qu'un panneau est ouvert repart de zéro

        guard AccessibilityPermission.isGranted else {
            AccessibilityPermission.request()
            AccessibilityPermission.showExplanation()
            return
        }

        // Capturés AVANT d'afficher quoi que ce soit.
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
        // Capture AVANT d'afficher le panneau : une fois key, le panneau
        // intercepterait le ⌘C simulé destiné à l'app source.
        let text = await SelectionCapture.capture()
        guard self.session === session else { return }  // re-déclenché/fermé entre-temps
        showPanel(for: session)

        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            session.phase = .noSelection
            return
        }
        session.originalText = text

        // Palette : rien à envoyer tant qu'une ligne n'est pas retenue.
        // La suite repart de `launchPaletteRow(at:)`.
        guard !session.opensPalette else {
            session.phase = .choosingAction
            return
        }

        // Action libre : rien à envoyer tant que la consigne n'est pas saisie.
        // La suite repart de `submitInstruction()`.
        guard !session.request.needsInstruction else {
            session.phase = .askingInstruction
            return
        }
        await stream(session: session)
    }

    /// Consigne validée dans le panneau : la requête libre se construit ici,
    /// puis emprunte le chemin commun.
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

    /// Ligne retenue dans la palette : sa requête devient celle de la session.
    /// L'action libre sans consigne fait escale par le champ de saisie plutôt
    /// que de partir avec une instruction vide.
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

    /// Flèches : ne consomme la touche que si la palette est ouverte, sinon
    /// elle continue sa route et fait défiler un résultat long.
    private func movePaletteSelection(by delta: Int) -> Bool {
        guard let session, session.phase == .choosingAction else { return false }
        session.movePaletteSelection(by: delta)
        return true
    }

    /// Chiffres : lance la ligne de ce rang quand la frappe la désigne bien.
    private func launchPaletteRank(_ rank: Int, withCommand: Bool) -> Bool {
        guard let session,
              let index = session.paletteIndex(forRank: rank, withCommand: withCommand)
        else { return false }
        launchPaletteRow(at: index)
        return true
    }

    private func stream(session: CorrectionSession) async {
        guard let apiKey = KeychainStore.currentAPIKey() else {
            session.phase = .missingKey
            return
        }
        session.beginStreaming()

        let client = AnthropicClient(apiKey: apiKey, workspaceID: AppSettings.currentWorkspaceID())
        let request = session.request
        do {
            let result = try await client.streamCompletion(
                of: request.userMessage(forText: session.originalText),
                system: request.system,
                model: request.model,
                maxTokens: request.maxTokens(forText: session.originalText,
                                             multiplier: session.maxTokensMultiplier)
            ) { @MainActor piece in
                session.appendStreamed(piece)
            }
            guard !Task.isCancelled else { return }
            session.finishStreaming(with: result.text, truncated: result.truncated)
            // Une action libre qui aboutit entre dans l'historique : sa consigne
            // pourra être relancée d'un geste depuis la barre de menus.
            if case .free(let instruction) = request.origin {
                TransformHistory.shared.record(instruction)
            }
            CostLedger.shared.record(model: request.model,
                                     inputTokens: result.inputTokens,
                                     outputTokens: result.outputTokens)
        } catch is CancellationError {
            // Esc pendant le stream : rien à faire
        } catch let error as URLError where error.code == .cancelled {
            // idem, URLSession signale l'annulation ainsi
        } catch {
            guard !Task.isCancelled else { return }
            session.phase = .error(error.localizedDescription)
        }
    }

    // MARK: - Actions du panneau

    /// Entrée : lance la ligne retenue dans la palette, valide la consigne
    /// pendant la saisie, colle le résultat ensuite.
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
        clipboardSnapshot = nil  // l'utilisateur veut ce contenu : ne pas le restaurer
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

    // MARK: - Panneau

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
