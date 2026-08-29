import Foundation

enum AnthropicError: LocalizedError {
    case badResponse
    case http(status: Int, message: String)
    case stream(String)

    var errorDescription: String? {
        switch self {
        case .badResponse:
            return "Réponse inattendue du serveur."
        case .http(let status, let message):
            switch status {
            case 401: return "Clé API invalide ou révoquée (401). Vérifie-la dans les Réglages."
            case 429: return "Limite de débit atteinte (429). Réessaie dans quelques secondes."
            case 529: return "API momentanément surchargée (529). Réessaie."
            default: return "Erreur API (\(status)) : \(message)"
            }
        case .stream(let message):
            return "Erreur de flux : \(message)"
        }
    }
}

/// Client minimal pour POST /v1/messages en streaming SSE.
/// (Pas de SDK Swift officiel Anthropic → HTTP brut via URLSession.)
struct AnthropicClient: Sendable {
    let apiKey: String
    /// Requis par les clés « liées à l'identité » (identity-linked), sinon 400.
    var workspaceID: String? = nil

    struct StreamResult: Sendable {
        let text: String
        let truncated: Bool
    }

    func streamCompletion(
        of text: String,
        system: String,
        model: ClaudioModel,
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
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw AnthropicError.badResponse }
        guard http.statusCode == 200 else {
            // Les erreurs HTTP arrivent en JSON classique, pas en SSE.
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            throw AnthropicError.http(status: http.statusCode, message: Self.apiErrorMessage(from: data))
        }

        var full = ""
        var truncated = false

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }  // ignore "event: …" et lignes vides
            guard let data = String(line.dropFirst(6)).data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = event["type"] as? String else { continue }

            switch type {
            case "content_block_delta":
                if let delta = event["delta"] as? [String: Any],
                   delta["type"] as? String == "text_delta",
                   let piece = delta["text"] as? String {
                    full += piece
                    await onDelta(piece)
                }
            case "message_delta":
                if let delta = event["delta"] as? [String: Any],
                   let stop = delta["stop_reason"] as? String {
                    truncated = (stop == "max_tokens")
                }
            case "error":
                let message = ((event["error"] as? [String: Any])?["message"] as? String) ?? "erreur inconnue"
                throw AnthropicError.stream(message)
            default:
                continue  // message_start, content_block_start/stop, message_stop, ping
            }
        }
        return StreamResult(text: full, truncated: truncated)
    }

    private static func apiErrorMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return String(data: data.prefix(300), encoding: .utf8) ?? "réponse illisible"
        }
        return message
    }
}
