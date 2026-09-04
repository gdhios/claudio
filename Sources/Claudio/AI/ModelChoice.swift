import Foundation

/// Le moteur effectif d'une action : un modèle Claude, facturé par Anthropic,
/// ou un modèle local servi par Ollama, gratuit et sans réseau sortant.
/// Distinct de `ClaudioModel`, qui reste le catalogue Claude (ID d'API, tarifs,
/// température) : ce type-ci ne fait que dire lequel des deux mondes répond.
enum ModelChoice: Sendable, Hashable {
    case claude(ClaudioModel)
    /// Nom du modèle tel qu'Ollama le connaît, ex. « qwen2.5:14b ».
    case ollama(model: String)

    /// Coût d'un appel en dollars. Un appel local ne coûte rien : la machine
    /// tourne de toute façon.
    func cost(inputTokens: Int, outputTokens: Int) -> Double {
        switch self {
        case .claude(let model): model.cost(inputTokens: inputTokens, outputTokens: outputTokens)
        case .ollama: 0
        }
    }

    var displayName: String {
        switch self {
        case .claude(let model): model.displayName
        case .ollama(let name): name
        }
    }

    /// Nom nu, pour les endroits où la place manque — le pied du panneau.
    var shortName: String {
        switch self {
        case .claude(let model): model.shortName
        case .ollama(let name): name
        }
    }

    /// Repère de tarif dans les Réglages, à côté du sélecteur de modèle.
    var costHint: String {
        switch self {
        case .claude(let model): model.costHint
        case .ollama: loc("Gratuit (local)", en: "Free (local)")
        }
    }

    /// Vrai quand rien ne sort de la machine (ou du réseau local).
    var isLocal: Bool {
        if case .ollama = self { return true }
        return false
    }

    // MARK: - Encodage des réglages

    /// Forme stockée dans UserDefaults. Le préfixe dit le fournisseur ; le reste
    /// est l'ID du modèle, tel quel — un ID Ollama contient des « : ».
    var storageValue: String {
        switch self {
        case .claude(let model): "claude:\(model.rawValue)"
        case .ollama(let name): "ollama:\(name)"
        }
    }

    /// Relit un réglage. Découpe sur le **premier** « : » seulement, sinon
    /// « ollama:qwen2.5:14b » perdrait sa balise de version.
    /// Sans préfixe reconnu, c'est un réglage écrit avant l'arrivée d'Ollama :
    /// il ne contenait que le rawValue d'un modèle Claude. Les ID Claude
    /// n'ont jamais de « : », donc aucune ambiguïté avec le schéma préfixé.
    init?(storageValue: String) {
        guard let separator = storageValue.firstIndex(of: ":") else {
            guard let model = ClaudioModel(rawValue: storageValue) else { return nil }
            self = .claude(model)
            return
        }
        let provider = String(storageValue[..<separator])
        let identifier = String(storageValue[storageValue.index(after: separator)...])

        switch provider {
        case "claude":
            guard let model = ClaudioModel(rawValue: identifier) else { return nil }
            self = .claude(model)
        case "ollama":
            guard !identifier.isEmpty else { return nil }
            self = .ollama(model: identifier)
        default:
            // Fournisseur inconnu (réglage écrit par une version future) :
            // reste la chance que ce soit un ID Claude hérité.
            guard let model = ClaudioModel(rawValue: storageValue) else { return nil }
            self = .claude(model)
        }
    }
}
