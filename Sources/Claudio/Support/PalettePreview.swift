import AppKit
import SwiftUI

/// Maquettes de la palette d'actions : cinq pistes de style, rendues avec le
/// vrai thème, les vraies polices et les vrais symboles pour choisir sur pièces.
///
///     Claudio --preview palette-planche          (toutes côte à côte)
///     Claudio --preview palette-terminal | palette-island | palette-neon
///                     | palette-vibe | palette-vibe-question
///     Claudio --preview palette-<style>-libre    (aucune correspondance → consigne)
///
/// Sans `--shot`, la fenêtre reste ouverte : c'est la seule façon de juger les
/// tailles réelles. Échafaudage jetable, remplacé par l'implémentation retenue.

struct PaletteMockRow: Identifiable {
    let id = UUID()
    let symbol: String
    let tint: Color
    let title: String
    /// Colonne de droite : raccourci, ou étiquette pour l'action libre.
    let trailing: String
    /// Sous-titre des styles en deux lignes ; ignoré par les autres.
    var detail: String = ""
}

enum PaletteMockData {
    /// Libellés courts propres à la palette : ceux du menu sont trop longs pour
    /// une liste (« Lapacompris : expliquer simplement » passe à la ligne).
    private static let labels: [(title: String, shortcut: String, detail: String)] = [
        ("Corriger", "⌃⌥⌘I", "Orthographe, grammaire, ponctuation"),
        ("Structurer en prompt", "⌃⌥⌘P", "Transforme une idée en prompt clair"),
        ("Prompt expert", "⌃⌥⌘^", "Contraintes, format et critères de sortie"),
        ("Traduire en français", "⌃⌥⌘F", "Depuis n'importe quelle langue"),
        ("Traduire en anglais", "⌃⌥⌘E", "Depuis n'importe quelle langue"),
        ("Ton professionnel", "⌃⌥⌘T", "Reformule pour un contexte de travail"),
        ("Résumer", "⌃⌥⌘R", "Points clés, format court"),
        ("Expliquer simplement", "⌃⌥⌘L", "Lapacompris : sans jargon"),
    ]

    static var catalog: [PaletteMockRow] {
        zip(ClaudioAction.allCases, labels).map { action, label in
            PaletteMockRow(symbol: action.symbolName, tint: action.tint,
                           title: label.title, trailing: label.shortcut, detail: label.detail)
        }
    }

    static func free(instruction: String) -> PaletteMockRow {
        let origin = ClaudioRequest.awaitingInstruction.origin
        return PaletteMockRow(
            symbol: origin.symbolName,
            tint: origin.tint,
            title: instruction.isEmpty ? "Action libre" : instruction,
            trailing: instruction.isEmpty ? "⌃⌥⌘D" : "consigne libre",
            detail: instruction.isEmpty ? "Écrire sa propre consigne" : "Envoyé tel quel comme instruction"
        )
    }

    /// Au repos : le catalogue, puis l'action libre en dernier.
    static var atRest: [PaletteMockRow] { catalog + [free(instruction: "")] }
}

// MARK: - Piste 1 : Terminal

/// Ligne de commande : monospace, chevron, barre d'accent à gauche de la
/// sélection. Rien de décoratif, tout est lisible d'un coup d'œil.
struct PaletteTerminal: View {
    var query: String = ""
    var rows: [PaletteMockRow] = PaletteMockData.atRest
    var selected: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Text("❯").foregroundStyle(ClaudioTheme.accent)
                if query.isEmpty {
                    Text("action ou consigne…").foregroundStyle(.white.opacity(0.26))
                } else {
                    Text(query).foregroundStyle(.white.opacity(0.95))
                    Text("▌").foregroundStyle(ClaudioTheme.accent)
                }
                Spacer()
                Text("\(rows.count)").foregroundStyle(.white.opacity(0.22))
            }
            .font(.system(size: 14, design: .monospaced))
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Color.white.opacity(0.07).frame(height: 1)

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    let isSelected = index == selected
                    HStack(spacing: 10) {
                        Rectangle()
                            .fill(isSelected ? ClaudioTheme.accent : .clear)
                            .frame(width: 2)
                        Image(systemName: row.symbol)
                            .font(.system(size: 11))
                            .foregroundStyle(isSelected ? row.tint : row.tint.opacity(0.5))
                            .frame(width: 16)
                        Text(row.title)
                            .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
                        Spacer()
                        Text(row.trailing)
                            .foregroundStyle(.white.opacity(isSelected ? 0.42 : 0.2))
                            .padding(.trailing, 13)
                    }
                    .font(.system(size: 12.5, design: .monospaced))
                    .frame(height: 30)
                    .background(isSelected ? Color.white.opacity(0.055) : .clear)
                }
            }
            .padding(.vertical, 4)

            Color.white.opacity(0.07).frame(height: 1)

            HStack(spacing: 16) {
                Text("↑↓ naviguer")
                Text("⏎ lancer")
                Text("esc fermer")
                Spacer()
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.white.opacity(0.3))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .frame(width: Constants.panelWidth)
        .background(Color(red: 0.048, green: 0.048, blue: 0.058),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(.white.opacity(0.09), lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Piste 2 : pastilles Claudio

/// Prolonge le panneau existant : pastilles colorées, capsules, dégradé Claudio
/// sur la ligne sélectionnée. La palette a l'air d'appartenir à la même app.
struct PaletteIsland: View {
    var query: String = ""
    var rows: [PaletteMockRow] = PaletteMockData.atRest
    var selected: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ClaudioBadge()
                Text("Claudio").font(.headline)
                StatusPill {
                    Image(systemName: "command")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(ClaudioTheme.accent)
                    Text("Palette")
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 11)
            .padding(.bottom, 10)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
                if query.isEmpty {
                    Text("Chercher une action, ou écrire une consigne…")
                        .foregroundStyle(.white.opacity(0.3))
                } else {
                    Text(query).foregroundStyle(.white.opacity(0.92))
                }
                Spacer()
            }
            .font(.body)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.06), in: Capsule())
            .padding(.horizontal, 12)
            .padding(.bottom, 9)

            VStack(spacing: 3) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    let isSelected = index == selected
                    HStack(spacing: 10) {
                        IconBadge(systemName: row.symbol, color: row.tint, size: 22)
                        Text(row.title)
                            .font(.callout)
                            .foregroundStyle(isSelected ? .white : .white.opacity(0.78))
                        Spacer()
                        Text(row.trailing)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(isSelected ? 0.85 : 0.34))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Color.white.opacity(isSelected ? 0.18 : 0.05), in: Capsule())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(ClaudioTheme.gradient)
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            ClaudioTheme.panelSeparator.frame(height: 1)

            HStack {
                Text("↑↓ naviguer · ⏎ lancer")
                Spacer()
                Text("Échap pour fermer")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .frame(width: Constants.panelWidth)
        .background(ClaudioTheme.panelBackground,
                    in: RoundedRectangle(cornerRadius: ClaudioTheme.panelCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ClaudioTheme.panelCornerRadius, style: .continuous)
                .strokeBorder(ClaudioTheme.panelBorder, lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Piste 3 : Néon

/// Cyberpunk assumé : quasi-noir, cyan et magenta autour du violet Claudio,
/// index numérotés, halo sur la sélection et sur le cadre.
struct PaletteNeon: View {
    var query: String = ""
    var rows: [PaletteMockRow] = PaletteMockData.atRest
    var selected: Int = 0

    private let cyan = Color(red: 0.42, green: 0.94, blue: 1.0)
    private let magenta = Color(red: 0.98, green: 0.36, blue: 0.78)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("CLAUDIO").foregroundStyle(magenta)
                Text("//").foregroundStyle(.white.opacity(0.22))
                Text("PALETTE").foregroundStyle(cyan)
                Spacer()
                Text("\(rows.count) ACTIONS").foregroundStyle(.white.opacity(0.22))
            }
            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
            .tracking(1.7)
            .padding(.horizontal, 15)
            .padding(.top, 12)
            .padding(.bottom, 10)

            HStack(spacing: 9) {
                Text(">").foregroundStyle(cyan)
                if query.isEmpty {
                    Text("action ou consigne…").foregroundStyle(.white.opacity(0.24))
                } else {
                    Text(query).foregroundStyle(.white.opacity(0.95))
                    Text("▮").foregroundStyle(cyan)
                }
                Spacer()
            }
            .font(.system(size: 14, design: .monospaced))
            .padding(.horizontal, 15)
            .padding(.bottom, 11)

            LinearGradient(colors: [magenta.opacity(0.6), cyan.opacity(0.35), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    let isSelected = index == selected
                    HStack(spacing: 11) {
                        Rectangle()
                            .fill(isSelected ? cyan : .clear)
                            .frame(width: 2)
                            .shadow(color: isSelected ? cyan.opacity(0.9) : .clear, radius: 5)
                        Text(String(format: "[%d]", index + 1))
                            .foregroundStyle(isSelected ? cyan : .white.opacity(0.22))
                        Image(systemName: row.symbol)
                            .font(.system(size: 11))
                            .foregroundStyle(isSelected ? row.tint : row.tint.opacity(0.5))
                            .frame(width: 16)
                        Text(row.title)
                            .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
                        Spacer()
                        Text(row.trailing)
                            .foregroundStyle(isSelected ? cyan.opacity(0.9) : .white.opacity(0.28))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder((isSelected ? cyan : Color.white).opacity(isSelected ? 0.45 : 0.1),
                                                  lineWidth: 1)
                            )
                            .padding(.trailing, 13)
                    }
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 31)
                    .background {
                        if isSelected {
                            LinearGradient(colors: [magenta.opacity(0.2), cyan.opacity(0.05)],
                                           startPoint: .leading, endPoint: .trailing)
                        }
                    }
                }
            }
            .padding(.vertical, 4)

            LinearGradient(colors: [.clear, cyan.opacity(0.25), magenta.opacity(0.45)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)

            HStack(spacing: 16) {
                Text("↑↓ NAV")
                Text("⏎ RUN")
                Text("ESC EXIT")
                Spacer()
            }
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(1.2)
            .foregroundStyle(cyan.opacity(0.5))
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
        }
        .frame(width: Constants.panelWidth)
        .background(Color(red: 0.035, green: 0.03, blue: 0.05),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(magenta.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: magenta.opacity(0.3), radius: 16)
        .padding(16)  // laisse la place au halo dans la fenêtre
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Vibe Island : vocabulaire commun

/// Vocabulaire relevé dans le code de Vibe Island (`open-vibe-island`) plutôt
/// que dans une capture : `V6Palette`, `IslandDesignPalette.Status` et les
/// couleurs de marque par agent d'`AgentSession`.
enum VibeTheme {
    /// Les deux seules couleurs du châssis. Le texte n'est jamais blanc pur :
    /// c'est un ivoire tiède posé sur une encre presque noire.
    static let ink = Color(red: 0x0d / 255.0, green: 0x0d / 255.0, blue: 0x0f / 255.0)
    static let paper = Color(red: 0xf1 / 255.0, green: 0xea / 255.0, blue: 0xd9 / 255.0)

    /// Le vocabulaire d'état, sourd et fermé : cinq teintes qui veulent chacune
    /// dire quelque chose. Rien d'autre n'a le droit d'être coloré.
    static let attention = Color(red: 0xff / 255.0, green: 0xd5 / 255.0, blue: 0x8a / 255.0)
    static let enCours = Color(red: 0x6e / 255.0, green: 0xa7 / 255.0, blue: 0xff / 255.0)
    static let fait = Color(red: 0x6f / 255.0, green: 0xb9 / 255.0, blue: 0x82 / 255.0)
    /// La couleur de marque de Claude Code : voilà l'ambre de la capture. Elle
    /// n'habille pas, elle dit « c'est Claude qui parle ».
    static let claude = Color(red: 0xd9 / 255.0, green: 0x77 / 255.0, blue: 0x42 / 255.0)

    /// Même largeur que le panneau de résultat : les deux surfaces doivent
    /// avoir l'air d'appartenir au même objet.
    static let width = Constants.panelWidth
}

/// La jauge de quota de Vibe Island, transposée au budget de Claudio :
/// nom, fenêtre, valeur — la valeur seule est colorée, par seuil.
private struct VibeGauge: View {
    var scope: String = "auj."
    var value: String = "0,42 €"
    var level: Double = 0.18

    private var tint: Color {
        switch level {
        case 0.9...: .red.opacity(0.95)
        case 0.7..<0.9: .orange.opacity(0.95)
        default: VibeTheme.fait
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Text("Claudio")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(VibeTheme.paper.opacity(0.74))
            Text(scope)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(VibeTheme.paper.opacity(0.42))
            Text(value)
                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.white.opacity(0.055), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.06), lineWidth: 1))
    }
}

/// L'étiquette latérale de Vibe Island : mono, ivoire éteint, fond neutre.
private struct VibeBadge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .foregroundStyle(VibeTheme.paper.opacity(0.7))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.white.opacity(0.06), in: Capsule())
    }
}

/// Le champ de réponse : sans bordure ni fond propre chez Vibe Island, posé
/// dans un bloc à peine plus clair, avec le rappel de la touche à droite.
private struct VibeField: View {
    let query: String

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if query.isEmpty {
                    Text("Filtrer, ou écrire une consigne…")
                        .foregroundStyle(VibeTheme.paper.opacity(0.35))
                } else {
                    Text(query).foregroundStyle(VibeTheme.paper)
                }
            }
            .font(.system(size: 13))
            Spacer(minLength: 8)
            Text("⏎")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(VibeTheme.paper.opacity(0.34))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.03),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.05), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }
}

// MARK: - Piste 4 : Vibe Island, registre liste

/// La liste de sessions de Vibe Island : aucune carte, des filets d'un pixel
/// entre les lignes, un liseré de 3 pt à gauche de la ligne active, et un texte
/// dense en ivoire. Les seules couleurs sont les icônes des actions.
struct PaletteVibe: View {
    var query: String = ""
    var rows: [PaletteMockRow] = PaletteMockData.atRest
    var selected: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "mustache.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(VibeTheme.paper.opacity(0.8))
                Text("Que faire de la sélection ?")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(VibeTheme.paper.opacity(0.6))
                Spacer(minLength: 10)
                VibeGauge()
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 11)

            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                let isSelected = index == selected
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: row.symbol)
                        .font(.system(size: 13))
                        .foregroundStyle(row.tint.opacity(isSelected ? 1 : 0.75))
                        .frame(width: 20, alignment: .top)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.title)
                            .font(.system(size: 13.2, weight: .semibold))
                            .foregroundStyle(VibeTheme.paper.opacity(isSelected ? 0.96 : 0.8))
                        Text(row.detail)
                            .font(.system(size: 11.2, weight: .medium))
                            .foregroundStyle(VibeTheme.paper.opacity(isSelected ? 0.52 : 0.36))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 10)
                    VibeBadge(text: row.trailing)
                }
                .padding(.leading, 28)
                .padding(.trailing, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isSelected ? Color.white.opacity(0.04) : .clear)
                .overlay(alignment: .top) {
                    Rectangle().fill(.white.opacity(0.045)).frame(height: 1)
                }
                .overlay(alignment: .leading) {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 999, style: .continuous)
                            .fill(VibeTheme.paper.opacity(0.85))
                            .frame(width: 3)
                            .padding(.vertical, 8)
                            .padding(.leading, 12)
                    }
                }
            }

            VibeField(query: query)
        }
        .frame(width: VibeTheme.width)
        .background(VibeTheme.ink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.07), lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Piste 5 : Vibe Island, registre options

/// Le bloc de question de Vibe Island : des options numérotées dans de petites
/// cartes, et une sélection qui s'annonce par une inversion ivoire plutôt que
/// par une couleur. Chaque ligne se lance aussi au chiffre.
struct PaletteVibeQuestion: View {
    var query: String = ""
    var rows: [PaletteMockRow] = PaletteMockData.atRest
    var selected: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "mustache.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(VibeTheme.paper.opacity(0.8))
                Text("Claudio")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VibeTheme.paper.opacity(0.8))
                Spacer(minLength: 10)
                VibeGauge()
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 9)

            Text("Que faire de la sélection ?")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(VibeTheme.paper.opacity(0.88))
                .padding(.horizontal, 14)
                .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    let isSelected = index == selected
                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(isSelected ? VibeTheme.ink.opacity(0.82)
                                                        : VibeTheme.paper.opacity(0.42))
                            .frame(width: 22, height: 20)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(isSelected ? VibeTheme.paper.opacity(0.88)
                                                     : Color.white.opacity(0.045))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .strokeBorder(.white.opacity(isSelected ? 0 : 0.08))
                            )
                        Image(systemName: row.symbol)
                            .font(.system(size: 12.5))
                            .foregroundStyle(row.tint.opacity(isSelected ? 1 : 0.75))
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.title)
                                .font(.system(size: 12.2, weight: .medium))
                                .foregroundStyle(VibeTheme.paper.opacity(isSelected ? 1 : 0.78))
                            Text(row.detail)
                                .font(.system(size: 10.5))
                                .foregroundStyle(VibeTheme.paper.opacity(isSelected ? 0.48 : 0.38))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        VibeBadge(text: row.trailing)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isSelected ? VibeTheme.paper.opacity(0.10)
                                             : Color.white.opacity(0.028))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isSelected ? VibeTheme.paper.opacity(0.36)
                                                     : .white.opacity(0.045))
                    )
                }
            }
            .padding(.horizontal, 10)

            VibeField(query: query)
        }
        .frame(width: VibeTheme.width)
        .background(VibeTheme.ink, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.07), lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Planche de comparaison

/// Les cinq pistes côte à côte, à leur taille réelle, sur un fond neutre.
struct PalettePlanche: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack(alignment: .top, spacing: 30) {
                labelled("1 · Terminal") { PaletteTerminal() }
                labelled("2 · Pastilles Claudio") { PaletteIsland() }
                labelled("3 · Néon") { PaletteNeon() }
            }
            HStack(alignment: .top, spacing: 30) {
                labelled("4 · Vibe Island, registre liste") { PaletteVibe() }
                labelled("5 · Vibe Island, registre options") { PaletteVibeQuestion() }
                Spacer(minLength: 0)
            }
        }
        .padding(34)
        .background(Color(red: 0.115, green: 0.115, blue: 0.13))
        .environment(\.colorScheme, .dark)
    }

    private func labelled<V: View>(_ title: String, @ViewBuilder content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            content()
        }
    }
}

// MARK: - Hôte d'aperçu

@MainActor
enum PaletteMockPanel {
    /// Construit le panneau de la maquette demandée, dimensionné à son contenu.
    static func make(mode: String) -> ResultPanel {
        let asksInstruction = mode.hasSuffix("-libre")
        let query = asksInstruction ? "mets ça au passé" : ""
        let rows = asksInstruction
            ? [PaletteMockData.free(instruction: query)]
            : PaletteMockData.atRest

        let content: AnyView
        if mode.hasPrefix("palette-planche") {
            content = AnyView(PalettePlanche())
        } else if mode.hasPrefix("palette-terminal") {
            content = AnyView(PaletteTerminal(query: query, rows: rows))
        } else if mode.hasPrefix("palette-neon") {
            content = AnyView(PaletteNeon(query: query, rows: rows))
        } else if mode.hasPrefix("palette-vibe-question") {
            content = AnyView(PaletteVibeQuestion(query: query, rows: rows))
        } else if mode.hasPrefix("palette-vibe") {
            content = AnyView(PaletteVibe(query: query, rows: rows))
        } else {
            content = AnyView(PaletteIsland(query: query, rows: rows))
        }

        let panel = ResultPanel(contentView: NSView())
        let hosting = NSHostingView(rootView: content)
        hosting.appearance = NSAppearance(named: .darkAqua)
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting
        panel.setContentSize(size)
        return panel
    }
}
