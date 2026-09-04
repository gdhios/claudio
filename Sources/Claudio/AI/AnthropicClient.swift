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

/// Client minimal pour POST /v1/messages en streaming SSE.
/// (Pas de SDK Swift officiel Anthropic → HTTP brut via URLSession.)
struct AnthropicClient: TextStreamClient {
    let apiKey: String
    /// Requis par les clés « liées à l'identité » (identity-linked), sinon 400.
    var workspaceID: String? = nil
    /// Un client parle à un modèle : celui de l'action qui l'a construit.
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
            // Les erreurs HTTP arrivent en JSON classique, pas en SSE.
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

    /// Corps du POST /v1/messages. Un champ mal nommé ou une température
    /// envoyée à un modèle qui la refuse est un 400 pour tout le monde :
    /// c'est ce que les tests verrouillent.
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

    /// Lit le flux SSE ligne à ligne et en tire tout ce que l'app en attend :
    /// le texte, la troncature et les jetons facturés. Séparé du transport
    /// réseau pour être exerçable en test sur des transcriptions du flux.
    struct StreamParser {
        private(set) var text = ""
        private(set) var truncated = false
        private(set) var inputTokens = 0
        private(set) var outputTokens = 0

        var result: StreamResult {
            StreamResult(text: text, truncated: truncated,
                         inputTokens: inputTokens, outputTokens: outputTokens)
        }

        /// Consomme une ligne du flux et renvoie le fragment de texte qu'elle
        /// apporte, s'il y en a un. Lève l'erreur que l'API signale en flux.
        mutating func consume(line: String) throws -> String? {
            guard line.hasPrefix("data: ") else { return nil }  // ignore "event: …" et lignes vides
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
                // Seul endroit où les jetons d'entrée sont annoncés.
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
                // Le compte de sortie est cumulatif : le dernier fait foi.
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
