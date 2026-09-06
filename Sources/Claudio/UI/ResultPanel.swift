import AppKit
import QuartzCore
import SwiftUI

/// Borderless floating panel that receives the keyboard (Return/Esc)
/// WITHOUT activating the app: the source application keeps focus.
final class ResultPanel: NSPanel {
    var onEnter: (() -> Void)?
    var onEscape: (() -> Void)?
    var onCopyShortcut: (() -> Void)?
    /// Up/down arrows: `-1` to go up, `+1` to go down. Returns `true` if the
    /// key was used, otherwise it goes its own way (scrolling a long result).
    var onArrow: ((Int) -> Bool)?
    /// Digit 1…9: launches the row at that rank. `withCommand` says whether ⌘ was
    /// held; what the key is allowed to do is decided in the session, not here.
    /// Same return contract.
    var onDigit: ((Int, Bool) -> Bool)?

    /// These keys only reach `keyDown` if nobody consumed them first:
    /// text fields absorb them. A local monitor sees them before the responder
    /// chain, so "esc to close" and palette navigation stay true while typing.
    private var keyMonitor: Any?

    /// The visible screen the panel opened on. Kept at opening time
    /// so height changes keep it centered in the same spot, without
    /// letting it drift from one screen to another while a result is being written.
    private var homeVisibleFrame: NSRect?

    /// False until the panel has taken its first real size: the very
    /// first measurement lands cleanly, without sliding, for a crisp
    /// opening rather than an unfolding.
    private var hasSizedOnce = false

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

    /// Builds the panel wired to its SwiftUI view: forced dark appearance
    /// (the panel keeps its theme regardless of the system mode) and window
    /// height that follows the content.
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

    /// Adjusts the window height to the content while keeping it centered on its
    /// screen: the panel grows and shrinks around its middle, without ever
    /// jumping from one edge to the other.
    ///
    /// A streaming tick (small step) lands instantly: the window follows the
    /// text frame by frame. A state jump (opening, palette, error) glides
    /// with a short easeOut, to change size without a jolt.
    func updateContentHeight(_ height: CGFloat) {
        // Upper bound: at the largest text size, the whole palette can
        // exceed a small screen. Better a panel that stops at the edge
        // than one that overruns it.
        let visible = homeVisibleFrame ?? (screen ?? NSScreen.main)?.visibleFrame
        let newHeight = min(max(height, 60), (visible?.height ?? .greatestFiniteMagnitude) - 16)
        guard abs(frame.height - newHeight) > 0.5 else { return }

        let target: NSRect
        if let visible {
            target = ResultPanel.centered(size: NSSize(width: frame.width, height: newHeight), in: visible)
        } else {
            // With no known screen, grow around the current center: the panel's
            // middle doesn't move, for lack of being able to target the screen's.
            var newFrame = frame
            newFrame.origin.y += (newFrame.height - newHeight) / 2
            newFrame.size.height = newHeight
            target = newFrame
        }

        // The first measurement (at opening) lands cleanly; after that, only
        // state jumps glide: streaming, for its part, is followed frame by frame.
        let glide = hasSizedOnce && ResultPanel.shouldAnimateResize(from: frame.height, to: newHeight)
        hasSizedOnce = true

        guard glide else {
            setFrame(target, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrame(target, display: true)
        }
    }

    /// Beyond this height jump, the window is no longer following the text as
    /// it's written but changing state (opening, palette, error): better then to
    /// glide than to jump.
    private static let abruptResizeThreshold: CGFloat = 120

    /// True if the height change is a state jump rather than a streaming
    /// tick. Pure and static: the decision can be tested without a window.
    static func shouldAnimateResize(from old: CGFloat, to new: CGFloat) -> Bool {
        abs(new - old) > abruptResizeThreshold
    }

    /// Frame for a panel of this size centered in the visible screen, clamped to
    /// its edges: a panel too tall stops at the edge rather than
    /// overrunning it.
    static func centered(size: NSSize, in visible: NSRect) -> NSRect {
        let x = min(max(visible.midX - size.width / 2, visible.minX + 8),
                    visible.maxX - size.width - 8)
        let y = min(max(visible.midY - size.height / 2, visible.minY + 8),
                    visible.maxY - size.height - 8)
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }

    /// Centers the panel on the active screen: the one carrying the pointer, so
    /// the one where the selection was just made, and fades it in, with no
    /// NSApp.activate() (thanks to .nonactivatingPanel).
    ///
    /// Always centered: no more panel stuck in a corner or spilling off
    /// the screen depending on where the shortcut was triggered from.
    func present() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        guard let visible = screen?.visibleFrame else {
            center()
            fadeIn()
            return
        }
        homeVisibleFrame = visible
        hasSizedOnce = false
        // Placeholder size first: the SwiftUI view isn't measured yet. The first
        // real height will re-center via updateContentHeight, at the same middle.
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

    /// Rank requested by the keystroke, and whether ⌘ came with it, or `nil` if
    /// this isn't a rank being requested.
    ///
    /// A real digit always counts, ⇧ included: on AZERTY there's no digit
    /// without it. The physical position, on the other hand, only counts with ⌘:
    /// without it, the top row of an AZERTY gives "& é " '", and an instruction
    /// starting with "écris" must not launch the second row.
    static func digitKey(keyCode: UInt16,
                         characters: String?,
                         modifiers: NSEvent.ModifierFlags) -> (rank: Int, withCommand: Bool)? {
        let flags = modifiers.intersection(.deviceIndependentFlagsMask)
        // ⌥ and ⌃ compose characters: that's not a rank being requested.
        guard !flags.contains(.option), !flags.contains(.control) else { return nil }
        let withCommand = flags.contains(.command)
        if let characters, let rank = Int(characters), (1...9).contains(rank) {
            return (rank, withCommand)
        }
        guard withCommand else { return nil }
        // kVK_ANSI_1…9, in digit order (6 and 7 aren't adjacent).
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
                case 126 where self.onArrow?(-1) == true,  // Up
                     125 where self.onArrow?(1) == true:   // Down
                    return nil
                default:
                    // Refused, either outside the palette or an instruction already
                    // started, the digit goes its own way and gets typed into the field.
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
        case 36, 76:  // Return, Enter (numeric keypad)
            onEnter?()
        case 53:      // Esc
            onEscape?()
        default:
            super.keyDown(with: event)
        }
    }
}
