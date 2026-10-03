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

/// The header's pill while a panel works: a spinner, and what it's doing.
struct WorkingPill: View {
    let label: String

    init(_ label: String) { self.label = label }

    var body: some View {
        StatusPill {
            ProgressView().controlSize(.mini)
            Text(label)
        }
    }
}

/// The header's pill while a panel listens: the spinner of the other phases
/// says "wait", but here it is the voice that moves, so the pill carries
/// the microphone's last six readings.
struct ListeningPill: View {
    let levels: LevelHistory
    let label: String

    var body: some View {
        StatusPill {
            DictationWaveform(levels: Array(levels.values.suffix(6)),
                              barWidth: 2, spacing: 1.5, maxHeight: 11)
            Text(label)
        }
    }
}

/// The header's pill once the text is all there.
struct ReadyPill: View {
    var body: some View {
        StatusPill(background: .green.opacity(0.16), foreground: .green) {
            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
            Text(loc("Prêt", en: "Ready"))
        }
    }
}

/// A text still coming in ends on a blinking caret; plain text once it's
/// all there.
struct StreamingText: View {
    let text: String
    let isStreaming: Bool

    var body: some View {
        if isStreaming {
            TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
                let caretOn = Int(timeline.date.timeIntervalSinceReferenceDate / 0.5) % 2 == 0
                Text(text)
                    + Text("▍").foregroundStyle(caretOn ? ClaudioTheme.accent : .clear)
            }
        } else {
            Text(text)
        }
    }
}

/// What stands in for the text when there is none: an icon, a title, the
/// sentence that says why and, at times, the one thing to do about it.
struct PanelMessage<Action: View>: View {
    let icon: String
    let title: String
    let detail: String
    let textSize: PanelTextSize
    var top: CGFloat = 26
    var bottom: CGFloat = 26
    @ViewBuilder let action: Action

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundStyle(.secondary)
            Text(title).font(.system(size: textSize.points(13), weight: .semibold))
            Text(detail)
                .font(.system(size: textSize.points(12)))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                // A message is a sentence, not a label: without this it is
                // cut off at one line, right where it says what went wrong
                // or what to do about it.
                .fixedSize(horizontal: false, vertical: true)
            action
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, top)
        .padding(.bottom, bottom)
    }
}

extension PanelMessage where Action == EmptyView {
    init(icon: String, title: String, detail: String, textSize: PanelTextSize,
         top: CGFloat = 26, bottom: CGFloat = 26) {
        self.init(icon: icon, title: title, detail: detail, textSize: textSize,
                  top: top, bottom: bottom) { EmptyView() }
    }
}

/// The footer's left end: how to close the panel, then the model at work,
/// whenever there is one worth naming.
struct PanelFooterCaption: View {
    /// The model's short name; `nil` leaves it out, its separator with it.
    let model: String?

    var body: some View {
        Text(loc("Échap pour fermer", en: "esc to close")).font(.caption2).foregroundStyle(.tertiary)
        if let model {
            // Neither the separator nor the model name are translated.
            Text(verbatim: "·").font(.caption2).foregroundStyle(.quaternary)
            Text(model)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }
}

/// Copy, its shortcut beside it, and "Copied ✓" for a moment after.
struct CopyButton: View {
    let justCopied: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if justCopied {
                Text(loc("Copié ✓", en: "Copied ✓"))
            } else {
                Text(loc("Copier ", en: "Copy ")) + Text("⌘C").foregroundStyle(.secondary)
            }
        }
        .buttonStyle(PanelPillButtonStyle())
    }
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
