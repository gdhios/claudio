import AppKit

/// The alert a missing permission ends on: what Claudio needs and why, then
/// a button straight to the pane of System Settings that grants it.
@MainActor
enum PrivacyAlert {
    /// `anchor` names the pane under Privacy & Security the way System
    /// Settings' own links do: `Privacy_Accessibility`, `Privacy_Microphone`.
    static func show(title: String, message: String, anchor: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: loc("Ouvrir les Réglages Système", en: "Open System Settings"))
        alert.addButton(withTitle: loc("Plus tard", en: "Later"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn,
              let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
