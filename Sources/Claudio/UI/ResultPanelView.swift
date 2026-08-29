import SwiftUI

@MainActor
final class CorrectionSession: ObservableObject {
    enum Phase: Equatable {
        case capturing
        case streaming
        case done
        case noSelection
        case missingKey
        case error(String)
    }

    let action: ClaudioAction
    init(action: ClaudioAction) { self.action = action }

    @Published var phase: Phase = .capturing
    @Published var correctedText = ""
    @Published var truncated = false
    @Published var justCopied = false
    var originalText = ""
    var maxTokensMultiplier = 1

    var canPaste: Bool { phase == .done && !correctedText.isEmpty }
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
    let onPaste: () -> Void
    let onCopy: () -> Void
    let onRetry: () -> Void
    let onOpenSettings: () -> Void
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
        .frame(width: Constants.panelWidth)
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
            StatusPill {
                Image(systemName: session.action.symbolName)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(session.action.tint)
                Text(session.action.panelTitle)
            }
            Spacer()
            statusLabel
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
                Text(session.action.progressLabel)
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
        case .noSelection, .missingKey, .error:
            EmptyView()
        }
    }

    @ViewBuilder private var content: some View {
        switch session.phase {
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
                            .font(.body)
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
                .frame(height: min(max(textHeight, 52), Constants.panelMaxTextHeight))
                .onPreferenceChange(TextHeightKey.self) { height in
                    Task { @MainActor in textHeight = height }
                }
                .onChange(of: session.correctedText) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
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
            Text(title).font(.headline)
            Text(detail)
                .font(.callout)
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
