import Foundation

/// MusicBrainz is asked once per track: what it said is kept on disk under
/// the track's normalized name. A result holds three months; a miss a week,
/// the record may be added meanwhile. One small JSON file, read and written
/// whole: a few hundred tracks at most.
struct TrackFactsCache: Sendable {
    enum Lookup: Equatable, Sendable {
        case facts(TrackFacts)
        /// Asked recently, and MusicBrainz had nothing.
        case miss
        /// Never asked, or too long ago.
        case unknown
    }

    static let resultLifetime: TimeInterval = 90 * 86_400
    static let missLifetime: TimeInterval = 7 * 86_400

    let fileURL: URL

    /// Under the user's caches: lost with them, and nothing is lost.
    static let standard = TrackFactsCache(
        fileURL: (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                  ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("Claudio", isDirectory: true)
            .appendingPathComponent("musicbrainz-facts.json"))

    private struct Entry: Codable {
        var facts: TrackFacts?
        var fetchedAt: Date
    }

    /// Case, accents, width, spacing and the "(Remastered)" tails players
    /// add don't make another track. The artist is part of the key: the
    /// same title by someone else is another track.
    static func key(title: String, artist: String?) -> String {
        "\(normalize(artist ?? ""))|\(normalize(title))"
    }

    private static let remasterTail = try! NSRegularExpression(
        pattern: #"\s*[-(\[]\s*remaster(ed)?\b[^)\]]*[)\]]?\s*$"#, options: [.caseInsensitive])

    private static func normalize(_ text: String) -> String {
        var folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                                  locale: nil)
        folded = remasterTail.stringByReplacingMatches(in: folded, range: NSRange(folded.startIndex..., in: folded),
                                                       withTemplate: "")
        return folded.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    func lookup(_ track: NowPlayingTrack, now: Date) -> Lookup {
        guard let entry = load()[Self.key(title: track.title, artist: track.artist)] else { return .unknown }
        let age = now.timeIntervalSince(entry.fetchedAt)
        if let facts = entry.facts {
            return age < Self.resultLifetime ? .facts(facts) : .unknown
        }
        return age < Self.missLifetime ? .miss : .unknown
    }

    /// `nil` facts record a miss.
    func store(_ facts: TrackFacts?, for track: NowPlayingTrack, at now: Date) {
        var entries = load()
        entries[Self.key(title: track.title, artist: track.artist)] = Entry(facts: facts, fetchedAt: now)
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
