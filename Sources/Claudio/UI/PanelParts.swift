import SwiftUI

// The parts the three floating panels share — correction, dictation and
// "What's playing?": each panel keeps its own header, content and footer,
// built from these.

extension View {
    /// The frame every panel wears: its width, its height reported to the
    /// window so the window hugs it, and the dark rounded card with its
    /// border, dark whatever the system mode.
    func panelChrome(width: CGFloat,
                     onHeightChange: (@MainActor @Sendable (CGFloat) -> Void)?) -> some View {
        frame(width: width)
            .reportsHeight(PanelHeightKey.self)
            .onPreferenceChange(PanelHeightKey.self) { [onHeightChange] height in
                // Report the height to the window in the same pass as the layout,
                // with no loop-turn delay: it follows the text frame by frame
                // instead of lagging one frame behind. That lag is what was
                // clipping the bottom then revealing it, hence the jerks. The report
                // is synchronous; it's the window that decides whether to animate the jump.
                MainActor.assumeIsolated { onHeightChange?(height) }
            }
            .background(ClaudioTheme.panelBackground,
                        in: RoundedRectangle(cornerRadius: ClaudioTheme.panelCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ClaudioTheme.panelCornerRadius, style: .continuous)
                    .strokeBorder(ClaudioTheme.panelBorder, lineWidth: 1)
            )
            .environment(\.colorScheme, .dark)
    }

    /// Measures this view's height and reports it under `key`.
    func reportsHeight<Key: PreferenceKey>(_ key: Key.Type) -> some View where Key.Value == CGFloat {
        background {
            GeometryReader { geo in
                Color.clear.preference(key: key, value: geo.size.height)
            }
        }
    }
}

/// Ideal height of the whole panel: reported to the window so it hugs the
/// content (no more half-empty rectangle).
private struct PanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Height of the text inside a panel's ScrollView, which bounds the
/// ScrollView. A key of its own: reduced into the panel's, a long text would
/// size the window to all of it instead of to the ScrollView's ceiling.
struct PanelTextHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Panel close button: discreet in the header, becomes a circle on hover.
struct PanelCloseButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(hovered ? .white : .white.opacity(0.45))
                .frame(width: 18, height: 18)
                .background(Color.white.opacity(hovered ? 0.14 : 0), in: Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(loc("Fermer (Échap)", en: "Close (esc)"))
    }
}
