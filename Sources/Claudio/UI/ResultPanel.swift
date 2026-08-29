import AppKit
import SwiftUI

/// Panneau flottant sans bordure qui reçoit le clavier (Entrée/Esc)
/// SANS activer l'app : l'application source garde le focus.
final class ResultPanel: NSPanel {
    var onEnter: (() -> Void)?
    var onEscape: (() -> Void)?
    var onCopyShortcut: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(origin: .zero,
                                size: NSSize(width: Constants.panelWidth, height: 160)),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        self.contentView = contentView
    }

    /// Construit le panneau câblé à sa vue SwiftUI : apparence sombre forcée
    /// (le panneau garde son thème quel que soit le mode système) et hauteur
    /// de fenêtre qui suit le contenu.
    @MainActor
    static func make(session: CorrectionSession,
                     onPaste: @escaping () -> Void = {},
                     onCopy: @escaping () -> Void = {},
                     onRetry: @escaping () -> Void = {},
                     onOpenSettings: @escaping () -> Void = {}) -> ResultPanel {
        let panel = ResultPanel(contentView: NSView())
        let view = ResultPanelView(
            session: session,
            onPaste: onPaste,
            onCopy: onCopy,
            onRetry: onRetry,
            onOpenSettings: onOpenSettings,
            onHeightChange: { [weak panel] height in panel?.updateContentHeight(height) }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.appearance = NSAppearance(named: .darkAqua)
        hosting.frame = NSRect(origin: .zero, size: panel.frame.size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        return panel
    }

    /// Ajuste la hauteur de la fenêtre au contenu en gardant le bord HAUT en
    /// place (le panneau grandit vers le bas, sans sortir de l'écran).
    func updateContentHeight(_ height: CGFloat) {
        let newHeight = max(height, 60)
        guard abs(frame.height - newHeight) > 0.5 else { return }
        var newFrame = frame
        newFrame.origin.y += newFrame.height - newHeight
        newFrame.size.height = newHeight
        if let visible = screen?.visibleFrame {
            newFrame.origin.y = min(max(newFrame.origin.y, visible.minY + 8),
                                    visible.maxY - newHeight - 8)
        }
        setFrame(newFrame, display: true)
    }

    /// Place le panneau près du pointeur, contraint à l'écran visible,
    /// et le montre en fondu sans NSApp.activate() (grâce à .nonactivatingPanel).
    func present(near location: NSPoint) {
        let screen = NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else {
            center()
            fadeIn()
            return
        }
        var origin = NSPoint(x: location.x + 12, y: location.y - frame.height - 12)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - frame.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - frame.height - 8)
        setFrameOrigin(origin)
        fadeIn()
    }

    private func fadeIn() {
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            animator().alphaValue = 1
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), event.keyCode == Keystroke.keyC {
            onCopyShortcut?()
            return
        }
        switch event.keyCode {
        case 36, 76:  // Retour, Entrée (pavé numérique)
            onEnter?()
        case 53:      // Esc
            onEscape?()
        default:
            super.keyDown(with: event)
        }
    }
}
