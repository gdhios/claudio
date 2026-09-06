import Foundation

/// `Claudio --selftest [text] [instruction]`: tests the streaming client from
/// the CLI, without the UI. With an instruction, the free-action path runs
/// instead of the catalog correction.
/// Non-zero exit code if the call fails: that's what lets
/// `Scripts/test.sh --release` use it as a release gate.
enum SelfTest {
    static func runBlocking() {
        let arguments = CommandLine.arguments
        let extras = arguments.firstIndex(of: "--selftest").map { Array(arguments[($0 + 1)...]) } ?? []
        let sample = extras.first
            ?? "Bonjour, je voulait savoir si tu pouvait m'envoyer les document avant demain matin. merci d'avance"
        let request = extras.count > 1
            ? ClaudioRequest.free(instruction: extras[1])
            : ClaudioAction.correct.request

        // The action's engine decides the client, just like in the app. An
        // action set to a local model is tested without an API key.
        let client: TextStreamClient
        switch request.model {
        case .claude(let model):
            guard let apiKey = KeychainStore.currentAPIKey() else {
                print("❌ No API key: export \(Constants.apiKeyEnvVar) or save a key in Settings.")
                exit(1)
            }
            client = AnthropicClient(apiKey: apiKey,
                                     workspaceID: AppSettings.currentWorkspaceID(),
                                     model: model)
        case .ollama(let name):
            client = OllamaClient(baseURL: AppSettings.ollamaBaseURL, model: name)
        }

        print("→ Action: \(request.panelTitle)")
        print("→ Model:  \(request.model.displayName)")
        print("→ Text:   \(sample)")
        print("---")

        // Semaphore + Task.detached: the work stays off the main thread
        // (blocked by wait()), no hop to the MainActor on this path.
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
                      ? "⚠️ Response truncated (max_tokens reached)"
                      : "✅ OK (\(result.text.count) characters)")
                // Makes visible what the cost counter will record.
                let cost = request.model.cost(inputTokens: result.inputTokens,
                                              outputTokens: result.outputTokens)
                print("→ Tokens: \(result.inputTokens) in / \(result.outputTokens) out"
                      + " → \(Money.format(cost))")
            } catch {
                // A CLI that fails must say so through its exit code,
                // not just on screen.
                print("\n❌ \(error.localizedDescription)")
                fflush(stdout)
                exit(1)
            }
            semaphore.signal()
        }
        semaphore.wait()
    }
}
