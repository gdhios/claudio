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
    /// Chiffre 1…9 : lance la ligne de ce rang. `withCommand` dit si ⌘ était
    /// tenu — ce que la touche autorise se décide dans la session, pas ici.
    /// Même contrat de retour.
    var onDigit: ((Int, Bool) -> Bool)?

    /// Ces touches n'atteignent `keyDown` que si personne ne les a consommées
    /// avant : les champs de saisie, eux, les absorbent. Un moniteur local les
    /// voit avant la chaîne des responders, donc « Échap pour fermer » et la
    /// navigation de la palette restent vrais pendant la frappe.
    private var keyMonitor: Any?

    /// L'écran visible sur lequel le panneau s'est ouvert. Retenu à l'ouverture
    /// pour que les changements de hauteur le gardent centré au même endroit,
    /// sans le faire glisser d'un écran à l'autre pendant qu'un résultat s'écrit.
    private var homeVisibleFrame: NSRect?

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

    /// Ajuste la hauteur de la fenêtre au contenu en la gardant centrée sur son
    /// écran : le panneau grandit et rétrécit autour de son milieu, sans jamais
    /// sauter d'un bord à l'autre.
    func updateContentHeight(_ height: CGFloat) {
        // Borne haute : au plus grand corps de texte, la palette entière peut
        // dépasser un petit écran. Mieux vaut un panneau qui s'arrête au bord
        // qu'un panneau qui le franchit.
        let visible = homeVisibleFrame ?? (screen ?? NSScreen.main)?.visibleFrame
        let newHeight = min(max(height, 60), (visible?.height ?? .greatestFiniteMagnitude) - 16)
        guard abs(frame.height - newHeight) > 0.5 else { return }
        let size = NSSize(width: frame.width, height: newHeight)

        // Sans écran connu, on grandit autour du centre courant : le milieu du
        // panneau ne bouge pas, faute de pouvoir viser celui de l'écran.
        guard let visible else {
            var newFrame = frame
            newFrame.origin.y += (newFrame.height - newHeight) / 2
            newFrame.size.height = newHeight
            setFrame(newFrame, display: true)
            return
        }

        setFrame(ResultPanel.centered(size: size, in: visible), display: true)
    }

    /// Cadre d'un panneau de cette taille centré dans l'écran visible, borné à
    /// ses bords : un panneau trop haut s'arrête au bord plutôt que de le
    /// franchir.
    static func centered(size: NSSize, in visible: NSRect) -> NSRect {
        let x = min(max(visible.midX - size.width / 2, visible.minX + 8),
                    visible.maxX - size.width - 8)
        let y = min(max(visible.midY - size.height / 2, visible.minY + 8),
                    visible.maxY - size.height - 8)
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }

    /// Centre le panneau sur l'écran actif — celui qui porte le pointeur, donc
    /// celui où la sélection vient d'être faite — et le montre en fondu, sans
    /// NSApp.activate() (grâce à .nonactivatingPanel).
    ///
    /// Toujours au centre : fini le panneau collé dans un coin ou débordant de
    /// l'écran selon l'endroit d'où l'on a lancé le raccourci.
    func present() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else {
            center()
            fadeIn()
            return
        }
        homeVisibleFrame = visible
        // Gabarit d'abord : la vue SwiftUI n'est pas encore mesurée. La première
        // hauteur réelle recentrera par updateContentHeight, au même milieu.
        setFrame(ResultPanel.centered(size: frame.size, in: visible), display: false)
        fadeIn()
    }

    override func orderOut(_ sender: Any?) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        super.orderOut(sender)
    }

    /// Rang demandé par la frappe, et si ⌘ l'accompagnait — ou `nil` si ce
    /// n'est pas un rang qu'on demande.
    ///
    /// Un vrai chiffre compte toujours, ⇧ compris : sur AZERTY il n'y en a pas
    /// sans. La position physique, elle, ne compte qu'avec ⌘ : sans lui la
    /// rangée du haut d'un AZERTY donne « & é " ' », et une consigne qui
    /// commence par « écris » ne doit pas lancer la deuxième ligne.
    static func digitKey(keyCode: UInt16,
                         characters: String?,
                         modifiers: NSEvent.ModifierFlags) -> (rank: Int, withCommand: Bool)? {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        // ⌥ et ⌃ composent des caractères : ce n'est pas un rang qu'on demande.
        guard !flags.contains(.option), !flags.contains(.control) else { return nil }
        let withCommand = flags.contains(.command)
        if let characters, let rank = Int(characters), (1...9).contains(rank) {
            return (rank, withCommand)
        }
        guard withCommand else { return nil }
        // kVK_ANSI_1…9, dans l'ordre des chiffres (6 et 7 ne se suivent pas).
        let positions: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        return positions.firstIndex(of: keyCode).map { ($0 + 1, true) }
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
                    // Refusé — hors palette, ou consigne déjà commencée — le
                    // chiffre poursuit sa route et s'écrit dans le champ.
                    if let digit = ResultPanel.digitKey(keyCode: event.keyCode,
                                                        characters: event.charactersIgnoringModifiers,
                                                        modifiers: event.modifierFlags),
                       self.onDigit?(digit.rank, digit.withCommand) == true {
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
