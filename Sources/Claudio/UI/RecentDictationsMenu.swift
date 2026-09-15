import Foundation

/// The "Recent dictations" submenu of the menu bar, as a value: the last few
/// dictations, each under a one-line title, with the text a click pastes
/// again. `AppDelegate` turns it into menu items; nothing here touches AppKit.
struct RecentDictationsMenu: Equatable {
    struct Item: Equatable {
        /// What the row shows: the text on one line, cut short.
        var title: String
        /// What the dictation pasted — the cleaned-up text, or the transcript
        /// when there was no cleanup — and what a click pastes again.
        var text: String
    }

    static var menuTitle: String { loc("Dernières dictées", en: "Recent dictations") }

    /// Enough to find the dictation that just went astray, few enough to take
    /// in at a glance: the whole history stays in Settings ▸ Dictation.
    static let limit = 5
    /// Characters in a title, "…" included. Past it, the row stretches the
    /// whole menu.
    static let titleLength = 50

    /// Most recent first, as the history keeps them.
    let items: [Item]

    init(_ recents: RecentDictations) {
        items = recents.entries.prefix(Self.limit).map { entry in
            let text = entry.cleaned ?? entry.raw
            return Item(title: Self.title(for: text), text: text)
        }
    }

    /// A dictation as a menu row: one line, every run of whitespace a single
    /// space, cut with "…" past `titleLength`. Counted in Swift characters —
    /// an accent with its letter, a whole emoji — so a cut never splits one.
    static func title(for text: String) -> String {
        let flat = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard flat.count > titleLength else { return flat }
        return flat.prefix(titleLength - 1).trimmingCharacters(in: .whitespaces) + "…"
    }
}
