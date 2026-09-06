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
