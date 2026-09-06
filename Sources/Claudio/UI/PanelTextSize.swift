import CoreGraphics

/// Text size in the floating panel. macOS's default body size is
/// small for anyone who reads poorly: this setting enlarges it wherever one reads
/// and writes, without touching the decor (badges, shortcuts, hints), which
/// doesn't need to grow to stay legible.
///
/// The `rawValue` is the storage key in UserDefaults: it no longer changes.
enum PanelTextSize: String, CaseIterable, Identifiable, Sendable {
    case small
    case normal
    case large
    case extraLarge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: loc("Petit", en: "Small")
        case .normal: loc("Normal", en: "Normal")
        case .large: loc("Grand", en: "Large")
        case .extraLarge: loc("Très grand", en: "Extra large")
        }
    }

    /// Body size for text read and written in the panel. `normal` equals the size of
    /// `.body` on macOS: the default setting changes nothing about the existing behavior.
    var bodyPoints: CGFloat {
        switch self {
        case .small: 12
        case .normal: 13
        case .large: 15.5
        case .extraLarge: 18
        }
    }

    /// Factor relative to the normal setting.
    var scale: CGFloat { bodyPoints / PanelTextSize.normal.bodyPoints }

    /// Size derived from a body expressed at the normal setting.
    func points(_ base: CGFloat) -> CGFloat { base * scale }

    /// Panel width: it grows with the text. A size of 18
    /// in 460 points of width would leave only lines of a few
    /// words, and reading would lose what the larger size gains it.
    var panelWidth: CGFloat {
        max((Constants.panelWidth * (1 + (scale - 1) * 0.7)).rounded(), Constants.panelWidth)
    }

    /// Minimum height of the text area: the panel opens at this welcoming
    /// size, and a short sentence settles in it without moving the window.
    /// It follows the text size, never exceeding the ceiling.
    var minTextHeight: CGFloat {
        min((Constants.panelMinTextHeight * scale).rounded(), maxTextHeight)
    }

    /// Maximum height of the text area: it also follows, but capped
    /// so the panel stays a panel. Beyond it, one scrolls.
    var maxTextHeight: CGFloat {
        min(max((Constants.panelMaxTextHeight * scale).rounded(), Constants.panelMaxTextHeight), 520)
    }
}
