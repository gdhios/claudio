import AppKit

/// A click on a row of "Recent dictations": the text goes back to the cursor
/// of the app in front, by the same paste as a dictation, or onto the
/// clipboard when no other app is there to take it.
///
/// Everything that touches the outside world is injected, as in
/// `DictationCoordinator`: a test plays a click without a permission, a
/// pasteboard, a panel or a keystroke.
@MainActor
struct RecentDictationPaster {
    var pasting: PasteService = .system
    /// Takes Claudio's own panels off the screen. One still up has the
    /// keyboard without Claudio being active, and the ⌘V would land in it.
    var closePanels: @MainActor () -> Void = {}
    /// Where the text goes when there is nowhere to paste it.
    var copy: @MainActor (String) -> Void = RecentDictationPaster.copyToClipboard
    /// Time for the menu to finish closing before the keystroke, as the
    /// menu's other entries wait before they act.
    var menuClosing: Duration = .milliseconds(250)

    func paste(_ text: String) async {
        // Read first. Claudio is an accessory app, and opening its menu
        // doesn't activate it: the app in front is still the one being typed
        // in. The permission alert below would bring Claudio forward.
        let target = pasting.capture()

        // Claudio itself in front (its Settings window, say), or no app at
        // all: a ⌘V would land in Claudio, which `DictationCoordinator` never
        // lets happen either. The clipboard takes the text instead, and a copy
        // needs no permission, so none is asked for.
        guard target.app != nil else {
            copy(text)
            return
        }

        guard pasting.isAllowed() else { return }
        closePanels()
        try? await Task.sleep(for: menuClosing)
        _ = await pasting.paste(text, target)
    }

    static func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
