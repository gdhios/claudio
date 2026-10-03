import AppKit

/// A click on a row of "Recent dictations": the text goes back to the cursor
/// of the app in front, by the same paste as a dictation, or onto the
/// clipboard when no other app is there to take it. Either way it stays on
/// the clipboard afterwards, and a pill says which of the two happened: a ⌘V
/// that found no field used to leave no trace, and the click looked dead.
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
    var copy: @MainActor (String) -> Void = { NSPasteboard.general.setText($0) }
    /// Says what the click did, once it is done.
    var announce: @MainActor (RecentDictationOutcome) -> Void = { ClipboardToast.shared.show($0) }
    /// Time for the menu to finish closing before the keystroke, as the
    /// menu's other entries wait before they act.
    var menuClosing: Duration = Constants.menuCloseDelay

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
            announce(.copied)
            return
        }

        // Without Accessibility the keystroke can't be sent, and the alert
        // has said why. The text still lands somewhere a ⌘V can reach.
        guard pasting.isAllowed() else {
            copy(text)
            announce(.copied)
            return
        }
        closePanels()
        try? await Task.sleep(for: menuClosing)
        // Not the clipboard of before: whether the ⌘V landed can't be seen
        // from here, and the text on the clipboard is the way out if it didn't.
        var keeping = target
        keeping.clipboard = nil
        await pasting.paste(text, keeping)
        announce(.pasted)
    }
}
