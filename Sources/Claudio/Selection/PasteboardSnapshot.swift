import AppKit

/// Multi-type copy of the clipboard, to restore it after pasting (preserves
/// images, RTF, etc, not just text).
struct PasteboardSnapshot {
    private let itemsByType: [[NSPasteboard.PasteboardType: Data]]

    @MainActor
    static func capture(from pasteboard: NSPasteboard = .general) -> PasteboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(
                item.types.compactMap { type in item.data(forType: type).map { (type, $0) } },
                uniquingKeysWith: { first, _ in first }
            )
        }
        return PasteboardSnapshot(itemsByType: items)
    }

    /// Puts the snapshot back, unless something else wrote the clipboard
    /// after `changeCount`: a copy the user made while the paste was in
    /// flight is theirs, and wins over the old content.
    @MainActor
    @discardableResult
    func restore(to pasteboard: NSPasteboard = .general, ifUnchangedSince changeCount: Int) -> Bool {
        guard pasteboard.changeCount == changeCount else { return false }
        pasteboard.clearContents()
        let objects = itemsByType.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dict { item.setData(data, forType: type) }
            return item
        }
        if !objects.isEmpty { pasteboard.writeObjects(objects) }
        return true
    }
}

extension NSPasteboard {
    /// Replaces the whole clipboard with `text`: the one way every copy and
    /// paste in the app writes it.
    /// Returns the change count it left, for `PasteboardSnapshot.restore`.
    @discardableResult
    func setText(_ text: String) -> Int {
        clearContents()
        setString(text, forType: .string)
        return changeCount
    }
}
