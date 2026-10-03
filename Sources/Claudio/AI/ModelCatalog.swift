import Foundation

/// The Claude models the pickers offer: the list the app ships, merged with
/// the list the API serves. The API is asked at most once a day, when
/// Settings open, and its answer is kept in the defaults so the next launch
/// starts from it. Without a key, without network, or when the API fails,
/// the last good list stays — at worst the bundled one.
///
/// The fetch is injected: a test hands a recorded answer, a failure, or
/// nothing, and never reaches the network.
@MainActor
final class ModelCatalog: ObservableObject {
    /// The raw answer of `GET /v1/models`, `nil` when there is nothing to
    /// ask (no key) — then nothing is recorded either.
    typealias Fetch = @MainActor () async throws -> Data?

    static let shared = ModelCatalog(fetch: systemFetch)

    /// The real fetch: the key from the Keychain, nothing without one, and
    /// nothing in a preview, which must render the same on every machine.
    static func systemFetch() async throws -> Data? {
        guard !PreviewRun.isActive, let apiKey = KeychainStore.currentAPIKey() else { return nil }
        return try await AnthropicModelsRequest.fetch(apiKey: apiKey,
                                                      workspaceID: AppSettings.currentWorkspaceID())
    }

    /// The list, grouped by family and newest first.
    @Published private(set) var models: [ClaudioModel]

    static let refreshInterval: TimeInterval = 24 * 3600
    static let storedListKey = "modelCatalog.fetched"
    static let fetchedAtKey = "modelCatalog.fetchedAt"

    private let bundled: [ClaudioModel]
    private let defaults: UserDefaults
    private let fetch: Fetch
    private let now: () -> Date

    init(bundled: [ClaudioModel] = ClaudioModel.bundled,
         defaults: UserDefaults = .standard,
         fetch: @escaping Fetch,
         now: @escaping () -> Date = Date.init) {
        self.bundled = bundled
        self.defaults = defaults
        self.fetch = fetch
        self.now = now
        let stored = defaults.data(forKey: Self.storedListKey)
            .flatMap { try? JSONDecoder().decode([FetchedModel].self, from: $0) } ?? []
        models = Self.merge(bundled: bundled, fetched: stored)
    }

    /// A model the app didn't ship: it came from the API's list.
    func isNew(_ model: ClaudioModel) -> Bool {
        !bundled.contains(model) && models.contains(model)
    }

    // MARK: - Refresh

    /// The last successful fetch, `nil` when there was none.
    private var lastFetch: Date? {
        let stored = defaults.double(forKey: Self.fetchedAtKey)
        return stored > 0 ? Date(timeIntervalSinceReferenceDate: stored) : nil
    }

    func needsRefresh(at date: Date) -> Bool {
        needsRefresh(at: date, lastFetch: lastFetch)
    }

    /// Pure: a day since the last fetch, or never fetched.
    func needsRefresh(at date: Date, lastFetch: Date?) -> Bool {
        guard let lastFetch else { return true }
        return date.timeIntervalSince(lastFetch) >= Self.refreshInterval
    }

    /// Asks the API when the list is a day old. A failure or an unreadable
    /// answer changes nothing and records nothing: the next call asks again.
    func refreshIfStale() async {
        let date = now()
        guard needsRefresh(at: date) else { return }
        guard let data = try? await fetch(),
              let fetched = try? Self.parse(data) else { return }
        models = Self.merge(bundled: bundled, fetched: fetched)
        defaults.set(try? JSONEncoder().encode(fetched), forKey: Self.storedListKey)
        defaults.set(date.timeIntervalSinceReferenceDate, forKey: Self.fetchedAtKey)
    }

    // MARK: - The API's answer

    /// One model as the API lists it; what is kept on disk.
    struct FetchedModel: Codable, Equatable, Sendable {
        let id: String
        let displayName: String?
    }

    /// Reads a `GET /v1/models` answer: `data[]` with `id` and
    /// `display_name`. Throws when the answer isn't one. The dates are
    /// ignored: the order comes from the ids (`merge`).
    static func parse(_ data: Data) throws -> [FetchedModel] {
        struct Answer: Decodable { let data: [FetchedModel] }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Answer.self, from: data).data
    }

    // MARK: - Merging

    /// The bundled models plus what the API adds: Claude identifiers only,
    /// a dated snapshot dropped when its alias is in the list, the API's
    /// name kept on the model it named. Grouped by family, newest version
    /// first within each.
    static func merge(bundled: [ClaudioModel], fetched: [FetchedModel]) -> [ClaudioModel] {
        var byID: [String: ClaudioModel] = [:]
        var order: [String] = []
        for model in bundled where byID[model.id] == nil {
            byID[model.id] = model
            order.append(model.id)
        }
        for entry in fetched where ClaudioModel.isClaudeID(entry.id) {
            let model = ClaudioModel(id: entry.id, displayName: entry.displayName)
            if byID[model.id] == nil { order.append(model.id) }
            // The API's name wins even over a bundled model: it is the
            // current one.
            byID[model.id] = model
        }
        let ids = Set(order)
        let kept = order.filter { id in
            let model = byID[id]!
            return model.snapshotDate == nil || !ids.contains(model.aliasID)
        }
        return kept.map { byID[$0]! }.sorted { lhs, rhs in
            if lhs.family != rhs.family { return lhs.family < rhs.family }
            if lhs.versionTokens != rhs.versionTokens {
                return lhs.versionTokens.lexicographicallyPrecedes(rhs.versionTokens) == false
            }
            return lhs.id < rhs.id
        }
    }
}

// MARK: - Pickers

extension Array where Element == ClaudioModel {
    /// This list, plus the chosen Claude model when it isn't in it: a model
    /// the API no longer lists, or that another version knew, stays a valid
    /// setting until it is changed — a picker with no row for its value
    /// would show a blank line.
    func offering(_ choice: ModelChoice) -> [ClaudioModel] {
        guard case .claude(let current) = choice, !contains(current) else { return self }
        return [current] + self
    }
}

extension ClaudioModel {
    /// The picker's line, flagged when the model came from the API rather
    /// than with the app.
    func pickerLabel(isNew: Bool) -> String {
        isNew ? "\(displayName) · \(loc("nouveau", en: "new"))" : displayName
    }
}
