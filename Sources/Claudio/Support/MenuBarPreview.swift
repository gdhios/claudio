import AppKit

/// The four gazes on the menu bar's two backgrounds: at their real size,
/// then enlarged without smoothing. That's where readability gets judged: a
/// gaze that can't be told apart here is useless in the app.
final class MenuBarPreviewView: NSView {
    private let gazes: [(String, ClaudioMascot.Gaze)] = [
        ("repos", .repos), ("veille", .veille), ("fait", .fait), ("vide", .vide),
    ]

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let backgrounds: [(NSColor, NSColor)] = [
            (NSColor(white: 0.96, alpha: 1), .black),   // light bar
            (NSColor(white: 0.11, alpha: 1), .white),   // dark bar
        ]
        let column: CGFloat = 104, band: CGFloat = 116

        for (row, (background, ink)) in backgrounds.enumerated() {
            let top = CGFloat(row) * band
            background.setFill()
            NSRect(x: 0, y: top, width: bounds.width, height: band).fill()

            for (index, (name, gaze)) in gazes.enumerated() {
                let x = 20 + CGFloat(index) * column
                let image = ClaudioMascot.menuBarImage(gaze: gaze).tinted(ink)
                let size = image.size

                NSAttributedString(string: name, attributes: [
                    .font: NSFont.systemFont(ofSize: 9),
                    .foregroundColor: ink.withAlphaComponent(0.55),
                ]).draw(at: NSPoint(x: x, y: top + 10))

                // Real size, that of the menu bar.
                image.draw(in: NSRect(x: x, y: top + 28,
                                      width: size.width, height: size.height))

                // Enlarged threefold, visible pixels.
                NSGraphicsContext.current?.imageInterpolation = .none
                image.draw(in: NSRect(x: x, y: top + 54,
                                      width: size.width * 3, height: size.height * 3))
                NSGraphicsContext.current?.imageInterpolation = .default
            }
        }
    }
}

private extension NSImage {
    /// A template image only carries its alpha: here is its inked version.
    func tinted(_ color: NSColor) -> NSImage {
        let copy = NSImage(size: size)
        copy.lockFocus()
        draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        color.set()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
        copy.unlockFocus()
        return copy
    }
}
