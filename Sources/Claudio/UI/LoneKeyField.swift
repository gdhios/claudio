import AppKit

/// Shows a dictation shortcut's lone key in Settings, looking like the
/// library's recorder in the rows around it: the same search field, text
/// centred, no magnifier, the clear button on the right. It never takes the
/// keyboard itself — a click hands it to the recorder underneath, and the
/// clear button clears.
final class LoneKeyField: NSSearchField {
    var onClick: () -> Void = {}
    var onClear: () -> Void = {}

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 130, height: 24))
        alignment = .center
        (cell as? NSSearchFieldCell)?.searchButtonCell = nil
        refusesFirstResponder = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let cell = cell as? NSSearchFieldCell,
           cell.cancelButtonRect(forBounds: bounds).contains(point) {
            onClear()
        } else {
            onClick()
        }
    }
}
