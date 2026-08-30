import SwiftUI

/// La palette d'actions : tout le catalogue sous les yeux, filtrable à la
/// frappe, et une dernière ligne qui reprend la saisie comme consigne libre
/// quand rien ne convient. Le même châssis que le panneau de résultat — c'est
/// le même objet qui se transforme une fois l'action choisie.
struct PaletteView: View {
    @ObservedObject var session: CorrectionSession
    /// Corps du texte, réglé dans les Réglages (Général → Panneau).
    var textSize: PanelTextSize = .normal
    /// Lance la ligne d'index donné.
    let onLaunch: (Int) -> Void

    @FocusState private var queryFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            question
            rows
            ClaudioTheme.panelSeparator.frame(height: 1).padding(.top, 10)
            field
            hints
        }
        .onAppear {
            // Même précaution que pour le champ de consigne : le focus posé
            // dans le cycle d'apparition est perdu, un tour plus tard il tient.
            Task { @MainActor in queryFocused = true }
        }
    }

    private var question: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Que faire de la sélection ?")
                .font(.system(size: textSize.points(12), weight: .medium))
                .foregroundStyle(.white.opacity(0.88))
            Text(session.originalText)
                .font(.system(size: textSize.points(10)))
                .foregroundStyle(.white.opacity(0.32))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.top, 11)
        .padding(.bottom, 9)
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(session.paletteRows.enumerated()), id: \.element.id) { index, row in
                PaletteRowView(row: row,
                               number: index + 1,
                               isSelected: index == session.paletteSelection,
                               textSize: textSize)
                    .contentShape(Rectangle())
                    .onHover { if $0 { session.paletteSelection = index } }
                    .onTapGesture { onLaunch(index) }
            }
        }
        .padding(.horizontal, 10)
    }

    /// Le champ fait deux métiers à la fois : il filtre le catalogue, et ce qui
    /// y reste écrit devient la consigne si c'est la dernière ligne qu'on lance.
    private var field: some View {
        HStack(spacing: 10) {
            TextField("", text: $session.paletteQuery,
                      prompt: Text("Filtrer, ou écrire une consigne…")
                        .foregroundStyle(.white.opacity(0.3)))
                .textFieldStyle(.plain)
                .font(.system(size: textSize.bodyPoints))
                .foregroundStyle(.white.opacity(0.95))
                .focused($queryFocused)
                .onSubmit { onLaunch(session.paletteSelection) }
            Text("⏎")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.34))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(.white.opacity(0.07), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }

    private var hints: some View {
        HStack(spacing: 12) {
            Text("↑↓ naviguer")
            // Le chiffre nu lance tant que rien n'est écrit ; après, il
            // s'écrit, et c'est ⌘ qui lance. L'indice suit plutôt qu'il ne
            // promette à moitié.
            Text(session.paletteQuery.isEmpty ? "1–9 lancer" : "⌘1–9 lancer")
            Text("échap fermer")
            Spacer()
        }
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.28))
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}

/// Une ligne : son rang, son icône, ce qu'elle fait en deux lignes, son
/// raccourci. La sélection s'annonce par une inversion sobre plutôt que par
/// une couleur — les seules couleurs de la liste sont les icônes des actions.
private struct PaletteRowView: View {
    let row: PaletteRow
    let number: Int
    let isSelected: Bool
    /// Le libellé de l'action suit le réglage de taille ; le rang, l'icône et
    /// le raccourci restent fixes — ce sont des repères, pas de la lecture.
    var textSize: PanelTextSize = .normal

    var body: some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(isSelected ? ClaudioTheme.panelBackground : .white.opacity(0.42))
                .frame(width: 22, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.88) : Color.white.opacity(0.045))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(.white.opacity(isSelected ? 0 : 0.08))
                )

            Image(systemName: row.origin.symbolName)
                .font(.system(size: 12.5))
                .foregroundStyle(row.origin.tint.opacity(isSelected ? 1 : 0.75))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .font(.system(size: textSize.points(12.2), weight: .medium))
                    .foregroundStyle(.white.opacity(isSelected ? 1 : 0.78))
                    .lineLimit(1)
                Text(row.detail)
                    .font(.system(size: textSize.points(10.5)))
                    .foregroundStyle(.white.opacity(isSelected ? 0.5 : 0.38))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if !row.trailing.isEmpty {
                Text(row.trailing)
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.62))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.white.opacity(0.06), in: Capsule())
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.10) : Color.white.opacity(0.028))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? .white.opacity(0.34) : .white.opacity(0.045))
        )
    }
}

/// Dépense du jour dans le header de la palette : le moment où on choisit une
/// action est le bon moment pour voir ce que la journée a coûté. Absente si le
/// compteur est désactivé dans les Réglages.
struct CostGauge: View {
    @ObservedObject private var ledger = CostLedger.shared

    var body: some View {
        if AppSettings.costCounterEnabled {
            HStack(spacing: 5) {
                Text("auj.")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.42))
                Text(ledger.day.formattedTotal)
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.78))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.055), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.06), lineWidth: 1))
            .onAppear { ledger.refresh() }
        }
    }
}
