import Foundation

/// The effective engine behind an action: a Claude model, billed by
/// Anthropic, or a local model served by Ollama, free and with no outgoing
/// network traffic. Distinct from `ClaudioModel`, which remains the Claude
/// catalog (API ID, pricing, temperature): this type only says which of the
/// two worlds is answering.
enum ModelChoice: Sendable, Hashable {
    case claude(ClaudioModel)
    /// Model name as Ollama knows it, e.g. "qwen2.5:14b".
    case ollama(model: String)

    /// Cost of a call in dollars. A local call costs nothing: the machine
    /// runs anyway.
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

    /// Bare name, for places short on space, like the panel's footer.
    var shortName: String {
        switch self {
        case .claude(let model): model.shortName
        case .ollama(let name): name
        }
    }

    /// Pricing hint in Settings, next to the model picker.
    var costHint: String {
        switch self {
        case .claude(let model): model.costHint
        case .ollama: loc("Gratuit (local)", en: "Free (local)")
        }
    }

    /// True when nothing leaves the machine (or the local network).
    var isLocal: Bool {
        if case .ollama = self { return true }
        return false
    }

    // MARK: - Settings encoding

    /// Form stored in UserDefaults. The prefix says the provider; the rest
    /// is the model ID, as is: an Ollama ID contains ":".
    var storageValue: String {
        switch self {
        case .claude(let model): "claude:\(model.rawValue)"
        case .ollama(let name): "ollama:\(name)"
        }
    }

    /// Reads back a setting. Splits on the **first** ":" only, otherwise
    /// "ollama:qwen2.5:14b" would lose its version tag.
    /// With no recognized prefix, it's a setting written before Ollama
    /// arrived: it only ever contained a Claude model's rawValue. Claude IDs
    /// never contain ":", so there's no ambiguity with the prefixed scheme.
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
            // Unknown provider (setting written by a future version):
            // there's still a chance it's a legacy Claude ID.
            guard let model = ClaudioModel(rawValue: storageValue) else { return nil }
            self = .claude(model)
        }
    }
}
