import Foundation

/// Une ligne de la palette : de quoi l'afficher, et l'origine qui donnera la
/// requête au moment du lancement. La requête n'est construite qu'à ce
/// moment-là : la bâtir à chaque frappe relirait les prompts personnalisés
/// des Réglages pour rien.
struct PaletteRow: Identifiable {
    let origin: ClaudioRequest.Origin
    let title: String
    let detail: String
    /// Colonne de droite : le raccourci global, ou l'étiquette de l'action libre.
    let trailing: String

    var id: String {
        switch origin {
        case .catalog(let action): action.rawValue
        case .free: "free"
        }
    }

    var request: ClaudioRequest {
        switch origin {
        case .catalog(let action): action.request
        case .free(let instruction): .free(instruction: instruction)
        }
    }
}

/// Ce que la palette propose, et comment la saisie le filtre.
enum PaletteCatalog {
    /// Libellé dans le menu de la barre et dans les Réglages.
    static let menuTitle = "Palette d'actions…"

    /// Étiquette de la ligne d'action libre quand une consigne est écrite : ce
    /// qui est tapé part tel quel comme instruction.
    static let freeBadge = "consigne"

    /// Actions du catalogue retenues par la saisie. Chaque mot de la requête
    /// doit commencer un mot du titre ou du sous-titre : « trad ang » trouve la
    /// traduction en anglais, et pas la française — dont le sous-titre contient
    /// pourtant « langue ». Accents et casse sont ignorés : personne ne tape
    /// « français » avec la cédille au troisième caractère.
    static func matches(_ query: String) -> [ClaudioAction] {
        let needles = query.searchWords
        guard !needles.isEmpty else { return ClaudioAction.allCases }
        return ClaudioAction.allCases.filter { action in
            let haystack = "\(action.paletteTitle) \(action.paletteDetail) \(action.menuTitle)".searchWords
            return needles.allSatisfy { needle in
                haystack.contains { $0.hasPrefix(needle) }
            }
        }
    }

    /// Lignes affichées pour une saisie donnée : les actions retenues, puis
    /// l'action libre en dernier. Elle est toujours là — c'est la porte de
    /// sortie quand le catalogue ne couvre pas ce qu'on veut, et elle reprend
    /// la saisie comme consigne.
    @MainActor
    static func rows(matching query: String) -> [PaletteRow] {
        let instruction = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let catalog = matches(query).map { action in
            PaletteRow(origin: .catalog(action),
                       title: action.paletteTitle,
                       detail: action.paletteDetail,
                       trailing: action.shortcutDescription)
        }
        let free = PaletteRow(
            origin: .free(instruction: instruction),
            title: instruction.isEmpty ? "Action libre" : instruction,
            detail: instruction.isEmpty ? "Écrire sa propre consigne"
                                        : "Envoyé tel quel comme instruction",
            trailing: instruction.isEmpty ? ClaudioRequest.freeShortcutDescription : freeBadge
        )
        return catalog + [free]
    }
}

private extension String {
    /// Mots comparables : sans accents, sans casse, sans ponctuation.
    var searchWords: [String] {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }
}
