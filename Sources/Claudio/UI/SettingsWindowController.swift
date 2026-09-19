import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    /// The tab on screen, kept outside the window: it outlives the view and
    /// can be moved while the window is open.
    let selection = SettingsSelection()

    private var window: NSWindow?

    /// Opens Settings where it was left. The menu's own entry: someone
    /// reopening Settings means to come back, not to be sent to the top.
    func show() {
        selection.broughtUp(on: nil)
        present()
    }

    /// Opens Settings on a named tab — a `claudio://` link, or the plugin
    /// asking for its switch. Named means named: the tab moves whether the
    /// window is being built or has been open for an hour, which is the case
    /// the plugin's own way out depends on.
    func show(initialSection: SettingsSection) {
        selection.broughtUp(on: initialSection)
        present()
    }

    private func present() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(selection: selection))
            let win = NSWindow(contentViewController: hosting)
            win.title = loc("Réglages Claudio", en: "Claudio Settings")
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            win.setContentSize(NSSize(width: 740, height: 520))
            win.setFrameAutosaveName("ClaudioSettings")
            win.isReleasedWhenClosed = false
            window = win
        }
        NSApp.activate(ignoringOtherApps: true)
        if window?.isVisible != true { window?.center() }
        window?.makeKeyAndOrderFront(nil)
    }
}
