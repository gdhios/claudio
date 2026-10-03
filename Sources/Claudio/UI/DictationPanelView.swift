import AppKit
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
        .panelChrome(width: textSize.panelWidth, onHeightChange: onHeightChange)
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
            // Squeezed by a long language name, the language gives way
            // first: a locked dictation's pill says how to end it.
            statusLabel.layoutPriority(1)
            PanelCloseButton(action: onClose)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    @ViewBuilder private var statusLabel: some View {
        switch session.phase {
        case .listening:
            // Locked by a tap, the waveform says it listens and the words say
            // how it ends: with the key up, nothing else on screen does.
            ListeningPill(levels: session.levels,
                          label: session.isLocked
                              ? loc("Appuie encore pour finir", en: "Press again to finish")
                              : loc("À l'écoute…", en: "Listening…"))
        case .finishing:
            WorkingPill(loc("Un instant…", en: "One moment…"))
        case .cleaning:
            // Named after the output rather than always "cleaning up": a
            // translation taking its time shouldn't look like a stuck one.
            WorkingPill(session.output.progressLabel)
        case .pasting:
            WorkingPill(loc("Collage…", en: "Pasting…"))
        case .done:
            ReadyPill()
        case .empty, .error:
            EmptyView()
        }
    }

    @ViewBuilder private var content: some View {
        switch session.phase {
        case .empty:
            PanelMessage(icon: "waveform.slash",
                         title: loc("Rien entendu", en: "Nothing heard"),
                         detail: loc("Aucune parole n'a été captée. Maintiens le raccourci en parlant.",
                                     en: "No speech was picked up. Hold the shortcut while you talk."),
                         textSize: textSize)
        case .error(let message):
            PanelMessage(icon: "exclamationmark.triangle",
                         title: loc("Dictée impossible", en: "Dictation stopped"),
                         detail: message,
                         textSize: textSize) {
                // A language that isn't installed is the one failure the
                // panel can act on: Claudio downloads nothing by itself, and
                // this opens the pane where it's added.
                if let settingsURL = session.failure?.settingsURL {
                    Button(loc("Ouvrir Réglages Système", en: "Open System Settings")) {
                        NSWorkspace.shared.open(settingsURL)
                    }
                    .buttonStyle(PanelPillButtonStyle())
                    .padding(.top, 2)
                }
            }
        default:
            Group {
                if session.phase == .listening, session.transcript.isEmpty {
                    listeningPlaceholder
                } else {
                    dictatedText
                }
            }
            .animation(.easeOut(duration: 0.2), value: session.transcript.isEmpty)
        }
    }

    /// Before the first word: the waveform, large, where the text will be, at
    /// the height the text will take so nothing jumps when it arrives.
    private var listeningPlaceholder: some View {
        VStack(spacing: 12) {
            DictationWaveform(levels: session.levels.values,
                              barWidth: textSize.points(3),
                              spacing: textSize.points(3),
                              maxHeight: textSize.points(40))
            Text(loc("Parle, je t'écoute…", en: "Go ahead, I'm listening…"))
                .font(.system(size: textSize.points(12)))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: textSize.minTextHeight)
        .transition(.opacity)
    }

    /// The text being written: the transcript while listening, the cleaned-up
    /// version as soon as one streams in. While it's being cleaned, the
    /// transcript stays underneath, dimmed: one sees what one said as it's
    /// tidied up.
    private var dictatedText: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    // A caret as long as words are still coming in.
                    StreamingText(text: session.finalText, isStreaming: session.isWorking)
                        .font(.system(size: textSize.bodyPoints))
                        .foregroundStyle(.white.opacity(0.92))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // Each new result crossfades over the previous one:
                        // the words already there don't move, the new ones
                        // fade in instead of popping.
                        .contentTransition(.opacity)
                        .animation(.easeOut(duration: 0.22), value: session.finalText)
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
                .reportsHeight(PanelTextHeightKey.self)
            }
            .frame(height: min(max(textHeight, textSize.minTextHeight), textSize.maxTextHeight))
            .onPreferenceChange(PanelTextHeightKey.self) { height in
                Task { @MainActor in
                    withAnimation(.easeOut(duration: 0.18)) { textHeight = height }
                }
            }
            .onChange(of: session.finalText) {
                if textHeight > textSize.maxTextHeight {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
        .transition(.opacity)
    }

    /// Bottom left, the model that cleaned up and, when there wasn't one,
    /// why — same spot as the correction panel's indicator. Copy only shows
    /// when the panel is staying: a pasted dictation closes by itself.
    private var footer: some View {
        HStack(spacing: 8) {
            PanelFooterCaption(model: session.model.shortName)
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
                CopyButton(justCopied: session.justCopied, action: onCopy)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
