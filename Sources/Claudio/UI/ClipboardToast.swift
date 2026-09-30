import AppKit
import SwiftUI

/// What a click on a recent dictation did with its text.
enum RecentDictationOutcome: Equatable, Sendable {
    /// ⌘V sent to the app in front. Whether a field took it can't be seen
    /// from Claudio, so the text stays on the clipboard as well.
    case pasted
    /// Nowhere to paste: Claudio itself was in front, or Accessibility is
    /// missing. The clipboard has the text.
    case copied

    var message: String {
        switch self {
        case .pasted: loc("Collée, et gardée dans le presse-papier",
                          en: "Pasted, and kept on the clipboard")
        case .copied: loc("Copiée : ⌘V pour coller", en: "Copied: ⌘V to paste")
        }
    }

    var symbolName: String {
        switch self {
        case .pasted: "text.insert"
        case .copied: "doc.on.clipboard"
        }
    }
}

/// The pill itself: an icon and a sentence, in the panels' dark theme.
struct ClipboardToastView: View {
    let outcome: RecentDictationOutcome

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: outcome.symbolName)
                .foregroundStyle(ClaudioTheme.accent)
            Text(outcome.message)
                .foregroundStyle(.primary)
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(ClaudioTheme.panelBackground, in: Capsule())
        .overlay(Capsule().strokeBorder(ClaudioTheme.panelBorder))
        .fixedSize()
    }
}

/// A window that never takes the keyboard: it shows up right after a ⌘V,
/// and a key window of Claudio's is exactly where a ⌘V must never land.
private final class ToastPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Shows a `ClipboardToastView` under the menu bar, on the screen the mouse
/// is on, for a moment. Clicks go through it; a new one replaces the last.
@MainActor
final class ClipboardToast {
    static let shared = ClipboardToast()

    private var panel: NSPanel?
    private var hiding: Task<Void, Never>?

    func show(_ outcome: RecentDictationOutcome, for duration: Duration = .milliseconds(1800)) {
        hiding?.cancel()
        panel?.orderOut(nil)

        let host = NSHostingView(rootView: ClipboardToastView(outcome: outcome))
        host.appearance = NSAppearance(named: .darkAqua)
        let size = host.fittingSize
        let panel = ToastPanel(contentRect: NSRect(origin: .zero, size: size),
                               styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.contentView = host

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2,
                                         y: visible.maxY - size.height - 12))
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 1 }
        self.panel = panel

        hiding = Task { [weak self, weak panel] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, let panel else { return }
            await NSAnimationContext.runAnimationGroup { $0.duration = 0.3; panel.animator().alphaValue = 0 }
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
            if self?.panel === panel { self?.panel = nil }
        }
    }
}
