import AppKit

/// Invisible main menu (app .accessory): without an Edit menu, macOS
/// doesn't route ⌘X/⌘C/⌘V/⌘A to text fields.
enum MainMenu {
    @MainActor
    static func make() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: loc("Quitter Claudio", en: "Quit Claudio"),
                                   action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let editMenu = NSMenu(title: loc("Édition", en: "Edit"))
        let rows: [(String, Selector?, String)] = [
            (loc("Annuler", en: "Undo"), Selector(("undo:")), "z"),
            (loc("Rétablir", en: "Redo"), Selector(("redo:")), "Z"),
            ("", nil, ""),
            (loc("Couper", en: "Cut"), #selector(NSText.cut(_:)), "x"),
            (loc("Copier", en: "Copy"), #selector(NSText.copy(_:)), "c"),
            (loc("Coller", en: "Paste"), #selector(NSText.paste(_:)), "v"),
            (loc("Tout sélectionner", en: "Select All"), #selector(NSText.selectAll(_:)), "a"),
        ]
        for (title, action, key) in rows {
            editMenu.addItem(action.map { NSMenuItem(title: title, action: $0, keyEquivalent: key) } ?? .separator())
        }

        for submenu in [appMenu, editMenu] {
            let item = NSMenuItem()
            item.submenu = submenu
            mainMenu.addItem(item)
        }
        return mainMenu
    }
}
