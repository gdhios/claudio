import SwiftUI

/// Which tab Settings shows. A value the window controller owns and the view
/// observes, rather than state locked inside the view: a `claudio://` link —
/// or the plugin sending someone to the switch that would bring it back —
/// has to move a window that is already open, not only decide which tab a
/// new one opens on.
@MainActor
final class SettingsSelection: ObservableObject {
    @Published var section: SettingsSection = .general

    /// How many times the window has come on screen. It is reused from one
    /// opening to the next, and SwiftUI replays no `.onAppear` or `.task`
    /// in a view that never left it: the view rebuilds its pane on each new
    /// count, so every opening reads this Mac afresh.
    @Published private(set) var openings = 0

    /// Called each time Settings is brought up. A pane that reads this Mac
    /// gets a fresh look even when the window never closed: the Stream Deck
    /// tab looks for the plugin's folder, and a plugin installed while that
    /// tab sat there would otherwise keep being reported absent.
    var onShown: (() -> Void)?

    /// Settings is being brought up — on a named tab, or wherever it was
    /// left. Named means named: the tab moves whether the window is being
    /// built or has been open for an hour. Only a window that wasn't on
    /// screen makes an opening.
    func broughtUp(on section: SettingsSection?, alreadyOnScreen: Bool) {
        if let section { self.section = section }
        if !alreadyOnScreen { openings += 1 }
        onShown?()
    }

    /// What the sidebar binds to. Two-way, because clicking a row is what
    /// moves the tab the rest of the time; and a sidebar that ends up with
    /// nothing selected — a ⌘-click on the selected row — leaves the tab
    /// where it was rather than emptying the window.
    var sidebar: Binding<SettingsSection?> {
        Binding(get: { self.section },
                set: { if let section = $0 { self.section = section } })
    }
}
