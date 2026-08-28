import AppKit

/// Copie multi-types du presse-papiers, pour le restaurer après le collage
/// (préserve images, RTF, etc. — pas seulement le texte).
struct PasteboardSnapshot {
    private let itemsByType: [[NSPasteboard.PasteboardType: Data]]

    @MainActor
    static func capture() -> PasteboardSnapshot {
        let pasteboard = NSPasteboard.general
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(
                item.types.compactMap { type in item.data(forType: type).map { (type, $0) } },
                uniquingKeysWith: { first, _ in first }
            )
        }
        return PasteboardSnapshot(itemsByType: items)
    }

    @MainActor
    func restore() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let objects = itemsByType.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dict { item.setData(data, forType: type) }
            return item
        }
        if !objects.isEmpty { pasteboard.writeObjects(objects) }
    }
}
