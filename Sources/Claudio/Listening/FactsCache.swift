import Foundation

/// MusicBrainz is asked once per thing: what it said is kept on disk under
/// the thing's normalized name. A result holds three months; a miss a
/// week, the record may be added meanwhile. One small JSON file per kind
/// of thing, read and written whole: a few hundred entries at most.
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
    }

    private static var remasterTail: NSRegularExpression {
        try! NSRegularExpression(pattern: #"\s*[-(\[]\s*remaster(ed)?\b[^)\]]*[)\]]?\s*$"#,
                                 options: [.caseInsensitive])
    }

    /// Case, accents, width, spacing and the "(Remastered)" tails players
    /// add don't make another thing.
    static func normalize(_ text: String) -> String {
        var folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                                  locale: nil)
        folded = remasterTail.stringByReplacingMatches(in: folded, range: NSRange(folded.startIndex..., in: folded),
                                                       withTemplate: "")
        return folded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    func lookup(key: String, now: Date) -> Lookup {
        guard let entry = load()[key] else { return .unknown }
        let age = now.timeIntervalSince(entry.fetchedAt)
        if let facts = entry.facts {
            return age < Self.resultLifetime ? .facts(facts) : .unknown
        }
        return age < Self.missLifetime ? .miss : .unknown
    }

    /// `nil` facts record a miss.
    func store(_ facts: Value?, key: String, at now: Date) {
        var entries = load()
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

    func lookup(artistNamed name: String, now: Date) -> Lookup {
        lookup(key: Self.normalize(name), now: now)
    }

    func store(_ facts: ArtistFacts?, forArtist name: String, at now: Date) {
        store(facts, key: Self.normalize(name), at: now)
    }
}
