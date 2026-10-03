import Foundation
@testable import Claudio

/// Answers in two pieces, or throws: one answer per call, the last one
/// again once the list runs out. Keeps what each call was sent — the text,
/// the prompt, the room the answer was given — so a test can also prove a
/// model was never asked anything.
///
/// `@unchecked Sendable`: every call is awaited before a test reads it.
final class FakeTextStreamClient: TextStreamClient, @unchecked Sendable {
    private var answers: [Result<String, Error>]
    /// A model that doesn't answer until the call is cancelled: the window a
    /// dictation used to be lost in — the transcript exists, the cleaned-up
    /// text doesn't yet.
    private let parks: Bool
    var stopReason: String? = "end_turn"
    var blockTypes: [String] = ["text"]
    private(set) var texts: [String] = []
    private(set) var systems: [String] = []
    private(set) var budgets: [Int] = []

    init(_ answers: [Result<String, Error>], parks: Bool = false) {
        self.answers = answers
        self.parks = parks
    }

    convenience init(_ answer: Result<String, Error>, parks: Bool = false) {
        self.init([answer], parks: parks)
    }

    var calls: Int { texts.count }

    func streamCompletion(of text: String,
                          system: String,
                          maxTokens: Int,
                          onDelta: @escaping @Sendable (String) async -> Void) async throws -> StreamResult {
        texts.append(text)
        systems.append(system)
        budgets.append(maxTokens)
        while parks, !Task.isCancelled { await Task.yield() }
        let answer = answers.count > 1 ? answers.removeFirst() : answers[0]
        let full = try answer.get()
        let middle = full.index(full.startIndex, offsetBy: full.count / 2)
        await onDelta(String(full[..<middle]))
        await onDelta(String(full[middle...]))
        return StreamResult(text: full, truncated: false, inputTokens: 0, outputTokens: 0,
                            stopReason: stopReason, blockTypes: blockTypes)
    }
}

/// What a model that isn't answering looks like from here.
struct ModelFailure: LocalizedError {
    var errorDescription: String? { "The API didn't answer" }
}
