import Foundation

/// The MusicBrainz WS/2 questions "What's playing?" asks, and how their
/// answers are read: a recording search by title and artist, then the
/// release group's own record; and before the long text, the artist — by
/// id or by name — then their release groups. Pure functions over URLs and
/// JSON; the cadence and the budget are `MusicBrainzService`'s.
enum MusicBrainzLookup {
    static let baseURL = URL(string: "https://musicbrainz.org/ws/2/")!
    /// Under this the search index is guessing: another song's facts would
    /// be worse than none.
    static let minimumScore = 90
    static let searchLimit = 5

    /// Who calls, as MusicBrainz requires: the app, its version, where to
    /// reach it. The repository rather than an address: it is public, and
    /// every installed Claudio sends the same.
    static func userAgent(version: String) -> String {
        "Claudio/\(version) ( https://github.com/gdhios/claudio )"
    }

    // MARK: - The questions

    /// A fielded Lucene query: the title without its version tail, and the
    /// artist when the player gave one — a browser's "artist" is a channel
    /// name, better left out than matched.
    static func searchURL(title: String, artist: String?) -> URL {
        var terms = ["recording:\(luceneQuoted(TrackTitle.plain(title)))"]
        if let artist, !artist.trimmingCharacters(in: .whitespaces).isEmpty {
            terms.append("artist:\(luceneQuoted(artist))")
        }
        return url("recording", [
            URLQueryItem(name: "query", value: terms.joined(separator: " AND ")),
            URLQueryItem(name: "limit", value: String(searchLimit)),
        ])
    }

    /// Quoted for Lucene: the backslash and the quote escaped, so the text
    /// is a phrase and never syntax.
    static func luceneQuoted(_ text: String) -> String {
        let escaped = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    static func releaseGroupURL(id: String) -> URL {
        url("release-group/\(id)")
    }

    static func artistSearchURL(name: String) -> URL {
        url("artist", [
            URLQueryItem(name: "query", value: "artist:\(luceneQuoted(name))"),
            URLQueryItem(name: "limit", value: String(searchLimit)),
        ])
    }

    static func artistURL(id: String) -> URL {
        url("artist/\(id)")
    }

    /// The artist's albums and EPs, a hundred at most: a browse, not a
    /// search, so it isn't held to the search index's cadence.
    static func releaseGroupsURL(artist id: String) -> URL {
        url("release-group", [
            URLQueryItem(name: "artist", value: id),
            URLQueryItem(name: "type", value: "album|ep"),
            URLQueryItem(name: "limit", value: "100"),
        ])
    }

    /// A WS/2 address: the path under `baseURL`, its parameters, and the
    /// JSON format asked for last.
    private static func url(_ path: String, _ items: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = items + [URLQueryItem(name: "fmt", value: "json")]
        return components.url!
    }

    static func request(_ url: URL, version: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(userAgent(version: version), forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    // MARK: - The answers

    /// The best recording at `minimumScore` or more is the track. Among the
    /// release groups of its releases, the compilations come first in the
    /// answer: the one bearing the player's album title wins, then a plain
    /// album, then whatever comes first. The recording's own first release
    /// stands in for the release group's until that one is looked up.
    static func parseSearch(_ data: Data, playerAlbum: String?) -> TrackFacts? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let best = Self.best(root["recordings"] as? [[String: Any]]),
              let id = best["id"] as? String
        else { return nil }

        let groups = (best["releases"] as? [[String: Any]] ?? [])
            .compactMap { $0["release-group"] as? [String: Any] }
        let named = playerAlbum.flatMap { album in
            groups.first { ($0["title"] as? String)?.isSameName(as: album) == true }
        }
        let chosen = named
            ?? groups.first { ($0["primary-type"] as? String)?.lowercased() == "album"
                && ($0["secondary-types"] as? [String] ?? []).isEmpty }
            ?? groups.first

        let credited = (best["artist-credit"] as? [[String: Any]])?.first?["artist"] as? [String: Any]
        return TrackFacts(recordingID: id,
                          releaseGroupID: chosen?["id"] as? String,
                          albumTitle: chosen?["title"] as? String,
                          primaryType: chosen?["primary-type"] as? String,
                          secondaryTypes: chosen?["secondary-types"] as? [String] ?? [],
                          firstReleaseDate: (best["first-release-date"] as? String)?.nonEmpty,
                          artistID: credited?["id"] as? String)
    }

    /// The release group's own record replaces what the search guessed. An
    /// answer that doesn't read leaves the facts as they were.
    static func parseReleaseGroup(_ data: Data, into facts: TrackFacts) -> TrackFacts {
        guard let group = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = group["id"] as? String else { return facts }
        var filled = facts
        filled.releaseGroupID = id
        filled.albumTitle = group["title"] as? String ?? facts.albumTitle
        filled.primaryType = group["primary-type"] as? String ?? facts.primaryType
        filled.secondaryTypes = group["secondary-types"] as? [String] ?? facts.secondaryTypes
        filled.firstReleaseDate = (group["first-release-date"] as? String)?.nonEmpty ?? facts.firstReleaseDate
        return filled
    }

    // MARK: - The artist

    /// The best artist at `minimumScore` or more, with what the search
    /// already says of them; their releases come from the browse.
    static func parseArtistSearch(_ data: Data) -> ArtistFacts? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let best = Self.best(root["artists"] as? [[String: Any]])
        else { return nil }
        return artistFacts(from: best)
    }

    /// The artist's own record, when their id is already known.
    static func parseArtist(_ data: Data) -> ArtistFacts? {
        guard let artist = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return artistFacts(from: artist)
    }

    private static func artistFacts(from artist: [String: Any]) -> ArtistFacts? {
        guard let id = artist["id"] as? String, let name = artist["name"] as? String else { return nil }
        let lifeSpan = artist["life-span"] as? [String: Any]
        return ArtistFacts(artistID: id,
                           name: name,
                           type: artist["type"] as? String,
                           country: (artist["country"] as? String)?.nonEmpty,
                           beginDate: (lifeSpan?["begin"] as? String)?.nonEmpty,
                           endDate: (lifeSpan?["end"] as? String)?.nonEmpty,
                           disambiguation: (artist["disambiguation"] as? String)?.nonEmpty)
    }

    /// The browse lists the release groups in no order: they are kept by
    /// first release, the undated last, and the plain ones only — a live
    /// or a remix album isn't the discography. An answer that doesn't
    /// read leaves the facts as they were.
    static func parseReleaseGroups(_ data: Data, into facts: ArtistFacts) -> ArtistFacts {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let groups = root["release-groups"] as? [[String: Any]] else { return facts }
        var filled = facts
        filled.releases = groups.compactMap { group -> ArtistFacts.Release? in
            guard let id = group["id"] as? String, let title = group["title"] as? String else { return nil }
            let secondary = group["secondary-types"] as? [String] ?? []
            guard secondary.isEmpty else { return nil }
            return ArtistFacts.Release(id: id, title: title,
                                       primaryType: group["primary-type"] as? String,
                                       secondaryTypes: secondary,
                                       firstReleaseDate: (group["first-release-date"] as? String)?.nonEmpty)
        }
        .sorted { ($0.firstReleaseDate ?? "9999") < ($1.firstReleaseDate ?? "9999") }
        return filled
    }

    /// The best-scored entry of a search, when it scores `minimumScore` or
    /// more: under that the index is guessing.
    private static func best(_ entries: [[String: Any]]?) -> [String: Any]? {
        func score(_ entry: [String: Any]) -> Int { entry["score"] as? Int ?? 0 }
        guard let best = entries?.max(by: { score($0) < score($1) }), score(best) >= minimumScore else { return nil }
        return best
    }
}
