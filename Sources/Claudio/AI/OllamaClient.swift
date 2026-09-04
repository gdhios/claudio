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
            // 404 = modèle absent du disque : c'est la panne courante, et elle
            // se répare d'une commande.
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

/// Client pour l'API native d'Ollama, en local ou sur le réseau local.
/// On vise `/api/chat` plutôt que l'endpoint compatible OpenAI : le natif
/// annonce les jetons consommés et la cause d'arrêt, donc le compteur et la
/// détection de troncature marchent sans rustine.
/// Aucune authentification : Ollama n'en propose pas.
struct OllamaClient: TextStreamClient {
    let baseURL: URL
    /// Nom du modèle tel qu'Ollama le connaît, ex. « qwen2.5:14b ».
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
            // Les erreurs HTTP arrivent en JSON d'un bloc, pas en NDJSON.
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

    /// Corps du POST /api/chat. Le budget de sortie s'appelle `num_predict` et
    /// vit sous `options` : posé ailleurs, il est ignoré en silence et la
    /// réponse part sans limite.
    /// `think: false` coupe la réflexion des modèles hybrides (qwen3.5, qwen3…) :
    /// laissée allumée, elle dévore tout `num_predict` et la réponse n'arrive
    /// jamais. Un modèle sans mode réflexion ignore le champ sans broncher, on
    /// l'envoie donc toujours. `keep_alive` et `num_ctx` sont posés ici pour
    /// que l'app ne dépende pas de la configuration du serveur.
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
            // Un modèle local n'a pas les caprices de température des modèles 5 :
            // on l'envoie toujours.
            "options": [
                "num_predict": maxTokens,
                "temperature": Constants.temperature,
                "num_ctx": contextLength(text: text, system: system, maxTokens: maxTokens)
            ] as [String: Any]
        ]
    }

    /// Fenêtre de contexte demandée. Fixe exprès : Ollama recharge le modèle
    /// dès qu'elle change d'une requête à l'autre, deux secondes perdues. Elle
    /// ne grandit, par paliers de 4096, que pour une entrée qui n'y tiendrait
    /// pas avec son budget de sortie — sinon Ollama tronque l'entrée en silence.
    static func contextLength(text: String, system: String, maxTokens: Int) -> Int {
        let approxInputTokens = (text.count + system.count) / 4
        let needed = approxInputTokens + maxTokens + 256
        guard needed > Constants.ollamaContextLength else { return Constants.ollamaContextLength }
        return (needed + 4095) / 4096 * 4096
    }

    // MARK: - Modèles installés

    /// Modèles tirés sur la machine qui sert Ollama. Injoignable → liste vide :
    /// le sélecteur des Réglages se contente de ne rien proposer.
    func availableModels() async -> [String] {
        (try? await reachableModels()) ?? []
    }

    /// Même liste, mais l'échec se dit : c'est ce qu'attend le bouton
    /// « Tester la connexion », qui doit distinguer « injoignable » de
    /// « joignable, aucun modèle tiré ».
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

    /// Noms de `GET /api/tags`, dans l'ordre rendu par Ollama.
    static func modelNames(from data: Data) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = object["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { $0["name"] as? String }
    }

    // MARK: - Transport

    /// Un serveur éteint est la panne la plus banale du moteur local : elle se
    /// dit avec l'URL visée, pas avec un code d'URLSession.
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

    /// Ollama annonce ses erreurs dans un champ `error` à la racine.
    static func apiErrorMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = object["error"] as? String else {
            return String(data: data.prefix(300), encoding: .utf8)
                ?? loc("réponse illisible", en: "unreadable response")
        }
        return message
    }
}

/// Lit le flux NDJSON d'Ollama ligne à ligne — un objet JSON complet par ligne,
/// pas du SSE — et en tire ce que l'app attend : le texte, la troncature et les
/// jetons consommés. Séparé du transport réseau pour être exerçable en test sur
/// des transcriptions du flux.
struct OllamaStreamParser {
    private(set) var text = ""
    private(set) var truncated = false
    private(set) var inputTokens = 0
    private(set) var outputTokens = 0

    var result: StreamResult {
        StreamResult(text: text, truncated: truncated,
                     inputTokens: inputTokens, outputTokens: outputTokens)
    }

    /// Consomme une ligne du flux et renvoie le fragment de texte qu'elle
    /// apporte, s'il y en a un. Lève l'erreur qu'Ollama signale en flux.
    mutating func consume(line: String) throws -> String? {
        guard let data = line.data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }  // ligne vide ou tronquée : rien à en tirer

        if let message = event["error"] as? String {
            throw OllamaError.stream(message)
        }

        // La dernière ligne porte les comptes : `done:true` est le seul endroit
        // où les jetons et la cause d'arrêt sont annoncés.
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
