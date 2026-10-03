import SwiftUI

/// Ideal height of the whole panel: reported to the window so it
/// hugs the content (no more half-empty rectangle).
private struct PanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Height of the text in the ScrollView: used to bound the content area.
private struct TextHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct ResultPanelView: View {
    @ObservedObject var session: CorrectionSession
    /// Body text size, read once when the panel is built: the setting
    /// applies to the next panel, and the current panel doesn't change
    /// size under the reader's eyes.
    var textSize: PanelTextSize = .normal
    let onPaste: () -> Void
    let onCopy: () -> Void
    let onRetry: () -> Void
    let onSubmitInstruction: () -> Void
    let onLaunchPaletteRow: (Int) -> Void
    let onOpenSettings: () -> Void
    let onClose: () -> Void
    var onOpenInGalette: (GaletteLink) -> Void = { _ in }
    var onHeightChange: (@MainActor @Sendable (CGFloat) -> Void)? = nil

    @State private var textHeight: CGFloat = 0
    @FocusState private var instructionFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ClaudioTheme.panelSeparator.frame(height: 1)
            content
            // The palette carries its own footer (input field and hints):
            // the shared footer only shows for the other phases.
            if session.phase != .choosingAction {
                ClaudioTheme.panelSeparator.frame(height: 1)
                footer
            }
        }
        .frame(width: textSize.panelWidth)
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: PanelHeightKey.self, value: geo.size.height)
            }
        }
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

    private var header: some View {
        HStack(spacing: 8) {
            // Claudio himself, at the top of his window. His gaze follows the
            // phase: he's listening, he's thinking, he's done.
            ClaudioMascot(gaze: .init(session.phase))
            Text("Claudio").font(.headline)
            // During the palette, no action is chosen: the pill
            // would be lying. Today's spending takes its place.
            if session.phase == .choosingAction {
                Spacer()
                CostGauge()
            } else {
                StatusPill {
                    Image(systemName: session.request.origin.symbolName)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(session.request.origin.tint)
                    Text(session.request.panelTitle)
                }
                Spacer()
                statusLabel
            }
            PanelCloseButton(action: onClose)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    @ViewBuilder private var statusLabel: some View {
        switch session.phase {
        case .capturing:
            StatusPill {
                ProgressView().controlSize(.mini)
                Text(loc("Capture…", en: "Reading…"))
            }
        case .listeningInstruction:
            // The spinner of the other phases says "wait"; while listening
            // it is the voice that moves, so the pill carries the last
            // readings — the dictation panel's own pill.
            StatusPill {
                DictationWaveform(levels: Array(session.levels.values.suffix(6)),
                                  barWidth: 2, spacing: 1.5, maxHeight: 11)
                Text(session.listeningEnded
                     ? loc("Un instant…", en: "One moment…")
                     : loc("À l'écoute…", en: "Listening…"))
            }
        case .streaming:
            StatusPill {
                ProgressView().controlSize(.mini)
                Text(session.progressLabel)
            }
        case .done:
            if session.truncated {
                StatusPill(background: .orange.opacity(0.18), foreground: .orange) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9))
                    Text(loc("Réponse tronquée", en: "Answer cut short"))
                }
            } else {
                StatusPill(background: .green.opacity(0.16), foreground: .green) {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                    Text(loc("Prêt", en: "Ready"))
                }
            }
        case .choosingAction, .askingInstruction, .instructionNotHeard,
             .noSelection, .missingKey, .error:
            EmptyView()
        }
    }

    @ViewBuilder private var content: some View {
        switch session.phase {
        case .choosingAction:
            PaletteView(session: session, textSize: textSize, onLaunch: onLaunchPaletteRow)
        case .askingInstruction:
            instructionPrompt
        case .listeningInstruction:
            spokenInstructionPrompt
        case .instructionNotHeard(let reason):
            // A silence and a microphone that gave up are two different
            // pieces of news: only the second one has something to report.
            messageView(icon: reason == nil ? "waveform.slash" : "exclamationmark.triangle",
                        title: reason == nil
                            ? loc("Rien entendu", en: "Nothing heard")
                            : loc("Consigne non entendue", en: "Couldn't hear the instruction"),
                        detail: reason ?? loc("Aucune parole n'a été captée. Maintiens le raccourci en parlant.",
                                              en: "No speech was picked up. Hold the shortcut while you talk."))
        case .noSelection:
            messageView(icon: "cursorarrow.rays",
                        title: loc("Aucune sélection détectée", en: "No selection found"),
                        detail: loc("Sélectionne du texte puis relance le raccourci.",
                                    en: "Select some text, then trigger the shortcut again."))
        case .missingKey:
            messageView(icon: "key",
                        title: loc("Clé API manquante", en: "No API key"),
                        detail: loc("Ajoute ta clé Anthropic dans les Réglages pour activer la correction.",
                                    en: "Add your Anthropic key in Settings to start using Claudio."))
        case .error(let message):
            messageView(icon: "exclamationmark.triangle",
                        title: loc("Erreur", en: "Error"),
                        detail: message)
        default:
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        resultText
                            .font(.system(size: textSize.bodyPoints))
                            .foregroundStyle(.white.opacity(0.92))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .background {
                        GeometryReader { geo in
                            Color.clear.preference(key: TextHeightKey.self, value: geo.size.height)
                        }
                    }
                }
                .frame(height: min(max(textHeight, textSize.minTextHeight), textSize.maxTextHeight))
                .onPreferenceChange(TextHeightKey.self) { height in
                    // The measured height jumps a whole line at a time.
                    // Interpolating it here rather than reporting it as-is
                    // makes the window follow frame by frame: it slides
                    // instead of jumping, with nothing animating the window itself.
                    Task { @MainActor in
                        withAnimation(.easeOut(duration: 0.18)) { textHeight = height }
                    }
                }
                .onChange(of: session.correctedText) {
                    // Only follow the bottom if there's something to scroll: as long as
                    // the text fits in the panel, there's nothing to catch up on.
                    if textHeight > textSize.maxTextHeight {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            // Out of the scroll, so a long answer never hides it, nor its
            // Galette buttons.
            if let track = session.sentTrack {
                SentTrackLine(track: track, textSize: textSize,
                              galette: GaletteButtons(galette: session.galette, links: session.galetteLinks,
                                                      onOpen: onOpenInGalette))
            }
        }
    }

    /// Instruction input (custom action), with an excerpt of the selection
    /// under the field: it's a text no longer visible on screen that gets
    /// transformed. With nothing selected, no excerpt: the field asks for a
    /// request instead.
    private var instructionPrompt: some View {
        VStack(alignment: .leading, spacing: 9) {
            TextField("", text: $session.instruction,
                      prompt: Text(instructionPlaceholder(spoken: false)))
                .textFieldStyle(.plain)
                .font(.system(size: textSize.bodyPoints))
                .foregroundStyle(.white.opacity(0.92))
                .focused($instructionFocused)
                .onSubmit(onSubmitInstruction)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                )

            selectionExcerpt
        }
        .padding(14)
        .onAppear {
            // Focus set in the same cycle as the appearance is lost:
            // one loop turn later, the field keeps it.
            Task { @MainActor in instructionFocused = true }
        }
    }

    /// The same prompt, said rather than typed: the waveform takes the
    /// field's place and the words land in it as they are spoken. Same box,
    /// same excerpt of the selection underneath, if there is one — one
    /// panel, which goes on to stream the answer.
    private var spokenInstructionPrompt: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                DictationWaveform(levels: Array(session.levels.values.suffix(12)),
                                  barWidth: textSize.points(2.5),
                                  spacing: textSize.points(2.5),
                                  maxHeight: textSize.points(18))
                Text(session.instruction.isEmpty
                     ? instructionPlaceholder(spoken: true)
                     : session.instruction)
                    .font(.system(size: textSize.bodyPoints))
                    .foregroundStyle(.white.opacity(session.instruction.isEmpty ? 0.35 : 0.92))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // The words already there don't move, the new ones fade
                    // in — as they do in the dictation panel.
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.22), value: session.instruction)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 1)
            )

            selectionExcerpt
        }
        .padding(14)
    }

    /// What the field says before the instruction comes: what to do with the
    /// selection — or, with nothing selected, what to ask for.
    private func instructionPlaceholder(spoken: Bool) -> String {
        switch (session.hasSelection, spoken) {
        case (true, false):
            loc("Que faire du texte sélectionné ?", en: "What should Claudio do with the selected text?")
        case (true, true):
            loc("Dis ce que Claudio doit en faire…", en: "Say what Claudio should do with it…")
        case (false, false):
            loc("Que demander à Claudio ?", en: "What should Claudio do?")
        case (false, true):
            loc("Dis ta demande à Claudio…", en: "Say what Claudio should do…")
        }
    }

    /// The selection under the instruction, the text it will be applied to.
    /// Nothing at all when nothing is selected.
    @ViewBuilder private var selectionExcerpt: some View {
        if session.hasSelection {
            Text(session.originalText)
                .font(.system(size: textSize.points(10)))
                .foregroundStyle(.white.opacity(0.35))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Streaming text with a blinking caret; plain text once finished.
    @ViewBuilder private var resultText: some View {
        if session.phase == .capturing || session.phase == .streaming {
            TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
                let caretOn = Int(timeline.date.timeIntervalSinceReferenceDate / 0.5) % 2 == 0
                Text(session.correctedText)
                    + Text("▍").foregroundStyle(caretOn ? ClaudioTheme.accent : .clear)
            }
        } else {
            Text(session.correctedText)
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

    /// The model that processed the selection, discreet at the bottom left: it makes
    /// it verifiable at a glance what answered, Claude or a local model.
    /// Nothing to show while the request is only a palette placeholder,
    /// or no call has gone out yet.
    private var showsModelName: Bool {
        switch session.phase {
        case .askingInstruction, .listeningInstruction, .streaming, .done, .error: return true
        case .capturing, .choosingAction, .instructionNotHeard, .noSelection, .missingKey:
            return false
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(loc("Échap pour fermer", en: "esc to close")).font(.caption2).foregroundStyle(.tertiary)
            if showsModelName {
                // Neither the separator nor the model name are translated.
                Text(verbatim: "·").font(.caption2).foregroundStyle(.quaternary)
                Text(session.request.model.shortName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
            switch session.phase {
            case .listeningInstruction:
                // No button: the gesture is the button. What ends it is the
                // key coming up, and nothing else on screen says so.
                Text(loc("Relâche pour lancer", en: "Release to run"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            case .askingInstruction:
                Button(action: onSubmitInstruction) {
                    Text(loc("Lancer ", en: "Run ")) + Text("⏎").fontWeight(.regular).foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(ClaudioProminentButtonStyle())
                .disabled(session.trimmedInstruction.isEmpty)
            case .missingKey:
                Button(loc("Réglages…", en: "Settings…"), action: onOpenSettings)
                    .buttonStyle(PanelPillButtonStyle())
            case .error:
                Button(loc("Réessayer", en: "Try again"), action: onRetry)
                    .buttonStyle(PanelPillButtonStyle())
            case .done:
                if session.truncated {
                    Button(loc("Réessayer +", en: "Try again +"), action: onRetry)
                        .buttonStyle(PanelPillButtonStyle())
                        .help(loc("Relance avec un budget de tokens doublé",
                                  en: "Runs again with twice the token budget"))
                }
                Button(action: onCopy) {
                    if session.justCopied {
                        Text(loc("Copié ✓", en: "Copied ✓"))
                    } else {
                        Text(loc("Copier ", en: "Copy ")) + Text("⌘C").foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(PanelPillButtonStyle())
                Button(action: onPaste) {
                    Text(loc("Coller ", en: "Paste ")) + Text("⏎").fontWeight(.regular).foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(ClaudioProminentButtonStyle())
                .disabled(!session.canPaste)
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// Panel close button: discreet in the header, becomes a circle on hover.
/// Shared with the dictation panel, which has the same one.
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
