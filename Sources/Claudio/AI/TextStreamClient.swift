import Foundation

/// What a streaming completion reports, regardless of provider: the assembled
/// text, the truncation, and the tokens the call consumed.
struct StreamResult: Sendable {
    let text: String
    let truncated: Bool
    /// Tokens counted, as reported by the provider itself. Zero when the
    /// stream stops before they've been given.
    let inputTokens: Int
    let outputTokens: Int
    /// Why the provider stopped ("end_turn", "max_tokens", "refusal"…),
    /// `nil` when it never said. Kept for the day the text is empty.
    var stopReason: String? = nil
    /// The types of the content blocks that came, in order ("text",
    /// "thinking"…): what the stream held when it held no text.
    var blockTypes: [String] = []

    /// What the panel says over an empty answer: how the stream ended,
    /// what it carried, what it cost. "?" where the provider said nothing.
    var emptyAnswerDescription: String {
        let blocks = blockTypes.isEmpty ? loc("aucun bloc", en: "no block") : blockTypes.joined(separator: ", ")
        return "\(stopReason ?? "?") · \(blocks) · \(outputTokens) \(loc("jetons", en: "tokens"))"
    }
}

/// Common contract for all streaming completion providers.
/// The model and configuration (key, URL) are carried by the concrete
/// client's init: a client = one provider + one given model. The caller
/// therefore no longer needs to know who it's talking to once the client is built.
protocol TextStreamClient: Sendable {
    func streamCompletion(
        of text: String,
        system: String,
        maxTokens: Int,
        onDelta: @escaping @Sendable (String) async -> Void
    ) async throws -> StreamResult
}
