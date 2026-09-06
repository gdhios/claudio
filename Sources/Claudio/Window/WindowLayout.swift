import CoreGraphics

/// Where a window can be snapped. The geometry is pure: `frame(in:current:)`
/// subdivides a rectangle and knows nothing about screens, displays or the
/// Accessibility API. The mover feeds it the usable area and reads back a
/// target frame, both in AX coordinates (top-left origin, y growing downward).
enum WindowLayout: CaseIterable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case maximize
    case center

    /// Target frame for this layout inside `visible` (the screen's usable
    /// area), given the window's `current` frame. `center` keeps the current
    /// size; every other layout ignores it.
    func frame(in visible: CGRect, current: CGRect) -> CGRect {
        let x = visible.minX, y = visible.minY
        let w = visible.width, h = visible.height
        let halfW = w / 2, halfH = h / 2

        switch self {
        case .leftHalf:    return CGRect(x: x, y: y, width: halfW, height: h)
        case .rightHalf:   return CGRect(x: x + halfW, y: y, width: halfW, height: h)
        case .topHalf:     return CGRect(x: x, y: y, width: w, height: halfH)
        case .bottomHalf:  return CGRect(x: x, y: y + halfH, width: w, height: halfH)
        case .topLeft:     return CGRect(x: x, y: y, width: halfW, height: halfH)
        case .topRight:    return CGRect(x: x + halfW, y: y, width: halfW, height: halfH)
        case .bottomLeft:  return CGRect(x: x, y: y + halfH, width: halfW, height: halfH)
        case .bottomRight: return CGRect(x: x + halfW, y: y + halfH, width: halfW, height: halfH)
        case .maximize:    return visible
        case .center:
            // Keep the size; center inside the usable area, but never push the
            // top-left past the origin, so an oversized window's title bar
            // stays reachable (it overflows to the right and bottom instead).
            let originX = max(x, x + (w - current.width) / 2)
            let originY = max(y, y + (h - current.height) / 2)
            return CGRect(x: originX, y: originY, width: current.width, height: current.height)
        }
    }
}

// MARK: - Presentation

extension WindowLayout {
    /// Label shown in Settings next to the shortcut recorder. "Maximize"
    /// rather than "Plein écran" to avoid the macOS green-button fullscreen:
    /// this fills the usable area, it doesn't enter fullscreen.
    var title: String {
        switch self {
        case .leftHalf:    loc("Moitié gauche", en: "Left half")
        case .rightHalf:   loc("Moitié droite", en: "Right half")
        case .topHalf:     loc("Moitié haute", en: "Top half")
        case .bottomHalf:  loc("Moitié basse", en: "Bottom half")
        case .topLeft:     loc("Quart haut-gauche", en: "Top-left quarter")
        case .topRight:    loc("Quart haut-droite", en: "Top-right quarter")
        case .bottomLeft:  loc("Quart bas-gauche", en: "Bottom-left quarter")
        case .bottomRight: loc("Quart bas-droite", en: "Bottom-right quarter")
        case .maximize:    loc("Maximiser", en: "Maximize")
        case .center:      loc("Centrer", en: "Center")
        }
    }

    /// SF Symbol picturing the target position.
    var symbolName: String {
        switch self {
        case .leftHalf:    "rectangle.lefthalf.filled"
        case .rightHalf:   "rectangle.righthalf.filled"
        case .topHalf:     "rectangle.tophalf.filled"
        case .bottomHalf:  "rectangle.bottomhalf.filled"
        case .topLeft:     "rectangle.inset.topleft.filled"
        case .topRight:    "rectangle.inset.topright.filled"
        case .bottomLeft:  "rectangle.inset.bottomleft.filled"
        case .bottomRight: "rectangle.inset.bottomright.filled"
        case .maximize:    "rectangle.fill"
        case .center:      "rectangle.center.inset.filled"
        }
    }
}

/// The one impure detail the mover needs, kept as a value so it can be tested:
/// the flip between Cocoa coordinates (bottom-left origin, y up) and the
/// Accessibility API (top-left origin, y down).
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
}
