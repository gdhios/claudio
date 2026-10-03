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

/// How a completion ended, seen from a coordinator.
enum StreamOutcome {
    case answered(StreamResult)
    /// Esc, a new press, a panel closed: nothing to show, nothing billed.
    case cancelled
    case failed(Error)
}

extension TextStreamClient {
    /// One completion the way every panel runs it: streamed piece by piece,
    /// its spend recorded, and cancellation — however the task or
    /// URLSession reports it — folded into one case.
    @MainActor
    func complete(_ text: String,
                  system: String,
                  maxTokens: Int,
                  model: ModelChoice,
                  onDelta: @escaping @Sendable @MainActor (String) -> Void) async -> StreamOutcome {
        do {
            let result = try await streamCompletion(of: text, system: system, maxTokens: maxTokens) {
                @MainActor piece in onDelta(piece)
            }
            guard !Task.isCancelled else { return .cancelled }
            CostLedger.shared.record(model: model,
                                     inputTokens: result.inputTokens,
                                     outputTokens: result.outputTokens)
            return .answered(result)
        } catch is CancellationError {
            return .cancelled
        } catch let error as URLError where error.code == .cancelled {
            return .cancelled
        } catch {
            return Task.isCancelled ? .cancelled : .failed(error)
        }
    }
}

extension URLSession.AsyncBytes {
    /// The whole body, for an HTTP error that arrives as one JSON block
    /// rather than as a stream.
    func collect() async throws -> Data {
        var data = Data()
        for try await byte in self { data.append(byte) }
        return data
    }
}
