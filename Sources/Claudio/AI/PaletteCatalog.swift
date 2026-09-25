import Foundation

/// One row of the palette: what's needed to display it, and what launching
/// it does. A request is only built at that moment: building it on every
/// keystroke would re-read the custom prompts from Settings for nothing.
struct PaletteRow: Identifiable {
    /// What a row launches. Most send a request about the selection; one
    /// isn't a request at all, and has no place in `ClaudioRequest.Origin`,
    /// whose cases the Stream Deck's names and Settings go through.
    enum Kind: Equatable {
        /// A catalog action, or the custom one.
        case request(ClaudioRequest.Origin)
        /// "What's playing?": reads the player, needs no selection, and
        /// hands over to a panel of its own.
        case whatsPlaying
    }

    let kind: Kind
    let title: String
    let detail: String
    /// Right-hand column: the global shortcut, or the custom action's label.
    let trailing: String

    var id: String {
        switch kind {
        case .request(.catalog(let action)): action.rawValue
        case .request(.free): "free"
        case .whatsPlaying: "whatsPlaying"
        }
    }

    /// Where the request this row sends comes from, `nil` for the row that
    /// sends none.
    var origin: ClaudioRequest.Origin? {
        guard case .request(let origin) = kind else { return nil }
        return origin
    }

    /// The request this row sends, built now; `nil` for "What's playing?".
    var request: ClaudioRequest? { origin.map(Self.request(for:)) }

    /// The request a row of this origin sends.
    static func request(for origin: ClaudioRequest.Origin) -> ClaudioRequest {
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

    /// The rank shown in front of the row at `index`, which is also the digit
    /// that launches it. Nine digits, nine ranks: a row past the ninth shows
    /// none rather than a "10" no key can type.
    static func rank(ofIndex index: Int) -> Int? {
        (0..<9).contains(index) ? index + 1 : nil
    }

    /// Catalog actions kept by the typed query (`finds(_:in:)`).
    static func matches(_ query: String) -> [ClaudioAction] {
        let needles = query.searchWords
        return ClaudioAction.allCases.filter { action in
            finds(needles, in: "\(action.paletteTitle) \(action.paletteDetail) \(action.menuTitle)")
        }
    }

    /// Every word of the query must start a word of the text: "trad ang"
    /// finds the English translation, not the French one, even though its
    /// subtitle contains "langue". Accents and case are ignored: nobody types
    /// "français" with the cedilla as the third character. An empty query
    /// finds everything.
    private static func finds(_ needles: [String], in text: String) -> Bool {
        let haystack = text.searchWords
        return needles.allSatisfy { needle in
            haystack.contains { $0.hasPrefix(needle) }
        }
    }

    /// Rows shown for a given query: the matched actions, then the custom
    /// action. It's always there: it's the escape hatch for when the catalog
    /// doesn't cover what's wanted, and it takes the typed text as its
    /// instruction.
    ///
    /// Where "What's playing?" goes depends on whether anything is typed.
    /// Nothing typed, the palette is a menu: it comes after everything that
    /// transforms the selection, so the ranks they have always had keep
    /// launching them — 9 is still the custom action — and it goes without
    /// one past the ninth, its own shortcut being there to launch it. Typed,
    /// the palette is a search: what the query finds comes first and the
    /// escape hatch last, so "What's playing?" found by "musique" takes the
    /// top, where Enter launches it.
    ///
    /// With nothing selected, only what works without a selection: "What's
    /// playing?", then the custom action — which, with no text to transform,
    /// sends what was typed as a request of its own. The catalog would have
    /// nothing to work on.
    @MainActor
    static func rows(matching query: String, hasSelection: Bool = true) -> [PaletteRow] {
        let whatsPlaying = whatsPlayingRow(matching: query).map { [$0] } ?? []
        let instruction = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let free = PaletteRow(
            kind: .request(.free(instruction: instruction)),
            title: instruction.isEmpty ? loc("Action libre", en: "Custom action") : instruction,
            detail: instruction.isEmpty ? loc("Écrire sa propre consigne", en: "Write your own instruction")
                                        : loc("Envoyé tel quel comme instruction", en: "Sent as-is as the instruction"),
            trailing: instruction.isEmpty ? ClaudioRequest.freeShortcutDescription : freeBadge
        )
        guard hasSelection else { return whatsPlaying + [free] }

        let catalog = matches(query).map { action in
            PaletteRow(kind: .request(.catalog(action)),
                       title: action.paletteTitle,
                       detail: action.paletteDetail,
                       trailing: action.shortcutDescription)
        }
        return instruction.isEmpty ? catalog + [free] + whatsPlaying
                                   : catalog + whatsPlaying + [free]
    }

    /// "What's playing?", when the query finds it: in its labels, or in the
    /// words someone after the track would type.
    @MainActor
    private static func whatsPlayingRow(matching query: String) -> PaletteRow? {
        let labels = "\(ListeningSession.menuTitle) \(ListeningSession.paletteDetail)"
        guard finds(query.searchWords, in: "\(labels) \(ListeningSession.searchTerms)") else { return nil }
        return PaletteRow(kind: .whatsPlaying,
                          title: ListeningSession.menuTitle,
                          detail: ListeningSession.paletteDetail,
                          trailing: ListeningSession.shortcutDescription)
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
