import Foundation

/// Modèles Claude proposés dans les Réglages. Le rawValue est l'ID envoyé à
/// l'API et la clé de stockage : ne pas le changer.
enum ClaudioModel: String, CaseIterable, Sendable {
    case haiku45 = "claude-haiku-4-5"
    case sonnet5 = "claude-sonnet-5"
    case opus5 = "claude-opus-5"

    var displayName: String {
        switch self {
        case .haiku45: "Haiku 4.5 — rapide et économique"
        case .sonnet5: "Sonnet 5 — qualité supérieure"
        case .opus5: "Opus 5 — le plus capable"
        }
    }

    /// `temperature` est accepté par Haiku 4.5 mais rejeté (400) par les
    /// modèles 4.6+ et 5 : on ne l'envoie que lorsqu'il est supporté.
    var supportsTemperature: Bool {
        self == .haiku45
    }

    /// Ordre de grandeur pour une action courte (~200 tokens entrée/sortie),
    /// d'après les tarifs publics par MTok — à rafraîchir si Anthropic les change.
    var costHint: String {
        switch self {
        case .haiku45: "≈ 0,2 centime par action courte"
        case .sonnet5: "≈ 0,5 centime par action courte (~3× Haiku)"
        case .opus5: "≈ 1 centime par action courte (~5× Haiku)"
        }
    }
}

extension ClaudioAction {
    /// Modèle par défaut : Haiku partout (latence minimale), sauf le prompt
    /// expert où la conception justifie Sonnet.
    var defaultModel: ClaudioModel {
        switch self {
        case .expertPrompt: .sonnet5
        default: .haiku45
        }
    }

    /// Modèle effectif : personnalisé (Réglages) sinon défaut.
    var model: ClaudioModel { AppSettings.customModel(for: self) ?? defaultModel }
}
