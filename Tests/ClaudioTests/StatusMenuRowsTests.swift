import AppKit
import KeyboardShortcuts
import XCTest
@testable import Claudio

/// The menu under Claudio in the menu bar, as the list of rows it is made
/// of: sections, titles, icons, the shortcut each action really answers to,
/// and what a click does. The menu only turns this list into items, and the
/// `barre-de-menus` preview draws the same list: a row lost or moved here is
/// lost or moved on screen.
@MainActor
final class StatusMenuRowsTests: XCTestCase {

    /// The titles compared are French: the suite pins the language rather
    /// than inheriting it from the machine.

    override func setUp() {
        super.setUp()
        useLanguage(.french)
    }

    private let lines = StatusMenuLines(dictation: "Dictée : maintenir ⌥ droite",
                                        ulanzi: "Ulanzi : 2 horloges prêtes",
                                        streamDeck: "Stream Deck : connecté")

    private func rows(update: StatusMenuRows.PendingUpdate? = nil,
                      recents: Bool = true, dictations: Bool = true) -> [StatusMenuRow] {
        StatusMenuRows.build(update: update, hasRecents: recents, hasRecentDictations: dictations, lines: lines)
    }

    /// The rows as one reads them down the menu: "—" a separator, "# " a
    /// section's header, then each row's title.
    private func outline(_ rows: [StatusMenuRow]) -> [String] {
        rows.map { row in
            switch row {
            case .separator: "—"
            case .header(let title): "# \(title)"
            case .item(let item): item.title
            }
        }
    }

    private func items(_ rows: [StatusMenuRow]) -> [StatusMenuItem] {
        rows.compactMap { row in
            guard case .item(let item) = row else { return nil }
            return item
        }
    }

    private func item(_ entry: StatusMenuItem.Entry, in rows: [StatusMenuRow]) -> StatusMenuItem? {
        items(rows).first { $0.entry == entry }
    }

    // MARK: - Order

    /// The order agreed: what to do with the selection, the music, the
    /// histories, where things stand, then Claudio himself.
    func testTheMenuReadsInTheOrderAgreed() {
        XCTAssertEqual(outline(rows(update: .init(version: "1.14"))), [
            "Mise à jour 1.14 disponible…",
            "—",
            "Palette d'actions…",
            "—",
            "# Texte sélectionné",
            "Corriger la sélection",
            "Structurer en prompt",
            "Structurer en prompt expert",
            "Traduire en français",
            "Traduire en anglais",
            "Ton professionnel",
            "Résumer",
            "Lapacompris",
            "Action libre…",
            "# Musique",
            "Qu'est-ce que j'écoute ?",
            "# Historique",
            "Récentes",
            "Dernières dictées",
            "Historique des dictées…",
            "—",
            "Dictée : maintenir ⌥ droite",
            "Ulanzi : 2 horloges prêtes",
            "Stream Deck : connecté",
            "—",
            "Laisser un pourboire à Claudio",
            "Réglages…",
            "À propos de Claudio",
            "Quitter Claudio",
        ])
    }

    /// No update waiting: the palette opens the menu, with nothing above it.
    func testWithoutAnUpdateThePaletteComesFirst() {
        let built = rows()
        XCTAssertEqual(outline(built).prefix(2), ["Palette d'actions…", "—"])
        XCTAssertNil(item(.update, in: built))
    }

    /// Clicked once, the update is downloading: the row says so, and a
    /// second click can't start a second download.
    func testAnUpdateDownloadingSaysSoAndTakesNoSecondClick() {
        let waiting = item(.update, in: rows(update: .init(version: "1.14")))
        XCTAssertEqual(waiting?.command, .installUpdate)
        XCTAssertEqual(waiting?.isEnabled, true)
        let downloading = item(.update, in: rows(update: .init(version: "1.14", isDownloading: true)))
        XCTAssertEqual(downloading?.title, "Téléchargement de la mise à jour…")
        XCTAssertEqual(downloading?.isEnabled, false)
    }

    /// A history with nothing in it has no submenu to open; the way to the
    /// whole dictation history stays, and so does its section.
    func testEmptyHistoriesHideTheirSubmenus() {
        let empty = outline(rows(recents: false, dictations: false))
        XCTAssertFalse(empty.contains("Récentes"))
        XCTAssertFalse(empty.contains("Dernières dictées"))
        XCTAssertTrue(empty.contains("# Historique"))
        XCTAssertTrue(empty.contains("Historique des dictées…"))

        let noDictation = outline(rows(recents: true, dictations: false))
        XCTAssertTrue(noDictation.contains("Récentes"))
        XCTAssertFalse(noDictation.contains("Dernières dictées"))
        XCTAssertFalse(outline(rows(recents: false, dictations: true)).contains("Récentes"))
    }

    // MARK: - Icons

    func testEveryRowWearsItsSymbol() {
        let symbols = Dictionary(uniqueKeysWithValues: items(rows(update: .init(version: "1.14")))
            .map { ($0.entry, $0.symbol) })
        let expected: [StatusMenuItem.Entry: String?] = [
            .update: nil,
            .palette: "square.grid.2x2",
            .action(.correct): "checkmark.circle",
            .action(.makePrompt): "text.badge.plus",
            .action(.expertPrompt): "text.badge.star",
            .action(.translateFR): "globe",
            .action(.translateEN): "globe",
            .action(.professionalTone): "briefcase",
            .action(.summarize): "text.alignleft",
            .action(.simplify): "lightbulb",
            .freeAction: "wand.and.stars",
            .whatsPlaying: ListeningSession.symbolName,
            .recents: "clock.arrow.circlepath",
            .recentDictations: "mic",
            .dictationHistory: "list.bullet.rectangle",
            .dictationStatus: "mic.fill",
            .ulanziStatus: "lightbulb.led",
            .streamDeckStatus: "rectangle.grid.3x2",
            .tip: "cup.and.saucer",
            .settings: "gearshape",
            .about: "info.circle",
            .quit: nil,
        ]
        XCTAssertEqual(symbols, expected)
    }

    /// A name the system doesn't have draws nothing, without a word: every
    /// symbol is checked here rather than on Guillaume's menu bar.
    func testEverySymbolExistsOnThisSystem() {
        for item in items(rows(update: .init(version: "1.14"))) {
            guard let symbol = item.symbol else { continue }
            XCTAssertNotNil(NSImage(systemSymbolName: symbol, accessibilityDescription: nil), symbol)
        }
    }

    // MARK: - Shortcuts

    /// The shortcut on the right is the one the row's action answers to:
    /// the library keeps it current when Settings changes it. Settings and
    /// Quit keep their usual ⌘, and ⌘Q.
    func testEachRowShowsTheShortcutItAnswersTo() {
        let built = items(rows(update: .init(version: "1.14")))
        var expected: [StatusMenuItem.Entry: KeyboardShortcuts.Name] = [
            .palette: .actionPalette,
            .freeAction: .freeAction,
            .whatsPlaying: .whatsPlaying,
        ]
        for action in ClaudioAction.allCases { expected[.action(action)] = action.shortcutName }
        for item in built {
            XCTAssertEqual(item.shortcut, expected[item.entry], "\(item.entry)")
        }
        let keys = Dictionary(uniqueKeysWithValues: built.map { ($0.entry, $0.keyEquivalent) })
            .filter { !$0.value.isEmpty }
        XCTAssertEqual(keys, [.settings: ",", .quit: "q"])
    }

    // MARK: - What a click does

    /// The status lines are rows like the others, not greyed out: each opens
    /// its tab. So do the tip, About and the dictation history.
    func testEachRowDoesWhatItSays() {
        let built = items(rows(update: .init(version: "1.14")))
        var expected: [StatusMenuItem.Entry: StatusMenuCommand] = [
            .update: .installUpdate,
            .palette: .palette,
            .freeAction: .freeAction,
            .whatsPlaying: .whatsPlaying,
            .dictationHistory: .settingsSection(.dictation),
            .dictationStatus: .settingsSection(.dictation),
            .ulanziStatus: .settingsSection(.ulanzi),
            .streamDeckStatus: .settingsSection(.streamDeck),
            .tip: .settingsSection(.tip),
            .settings: .settings,
            .about: .settingsSection(.about),
            .quit: .quit,
        ]
        for action in ClaudioAction.allCases { expected[.action(action)] = .action(action) }
        for item in built {
            XCTAssertEqual(item.command, expected[item.entry], "\(item.entry)")
            XCTAssertTrue(item.isEnabled, "\(item.entry)")
        }
        // The two histories only open their submenu.
        XCTAssertEqual(built.filter(\.opensSubmenu).map(\.entry), [.recents, .recentDictations])
    }

    // MARK: - Titles

    /// "Lapacompris: explain simply" would stretch the menu: there, and only
    /// there, Lapacompris goes by its name alone.
    func testOnlyLapacomprisIsShortenedForTheMenu() {
        for action in ClaudioAction.allCases where action != .simplify {
            XCTAssertEqual(action.shortMenuTitle, action.menuTitle)
        }
        XCTAssertEqual(ClaudioAction.simplify.shortMenuTitle, "Lapacompris")
        XCTAssertEqual(ClaudioAction.simplify.menuTitle, "Lapacompris : expliquer simplement")
    }

    /// The menu is named again in the interface language at every opening.
    func testTheMenuSpeaksEnglishToo() {
        useLanguage(.english)
        let english = outline(rows(update: .init(version: "1.14")))
        for title in ["Update 1.14 available…", "# Selected text", "# Music", "# History", "Recent",
                      "Recent dictations", "Dictation history…", "Leave Claudio a tip", "Settings…",
                      "About Claudio", "Quit Claudio"] {
            XCTAssertTrue(english.contains(title), title)
        }
    }
}
