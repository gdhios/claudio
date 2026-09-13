import AppKit

/// Where a text goes back to once Claudio is done with it: the app that had
/// focus when the cycle started, and the clipboard as it was then. Captured
/// before anything shows on screen, replayed when the text is ready.
struct PasteTarget {
    /// The app to give focus back to, `nil` when Claudio itself was
    /// frontmost: there is then nowhere to paste.
    var app: NSRunningApplication?
    /// The clipboard as it was, put back after the paste. `nil` leaves the
    /// pasted text on it.
    var clipboard: PasteboardSnapshot?
}

/// The one path that puts a text into another app: activate it, write the
/// pasteboard, simulate ⌘V, restore the clipboard. Shared by the correction
/// cycle and by dictation, so a result and a dictation land the same way.
@MainActor
enum PasteBack {
    /// The app to paste back into: the frontmost one, unless it's Claudio.
    static func frontmostApp() -> NSRunningApplication? {
        let frontmost = NSWorkspace.shared.frontmostApplication
        return frontmost?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : frontmost
    }

    /// Everything worth remembering before the panel opens.
    static func captureTarget() -> PasteTarget {
        PasteTarget(app: frontmostApp(),
                    clipboard: Constants.restoreClipboardAfterPaste ? PasteboardSnapshot.capture() : nil)
    }

    /// Pastes into the target, and says whether anything could receive the
    /// text: `false` when Claudio itself was frontmost. The caller then keeps
    /// its panel open rather than dropping the text into nowhere.
    @discardableResult
    static func paste(_ text: String, into target: PasteTarget) async -> Bool {
        target.app?.activate()
        try? await Task.sleep(nanoseconds: Constants.activationDelayNs)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        Keystroke.simulate(virtualKey: Keystroke.keyV, flags: .maskCommand)

        if let snapshot = target.clipboard {
            try? await Task.sleep(nanoseconds: Constants.clipboardRestoreDelayNs)
            snapshot.restore()
        }
        return target.app != nil
    }
}

/// Everything a cycle does outside Claudio's own window: make sure the app
/// is allowed to paste at all, remember where the text came from, put it
/// back there. Injected as one value, so a test can be handed a harmless one
/// and run a whole cycle without a permission, a pasteboard or a keystroke.
@MainActor
struct PasteService {
    /// Accessibility, without which nothing can be pasted anywhere. Asks for
    /// it and explains itself when it's missing.
    var isAllowed: @MainActor () -> Bool
    var capture: @MainActor () -> PasteTarget
    var paste: @MainActor (String, PasteTarget) async -> Bool

    static let system = PasteService(isAllowed: AccessibilityPermission.ensureGranted,
                                     capture: PasteBack.captureTarget,
                                     paste: PasteBack.paste)
}
