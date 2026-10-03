import XCTest
@testable import Claudio

/// The picker's list of Claude models: what the app ships, merged with what
/// the API lists, read once a day and kept on disk. Nothing here touches the
/// network: the fetch is a closure handed to the catalog.
@MainActor
final class ModelCatalogTests: XCTestCase {

    private let noon = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func freshDefaults() -> UserDefaults {
        InMemoryDefaults()
    }

    /// A trimmed `GET /v1/models` answer, as the API shapes it.
    static let apiAnswer = """
        {"data":[
          {"type":"model","id":"claude-sonnet-6","display_name":"Claude Sonnet 6","created_at":"2026-11-02T00:00:00Z"},
          {"type":"model","id":"claude-opus-5-5","display_name":"Claude Opus 5.5","created_at":"2026-08-20T00:00:00Z"},
          {"type":"model","id":"claude-opus-4-1-20250805","display_name":"Claude Opus 4.1","created_at":"2025-08-05T00:00:00Z"},
          {"type":"model","id":"claude-opus-4-1","display_name":"Claude Opus 4.1","created_at":"2025-08-05T00:00:00Z"},
          {"type":"model","id":"claude-haiku-4-5","display_name":"Claude Haiku 4.5","created_at":"2025-10-15T00:00:00Z"},
          {"type":"model","id":"not-a-claude-model","display_name":"Other","created_at":"2025-01-01T00:00:00Z"}
        ],"first_id":"claude-sonnet-6","has_more":false,"last_id":"not-a-claude-model"}
        """.data(using: .utf8)!

    // MARK: - Reading the API

    func testTheAPIsAnswerReads() throws {
        let fetched = try ModelCatalog.parse(Self.apiAnswer)
        XCTAssertEqual(fetched.map(\.id),
                       ["claude-sonnet-6", "claude-opus-5-5", "claude-opus-4-1-20250805",
                        "claude-opus-4-1", "claude-haiku-4-5", "not-a-claude-model"])
        XCTAssertEqual(fetched.first?.displayName, "Claude Sonnet 6")
    }

    func testAnAnswerThatIsntTheAPIsThrows() {
        XCTAssertThrowsError(try ModelCatalog.parse(Data("<html>".utf8)))
        XCTAssertThrowsError(try ModelCatalog.parse(Data(#"{"error":"x"}"#.utf8)))
    }

    // MARK: - Merging

    /// What the API adds joins the bundled list; what it lists twice (a dated
    /// snapshot next to its alias) and what isn't Claude stay out; the whole
    /// is grouped by family, newest first.
    func testTheMergeKeepsClaudeAliasesGroupedByFamilyNewestFirst() throws {
        let fetched = try ModelCatalog.parse(Self.apiAnswer)
        let merged = ModelCatalog.merge(bundled: ClaudioModel.bundled, fetched: fetched)
        XCTAssertEqual(merged.map(\.id),
                       ["claude-haiku-4-5",
                        "claude-sonnet-6", "claude-sonnet-5-5", "claude-sonnet-5",
                        "claude-opus-5-5", "claude-opus-5", "claude-opus-4-1"])
        // The API's name travels with the model it named.
        XCTAssertEqual(merged.first { $0.id == "claude-sonnet-6" }?.shortName, "Sonnet 6")
    }

    /// A dated snapshot with no alias in the list is a model like another.
    func testADatedSnapshotWithoutAnAliasStays() {
        let fetched = [ModelCatalog.FetchedModel(id: "claude-opus-4-1-20250805",
                                                 displayName: "Claude Opus 4.1")]
        let merged = ModelCatalog.merge(bundled: [], fetched: fetched)
        XCTAssertEqual(merged.map(\.id), ["claude-opus-4-1-20250805"])
    }

    // MARK: - Freshness

    func testTheListIsReadOnceADay() {
        let catalog = ModelCatalog(bundled: ClaudioModel.bundled, defaults: freshDefaults(),
                                   fetch: { nil }, now: { self.noon })
        XCTAssertTrue(catalog.needsRefresh(at: noon), "never fetched")
        XCTAssertFalse(catalog.needsRefresh(at: noon, lastFetch: noon.addingTimeInterval(-3600)))
        XCTAssertTrue(catalog.needsRefresh(at: noon, lastFetch: noon.addingTimeInterval(-25 * 3600)))
    }

    // MARK: - The whole cycle

    /// Without a key there is nothing to ask: the bundled list is the list,
    /// and nothing is marked new.
    func testWithoutAFetchTheBundledListIsTheList() async {
        let catalog = ModelCatalog(bundled: ClaudioModel.bundled, defaults: freshDefaults(),
                                   fetch: { nil }, now: { self.noon })
        await catalog.refreshIfStale()
        XCTAssertEqual(catalog.models, ClaudioModel.bundled)
        XCTAssertFalse(catalog.isNew(.sonnet55))
    }

    /// A fetched list is merged in, marked where it adds something, and kept
    /// on disk: the next catalog starts from it without asking again.
    func testAFetchedListIsMergedMarkedAndKept() async {
        let defaults = freshDefaults()
        var calls = 0
        let catalog = ModelCatalog(bundled: ClaudioModel.bundled, defaults: defaults,
                                   fetch: { calls += 1; return Self.apiAnswer },
                                   now: { self.noon })
        await catalog.refreshIfStale()
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(catalog.models.contains(ClaudioModel(id: "claude-sonnet-6")))
        XCTAssertTrue(catalog.isNew(ClaudioModel(id: "claude-sonnet-6")))
        XCTAssertFalse(catalog.isNew(.sonnet55), "shipped with the app: not new")

        // Same day, same catalog: no second call.
        await catalog.refreshIfStale()
        XCTAssertEqual(calls, 1)

        // A catalog opened later the same day starts from the stored list.
        let later = ModelCatalog(bundled: ClaudioModel.bundled, defaults: defaults,
                                 fetch: { calls += 1; return Self.apiAnswer },
                                 now: { self.noon.addingTimeInterval(3600) })
        XCTAssertTrue(later.models.contains(ClaudioModel(id: "claude-sonnet-6")))
        await later.refreshIfStale()
        XCTAssertEqual(calls, 1, "still fresh")

        // The day after, it asks again.
        let tomorrow = ModelCatalog(bundled: ClaudioModel.bundled, defaults: defaults,
                                    fetch: { calls += 1; return Self.apiAnswer },
                                    now: { self.noon.addingTimeInterval(25 * 3600) })
        await tomorrow.refreshIfStale()
        XCTAssertEqual(calls, 2)
    }

    /// A failed fetch changes nothing: the list on screen is the last good
    /// one, and the failure is retried next time rather than remembered.
    func testAFailedFetchKeepsTheLastList() async {
        struct Down: Error {}
        let catalog = ModelCatalog(bundled: ClaudioModel.bundled, defaults: freshDefaults(),
                                   fetch: { throw Down() }, now: { self.noon })
        await catalog.refreshIfStale()
        XCTAssertEqual(catalog.models, ClaudioModel.bundled)
        XCTAssertTrue(catalog.needsRefresh(at: noon), "a failure isn't a fetch")
    }

    /// A stored list that no longer reads (another version wrote it) is
    /// ignored, not fatal.
    func testAnUnreadableStoredListIsIgnored() {
        let defaults = freshDefaults()
        defaults.set(Data("junk".utf8), forKey: ModelCatalog.storedListKey)
        let catalog = ModelCatalog(bundled: ClaudioModel.bundled, defaults: defaults,
                                   fetch: { nil }, now: { self.noon })
        XCTAssertEqual(catalog.models, ClaudioModel.bundled)
    }

    // MARK: - The request

    /// Same headers as every call to the API, no body, one page of everything.
    func testTheRequestIsTheModelsEndpointWithTheUsualHeaders() {
        let request = AnthropicModelsRequest.make(apiKey: "sk-test", workspaceID: "wrkspc_1")
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/models?limit=1000")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), Constants.anthropicVersion)
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-workspace-id"), "wrkspc_1")
        XCTAssertNil(request.httpBody)
        XCTAssertNil(AnthropicModelsRequest.make(apiKey: "k", workspaceID: nil)
            .value(forHTTPHeaderField: "anthropic-workspace-id"))
    }
}
