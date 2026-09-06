import SwiftUI

@MainActor
final class CorrectionSession: ObservableObject {
    enum Phase: Equatable {
        case capturing
        /// Palette: the selection is captured, the action is chosen in the panel.
        case choosingAction
        /// Custom action: the selection is captured, the instruction is entered in the panel.
        case askingInstruction
        case streaming
        case done
        case noSelection
        case missingKey
        case error(String)
    }

    @Published private(set) var request: ClaudioRequest
    /// The palette opens between the capture and the call: the request is then
    /// only a placeholder, replaced by the chosen row.
    let opensPalette: Bool

    init(request: ClaudioRequest, opensPalette: Bool = false) {
        self.request = request
        self.opensPalette = opensPalette
    }

    /// Convenience for calls that start from a catalog entry.
    convenience init(action: ClaudioAction) { self.init(request: action.request) }

    /// The custom action only learns its request once the instruction is confirmed.
    func adopt(_ request: ClaudioRequest) { self.request = request }

    @Published var phase: Phase = .capturing
    @Published var correctedText = ""
    @Published var truncated = false
    @Published var justCopied = false
    /// Instruction currently being typed (custom action).
    @Published var instruction = ""
    /// Palette input: filters the catalog, and serves as the instruction if it's
    /// the custom-action row that gets launched.
    @Published var paletteQuery = "" {
        didSet { paletteSelection = 0 }  // the filter changed, so does the list
    }
    @Published var paletteSelection = 0
    var originalText = ""
    var maxTokensMultiplier = 1

    /// Palette rows for the current input.
    var paletteRows: [PaletteRow] { PaletteCatalog.rows(matching: paletteQuery) }

    /// Highlighted row, clamped: the filter can shorten the list below
    /// the current index between two keystrokes.
    var selectedPaletteRow: PaletteRow? {
        let rows = paletteRows
        guard !rows.isEmpty else { return nil }
        return rows[min(max(paletteSelection, 0), rows.count - 1)]
    }

    /// Pointer position when the palette opens. As long as it hasn't
    /// moved, hovering over it selects nothing: the panel opens near the cursor,
    /// and a row it happens to cover would otherwise grab the selection with no
    /// hand involved.
    private var hoverOrigin: CGPoint?

    /// When the palette appears: hovering is pending a movement.
    func armHover(at location: CGPoint) { hoverOrigin = location }

    /// `true` if this hover comes from a hand that has moved. The first real
    /// movement hands the mouse back to its job, for good.
    func acceptsHover(at location: CGPoint) -> Bool {
        guard let origin = hoverOrigin else { return true }
        guard hypot(location.x - origin.x, location.y - origin.y) > 2 else { return false }
        hoverOrigin = nil
        return true
    }

    /// Moves the selection without leaving the list: once at the bottom, it stays there.
    func movePaletteSelection(by delta: Int) {
        let count = paletteRows.count
        guard count > 0 else { return }
        paletteSelection = min(max(paletteSelection + delta, 0), count - 1)
    }

    /// Index of the row a digit launches, or `nil` if the key should
    /// go its own way. The rank shown in front of each row is therefore typed as
    /// is: that's what it promises. Without ⌘ it only launches, though, as long as
    /// nothing has been typed yet: past the first keystroke the field is dictating an
    /// instruction, and "3" has to be written into it. A leading space is then enough
    /// to start an instruction with a digit.
    func paletteIndex(forRank rank: Int, withCommand: Bool) -> Int? {
        guard phase == .choosingAction else { return nil }
        guard withCommand || paletteQuery.isEmpty else { return nil }
        let index = rank - 1
        return paletteRows.indices.contains(index) ? index : nil
    }

    var canPaste: Bool { phase == .done && !correctedText.isEmpty }

    /// Usable instruction: the "Run" button and ⏎ stay inert without it.
    var trimmedInstruction: String {
        instruction.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Stream

    /// Fragments received since the last publish. The SSE stream delivers
    /// several dozen a second; republishing `correctedText` on each one
    /// triggers a full re-layout of the text, growing more costly as it
    /// gets longer. That's what was saturating the main loop and
    /// making the window advance in jerks on long answers. So we
    /// accumulate, and publish at a fixed cadence.
    private var streamBuffer = ""
    private var flushScheduled = false

    /// Publish cadence: short enough for the text to feel alive,
    /// long enough to let the layout pass happen in between.
    static let streamFlushInterval: Duration = .milliseconds(60)

    /// Opens a response: buffer cleared, text reset.
    func beginStreaming() {
        streamBuffer = ""
        flushScheduled = false
        correctedText = ""
        truncated = false
        justCopied = false
        phase = .streaming
    }

    /// Receives a fragment. The first one goes out immediately: the panel must
    /// react from the very first word; the following ones wait for the next flush.
    func appendStreamed(_ piece: String) {
        streamBuffer += piece
        guard !correctedText.isEmpty else {
            flushStreamed()
            return
        }
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: CorrectionSession.streamFlushInterval)
            self?.flushStreamed()
        }
    }

    /// Publishes whatever is waiting in the buffer.
    func flushStreamed() {
        flushScheduled = false
        guard !streamBuffer.isEmpty else { return }
        correctedText += streamBuffer
        streamBuffer = ""
    }

    /// End of stream: the full text replaces whatever went out along the way, and
    /// whatever remained in the buffer with it.
    func finishStreaming(with text: String, truncated: Bool) {
        streamBuffer = ""
        flushScheduled = false
        correctedText = text
        self.truncated = truncated
        phase = .done
    }
}

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
        case .streaming:
            StatusPill {
                ProgressView().controlSize(.mini)
                Text(session.request.progressLabel)
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
        case .choosingAction, .askingInstruction, .noSelection, .missingKey, .error:
            EmptyView()
        }
    }

    @ViewBuilder private var content: some View {
        switch session.phase {
        case .choosingAction:
            PaletteView(session: session, textSize: textSize, onLaunch: onLaunchPaletteRow)
        case .askingInstruction:
            instructionPrompt
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
        }
    }

    /// Instruction input (custom action), with an excerpt of the selection
    /// under the field: it's a text no longer visible on screen that gets transformed.
    private var instructionPrompt: some View {
        VStack(alignment: .leading, spacing: 9) {
            TextField("", text: $session.instruction,
                      prompt: Text(loc("Que faire du texte sélectionné ?",
                                       en: "What should Claudio do with the selected text?")))
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

            Text(session.originalText)
                .font(.system(size: textSize.points(10)))
                .foregroundStyle(.white.opacity(0.35))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .onAppear {
            // Focus set in the same cycle as the appearance is lost:
            // one loop turn later, the field keeps it.
            Task { @MainActor in instructionFocused = true }
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
        case .askingInstruction, .streaming, .done, .error: return true
        case .capturing, .choosingAction, .noSelection, .missingKey: return false
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
private struct PanelCloseButton: View {
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
