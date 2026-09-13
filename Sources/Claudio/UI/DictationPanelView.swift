import SwiftUI

/// The panel while dictating: what Claudio hears, then what the model makes
/// of it. Its own view rather than one more branch inside `ResultPanelView`:
/// a dictation has no action, no palette and no instruction — a header, a
/// text, and a note when the cleanup didn't happen.
struct DictationPanelView: View {
    @ObservedObject var session: DictationSession
    /// Body text size, read once when the panel is built, like the
    /// correction panel: the setting applies to the next one.
    var textSize: PanelTextSize = .normal
    let onCopy: () -> Void
    let onClose: () -> Void
    var onHeightChange: (@MainActor @Sendable (CGFloat) -> Void)? = nil

    @State private var textHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ClaudioTheme.panelSeparator.frame(height: 1)
            content
            ClaudioTheme.panelSeparator.frame(height: 1)
            footer
        }
        .frame(width: textSize.panelWidth)
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: DictationPanelHeightKey.self, value: geo.size.height)
            }
        }
        .onPreferenceChange(DictationPanelHeightKey.self) { [onHeightChange] height in
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

    private var header: some View {
        HStack(spacing: 8) {
            // Claudio's gaze follows the phase, as it does for a correction:
            // he listens, he works, it's done.
            ClaudioMascot(gaze: .init(session.phase))
            Text("Claudio").font(.headline)
            StatusPill {
                Image(systemName: "mic.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ClaudioTheme.accent)
                Text(session.language.displayName)
            }
            Spacer()
            statusLabel
            PanelCloseButton(action: onClose)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    @ViewBuilder private var statusLabel: some View {
        switch session.phase {
        case .listening:
            workingPill(loc("À l'écoute…", en: "Listening…"))
        case .finishing:
            workingPill(loc("Un instant…", en: "One moment…"))
        case .cleaning:
            workingPill(loc("Nettoyage…", en: "Cleaning up…"))
        case .pasting:
            workingPill(loc("Collage…", en: "Pasting…"))
        case .done:
            StatusPill(background: .green.opacity(0.16), foreground: .green) {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                Text(loc("Prêt", en: "Ready"))
            }
        case .empty, .error:
            EmptyView()
        }
    }

    private func workingPill(_ label: String) -> some View {
        StatusPill {
            ProgressView().controlSize(.mini)
            Text(label)
        }
    }

    @ViewBuilder private var content: some View {
        switch session.phase {
        case .empty:
            messageView(icon: "waveform.slash",
                        title: loc("Rien entendu", en: "Nothing heard"),
                        detail: loc("Aucune parole n'a été captée. Maintiens le raccourci en parlant.",
                                    en: "No speech was picked up. Hold the shortcut while you talk."))
        case .error(let message):
            messageView(icon: "exclamationmark.triangle",
                        title: loc("Dictée impossible", en: "Dictation stopped"),
                        detail: message)
        default:
            dictatedText
        }
    }

    /// The text being written: the transcript while listening, the cleaned-up
    /// version as soon as one streams in. While it's being cleaned, the
    /// transcript stays underneath, dimmed: one sees what one said as it's
    /// tidied up.
    private var dictatedText: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    liveText
                        .font(.system(size: textSize.bodyPoints))
                        .foregroundStyle(.white.opacity(0.92))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if session.phase == .cleaning, !session.transcript.isEmpty {
                        Text(session.transcript)
                            .font(.system(size: textSize.points(10)))
                            .foregroundStyle(.white.opacity(0.35))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(14)
                .background {
                    GeometryReader { geo in
                        Color.clear.preference(key: DictationTextHeightKey.self, value: geo.size.height)
                    }
                }
            }
            .frame(height: min(max(textHeight, textSize.minTextHeight), textSize.maxTextHeight))
            .onPreferenceChange(DictationTextHeightKey.self) { height in
                Task { @MainActor in
                    withAnimation(.easeOut(duration: 0.18)) { textHeight = height }
                }
            }
            .onChange(of: session.finalText) {
                if textHeight > textSize.maxTextHeight {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    /// A blinking caret as long as words are still coming in; plain text
    /// once the dictation is out.
    @ViewBuilder private var liveText: some View {
        if session.isWorking {
            TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
                let caretOn = Int(timeline.date.timeIntervalSinceReferenceDate / 0.5) % 2 == 0
                Text(session.finalText)
                    + Text("▍").foregroundStyle(caretOn ? ClaudioTheme.accent : .clear)
            }
        } else {
            Text(session.finalText)
        }
    }

    private func messageView(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundStyle(.secondary)
            Text(title).font(.system(size: textSize.points(13), weight: .semibold))
            Text(detail)
                .font(.system(size: textSize.points(12)))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 26)
    }

    /// Bottom left, the model that cleaned up and, when there wasn't one,
    /// why — same spot as the correction panel's indicator. Copy only shows
    /// when the panel is staying: a pasted dictation closes by itself.
    private var footer: some View {
        HStack(spacing: 8) {
            Text(loc("Échap pour fermer", en: "esc to close")).font(.caption2).foregroundStyle(.tertiary)
            // Neither the separator nor the model name are translated.
            Text(verbatim: "·").font(.caption2).foregroundStyle(.quaternary)
            Text(session.model.shortName)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            if let note = session.note {
                Text(verbatim: "·").font(.caption2).foregroundStyle(.quaternary)
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.orange.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            if session.canCopy {
                Button(action: onCopy) {
                    if session.justCopied {
                        Text(loc("Copié ✓", en: "Copied ✓"))
                    } else {
                        Text(loc("Copier ", en: "Copy ")) + Text("⌘C").foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(PanelPillButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// Ideal height of the whole panel, reported to the window so it hugs its
/// content.
private struct DictationPanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Height of the text inside the ScrollView, to bound the content area.
private struct DictationTextHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
