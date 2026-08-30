import Foundation

/// Modèles Claude proposés dans les Réglages. Le rawValue est l'ID envoyé à
/// l'API et la clé de stockage : ne pas le changer.
enum ClaudioModel: String, CaseIterable, Sendable {
    case haiku45 = "claude-haiku-4-5"
    case sonnet5 = "claude-sonnet-5"
    case opus5 = "claude-opus-5"

    var displayName: String {
        switch self {
        case .haiku45: "Haiku 4.5 (rapide et économique)"
        case .sonnet5: "Sonnet 5 (qualité supérieure)"
        case .opus5: "Opus 5 (le plus capable)"
        }
    }

    /// Nom nu, pour les phrases où le qualificatif encombre.
    var shortName: String {
        switch self {
        case .haiku45: "Haiku 4.5"
        case .sonnet5: "Sonnet 5"
        case .opus5: "Opus 5"
        }
    }

    /// `temperature` est accepté par Haiku 4.5 mais rejeté (400) par les
    /// modèles 4.6+ et 5 : on ne l'envoie que lorsqu'il est supporté.
    var supportsTemperature: Bool {
        self == .haiku45
    }

    // MARK: - Tarifs

    /// Tarifs publics Anthropic, en dollars par million de jetons, relevés sur
    /// platform.claude.com/docs — à rafraîchir s'ils changent.
    var inputPricePerMTok: Double {
        switch self {
        case .haiku45: 1
        case .sonnet5: 2
        case .opus5: 5
        }
    }

    var outputPricePerMTok: Double {
        switch self {
        case .haiku45: 5
        case .sonnet5: 10
        case .opus5: 25
        }
    }

    /// Coût d'un appel en dollars, d'après les jetons réellement facturés.
    func cost(inputTokens: Int, outputTokens: Int) -> Double {
        (Double(inputTokens) * inputPricePerMTok
            + Double(outputTokens) * outputPricePerMTok) / 1_000_000
    }

    /// Repère pour les Réglages. Une action courte coûte des millièmes de
    /// dollar : on en compte cent pour rester lisible.
    var costHint: String {
        let hundred = cost(inputTokens: 200, outputTokens: 200) * 100
        return "≈ \(Money.format(hundred)) pour 100 actions courtes"
    }

    /// Tarif brut, tel qu'Anthropic l'affiche.
    var priceLine: String {
        "\(shortName) \(Money.formatRounded(inputPricePerMTok)) / \(Money.formatRounded(outputPricePerMTok))"
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
