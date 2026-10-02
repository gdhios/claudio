import Foundation

/// `GET /v1/models`: the list of models the key can use, one page of
/// everything. Same headers as the messages call, no body. The answer is
/// handed back raw: `ModelCatalog` reads it, and is tested on recorded ones.
enum AnthropicModelsRequest {
    static let url = URL(string: "https://api.anthropic.com/v1/models?limit=1000")!

    static func make(apiKey: String, workspaceID: String?) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(Constants.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        if let workspaceID, !workspaceID.isEmpty {
            request.setValue(workspaceID, forHTTPHeaderField: "anthropic-workspace-id")
        }
        return request
    }

    static func fetch(apiKey: String, workspaceID: String?) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: make(apiKey: apiKey,
                                                                          workspaceID: workspaceID))
        guard let http = response as? HTTPURLResponse else { throw AnthropicError.badResponse }
        guard http.statusCode == 200 else {
            throw AnthropicError.http(status: http.statusCode,
                                      message: AnthropicClient.apiErrorMessage(from: data))
        }
        return data
    }
}
