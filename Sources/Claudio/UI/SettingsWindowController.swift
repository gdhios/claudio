import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show(initialSection: SettingsSection = .general) {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(initialSection: initialSection))
            let win = NSWindow(contentViewController: hosting)
            win.title = "Réglages Claudio"
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
