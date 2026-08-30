import SwiftUI

@MainActor
final class CorrectionSession: ObservableObject {
    enum Phase: Equatable {
        case capturing
        /// Palette : la sélection est prise, l'action se choisit dans le panneau.
        case choosingAction
        /// Action libre : la sélection est prise, la consigne se saisit dans le panneau.
        case askingInstruction
        case streaming
        case done
        case noSelection
        case missingKey
        case error(String)
    }

    @Published private(set) var request: ClaudioRequest
    /// La palette s'ouvre entre la capture et l'appel : la requête n'est alors
    /// qu'un garnissage, remplacé par la ligne choisie.
    let opensPalette: Bool

    init(request: ClaudioRequest, opensPalette: Bool = false) {
        self.request = request
        self.opensPalette = opensPalette
    }

    /// Confort pour les appels qui partent d'une entrée du catalogue.
    convenience init(action: ClaudioAction) { self.init(request: action.request) }

    /// L'action libre ne connaît sa requête qu'une fois la consigne validée.
    func adopt(_ request: ClaudioRequest) { self.request = request }

    @Published var phase: Phase = .capturing
    @Published var correctedText = ""
    @Published var truncated = false
    @Published var justCopied = false
    /// Consigne en cours de saisie (action libre).
    @Published var instruction = ""
    /// Saisie de la palette : filtre le catalogue, et sert de consigne si c'est
    /// la ligne d'action libre qu'on lance.
    @Published var paletteQuery = "" {
        didSet { paletteSelection = 0 }  // le filtre a changé : la liste aussi
    }
    @Published var paletteSelection = 0
    var originalText = ""
    var maxTokensMultiplier = 1

    /// Lignes de la palette pour la saisie courante.
    var paletteRows: [PaletteRow] { PaletteCatalog.rows(matching: paletteQuery) }

    /// Ligne mise en avant, bornée : le filtre peut raccourcir la liste sous
    /// l'index courant entre deux frappes.
    var selectedPaletteRow: PaletteRow? {
        let rows = paletteRows
        guard !rows.isEmpty else { return nil }
        return rows[min(max(paletteSelection, 0), rows.count - 1)]
    }

    /// Déplace la sélection sans sortir de la liste : arrivé en bas, on y reste.
    func movePaletteSelection(by delta: Int) {
        let count = paletteRows.count
        guard count > 0 else { return }
        paletteSelection = min(max(paletteSelection + delta, 0), count - 1)
    }

    var canPaste: Bool { phase == .done && !correctedText.isEmpty }

    /// Consigne exploitable : le bouton « Lancer » et ⏎ restent inertes sans elle.
    var trimmedInstruction: String {
        instruction.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Flux

    /// Fragments reçus depuis la dernière publication. Le flux SSE en livre
    /// plusieurs dizaines par seconde ; republier `correctedText` à chacun
    /// relance une mise en page complète du texte, de plus en plus coûteuse à
    /// mesure qu'il s'allonge. C'est ce qui saturait la boucle principale et
    /// faisait avancer la fenêtre par à-coups sur les réponses longues. On
    /// accumule, et on publie à cadence fixe.
    private var streamBuffer = ""
    private var flushScheduled = false

    /// Cadence de publication : assez courte pour que le texte reste vivant,
    /// assez longue pour laisser la mise en page se faire entre deux.
    static let streamFlushInterval: Duration = .milliseconds(60)

    /// Ouvre une réponse : tampon vidé, texte remis à zéro.
    func beginStreaming() {
        streamBuffer = ""
        flushScheduled = false
        correctedText = ""
        truncated = false
        justCopied = false
        phase = .streaming
    }

    /// Reçoit un fragment. Le premier part tout de suite — le panneau doit
    /// réagir dès le premier mot ; les suivants attendent le prochain vidage.
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

    /// Publie ce qui attend dans le tampon.
    func flushStreamed() {
        flushScheduled = false
        guard !streamBuffer.isEmpty else { return }
        correctedText += streamBuffer
        streamBuffer = ""
    }

    /// Fin du flux : le texte complet remplace ce qui est passé en route, et
    /// ce qui restait dans le tampon avec lui.
    func finishStreaming(with text: String, truncated: Bool) {
        streamBuffer = ""
        flushScheduled = false
        correctedText = text
        self.truncated = truncated
        phase = .done
    }
}

/// Hauteur idéale du panneau entier — remontée à la fenêtre pour qu'elle
/// épouse le contenu (fini le grand rectangle à moitié vide).
private struct PanelHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Hauteur du texte dans le ScrollView — sert à borner la zone de contenu.
private struct TextHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct ResultPanelView: View {
    @ObservedObject var session: CorrectionSession
    /// Corps du texte, lu une fois à la construction du panneau : le réglage
    /// s'applique au panneau suivant, et le panneau courant ne change pas de
    /// taille sous les yeux de qui le lit.
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
            // La palette porte son propre pied (champ de saisie et indices) :
            // le pied commun ne s'affiche que pour les autres phases.
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
            Task { @MainActor in onHeightChange?(height) }
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
            ClaudioBadge()
            Text("Claudio").font(.headline)
            // Pendant la palette, aucune action n'est choisie : la pastille
            // mentirait. La dépense du jour prend sa place.
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
                Text("Capture…")
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
                    Text("Réponse tronquée")
                }
            } else {
                StatusPill(background: .green.opacity(0.16), foreground: .green) {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                    Text("Prêt")
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
                        title: "Aucune sélection détectée",
                        detail: "Sélectionne du texte puis relance le raccourci.")
        case .missingKey:
            messageView(icon: "key",
                        title: "Clé API manquante",
                        detail: "Ajoute ta clé Anthropic dans les Réglages pour activer la correction.")
        case .error(let message):
            messageView(icon: "exclamationmark.triangle",
                        title: "Erreur",
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
                .frame(height: min(max(textHeight, 52), textSize.maxTextHeight))
                .onPreferenceChange(TextHeightKey.self) { height in
                    // La hauteur mesurée saute d'une ligne entière à la fois.
                    // L'interpoler ici plutôt que de la reporter telle quelle
                    // fait suivre la fenêtre image par image : elle glisse au
                    // lieu de sauter, sans que rien n'anime la fenêtre elle-même.
                    Task { @MainActor in
                        withAnimation(.easeOut(duration: 0.18)) { textHeight = height }
                    }
                }
                .onChange(of: session.correctedText) {
                    // Ne suivre le bas que s'il y a de quoi défiler : tant que
                    // le texte tient dans le panneau, il n'y a rien à rattraper.
                    if textHeight > textSize.maxTextHeight {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
    }

    /// Saisie de la consigne (action libre), avec un extrait de la sélection
    /// sous le champ : on transforme un texte qu'on ne voit plus à l'écran.
    private var instructionPrompt: some View {
        VStack(alignment: .leading, spacing: 9) {
            TextField("", text: $session.instruction,
                      prompt: Text("Que faire du texte sélectionné ?"))
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
            // Le focus posé dans le même cycle que l'apparition est perdu :
            // un tour de boucle plus tard, le champ le garde.
            Task { @MainActor in instructionFocused = true }
        }
    }

    /// Texte en streaming avec caret clignotant ; texte simple une fois terminé.
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

    private var footer: some View {
        HStack(spacing: 8) {
            Text("Échap pour fermer").font(.caption2).foregroundStyle(.tertiary)
            Spacer()
            switch session.phase {
            case .askingInstruction:
                Button(action: onSubmitInstruction) {
                    Text("Lancer ") + Text("⏎").fontWeight(.regular).foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(ClaudioProminentButtonStyle())
                .disabled(session.trimmedInstruction.isEmpty)
            case .missingKey:
                Button("Réglages…", action: onOpenSettings)
                    .buttonStyle(PanelPillButtonStyle())
            case .error:
                Button("Réessayer", action: onRetry)
                    .buttonStyle(PanelPillButtonStyle())
            case .done:
                if session.truncated {
                    Button("Réessayer +", action: onRetry)
                        .buttonStyle(PanelPillButtonStyle())
                        .help("Relance avec un budget de tokens doublé")
                }
                Button(action: onCopy) {
                    if session.justCopied {
                        Text("Copié ✓")
                    } else {
                        Text("Copier ") + Text("⌘C").foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(PanelPillButtonStyle())
                Button(action: onPaste) {
                    Text("Coller ") + Text("⏎").fontWeight(.regular).foregroundStyle(.white.opacity(0.7))
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

/// Croix de fermeture du panneau : discrète dans le header, cercle au survol.
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
        .help("Fermer (Échap)")
    }
}
