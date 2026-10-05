import AppKit
import KeyboardShortcuts

/// The rows of the menu bar's menu, made into menu items. One item per row
/// entry, made the first time the row shows and kept from one opening to
/// the next: its shortcut is bound once, and the library keeps it current
/// when Settings changes it. Titles, and whether a row takes a click, are
/// set again at every filling.
@MainActor
final class StatusMenuItems {
    /// Who answers a click, with the row's command as represented object.
    private weak var target: AnyObject?
    private let action: Selector
    /// The submenus the history rows open; their rows are made elsewhere.
    private let submenus: [StatusMenuItem.Entry: NSMenu]
    private var items: [StatusMenuItem.Entry: NSMenuItem] = [:]

    init(target: AnyObject, action: Selector, submenus: [StatusMenuItem.Entry: NSMenu]) {
        self.target = target
        self.action = action
        self.submenus = submenus
    }

    /// Empties `menu`, then fills it with `rows` in their order.
    func fill(_ menu: NSMenu, with rows: [StatusMenuRow]) {
        menu.removeAllItems()
        for row in rows {
            switch row {
            case .separator: menu.addItem(.separator())
            case .header(let title): menu.addItem(.sectionHeader(title: title))
            case .item(let row): menu.addItem(item(for: row))
            }
        }
    }

    private func item(for row: StatusMenuItem) -> NSMenuItem {
        let item = items[row.entry] ?? makeItem(for: row)
        item.title = row.title
        item.isEnabled = row.isEnabled
        item.representedObject = row.command
        return item
    }

    private func makeItem(for row: StatusMenuItem) -> NSMenuItem {
        let item = NSMenuItem(title: row.title, action: action, keyEquivalent: row.keyEquivalent)
        item.target = target
        if let symbol = row.symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        if let shortcut = row.shortcut { item.setShortcut(for: shortcut) }
        if let submenu = submenus[row.entry] { item.submenu = submenu }
        items[row.entry] = item
        return item
    }
}
