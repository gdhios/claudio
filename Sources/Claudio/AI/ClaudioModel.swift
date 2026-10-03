import Foundation

/// A Claude model, known by its API identifier. The identifier is the whole
/// identity: it is what goes in the request's `model` field and in the
/// settings' storage, and two values with the same id are the same model
/// whatever name either carries. Everything else — name, family, price,
/// whether `temperature` is accepted — derives from the id and from the
/// tables below, so a model this version has never heard of still works.
struct ClaudioModel: Hashable, Sendable {
    /// The API identifier, e.g. "claude-sonnet-5-5". Also the storage key:
    /// never rewritten.
    let id: String
    /// The name the API gave, when the model came from its list. `nil` for
    /// a model built from its id alone.
    private let apiDisplayName: String?

    init(id: String, displayName: String? = nil) {
        self.id = id
        self.apiDisplayName = displayName
    }

    static func == (lhs: ClaudioModel, rhs: ClaudioModel) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    // MARK: - Identifier

    /// `nil` unless the text is a Claude identifier: settings only ever held
    /// those, and the API only answers for those.
    init?(rawValue: String) {
        guard Self.isClaudeID(rawValue) else { return nil }
        self.init(id: rawValue)
    }

    /// A Claude identifier starts with "claude-" and names something after it.
    static func isClaudeID(_ text: String) -> Bool {
        text.hasPrefix(idPrefix) && text.count > idPrefix.count
    }

    private static let idPrefix = "claude-"

    // MARK: - The models the app ships

    static let haiku45 = ClaudioModel(id: "claude-haiku-4-5")
    static let sonnet5 = ClaudioModel(id: "claude-sonnet-5")
    static let sonnet55 = ClaudioModel(id: "claude-sonnet-5-5")
    static let opus5 = ClaudioModel(id: "claude-opus-5")
    static let opus55 = ClaudioModel(id: "claude-opus-5-5")

    /// The list without network: grouped by family, newest first. Every
    /// model here has a row in `known`. The API's list adds to it
    /// (`ModelCatalog`), never replaces it.
    static let bundled: [ClaudioModel] = [haiku45, sonnet55, sonnet5, opus55, opus5]

    // MARK: - Family and version

    /// The tier, read from the id. Also the picker's grouping order.
    enum Family: Int, Comparable, Sendable {
        case haiku, sonnet, opus, other

        static func < (lhs: Family, rhs: Family) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    var family: Family {
        for token in Self.tokens(of: id) {
            switch token {
            case "haiku": return .haiku
            case "sonnet": return .sonnet
            case "opus": return .opus
            default: continue
            }
        }
        return .other
    }

    /// The version numbers of the id, in order: "claude-sonnet-5-5" is
    /// [5, 5], newer than [5]. A dated snapshot's date is not a version.
    var versionTokens: [Int] {
        Self.tokens(of: id).compactMap { token in
            Self.isDate(token) ? nil : Int(token)
        }
    }

    /// The dated snapshot's date, "20250805", when the id carries one.
    var snapshotDate: String? {
        Self.tokens(of: id).first(where: Self.isDate).map(String.init)
    }

    /// The id without its snapshot date: the alias the API also lists.
    var aliasID: String {
        guard snapshotDate != nil else { return id }
        return ([Self.idPrefix.dropLast()] + Self.tokens(of: id).filter { !Self.isDate($0) })
            .joined(separator: "-")
    }

    private static func tokens(of id: String) -> [Substring] {
        id.dropFirst(idPrefix.count).split(separator: "-")
    }

    private static func isDate(_ token: Substring) -> Bool {
        token.count == 8 && token.allSatisfy(\.isNumber)
    }

    // MARK: - Names

    /// The bare name, for the footer and for sentences: the API's name
    /// without its "Claude " ("Sonnet 5.5"), else one read from the id.
    var shortName: String {
        if let apiDisplayName {
            let trimmed = apiDisplayName.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("claude ") {
                return String(trimmed.dropFirst("claude ".count))
            }
            return trimmed
        }
        return Self.derivedName(fromID: id)
    }

    /// "claude-sonnet-5-5" reads "Sonnet 5.5"; "claude-opus-4-1-20250805"
    /// reads "Opus 4.1 (2025-08-05)". Words first, then the version, then
    /// the snapshot date — whatever order the id had them in.
    static func derivedName(fromID id: String) -> String {
        var words: [String] = []
        var numbers: [String] = []
        var date: String?
        for token in tokens(of: id) {
            if isDate(token) {
                date = "\(token.prefix(4))-\(token.dropFirst(4).prefix(2))-\(token.suffix(2))"
            } else if Int(token) != nil {
                numbers.append(String(token))
            } else {
                words.append(token.prefix(1).uppercased() + token.dropFirst())
            }
        }
        var parts: [String] = []
        if !words.isEmpty { parts.append(words.joined(separator: " ")) }
        if !numbers.isEmpty { parts.append(numbers.joined(separator: ".")) }
        if let date { parts.append("(\(date))") }
        return parts.joined(separator: " ")
    }

    /// The picker's line: the name and what the family is for.
    var displayName: String {
        switch family {
        case .haiku: "\(shortName) \(loc("(rapide et économique)", en: "(fast and cheap)"))"
        case .sonnet: "\(shortName) \(loc("(qualité supérieure)", en: "(higher quality)"))"
        case .opus: "\(shortName) \(loc("(le plus capable)", en: "(the most capable)"))"
        case .other: shortName
        }
    }

    // MARK: - What this version knows of each model

    /// Dollars per million tokens, input and output.
    struct Pricing: Hashable, Sendable {
        let input: Double
        let output: Double
    }

    /// What one model accepts and costs. A wrong value is a 400 or a wrong
    /// bill, so these only apply to the closed list below: a model this
    /// version has never heard of gets no price, no `temperature` and no
    /// thinking switch.
    struct Traits: Sendable {
        /// Anthropic's public pricing, platform.claude.com/docs (read
        /// 2026-09-25): refresh when it changes. Never the family's.
        var pricing: Pricing
        /// `temperature` is accepted by the old models and rejected (400) by
        /// every model since 4.6.
        var acceptsTemperature = false
        /// The `thinking.type` that turns thinking off
        /// (platform.claude.com/docs, thinking-troubleshooting, read
        /// 2026-10-03). Claudio asks one short answer and uses no tool:
        /// thinking only spends the answer's budget, and a `thinking` block
        /// alone in 400 tokens is an empty card. Haiku 4.5 doesn't think
        /// unless asked.
        var thinkingOffType: String?
        /// Cannot stop thinking: the request lowers its effort instead and
        /// gives the budget headroom.
        var alwaysThinks = false
    }

    static let known: [String: Traits] = [
        "claude-haiku-4-5": Traits(pricing: Pricing(input: 1, output: 5), acceptsTemperature: true),
        "claude-sonnet-5": Traits(pricing: Pricing(input: 2, output: 10), thinkingOffType: "disabled"),
        "claude-sonnet-5-5": Traits(pricing: Pricing(input: 2, output: 10), thinkingOffType: "between_tools"),
        "claude-opus-5": Traits(pricing: Pricing(input: 5, output: 25), thinkingOffType: "disabled"),
        "claude-opus-5-5": Traits(pricing: Pricing(input: 4, output: 20), alwaysThinks: true),
    ]

    private var traits: Traits? { Self.known[id] }

    var supportsTemperature: Bool { traits?.acceptsTemperature ?? false }
    /// `nil` when the model has no such switch.
    var thinkingOffType: String? { traits?.thinkingOffType }
    var alwaysThinks: Bool { traits?.alwaysThinks ?? false }
    /// A model missing from the table has no price.
    var pricing: Pricing? { traits?.pricing }

    // MARK: - Pricing

    /// Cost of a call in dollars, based on the tokens actually billed. An
    /// unpriced model costs nothing on paper: the ledger counts the call
    /// apart rather than guess (`DailyCost.unpricedActions`).
    func cost(inputTokens: Int, outputTokens: Int) -> Double {
        guard let pricing else { return 0 }
        return (Double(inputTokens) * pricing.input
            + Double(outputTokens) * pricing.output) / 1_000_000
    }

    /// Hint for Settings. A short action costs thousandths of a dollar: a
    /// hundred of them are counted to stay readable.
    var costHint: String {
        guard pricing != nil else {
            return loc("Tarif non connu de cette version de Claudio",
                       en: "Price unknown to this version of Claudio")
        }
        let hundred = cost(inputTokens: 200, outputTokens: 200) * 100
        return loc("≈ \(Money.format(hundred)) pour 100 actions courtes",
                   en: "≈ \(Money.format(hundred)) per 100 short actions")
    }

    /// Raw pricing, as Anthropic displays it. `nil` without a price.
    var priceLine: String? {
        guard let pricing else { return nil }
        return "\(shortName) \(Money.formatRounded(pricing.input)) / \(Money.formatRounded(pricing.output))"
    }
}
