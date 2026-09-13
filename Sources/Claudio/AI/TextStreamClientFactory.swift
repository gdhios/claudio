import Foundation

/// Turns a model choice into the client that answers for it: Claude through
/// the API, with the key from the Keychain and the workspace from the
/// settings; a local model through Ollama, at the configured address.
///
/// One place, so an action and a dictation reach the same model the same
/// way. `nil` means no client for this choice: the Claude key is missing, or
/// the choice names no model at all.
enum TextStreamClientFactory {
    @MainActor
    static func make(for choice: ModelChoice) -> TextStreamClient? {
        switch choice {
        case .claude(let model):
            guard let apiKey = KeychainStore.currentAPIKey() else { return nil }
            return AnthropicClient(apiKey: apiKey,
                                   workspaceID: AppSettings.currentWorkspaceID(),
                                   model: model)
        case .ollama(let name):
            return OllamaClient(baseURL: AppSettings.ollamaBaseURL, model: name)
        case .raw:
            // "Raw" is the absence of a model: there is nothing to call.
            return nil
        }
    }
}
