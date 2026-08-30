import AppKit
import SwiftUI

/// Panneau flottant sans bordure qui reçoit le clavier (Entrée/Esc)
/// SANS activer l'app : l'application source garde le focus.
final class ResultPanel: NSPanel {
    var onEnter: (() -> Void)?
    var onEscape: (() -> Void)?
    var onCopyShortcut: (() -> Void)?
    /// Flèches haut/bas : `-1` monter, `+1` descendre. Renvoie `true` si la
    /// touche a servi — sinon elle poursuit sa route (défiler un résultat long).
    var onArrow: ((Int) -> Bool)?
    /// ⌘1…⌘9 : lance la ligne de ce rang. Même contrat de retour.
    var onDigit: ((Int) -> Bool)?

    /// Ces touches n'atteignent `keyDown` que si personne ne les a consommées
    /// avant : les champs de saisie, eux, les absorbent. Un moniteur local les
    /// voit avant la chaîne des responders, donc « Échap pour fermer » et la
    /// navigation de la palette restent vrais pendant la frappe.
    private var keyMonitor: Any?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentView: NSView, width: CGFloat = Constants.panelWidth) {
        super.init(
            contentRect: NSRect(origin: .zero,
                                size: NSSize(width: width, height: 160)),
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
                     textSize: PanelTextSize = AppSettings.panelTextSize,
                     onPaste: @escaping () -> Void = {},
                     onCopy: @escaping () -> Void = {},
                     onRetry: @escaping () -> Void = {},
                     onSubmitInstruction: @escaping () -> Void = {},
                     onLaunchPaletteRow: @escaping (Int) -> Void = { _ in },
                     onOpenSettings: @escaping () -> Void = {},
                     onClose: @escaping () -> Void = {}) -> ResultPanel {
        let panel = ResultPanel(contentView: NSView(), width: textSize.panelWidth)
        let view = ResultPanelView(
            session: session,
            textSize: textSize,
            onPaste: onPaste,
            onCopy: onCopy,
            onRetry: onRetry,
            onSubmitInstruction: onSubmitInstruction,
            onLaunchPaletteRow: onLaunchPaletteRow,
            onOpenSettings: onOpenSettings,
            onClose: onClose,
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
        // Borne haute : au plus grand corps de texte, la palette entière peut
        // dépasser un petit écran. Mieux vaut un panneau qui s'arrête au bord
        // qu'un panneau qui le franchit.
        let visible = (screen ?? NSScreen.main)?.visibleFrame
        let newHeight = min(max(height, 60), (visible?.height ?? .greatestFiniteMagnitude) - 16)
        guard abs(frame.height - newHeight) > 0.5 else { return }
        var newFrame = frame
        newFrame.origin.y += newFrame.height - newHeight
        newFrame.size.height = newHeight
        if let visible {
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

    override func orderOut(_ sender: Any?) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        super.orderOut(sender)
    }

    /// Rang demandé par ⌘1…⌘9, ou `nil`. Le caractère couvre le QWERTY ; la
    /// position physique couvre l'AZERTY, où la rangée du haut ne donne pas de
    /// chiffres sans ⇧ mais où les touches sont au même endroit.
    private func digitRank(of event: NSEvent) -> Int? {
        guard event.modifierFlags.contains(.command) else { return nil }
        if let character = event.charactersIgnoringModifiers,
           let rank = Int(character), (1...9).contains(rank) {
            return rank
        }
        // kVK_ANSI_1…9, dans l'ordre des chiffres (6 et 7 ne se suivent pas).
        let positions: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        return positions.firstIndex(of: event.keyCode).map { $0 + 1 }
    }

    private func fadeIn() {
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === self else { return event }
                switch event.keyCode {
                case 53:  // Esc
                    self.onEscape?()
                    return nil
                case 126 where self.onArrow?(-1) == true,  // Haut
                     125 where self.onArrow?(1) == true:   // Bas
                    return nil
                default:
                    if let rank = self.digitRank(of: event), self.onDigit?(rank) == true {
                        return nil
                    }
                    return event
                }
            }
        }
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
