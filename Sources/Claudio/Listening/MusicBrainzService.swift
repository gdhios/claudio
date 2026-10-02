import AppKit

/// Asks MusicBrainz about a track under its rules and the panel's budget:
/// the cache first, then the recording search, then the release group,
/// each on its own cadence, and nothing past six seconds. Time is
/// injected: a test moves the clock by sleeping.
actor MusicBrainzService {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// The search index is throttled harder than the rest of the service:
    /// four seconds held in Galette's measurements of 2026-09-07, 1.1 s
    /// drew 503s.
    static let searchSpacing: TimeInterval = 4
    /// About one request per second per IP, for everything.
    static let requestSpacing: TimeInterval = 1.1
    /// Past this the facts aren't worth waiting for: MusicBrainz is a
    /// bonus under the card, not the card.
    static let budget: TimeInterval = 6
    /// A request with less than this left would be sent to time out.
    static let minimumRemaining: TimeInterval = 1

    private let transport: Transport
    private let version: String
    private let cache: TrackFactsCache
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void
    private var lastSearch: Date?
    private var lastRequest: Date?

    init(transport: @escaping Transport,
         version: String,
         cache: TrackFactsCache,
         now: @escaping @Sendable () -> Date = { Date() },
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.transport = transport
        self.version = version
        self.cache = cache
        self.now = now
        self.sleep = sleep
    }

    static let shared = MusicBrainzService(
        transport: { try await URLSession.shared.data(for: $0) },
        version: MusicBrainzLookup.appVersion,
        cache: .standard)

    /// The facts, `nil` when MusicBrainz has none, failed, or took too
    /// long. A miss is cached, a failure is not: the next listen may find
    /// the service back.
    func facts(for track: NowPlayingTrack) async -> TrackFacts? {
        switch cache.lookup(track, now: now()) {
        case .facts(let facts): return facts
        case .miss: return nil
        case .unknown: break
        }
        let deadline = now().addingTimeInterval(Self.budget)
        guard let searched = await send(MusicBrainzLookup.searchURL(title: track.title, artist: track.artist),
                                        search: true, deadline: deadline) else { return nil }
        guard var facts = MusicBrainzLookup.parseSearch(searched, playerAlbum: track.album) else {
            cache.store(nil, for: track, at: now())
            return nil
        }
        if let groupID = facts.releaseGroupID,
           let group = await send(MusicBrainzLookup.releaseGroupURL(id: groupID), search: false, deadline: deadline) {
            facts = MusicBrainzLookup.parseReleaseGroup(group, into: facts)
        }
        cache.store(facts, for: track, at: now())
        return facts
    }

    /// One request, after its turn in the cadence and within the budget.
    /// `nil` on any failure.
    private func send(_ url: URL, search: Bool, deadline: Date) async -> Data? {
        var wait: TimeInterval = 0
        if let lastRequest {
            wait = max(wait, Self.requestSpacing - now().timeIntervalSince(lastRequest))
        }
        if search, let lastSearch {
            wait = max(wait, Self.searchSpacing - now().timeIntervalSince(lastSearch))
        }
        if wait > 0 {
            guard deadline.timeIntervalSince(now()) - wait >= Self.minimumRemaining else { return nil }
            guard (try? await sleep(.seconds(wait))) != nil else { return nil }
        }
        let remaining = deadline.timeIntervalSince(now())
        guard remaining >= Self.minimumRemaining else { return nil }

        var request = MusicBrainzLookup.request(url, version: version)
        request.timeoutInterval = remaining
        let sentAt = now()
        lastRequest = sentAt
        if search { lastSearch = sentAt }
        guard let (data, response) = try? await transport(request),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true
        else { return nil }
        return data
    }
}

/// Where the coordinator gets its facts: a synchronous look at the cache
/// before Claude is asked, so facts already known go out with the first
/// request, and the fetch beside the cycle for the rest.
@MainActor
struct FactsSource {
    var cached: @MainActor (NowPlayingTrack) -> TrackFacts?
    var fetch: @MainActor (NowPlayingTrack) async -> TrackFacts?

    static let system = FactsSource(
        cached: { track in
            guard !PreviewRun.isActive,
                  case .facts(let facts) = TrackFactsCache.standard.lookup(track, now: Date()) else { return nil }
            return facts
        },
        fetch: { track in
            guard !PreviewRun.isActive else { return nil }
            return await MusicBrainzService.shared.facts(for: track)
        })

    static let none = FactsSource(cached: { _ in nil }, fetch: { _ in nil })
}

/// The cover the Cover Art Archive holds for the release group the facts
/// name: the fallback when the player gave none.
@MainActor
struct RemoteArtworkSource {
    var image: @MainActor (TrackFacts) async -> NSImage?

    static let archiveBaseURL = URL(string: "https://coverartarchive.org/")!

    static func frontURL(releaseGroup id: String) -> URL {
        archiveBaseURL.appendingPathComponent("release-group/\(id)/front-250")
    }

    static let system = RemoteArtworkSource { facts in
        guard !PreviewRun.isActive, let id = facts.releaseGroupID else { return nil }
        return await LocalArtwork.fetch(frontURL(releaseGroup: id),
                                        userAgent: MusicBrainzLookup.userAgent(version: MusicBrainzLookup.appVersion))
    }

    static let none = RemoteArtworkSource { _ in nil }
}
