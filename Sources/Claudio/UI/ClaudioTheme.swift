import SwiftUI

/// Claudio's visual identity: the deep purple of the mustachioed robot (the same
/// gradient as the icon), permanently dark panel, "pill" badges and
/// colored icon dots.
enum ClaudioTheme {
    static let violetHaut = Color(red: 0.369, green: 0.208, blue: 0.651)  // #5e35a6
    static let violetBas = Color(red: 0.243, green: 0.063, blue: 0.435)   // #3e106f
    static let accent = Color(red: 0.486, green: 0.310, blue: 0.816)      // #7c4fd0

    static let gradient = LinearGradient(colors: [violetHaut, violetBas],
                                         startPoint: .top,
                                         endPoint: .bottom)

    // Panel: dark regardless of the system mode (the source app keeps its theme,
    // the panel keeps its own, same stance as the landing page).
    static let panelBackground = Color(red: 0.075, green: 0.075, blue: 0.09)
    static let panelBorder = Color.white.opacity(0.09)
    static let panelSeparator = Color.white.opacity(0.06)
    static let panelCornerRadius: CGFloat = 18
}

/// Icon and tint per action, used in the panel header
/// and in front of each shortcut in Settings.
extension ClaudioAction {
    var symbolName: String {
        switch self {
        case .correct: "pencil"
        case .makePrompt: "text.bubble.fill"
        case .expertPrompt: "brain.fill"
        case .translateFR: "globe.europe.africa.fill"
        case .translateEN: "globe.americas.fill"
        case .professionalTone: "briefcase.fill"
        case .summarize: "list.bullet.rectangle.fill"
        case .simplify: "hare.fill"
        }
    }

    var tint: Color {
        switch self {
        case .correct: ClaudioTheme.accent
        case .makePrompt: .blue
        case .expertPrompt: .purple
        case .translateFR: .cyan
        case .translateEN: .teal
        case .professionalTone: .brown
        case .summarize: .green
        case .simplify: .pink
        }
    }
}

/// Same pair for a request, whatever its origin: the catalog
/// delegates to the action, the custom action has its own pair.
extension ClaudioRequest.Origin {
    var symbolName: String {
        switch self {
        case .catalog(let action): action.symbolName
        case .free: "wand.and.stars"
        }
    }

    var tint: Color {
        switch self {
        case .catalog(let action): action.tint
        case .free: .orange
        }
    }
}

/// The palette isn't an action: it contains them all.
extension PaletteCatalog {
    static let symbolName = "square.grid.2x2.fill"
    static let tint = ClaudioTheme.accent
}

/// Colored icon dot, styled after System Settings.
struct IconBadge: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
    }
}

/// "Pill" badge, styled after Vibe Island: discreet background, compact text.
struct StatusPill<Content: View>: View {
    var background: Color = .white.opacity(0.08)
    var foreground: Color = .secondary
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 5) { content }
            .font(.caption.weight(.medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .background(background, in: Capsule())
    }
}

/// Panel's main button: Claudio gradient.
struct ClaudioProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.4))
            .padding(.horizontal, 13)
            .padding(.vertical, 5)
            .background(
                ClaudioTheme.gradient.opacity(isEnabled ? 1 : 0.35),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Panel's secondary buttons: discreet dark pill.
struct PanelPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                Color.white.opacity(configuration.isPressed ? 0.16 : 0.08),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
    }
}
