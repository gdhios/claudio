import Foundation

/// `Claudio --selftest [texte] [instruction]` : teste le client streaming en
/// CLI, sans UI. Avec une instruction, c'est le chemin de l'action libre qui est
/// exercé au lieu de la correction du catalogue.
enum SelfTest {
    static func runBlocking() {
        let arguments = CommandLine.arguments
        let extras = arguments.firstIndex(of: "--selftest").map { Array(arguments[($0 + 1)...]) } ?? []
        let sample = extras.first
            ?? "Bonjour, je voulait savoir si tu pouvait m'envoyer les document avant demain matin. merci d'avance"
        let request = extras.count > 1
            ? ClaudioRequest.free(instruction: extras[1])
            : ClaudioAction.correct.request

        guard let apiKey = KeychainStore.currentAPIKey() else {
            print("❌ Aucune clé API : exporte \(Constants.apiKeyEnvVar) ou enregistre une clé dans les Réglages.")
            exit(1)
        }

        print("→ Action : \(request.panelTitle)")
        print("→ Modèle : \(request.model.rawValue)")
        print("→ Texte  : \(sample)")
        print("---")

        // Semaphore + Task.detached : le travail reste hors du main thread
        // (bloqué par wait()), aucun saut vers le MainActor dans ce chemin.
        let semaphore = DispatchSemaphore(value: 0)
        let client = AnthropicClient(apiKey: apiKey, workspaceID: AppSettings.currentWorkspaceID())
        Task.detached {
            do {
                let result = try await client.streamCompletion(
                    of: request.userMessage(forText: sample),
                    system: request.system,
                    model: request.model,
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
                print("\n❌ \(error.localizedDescription)")
            }
            semaphore.signal()
        }
        semaphore.wait()
    }
}
