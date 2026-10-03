import Foundation

/// The "Recent dictations" submenu of the menu bar, as a value: the last few
/// dictations, each under a one-line title, with the text a click pastes
/// again. `StatusMenu` turns it into menu items; nothing here touches AppKit.
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
            Item(title: Self.title(for: entry.pastedText), text: entry.pastedText)
        }
    }

    /// A dictation as a menu row: one line, cut with "…" past `titleLength`.
    static func title(for text: String) -> String {
        text.menuRowTitle(length: titleLength)
    }
}
