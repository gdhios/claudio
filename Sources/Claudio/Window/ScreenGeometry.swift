import CoreGraphics

/// The screen-level geometry the mover needs, kept as values so it can be
/// tested: the flip between Cocoa coordinates (bottom-left origin, y up) and
/// the Accessibility API (top-left origin, y down), which display comes next
/// in the cycle, and how a window keeps its placement when it lands there.
/// Every rect below the flip is in AX coordinates.
enum ScreenGeometry {
    /// Convert a Cocoa rect to AX coordinates, given the primary display's full
    /// height. Works for secondary displays too, whose Cocoa y falls outside
    /// `[0, primaryHeight]`.
    static func axRect(fromCocoa cocoa: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: cocoa.minX,
               y: primaryHeight - cocoa.maxY,
               width: cocoa.width,
               height: cocoa.height)
    }

    /// The usable area after `current` in a left-to-right cycle. Displays are
    /// ordered by their left edge, then their top one, so the cycle follows the
    /// physical arrangement rather than the order macOS reports them in. Nil
    /// with a single display, or when `current` isn't one of them: there is
    /// nowhere to send the window.
    static func next(after current: CGRect, in rects: [CGRect]) -> CGRect? {
        let ordered = rects.sorted { ($0.minX, $0.minY) < ($1.minX, $1.minY) }
        guard ordered.count > 1, let index = ordered.firstIndex(of: current) else { return nil }
        return ordered[(index + 1) % ordered.count]
    }

    /// The frame `window` takes on `target` to keep the placement it had on
    /// `source`. Both usable areas are read as unit rectangles, so a half stays
    /// a half and a maximized window stays maximized whatever the two displays'
    /// sizes and ratios.
    static func reproject(_ window: CGRect, from source: CGRect, to target: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0 else {
            return CGRect(origin: target.origin, size: window.size)
        }
        let scaleX = target.width / source.width
        let scaleY = target.height / source.height
        // Same guard as `WindowLayout.center`: the top-left never lands outside
        // the target area, so a window that overflowed its display stays
        // reachable on the next one.
        return CGRect(x: max(target.minX, target.minX + (window.minX - source.minX) * scaleX),
                      y: max(target.minY, target.minY + (window.minY - source.minY) * scaleY),
                      width: window.width * scaleX,
                      height: window.height * scaleY)
    }
}
