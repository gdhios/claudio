import AppKit
import KeyboardShortcuts
import XCTest
@testable import Claudio

/// The rows made into the menu's items: in order, headers as headers, each
/// item with its icon, its shortcut and its submenu. An item is made once
/// and kept: the shortcut it shows is bound once, and the library keeps it
/// current from there; a menu that made new items at every opening would
/// pile up a watcher per item per opening.
@MainActor
final class StatusMenuItemsTests: XCTestCase {

    override func setUp() {
        super.setUp()
        useLanguage(.french)
    }

    private let recents = NSMenu()
    private let recentDictations = NSMenu()
    private let lines = StatusMenuLines(dictation: "Dictée : désactivée", ulanzi: "Ulanzi : aucune horloge",
                                        streamDeck: "Stream Deck : plugin absent")

    /// Stands in for the menu's own answer to a click.
    @objc private func rowClicked(_ sender: NSMenuItem) {}

    private func makeItems() -> StatusMenuItems {
        StatusMenuItems(target: self, action: #selector(rowClicked(_:)),
                        submenus: [.recents: recents, .recentDictations: recentDictations])
    }

    private func rows(update: StatusMenuRows.PendingUpdate? = .init(version: "1.14")) -> [StatusMenuRow] {
        StatusMenuRows.build(update: update, hasRecents: true, hasRecentDictations: true, lines: lines)
    }

    private func menuItem(_ title: String, in menu: NSMenu) -> NSMenuItem? {
        menu.items.first { $0.title == title }
    }

    func testTheMenuHoldsTheRowsInOrder() {
        let menu = NSMenu()
        let built = rows()
        makeItems().fill(menu, with: built)
        XCTAssertEqual(menu.items.count, built.count)
        for (item, row) in zip(menu.items, built) {
            switch row {
            case .separator:
                XCTAssertTrue(item.isSeparatorItem)
            case .header(let title):
                XCTAssertTrue(item.isSectionHeader, title)
                XCTAssertEqual(item.title, title)
            case .item(let row):
                XCTAssertEqual(item.title, row.title)
                XCTAssertEqual(item.image != nil, row.symbol != nil, row.title)
                XCTAssertEqual(item.representedObject as? StatusMenuCommand, row.command, row.title)
                XCTAssertEqual(item.isEnabled, row.isEnabled, row.title)
                if row.command != nil {
                    XCTAssertEqual(item.action, #selector(rowClicked(_:)), row.title)
                    XCTAssertTrue(item.target === self, row.title)
                }
            }
        }
    }

    /// The shortcut shown is the one the library holds for the action, and
    /// Settings and Quit keep ⌘, and ⌘Q.
    func testItemsShowTheirShortcuts() {
        let menu = NSMenu()
        makeItems().fill(menu, with: rows())
        let correct = menuItem("Corriger", in: menu)
        let shortcut = KeyboardShortcuts.getShortcut(for: .correctSelection)
        XCTAssertNotNil(shortcut)
        XCTAssertEqual(correct?.keyEquivalent, shortcut?.nsMenuItemKeyEquivalent)
        XCTAssertEqual(correct?.keyEquivalentModifierMask, shortcut?.modifiers)
        XCTAssertEqual(menuItem("Réglages…", in: menu)?.keyEquivalent, ",")
        XCTAssertEqual(menuItem("Quitter Claudio", in: menu)?.keyEquivalent, "q")
        XCTAssertEqual(menuItem("Laisser un pourboire à Claudio", in: menu)?.keyEquivalent, "")
    }

    func testTheHistoriesOpenTheirSubmenus() {
        let menu = NSMenu()
        makeItems().fill(menu, with: rows())
        XCTAssertTrue(menuItem("Récentes", in: menu)?.submenu === recents)
        XCTAssertTrue(menuItem("Dernières dictées", in: menu)?.submenu === recentDictations)
    }

    /// Opened again, in another language and with the update downloading:
    /// the same items, named again, the update greyed out.
    func testItemsAreKeptFromOneOpeningToTheNext() {
        let menu = NSMenu()
        let items = makeItems()
        items.fill(menu, with: rows())
        let palette = menuItem("Palette d'actions…", in: menu)
        XCTAssertNotNil(palette)

        useLanguage(.english)
        items.fill(menu, with: rows(update: .init(version: "1.14", isDownloading: true)))
        XCTAssertTrue(menuItem("Action palette…", in: menu) === palette)
        XCTAssertEqual(menu.items.first?.title, "Downloading the update…")
        XCTAssertEqual(menu.items.first?.isEnabled, false)
    }
}
