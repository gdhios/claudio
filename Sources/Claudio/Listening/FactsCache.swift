import Foundation

/// MusicBrainz, and Deezer behind it, are asked once per thing: what they
/// said is kept on disk under the key each kind of thing defines (a
/// track's normalized title and artist, an artist's id or normalized name).
/// A result holds three months; a miss a week, the record may be added
/// meanwhile. One small JSON file per kind of thing, read and written
/// whole, what has expired dropped at each write: a few hundred entries
/// at most.
struct FactsCache<Value: Codable & Equatable & Sendable>: Sendable {
    enum Lookup: Equatable, Sendable {
        case facts(Value)
        /// Asked recently, and MusicBrainz had nothing.
        case miss
        /// Never asked, or too long ago.
        case unknown
    }

    static var resultLifetime: TimeInterval { 90 * 86_400 }
    static var missLifetime: TimeInterval { 7 * 86_400 }

    let fileURL: URL

    /// Under the user's caches: lost with them, and nothing is lost.
    static func standard(file: String) -> FactsCache {
        FactsCache(fileURL: (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                             ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("Claudio", isDirectory: true)
            .appendingPathComponent(file))
    }

    private struct Entry: Codable {
        var facts: Value?
        var fetchedAt: Date

        /// Past its lifetime: a result's three months, a miss's week.
        func hasExpired(at now: Date) -> Bool {
            now.timeIntervalSince(fetchedAt) >= (facts == nil ? FactsCache.missLifetime : FactsCache.resultLifetime)
        }
    }

    /// Case, accents, width, spacing and the version tails players add
    /// ("(Remastered)", "- Olympic Mix") don't make another thing.
    static func normalize(_ text: String) -> String {
        TrackTitle.plain(text)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .collapsingWhitespace()
    }

    func lookup(key: String, now: Date) -> Lookup {
        guard let entry = load()[key], !entry.hasExpired(at: now) else { return .unknown }
        return entry.facts.map(Lookup.facts) ?? .miss
    }

    /// `nil` facts record a miss. What has expired goes with the write.
    func store(_ facts: Value?, key: String, at now: Date) {
        var entries = load().filter { !$0.value.hasExpired(at: now) }
        entries[key] = Entry(facts: facts, fetchedAt: now)
        save(entries)
    }

    private func load() -> [String: Entry] {
        guard let data = try? Data(contentsOf: fileURL),
              let entries = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        return entries
    }

    private func save(_ entries: [String: Entry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - Tracks

typealias TrackFactsCache = FactsCache<TrackFacts>

extension FactsCache where Value == TrackFacts {
    static var standard: TrackFactsCache { standard(file: "musicbrainz-facts.json") }

    /// The artist is part of the key: the same title by someone else is
    /// another track.
    static func key(title: String, artist: String?) -> String {
        "\(normalize(artist ?? ""))|\(normalize(title))"
    }

    func lookup(_ track: NowPlayingTrack, now: Date) -> Lookup {
        lookup(key: Self.key(title: track.title, artist: track.artist), now: now)
    }

    func store(_ facts: TrackFacts?, for track: NowPlayingTrack, at now: Date) {
        store(facts, key: Self.key(title: track.title, artist: track.artist), at: now)
    }
}

// MARK: - Artists

typealias ArtistFactsCache = FactsCache<ArtistFacts>

extension FactsCache where Value == ArtistFacts {
    static var standard: ArtistFactsCache { standard(file: "musicbrainz-artists.json") }

    /// The subject's artist by their MusicBrainz id when it has one, by
    /// name otherwise: two artists may share a name, never an id.
    static func key(for subject: MusicSubject) -> String {
        subject.artistMBID ?? normalize(subject.artist)
    }

    func lookup(_ subject: MusicSubject, now: Date) -> Lookup {
        lookup(key: Self.key(for: subject), now: now)
    }

    func store(_ facts: ArtistFacts?, for subject: MusicSubject, at now: Date) {
        store(facts, key: Self.key(for: subject), at: now)
    }
}
