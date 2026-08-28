import Foundation

/// `Plume --selftest [texte]` : teste le client streaming en CLI, sans UI.
enum SelfTest {
    static func runBlocking() {
        let arguments = CommandLine.arguments
        let sample: String
        if let last = arguments.last, last != "--selftest" {
            sample = last
        } else {
            sample = "Bonjour, je voulait savoir si tu pouvait m'envoyer les document avant demain matin. merci d'avance"
        }

        guard let apiKey = KeychainStore.currentAPIKey() else {
            print("❌ Aucune clé API : exporte \(Constants.apiKeyEnvVar) ou enregistre une clé dans les Réglages.")
            exit(1)
        }

        print("→ Modèle : \(Constants.model)")
        print("→ Texte  : \(sample)")
        print("---")

        // Semaphore + Task.detached : le travail reste hors du main thread
        // (bloqué par wait()), aucun saut vers le MainActor dans ce chemin.
        let semaphore = DispatchSemaphore(value: 0)
        let client = AnthropicClient(apiKey: apiKey, workspaceID: AppSettings.currentWorkspaceID())
        Task.detached {
            do {
                let result = try await client.streamCorrection(of: sample) { piece in
                    print(piece, terminator: "")
                }
                print("\n---")
                print(result.truncated
                      ? "⚠️ Réponse tronquée (max_tokens atteint)"
                      : "✅ OK (\(result.text.count) caractères)")
            } catch {
                print("\n❌ \(error.localizedDescription)")
            }
            semaphore.signal()
        }
        semaphore.wait()
    }
}
