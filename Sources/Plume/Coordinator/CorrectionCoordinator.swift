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

    func trigger() {
        dismiss()  // idempotent : un ⌃⌥C pendant qu'un panneau est ouvert repart de zéro

        guard AccessibilityPermission.isGranted else {
            AccessibilityPermission.request()
            AccessibilityPermission.showExplanation()
            return
        }

        // Capturés AVANT d'afficher quoi que ce soit.
        let frontmost = NSWorkspace.shared.frontmostApplication
        previousApp = (frontmost?.bundleIdentifier == Bundle.main.bundleIdentifier) ? nil : frontmost
        clipboardSnapshot = PasteboardSnapshot.capture()

        let session = CorrectionSession()
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
        await stream(session: session)
    }

    private func stream(session: CorrectionSession) async {
        guard let apiKey = KeychainStore.currentAPIKey() else {
            session.phase = .missingKey
            return
        }
        session.phase = .streaming
        session.correctedText = ""
        session.truncated = false
        session.justCopied = false

        let client = AnthropicClient(apiKey: apiKey, workspaceID: AppSettings.currentWorkspaceID())
        do {
            let result = try await client.streamCorrection(
                of: session.originalText,
                maxTokensMultiplier: session.maxTokensMultiplier
            ) { @MainActor piece in
                session.correctedText += piece
            }
            guard !Task.isCancelled else { return }
            session.correctedText = result.text
            session.truncated = result.truncated
            session.phase = .done
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
        let view = ResultPanelView(
            session: session,
            onPaste: { [weak self] in self?.pasteResult() },
            onCopy: { [weak self] in self?.copyResult() },
            onRetry: { [weak self] in self?.retry() },
            onOpenSettings: { [weak self] in
                self?.dismiss()
                self?.openSettings?()
            }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: Constants.panelSize)

        let panel = ResultPanel(contentView: hosting)
        panel.onEnter = { [weak self] in self?.pasteResult() }
        panel.onEscape = { [weak self] in self?.dismiss() }
        panel.onCopyShortcut = { [weak self] in self?.copyResult() }
        self.panel = panel
        panel.present(near: NSEvent.mouseLocation)
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
