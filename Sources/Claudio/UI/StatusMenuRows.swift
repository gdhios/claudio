import KeyboardShortcuts

/// A line of the menu under Claudio in the menu bar, as a value. `StatusMenu`
/// turns the list into menu items, the `barre-de-menus` preview draws it,
/// and a test reads it; nothing here touches AppKit.
enum StatusMenuRow: Equatable {
    case separator
    /// A section's name, above its rows.
    case header(String)
    case item(StatusMenuItem)
}

/// What a click on a row does. The app delegate answers through
/// `StatusMenuActions`.
enum StatusMenuCommand: Equatable {
    case installUpdate
    case palette
    case action(ClaudioAction)
    case freeAction
    case whatsPlaying
    /// Settings where they were left: the menu's own "Settings…".
    case settings
    /// Settings on a named tab.
    case settingsSection(SettingsSection)
    case quit
}

struct StatusMenuItem: Equatable {
    /// Which row it is, whatever its title says today: the menu keeps one
    /// menu item per entry from one opening to the next.
    enum Entry: Hashable {
        case update, palette, action(ClaudioAction), freeAction, whatsPlaying
        case recents, recentDictations, dictationHistory
        case dictationStatus, ulanziStatus, streamDeckStatus
        case tip, settings, about, quit
    }

    let entry: Entry
    let title: String
    /// An SF Symbol, drawn as a template at the menu's size.
    var symbol: String?
    /// The global shortcut shown on the right.
    var shortcut: KeyboardShortcuts.Name?
    /// A plain ⌘ key equivalent, for Settings and Quit. Empty: none.
    var keyEquivalent = ""
    /// nil for a row that only opens its submenu.
    var command: StatusMenuCommand?
    var isEnabled = true

    /// The two histories, whose rows are made when their submenu opens.
    var opensSubmenu: Bool { entry == .recents || entry == .recentDictations }
}

/// The menu's rows, in the order agreed for OKO-343: the update when there
/// is one, the palette, what to do with the selection, the music, the
/// histories, where dictation and the devices stand, then Claudio himself.
@MainActor
enum StatusMenuRows {
    /// The update the daily check found, and whether a click has started
    /// downloading it.
    struct PendingUpdate: Equatable {
        var version: String
        var isDownloading = false
    }

    /// The whole dictation history lives in Settings ▸ Dictation: a row of
    /// the menu, and the foot of "Recent dictations".
    static var dictationHistoryTitle: String { loc("Historique des dictées…", en: "Dictation history…") }

    /// A history with nothing in it has no row: its submenu would be empty.
    static func build(update: PendingUpdate?, hasRecents: Bool, hasRecentDictations: Bool,
                      lines: StatusMenuLines) -> [StatusMenuRow] {
        var rows: [StatusMenuRow] = []
        if let update { rows += [.item(updateItem(update)), .separator] }
        rows += [
            .item(StatusMenuItem(entry: .palette, title: PaletteCatalog.menuTitle, symbol: "square.grid.2x2",
                                 shortcut: .actionPalette, command: .palette)),
            .separator,
            .header(loc("Texte sélectionné", en: "Selected text")),
        ]
        rows += ClaudioAction.allCases.map { action in
            .item(StatusMenuItem(entry: .action(action), title: action.shortMenuTitle, symbol: action.menuSymbolName,
                                 shortcut: action.shortcutName, command: .action(action)))
        }
        rows += [
            .item(StatusMenuItem(entry: .freeAction, title: ClaudioRequest.freeMenuTitle, symbol: "wand.and.stars",
                                 shortcut: .freeAction, command: .freeAction)),
            .header(loc("Musique", en: "Music")),
            .item(StatusMenuItem(entry: .whatsPlaying, title: ListeningSession.menuTitle,
                                 symbol: ListeningSession.symbolName, shortcut: .whatsPlaying, command: .whatsPlaying)),
            .header(loc("Historique", en: "History")),
        ]
        if hasRecents {
            rows.append(.item(StatusMenuItem(entry: .recents, title: loc("Récentes", en: "Recent"),
                                             symbol: "clock.arrow.circlepath")))
        }
        if hasRecentDictations {
            rows.append(.item(StatusMenuItem(entry: .recentDictations, title: RecentDictationsMenu.menuTitle,
                                             symbol: "mic")))
        }
        rows += [
            .item(StatusMenuItem(entry: .dictationHistory, title: dictationHistoryTitle,
                                 symbol: "list.bullet.rectangle", command: .settingsSection(.dictation))),
            .separator,
            .item(StatusMenuItem(entry: .dictationStatus, title: lines.dictation, symbol: "mic.fill",
                                 command: .settingsSection(.dictation))),
            .item(StatusMenuItem(entry: .ulanziStatus, title: lines.ulanzi, symbol: "lightbulb.led",
                                 command: .settingsSection(.ulanzi))),
            .item(StatusMenuItem(entry: .streamDeckStatus, title: lines.streamDeck, symbol: "rectangle.grid.3x2",
                                 command: .settingsSection(.streamDeck))),
            .separator,
            .item(StatusMenuItem(entry: .tip, title: loc("Laisser un pourboire à Claudio", en: "Leave Claudio a tip"),
                                 symbol: "cup.and.saucer", command: .settingsSection(.tip))),
            .item(StatusMenuItem(entry: .settings, title: loc("Réglages…", en: "Settings…"), symbol: "gearshape",
                                 keyEquivalent: ",", command: .settings)),
            .item(StatusMenuItem(entry: .about, title: loc("À propos de Claudio", en: "About Claudio"),
                                 symbol: "info.circle", command: .settingsSection(.about))),
            .item(StatusMenuItem(entry: .quit, title: loc("Quitter Claudio", en: "Quit Claudio"),
                                 keyEquivalent: "q", command: .quit)),
        ]
        return rows
    }

    /// Downloading, the row says so and takes no second click.
    private static func updateItem(_ update: PendingUpdate) -> StatusMenuItem {
        StatusMenuItem(entry: .update,
                       title: update.isDownloading
                           ? loc("Téléchargement de la mise à jour…", en: "Downloading the update…")
                           : loc("Mise à jour \(update.version) disponible…", en: "Update \(update.version) available…"),
                       command: .installUpdate, isEnabled: !update.isDownloading)
    }
}

private extension ClaudioAction {
    /// The menu's own outline symbols, drawn as templates: the colored
    /// badges of the panel and of Settings would be too loud in a menu.
    var menuSymbolName: String {
        switch self {
        case .correct: "checkmark.circle"
        case .makePrompt: "text.badge.plus"
        case .expertPrompt: "text.badge.star"
        case .translateFR, .translateEN: "globe"
        case .professionalTone: "briefcase"
        case .summarize: "text.alignleft"
        case .simplify: "lightbulb"
        }
    }
}
