import Foundation

enum AnthropicError: LocalizedError {
    case badResponse
    case http(status: Int, message: String)
    case stream(String)

    var errorDescription: String? {
        switch self {
        case .badResponse:
            return loc("Réponse inattendue du serveur.", en: "Unexpected response from the server.")
        case .http(let status, let message):
            switch status {
            case 401: return loc("Clé API invalide ou révoquée (401). Vérifie-la dans les Réglages.",
                                 en: "Invalid or revoked API key (401). Check it in Settings.")
            case 429: return loc("Limite de débit atteinte (429). Réessaie dans quelques secondes.",
                                 en: "Rate limit reached (429). Try again in a few seconds.")
            case 529: return loc("API momentanément surchargée (529). Réessaie.",
                                 en: "The API is briefly overloaded (529). Try again.")
            default: return loc("Erreur API (\(status)) : \(message)", en: "API error (\(status)): \(message)")
            }
        case .stream(let message):
            return loc("Erreur de flux : \(message)", en: "Stream error: \(message)")
        }
    }
}

/// Minimal client for POST /v1/messages in SSE streaming.
/// (No official Anthropic Swift SDK, so raw HTTP via URLSession.)
struct AnthropicClient: TextStreamClient {
    let apiKey: String
    /// Required for "identity-linked" keys, otherwise a 400.
    var workspaceID: String? = nil
    /// A client talks to one model: the one from the action that built it.
    let model: ClaudioModel

    func streamCompletion(
        of text: String,
        system: String,
        maxTokens: Int,
        onDelta: @escaping @Sendable (String) async -> Void
    ) async throws -> StreamResult {
        var request = URLRequest(url: Constants.apiURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Constants.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        if let workspaceID, !workspaceID.isEmpty {
            request.setValue(workspaceID, forHTTPHeaderField: "anthropic-workspace-id")
        }

        request.httpBody = try JSONSerialization.data(
            withJSONObject: Self.makeBody(text: text, system: system, model: model, maxTokens: maxTokens))

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw AnthropicError.badResponse }
        guard http.statusCode == 200 else {
            // HTTP errors arrive as plain JSON, not SSE.
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            throw AnthropicError.http(status: http.statusCode, message: Self.apiErrorMessage(from: data))
        }

        var parser = StreamParser()
        for try await line in bytes.lines {
            if let piece = try parser.consume(line: line) {
                await onDelta(piece)
            }
        }
        return parser.result
    }

    /// Body of the POST /v1/messages. A misnamed field or a temperature
    /// sent to a model that rejects it is a 400 for everyone: that's what
    /// the tests lock down.
    static func makeBody(
        text: String, system: String, model: ClaudioModel, maxTokens: Int
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": maxTokens,
            "system": system,
            "stream": true,
            "messages": [["role": "user", "content": text]]
        ]
        if model.supportsTemperature {
            body["temperature"] = Constants.temperature
        }
        return body
    }

    /// Reads the SSE stream line by line and pulls out everything the app
    /// needs from it: the text, the truncation, and the billed tokens.
    /// Kept separate from the network transport so it's testable against
    /// stream transcripts.
    struct StreamParser {
        private(set) var text = ""
        private(set) var truncated = false
        private(set) var inputTokens = 0
        private(set) var outputTokens = 0

        var result: StreamResult {
            StreamResult(text: text, truncated: truncated,
                         inputTokens: inputTokens, outputTokens: outputTokens)
        }

        /// Consumes one line of the stream and returns the text fragment it
        /// carries, if any. Throws whatever error the API reports in-stream.
        mutating func consume(line: String) throws -> String? {
            guard line.hasPrefix("data: ") else { return nil }  // ignore "event: …" and blank lines
            guard let data = String(line.dropFirst(6)).data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = event["type"] as? String else { return nil }

            switch type {
            case "content_block_delta":
                if let delta = event["delta"] as? [String: Any],
                   delta["type"] as? String == "text_delta",
                   let piece = delta["text"] as? String {
                    text += piece
                    return piece
                }
            case "message_start":
                // The only place input tokens are reported.
                if let message = event["message"] as? [String: Any],
                   let usage = message["usage"] as? [String: Any] {
                    inputTokens = usage["input_tokens"] as? Int ?? inputTokens
                    outputTokens = usage["output_tokens"] as? Int ?? outputTokens
                }
            case "message_delta":
                if let delta = event["delta"] as? [String: Any],
                   let stop = delta["stop_reason"] as? String {
                    truncated = (stop == "max_tokens")
                }
                // The output count is cumulative: the last one wins.
                if let usage = event["usage"] as? [String: Any] {
                    inputTokens = usage["input_tokens"] as? Int ?? inputTokens
                    outputTokens = usage["output_tokens"] as? Int ?? outputTokens
                }
            case "error":
                let message = ((event["error"] as? [String: Any])?["message"] as? String) ?? "erreur inconnue"
                throw AnthropicError.stream(message)
            default:
                break  // content_block_start/stop, message_stop, ping
            }
            return nil
        }
    }

    static func apiErrorMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return String(data: data.prefix(300), encoding: .utf8) ?? loc("réponse illisible", en: "unreadable response")
        }
        return message
    }
}
