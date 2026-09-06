import Foundation

enum OllamaError: LocalizedError {
    case notReachable(url: URL)
    case badResponse
    case http(status: Int, message: String)
    case stream(String)

    var errorDescription: String? {
        switch self {
        case .notReachable(let url):
            return loc("Ollama ne répond pas sur \(url.absoluteString) — est-il lancé ?",
                       en: "Ollama isn't responding at \(url.absoluteString) — is it running?")
        case .badResponse:
            return loc("Réponse inattendue d'Ollama.", en: "Unexpected response from Ollama.")
        case .http(let status, let message):
            // 404 = model missing from disk: it's the common failure, and it
            // fixes itself with a single command.
            if status == 404 {
                return loc("Modèle introuvable dans Ollama : \(message). Tire-le avec « ollama pull ».",
                           en: "Model not found in Ollama: \(message). Pull it with “ollama pull”.")
            }
            return loc("Erreur Ollama (\(status)) : \(message)", en: "Ollama error (\(status)): \(message)")
        case .stream(let message):
            return loc("Erreur de flux Ollama : \(message)", en: "Ollama stream error: \(message)")
        }
    }
}

/// Client for Ollama's native API, locally or over the local network.
/// Targets `/api/chat` rather than the OpenAI-compatible endpoint: the native
/// one reports the tokens consumed and the stop reason, so the counter and
/// truncation detection work without a workaround.
/// No authentication: Ollama doesn't offer any.
struct OllamaClient: TextStreamClient {
    let baseURL: URL
    /// Model name as Ollama knows it, e.g. "qwen2.5:14b".
    let model: String

    func streamCompletion(
        of text: String,
        system: String,
        maxTokens: Int,
        onDelta: @escaping @Sendable (String) async -> Void
    ) async throws -> StreamResult {
        var request = URLRequest(url: baseURL.appending(path: "api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: Self.makeBody(text: text, system: system, model: model, maxTokens: maxTokens))

        let (bytes, response) = try await Self.send(request, baseURL: baseURL)
        guard let http = response as? HTTPURLResponse else { throw OllamaError.badResponse }
        guard http.statusCode == 200 else {
            // HTTP errors arrive as a single JSON block, not as NDJSON.
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            throw OllamaError.http(status: http.statusCode, message: Self.apiErrorMessage(from: data))
        }

        var parser = OllamaStreamParser()
        for try await line in bytes.lines {
            if let piece = try parser.consume(line: line) {
                await onDelta(piece)
            }
        }
        return parser.result
    }

    /// Body of the POST /api/chat. The output budget is called `num_predict`
    /// and lives under `options`: set anywhere else, it's silently ignored
    /// and the response goes out with no limit.
    /// `think: false` turns off reasoning on hybrid models (qwen3.5, qwen3…):
    /// left on, it eats up all of `num_predict` and the response never
    /// arrives. A model without a reasoning mode ignores the field without
    /// complaint, so it's always sent. `keep_alive` and `num_ctx` are set
    /// here so the app doesn't depend on the server's own configuration.
    static func makeBody(
        text: String, system: String, model: String, maxTokens: Int
    ) -> [String: Any] {
        [
            "model": model,
            "stream": true,
            "think": false,
            "keep_alive": Constants.ollamaKeepAlive,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": text]
            ],
            // A local model doesn't have the temperature quirks of the 5
            // models: it's always sent.
            "options": [
                "num_predict": maxTokens,
                "temperature": Constants.temperature,
                "num_ctx": contextLength(text: text, system: system, maxTokens: maxTokens)
            ] as [String: Any]
        ]
    }

    /// Requested context window. Fixed on purpose: Ollama reloads the model
    /// every time it changes between requests, wasting two seconds. It only
    /// grows, in steps of 4096, for an input that wouldn't fit alongside its
    /// output budget: otherwise Ollama silently truncates the input.
    static func contextLength(text: String, system: String, maxTokens: Int) -> Int {
        let approxInputTokens = (text.count + system.count) / 4
        let needed = approxInputTokens + maxTokens + 256
        guard needed > Constants.ollamaContextLength else { return Constants.ollamaContextLength }
        return (needed + 4095) / 4096 * 4096
    }

    // MARK: - Installed models

    /// Models pulled on the machine serving Ollama. Unreachable → empty list:
    /// the Settings picker simply has nothing to offer.
    func availableModels() async -> [String] {
        (try? await reachableModels()) ?? []
    }

    /// Same list, but the failure is reported: that's what the "Test
    /// connection" button expects, since it must distinguish "unreachable"
    /// from "reachable, no model pulled".
    func reachableModels() async throws -> [String] {
        let request = URLRequest(url: baseURL.appending(path: "api/tags"))
        let (bytes, response) = try await Self.send(request, baseURL: baseURL)
        var data = Data()
        for try await byte in bytes { data.append(byte) }

        guard let http = response as? HTTPURLResponse else { throw OllamaError.badResponse }
        guard http.statusCode == 200 else {
            throw OllamaError.http(status: http.statusCode, message: Self.apiErrorMessage(from: data))
        }
        return Self.modelNames(from: data)
    }

    /// Names from `GET /api/tags`, in the order Ollama returns them.
    static func modelNames(from data: Data) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = object["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { $0["name"] as? String }
    }

    // MARK: - Transport

    /// A server that's off is the most banal failure of the local engine: it
    /// should be reported with the URL it was aiming at, not a raw URLSession code.
    private static func send(
        _ request: URLRequest, baseURL: URL
    ) async throws -> (URLSession.AsyncBytes, URLResponse) {
        do {
            return try await URLSession.shared.bytes(for: request)
        } catch let error as URLError where isUnreachable(error) {
            throw OllamaError.notReachable(url: baseURL)
        }
    }

    private static func isUnreachable(_ error: URLError) -> Bool {
        switch error.code {
        case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost,
             .timedOut, .dnsLookupFailed, .notConnectedToInternet:
            true
        default:
            false
        }
    }

    /// Ollama reports its errors in a top-level `error` field.
    static func apiErrorMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = object["error"] as? String else {
            return String(data: data.prefix(300), encoding: .utf8)
                ?? loc("réponse illisible", en: "unreadable response")
        }
        return message
    }
}

/// Reads Ollama's NDJSON stream line by line (one complete JSON object per
/// line, not SSE) and pulls out what the app needs: the text, the truncation,
/// and the tokens consumed. Kept separate from the network transport so it's
/// testable against stream transcripts.
struct OllamaStreamParser {
    private(set) var text = ""
    private(set) var truncated = false
    private(set) var inputTokens = 0
    private(set) var outputTokens = 0

    var result: StreamResult {
        StreamResult(text: text, truncated: truncated,
                     inputTokens: inputTokens, outputTokens: outputTokens)
    }

    /// Consumes one line of the stream and returns the text fragment it
    /// carries, if any. Throws whatever error Ollama reports in-stream.
    mutating func consume(line: String) throws -> String? {
        guard let data = line.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }  // blank or truncated line: nothing to pull from it

        if let message = event["error"] as? String {
            throw OllamaError.stream(message)
        }

        // The last line carries the counts: `done:true` is the only place
        // where the tokens and stop reason are reported.
        if event["done"] as? Bool == true {
            truncated = (event["done_reason"] as? String) == "length"
            inputTokens = event["prompt_eval_count"] as? Int ?? inputTokens
            outputTokens = event["eval_count"] as? Int ?? outputTokens
        }

        guard let message = event["message"] as? [String: Any],
              let piece = message["content"] as? String,
              !piece.isEmpty else { return nil }
        text += piece
        return piece
    }
}
