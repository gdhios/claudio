import Foundation

/// `Claudio --selftest [texte] [instruction]` : teste le client streaming en
/// CLI, sans UI. Avec une instruction, c'est le chemin de l'action libre qui est
/// exercé au lieu de la correction du catalogue.
/// Code de sortie non nul si l'appel échoue : c'est ce qui permet à
/// `Scripts/test.sh --release` de s'en servir comme verrou de publication.
enum SelfTest {
    static func runBlocking() {
        let arguments = CommandLine.arguments
        let extras = arguments.firstIndex(of: "--selftest").map { Array(arguments[($0 + 1)...]) } ?? []
        let sample = extras.first
            ?? "Bonjour, je voulait savoir si tu pouvait m'envoyer les document avant demain matin. merci d'avance"
        let request = extras.count > 1
            ? ClaudioRequest.free(instruction: extras[1])
            : ClaudioAction.correct.request

        // Le moteur de l'action décide du client, comme dans l'app. Une action
        // réglée en local se teste sans clé API.
        let client: TextStreamClient
        switch request.model {
        case .claude(let model):
            guard let apiKey = KeychainStore.currentAPIKey() else {
                print("❌ Aucune clé API : exporte \(Constants.apiKeyEnvVar) ou enregistre une clé dans les Réglages.")
                exit(1)
            }
            client = AnthropicClient(apiKey: apiKey,
                                     workspaceID: AppSettings.currentWorkspaceID(),
                                     model: model)
        case .ollama(let name):
            client = OllamaClient(baseURL: AppSettings.ollamaBaseURL, model: name)
        }

        print("→ Action : \(request.panelTitle)")
        print("→ Modèle : \(request.model.displayName)")
        print("→ Texte  : \(sample)")
        print("---")

        // Semaphore + Task.detached : le travail reste hors du main thread
        // (bloqué par wait()), aucun saut vers le MainActor dans ce chemin.
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                let result = try await client.streamCompletion(
                    of: request.userMessage(forText: sample),
                    system: request.system,
                    maxTokens: request.maxTokens(forText: sample)
                ) { piece in
                    print(piece, terminator: "")
                }
                print("\n---")
                print(result.truncated
                      ? "⚠️ Réponse tronquée (max_tokens atteint)"
                      : "✅ OK (\(result.text.count) caractères)")
                // Rend visible ce que le compteur de dépense enregistrera.
                let cost = request.model.cost(inputTokens: result.inputTokens,
                                              outputTokens: result.outputTokens)
                print("→ Jetons : \(result.inputTokens) entrée / \(result.outputTokens) sortie"
                      + " → \(Money.format(cost))")
            } catch {
                // Une CLI qui échoue doit le dire par son code de sortie,
                // pas seulement à l'écran.
                print("\n❌ \(error.localizedDescription)")
                fflush(stdout)
                exit(1)
            }
            semaphore.signal()
        }
        semaphore.wait()
    }
}
