import AppKit

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
            contentRect: NSRect(origin: .zero, size: Constants.panelSize),
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

    /// Place le panneau près du pointeur, contraint à l'écran visible,
    /// et le montre sans NSApp.activate() (grâce à .nonactivatingPanel).
    func present(near location: NSPoint) {
        let screen = NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else {
            center()
            makeKeyAndOrderFront(nil)
            return
        }
        var origin = NSPoint(x: location.x + 12, y: location.y - frame.height - 12)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - frame.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - frame.height - 8)
        setFrameOrigin(origin)
        makeKeyAndOrderFront(nil)
    }
}
