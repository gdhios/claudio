import Foundation

/// Claude models offered in Settings. The rawValue is the ID sent to the API
/// and the storage key: do not change it.
enum ClaudioModel: String, CaseIterable, Sendable {
    case haiku45 = "claude-haiku-4-5"
    case sonnet5 = "claude-sonnet-5"
    case opus5 = "claude-opus-5"

    var displayName: String {
        switch self {
        case .haiku45: loc("Haiku 4.5 (rapide et économique)", en: "Haiku 4.5 (fast and cheap)")
        case .sonnet5: loc("Sonnet 5 (qualité supérieure)", en: "Sonnet 5 (higher quality)")
        case .opus5: loc("Opus 5 (le plus capable)", en: "Opus 5 (the most capable)")
        }
    }

    /// Bare name, for sentences where the qualifier gets in the way.
    var shortName: String {
        switch self {
        case .haiku45: "Haiku 4.5"
        case .sonnet5: "Sonnet 5"
        case .opus5: "Opus 5"
        }
    }

    /// `temperature` is accepted by Haiku 4.5 but rejected (400) by the
    /// 4.6+ and 5 models: it's only sent when supported.
    var supportsTemperature: Bool {
        self == .haiku45
    }

    // MARK: - Pricing

    /// Anthropic's public pricing, in dollars per million tokens, taken from
    /// platform.claude.com/docs: refresh if they change.
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

    /// Cost of a call in dollars, based on the tokens actually billed.
    func cost(inputTokens: Int, outputTokens: Int) -> Double {
        (Double(inputTokens) * inputPricePerMTok
            + Double(outputTokens) * outputPricePerMTok) / 1_000_000
    }

    /// Hint for Settings. A short action costs thousandths of a dollar: a
    /// hundred of them are counted to stay readable.
    var costHint: String {
        let hundred = cost(inputTokens: 200, outputTokens: 200) * 100
        return loc("≈ \(Money.format(hundred)) pour 100 actions courtes",
                   en: "≈ \(Money.format(hundred)) per 100 short actions")
    }

    /// Raw pricing, as Anthropic displays it.
    var priceLine: String {
        "\(shortName) \(Money.formatRounded(inputPricePerMTok)) / \(Money.formatRounded(outputPricePerMTok))"
    }
}

extension ClaudioAction {
    /// Default model: Haiku everywhere (minimal latency), except for the
    /// expert prompt where the design work justifies Sonnet.
    var defaultModel: ClaudioModel {
        switch self {
        case .expertPrompt: .sonnet5
        default: .haiku45
        }
    }

    /// Effective engine: custom (Settings) otherwise the Claude default.
    var model: ModelChoice { AppSettings.customModel(for: self) ?? .claude(defaultModel) }
}
