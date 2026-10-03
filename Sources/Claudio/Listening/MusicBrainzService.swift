import AppKit

/// Asks MusicBrainz about a track under its rules and the panel's budget:
/// the cache first, then the recording search, then the release group,
/// each on its own cadence, and nothing past six seconds. Before the long
/// text, the artist and their discography the same way, on a wider budget
/// since the text waits for them. Time is injected: a test moves the
/// clock by sleeping.
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
    /// The long text waits for the artist: the wait is the price of a
    /// text that doesn't invent, within reason.
    static let artistBudget: TimeInterval = 10

    private let transport: Transport
    private let version: String
    private let cache: TrackFactsCache
    private let artists: ArtistFactsCache
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void
    private var lastSearch: Date?
    private var lastRequest: Date?

    init(transport: @escaping Transport,
         version: String,
         cache: TrackFactsCache,
         artists: ArtistFactsCache,
         now: @escaping @Sendable () -> Date = { Date() },
         sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.transport = transport
        self.version = version
        self.cache = cache
        self.artists = artists
        self.now = now
        self.sleep = sleep
    }

    static let shared = MusicBrainzService(
        transport: { try await URLSession.shared.data(for: $0) },
        version: MusicBrainzLookup.appVersion,
        cache: .standard,
        artists: .standard)

    /// The facts, `nil` when neither base has them, or they failed or took
    /// too long. MusicBrainz first; Deezer when it had nothing and the
    /// player named the album — a record three days old isn't in a
    /// community base yet. A miss is cached once both have answered, a
    /// failure never — nor a half answer, the second question of either
    /// base failed: the next listen may find the service back.
    func facts(for track: NowPlayingTrack) async -> TrackFacts? {
        switch cache.lookup(track, now: now()) {
        case .facts(let facts): return facts
        case .miss: return nil
        case .unknown: break
        }
        let deadline = now().addingTimeInterval(Self.budget)
        guard let searched = await send(MusicBrainzLookup.searchURL(title: track.title, artist: track.artist),
                                        search: true, deadline: deadline) else { return nil }
        if var facts = MusicBrainzLookup.parseSearch(searched, playerAlbum: track.album) {
            if let groupID = facts.releaseGroupID {
                // The search's guess is shown, never kept in place of
                // the release group's own record.
                guard let group = await send(MusicBrainzLookup.releaseGroupURL(id: groupID),
                                             search: false, deadline: deadline) else { return facts }
                facts = MusicBrainzLookup.parseReleaseGroup(group, into: facts)
            }
            cache.store(facts, for: track, at: now())
            return facts
        }
        guard let album = track.album, let artist = track.artist else {
            cache.store(nil, for: track, at: now())
            return nil
        }
        guard let found = await send(DeezerLookup.albumSearchURL(artist: artist, album: album),
                                     search: false, deadline: deadline) else { return nil }
        guard let id = DeezerLookup.parseAlbumSearch(found, artist: artist) else {
            cache.store(nil, for: track, at: now())
            return nil
        }
        guard let record = await send(DeezerLookup.albumURL(id: id), search: false, deadline: deadline)
        else { return nil }
        let facts = DeezerLookup.parseAlbum(record)
        cache.store(facts, for: track, at: now())
        return facts
    }

    /// The subject's artist and their albums, `nil` when MusicBrainz
    /// doesn't know them, failed, or took too long. By id when the subject
    /// has one — the record, no search — by name otherwise. Past the
    /// budget, the artist without their releases is still handed over.
    func artist(for subject: MusicSubject) async -> ArtistFacts? {
        switch artists.lookup(artistNamed: subject.artist, now: now()) {
        case .facts(let facts): return facts
        case .miss: return nil
        case .unknown: break
        }
        let deadline = now().addingTimeInterval(Self.artistBudget)
        let found: ArtistFacts?
        if let id = subject.artistMBID {
            guard let data = await send(MusicBrainzLookup.artistURL(id: id), search: false, deadline: deadline)
            else { return nil }
            found = MusicBrainzLookup.parseArtist(data)
        } else {
            guard let data = await send(MusicBrainzLookup.artistSearchURL(name: subject.artist),
                                        search: true, deadline: deadline) else { return nil }
            found = MusicBrainzLookup.parseArtistSearch(data)
        }
        guard var facts = found else {
            artists.store(nil, forArtist: subject.artist, at: now())
            return nil
        }
        if let groups = await send(MusicBrainzLookup.releaseGroupsURL(artist: facts.artistID),
                                   search: false, deadline: deadline) {
            facts = MusicBrainzLookup.parseReleaseGroups(groups, into: facts)
            artists.store(facts, forArtist: subject.artist, at: now())
        }
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
    /// The subject's artist, before the long text.
    var artist: @MainActor (MusicSubject) async -> ArtistFacts? = { _ in nil }

    static let system = FactsSource(
        cached: { track in
            guard !PreviewRun.isActive,
                  case .facts(let facts) = TrackFactsCache.standard.lookup(track, now: Date()) else { return nil }
            return facts
        },
        fetch: { track in
            guard !PreviewRun.isActive else { return nil }
            return await MusicBrainzService.shared.facts(for: track)
        },
        artist: { subject in
            guard !PreviewRun.isActive else { return nil }
            return await MusicBrainzService.shared.artist(for: subject)
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
