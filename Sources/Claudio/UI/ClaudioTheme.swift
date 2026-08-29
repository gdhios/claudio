import SwiftUI

/// Identité visuelle de Claudio : violet profond du robot moustachu (le même
/// dégradé que l'icône), panneau sombre en permanence, badges « pill » et
/// pastilles d'icônes colorées.
enum ClaudioTheme {
    static let violetHaut = Color(red: 0.369, green: 0.208, blue: 0.651)  // #5e35a6
    static let violetBas = Color(red: 0.243, green: 0.063, blue: 0.435)   // #3e106f
    static let accent = Color(red: 0.486, green: 0.310, blue: 0.816)      // #7c4fd0

    static let gradient = LinearGradient(colors: [violetHaut, violetBas],
                                         startPoint: .top,
                                         endPoint: .bottom)

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
