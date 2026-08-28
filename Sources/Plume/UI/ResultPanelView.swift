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

    let action: PlumeAction
    init(action: PlumeAction) { self.action = action }

    @Published var phase: Phase = .capturing
    @Published var correctedText = ""
    @Published var truncated = false
    @Published var justCopied = false
    var originalText = ""
    var maxTokensMultiplier = 1

    var canPaste: Bool { phase == .done && !correctedText.isEmpty }
}

struct ResultPanelView: View {
    @ObservedObject var session: CorrectionSession
    let onPaste: () -> Void
    let onCopy: () -> Void
    let onRetry: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: Constants.panelSize.width, height: Constants.panelSize.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.separator, lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "wand.and.stars").foregroundStyle(.secondary)
            Text("Plume").font(.headline)
            Text(session.action.panelTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            statusLabel
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder private var statusLabel: some View {
        switch session.phase {
        case .capturing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Capture…")
            }
            .font(.caption).foregroundStyle(.secondary)
        case .streaming:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(session.action.progressLabel)
            }
            .font(.caption).foregroundStyle(.secondary)
        case .done:
            if session.truncated {
                Label("Réponse tronquée", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            } else {
                Label("Prêt", systemImage: "checkmark.circle")
                    .font(.caption).foregroundStyle(.green)
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
                    Text(session.correctedText.isEmpty ? " " : session.correctedText)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                    Color.clear.frame(height: 1).id("bottom")
                }
                .onChange(of: session.correctedText) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("Échap pour fermer").font(.caption2).foregroundStyle(.tertiary)
            Spacer()
            switch session.phase {
            case .missingKey:
                Button("Réglages…", action: onOpenSettings)
            case .error:
                Button("Réessayer", action: onRetry)
            case .done:
                if session.truncated {
                    Button("Réessayer +", action: onRetry)
                        .help("Relance avec un budget de tokens doublé")
                }
                Button(session.justCopied ? "Copié ✓" : "Copier", action: onCopy)
                Button("Coller ⏎", action: onPaste)
                    .buttonStyle(.borderedProminent)
                    .disabled(!session.canPaste)
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
