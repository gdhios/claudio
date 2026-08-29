import SwiftUI

/// Identité visuelle de Claudio : accent indigo→violet (le même dégradé que la landing),
/// panneau sombre en permanence, badges « pill » et pastilles d'icônes colorées.
enum ClaudioTheme {
    static let indigo = Color(red: 0.36, green: 0.30, blue: 0.93)   // #5c4ded
    static let violet = Color(red: 0.63, green: 0.29, blue: 0.90)   // #a14ae6
    static let accent = Color(red: 0.48, green: 0.33, blue: 0.93)

    static let gradient = LinearGradient(colors: [indigo, violet],
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing)

    // Panneau : sombre quel que soit le mode système (l'app source garde son thème,
    // le panneau garde le sien — même parti pris que la landing).
    static let panelBackground = Color(red: 0.075, green: 0.075, blue: 0.09)
    static let panelBorder = Color.white.opacity(0.09)
    static let panelSeparator = Color.white.opacity(0.06)
    static let panelCornerRadius: CGFloat = 18
}

/// Icône et teinte par action — utilisées dans le header du panneau
/// et devant chaque raccourci dans les Réglages.
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
        }
    }
}

/// Pastille d'icône colorée façon Réglages Système.
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

/// Variante Claudio : pastille au dégradé maison (le badge moustache du panneau).
struct ClaudioBadge: View {
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: "mustache.fill")
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(ClaudioTheme.gradient, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

/// Badge « pill » façon Vibe Island : fond discret, texte compact.
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

/// Bouton principal du panneau : dégradé Claudio.
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

/// Boutons secondaires du panneau : pill sombre discret.
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
