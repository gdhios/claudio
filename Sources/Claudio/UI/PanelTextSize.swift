import CoreGraphics

/// Taille du texte dans le panneau flottant. Le corps par défaut de macOS est
/// petit pour qui lit mal : ce réglage l'agrandit là où l'on lit et où l'on
/// écrit, sans toucher au décor (badges, raccourcis, indices), qui n'a pas à
/// grossir pour rester lisible.
///
/// Le `rawValue` est la clé de stockage dans UserDefaults : il ne change plus.
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

    /// Corps du texte lu et écrit dans le panneau. `normal` vaut le corps de
    /// `.body` sur macOS : le réglage par défaut ne change rien à l'existant.
    var bodyPoints: CGFloat {
        switch self {
        case .small: 12
        case .normal: 13
        case .large: 15.5
        case .extraLarge: 18
        }
    }

    /// Facteur par rapport au réglage normal.
    var scale: CGFloat { bodyPoints / PanelTextSize.normal.bodyPoints }

    /// Taille dérivée d'un corps exprimé au réglage normal.
    func points(_ base: CGFloat) -> CGFloat { base * scale }

    /// Largeur du panneau : elle suit le texte vers le haut. Un corps de 18
    /// dans 460 points de large ne donnerait plus que des lignes de quelques
    /// mots, et la lecture y perdrait ce que le corps lui fait gagner.
    var panelWidth: CGFloat {
        max((Constants.panelWidth * (1 + (scale - 1) * 0.7)).rounded(), Constants.panelWidth)
    }

    /// Hauteur minimale de la zone de texte : le panneau s'ouvre à cette taille
    /// d'accueil et une phrase courte s'y pose sans faire bouger la fenêtre.
    /// Elle suit le corps du texte, sans jamais dépasser le plafond.
    var minTextHeight: CGFloat {
        min((Constants.panelMinTextHeight * scale).rounded(), maxTextHeight)
    }

    /// Hauteur maximale de la zone de texte : elle suit aussi, mais plafonnée
    /// pour que le panneau reste un panneau. Au-delà, on défile.
    var maxTextHeight: CGFloat {
        min(max((Constants.panelMaxTextHeight * scale).rounded(), Constants.panelMaxTextHeight), 520)
    }
}
