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
        present(on: nil)
    }

    /// Opens Settings on a named tab — a `claudio://` link, or the plugin
    /// asking for its switch. Named means named: the tab moves whether the
    /// window is being built or has been open for an hour, which is the case
    /// the plugin's own way out depends on.
    func show(initialSection: SettingsSection) {
        present(on: initialSection)
    }

    /// The selection hears about the opening before the window is built, so
    /// a first opening builds its pane once, not twice.
    private func present(on section: SettingsSection?) {
        let onScreen = window?.isVisible == true
        selection.broughtUp(on: section, alreadyOnScreen: onScreen)
        let win = window ?? makeWindow()
        window = win
        // Named on every opening: the language may have changed in General
        // since the window was built.
        win.title = loc("Réglages Claudio", en: "Claudio Settings")
        NSApp.activate(ignoringOtherApps: true)
        if !onScreen { win.center() }
        win.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView(selection: selection))
        let win = NSWindow(contentViewController: hosting)
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        win.setContentSize(NSSize(width: 740, height: 520))
        win.setFrameAutosaveName("ClaudioSettings")
        win.isReleasedWhenClosed = false
        return win
    }
}
