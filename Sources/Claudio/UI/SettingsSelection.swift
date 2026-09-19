import SwiftUI

/// Which tab Settings shows. A value the window controller owns and the view
/// observes, rather than state locked inside the view: a `claudio://` link —
/// or the plugin sending someone to the switch that would bring it back —
/// has to move a window that is already open, not only decide which tab a
/// new one opens on.
@MainActor
final class SettingsSelection: ObservableObject {
    @Published var section: SettingsSection = .general

    /// What the sidebar binds to. Two-way, because clicking a row is what
    /// moves the tab the rest of the time; and a sidebar that ends up with
    /// nothing selected — a ⌘-click on the selected row — leaves the tab
    /// where it was rather than emptying the window.
    var sidebar: Binding<SettingsSection?> {
        Binding(get: { self.section },
                set: { if let section = $0 { self.section = section } })
    }
}
