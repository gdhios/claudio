import Foundation

/// One row of the palette: what's needed to display it, and the origin that
/// will produce the request at launch time. The request is only built at
/// that moment: building it on every keystroke would re-read the custom
/// prompts from Settings for nothing.
struct PaletteRow: Identifiable {
    let origin: ClaudioRequest.Origin
    let title: String
    let detail: String
    /// Right-hand column: the global shortcut, or the custom action's label.
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

/// What the palette offers, and how typing filters it.
enum PaletteCatalog {
    /// Label in the menu bar's menu and in Settings.
    static var menuTitle: String { loc("Palette d'actions…", en: "Action palette…") }

    /// Label of the custom-action row when an instruction has been typed: what
    /// was typed goes out as is as the instruction.
    static var freeBadge: String { loc("consigne", en: "custom") }

    /// Catalog actions kept by the typed query. Every word of the query must
    /// start a word of the title or subtitle: "trad ang" finds the English
    /// translation, not the French one, even though its subtitle contains
    /// "langue". Accents and case are ignored: nobody types "français" with
    /// the cedilla as the third character.
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

    /// Rows shown for a given query: the matched actions, then the custom
    /// action last. It's always there: it's the escape hatch for when the
    /// catalog doesn't cover what's wanted, and it takes the typed text as
    /// its instruction.
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
            title: instruction.isEmpty ? loc("Action libre", en: "Custom action") : instruction,
            detail: instruction.isEmpty ? loc("Écrire sa propre consigne", en: "Write your own instruction")
                                        : loc("Envoyé tel quel comme instruction", en: "Sent as-is as the instruction"),
            trailing: instruction.isEmpty ? ClaudioRequest.freeShortcutDescription : freeBadge
        )
        return catalog + [free]
    }
}

private extension String {
    /// Comparable words: no accents, no case, no punctuation.
    var searchWords: [String] {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }
}
