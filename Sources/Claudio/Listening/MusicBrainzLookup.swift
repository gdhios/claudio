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

    /// The version the bundle carries, "dev" from `swift run`.
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
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
        var components = URLComponents(url: baseURL.appendingPathComponent("recording"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "query", value: terms.joined(separator: " AND ")),
            URLQueryItem(name: "limit", value: String(searchLimit)),
            URLQueryItem(name: "fmt", value: "json"),
        ]
        return components.url!
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
        var components = URLComponents(url: baseURL.appendingPathComponent("release-group/\(id)"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "fmt", value: "json")]
        return components.url!
    }

    static func artistSearchURL(name: String) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent("artist"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "query", value: "artist:\(luceneQuoted(name))"),
            URLQueryItem(name: "limit", value: String(searchLimit)),
            URLQueryItem(name: "fmt", value: "json"),
        ]
        return components.url!
    }

    static func artistURL(id: String) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent("artist/\(id)"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "fmt", value: "json")]
        return components.url!
    }

    /// The artist's albums and EPs, a hundred at most: a browse, not a
    /// search, so it isn't held to the search index's cadence.
    static func releaseGroupsURL(artist id: String) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent("release-group"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "artist", value: id),
            URLQueryItem(name: "type", value: "album|ep"),
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "fmt", value: "json"),
        ]
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
    static func parseSearch(_ json: String, playerAlbum: String?) -> TrackFacts? {
        parseSearch(Data(json.utf8), playerAlbum: playerAlbum)
    }

    static func parseSearch(_ data: Data, playerAlbum: String?) -> TrackFacts? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let recordings = root["recordings"] as? [[String: Any]],
              let best = recordings.max(by: { ($0["score"] as? Int ?? 0) < ($1["score"] as? Int ?? 0) }),
              (best["score"] as? Int ?? 0) >= minimumScore,
              let id = best["id"] as? String
        else { return nil }

        let groups = (best["releases"] as? [[String: Any]] ?? [])
            .compactMap { $0["release-group"] as? [String: Any] }
        let chosen = groups.first { sameTitle($0["title"] as? String, playerAlbum) }
            ?? groups.first { ($0["primary-type"] as? String)?.lowercased() == "album"
                && ($0["secondary-types"] as? [String] ?? []).isEmpty }
            ?? groups.first

        let credited = (best["artist-credit"] as? [[String: Any]])?.first?["artist"] as? [String: Any]
        return TrackFacts(recordingID: id,
                          releaseGroupID: chosen?["id"] as? String,
                          albumTitle: chosen?["title"] as? String,
                          primaryType: chosen?["primary-type"] as? String,
                          secondaryTypes: chosen?["secondary-types"] as? [String] ?? [],
                          firstReleaseDate: nonEmpty(best["first-release-date"] as? String),
                          artistID: credited?["id"] as? String)
    }

    /// The release group's own record replaces what the search guessed. An
    /// answer that doesn't read leaves the facts as they were.
    static func parseReleaseGroup(_ json: String, into facts: TrackFacts) -> TrackFacts {
        parseReleaseGroup(Data(json.utf8), into: facts)
    }

    static func parseReleaseGroup(_ data: Data, into facts: TrackFacts) -> TrackFacts {
        guard let group = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = group["id"] as? String else { return facts }
        var filled = facts
        filled.releaseGroupID = id
        filled.albumTitle = group["title"] as? String ?? facts.albumTitle
        filled.primaryType = group["primary-type"] as? String ?? facts.primaryType
        filled.secondaryTypes = group["secondary-types"] as? [String] ?? facts.secondaryTypes
        filled.firstReleaseDate = nonEmpty(group["first-release-date"] as? String) ?? facts.firstReleaseDate
        return filled
    }

    // MARK: - The artist

    /// The best artist at `minimumScore` or more, with what the search
    /// already says of them; their releases come from the browse.
    static func parseArtistSearch(_ json: String) -> ArtistFacts? {
        parseArtistSearch(Data(json.utf8))
    }

    static func parseArtistSearch(_ data: Data) -> ArtistFacts? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let artists = root["artists"] as? [[String: Any]],
              let best = artists.max(by: { ($0["score"] as? Int ?? 0) < ($1["score"] as? Int ?? 0) }),
              (best["score"] as? Int ?? 0) >= minimumScore
        else { return nil }
        return artistFacts(from: best)
    }

    /// The artist's own record, when their id is already known.
    static func parseArtist(_ json: String) -> ArtistFacts? {
        parseArtist(Data(json.utf8))
    }

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
                           country: nonEmpty(artist["country"] as? String),
                           beginDate: nonEmpty(lifeSpan?["begin"] as? String),
                           endDate: nonEmpty(lifeSpan?["end"] as? String),
                           disambiguation: nonEmpty(artist["disambiguation"] as? String))
    }

    /// The browse lists the release groups in no order: they are kept by
    /// first release, the undated last, and the plain ones only — a live
    /// or a remix album isn't the discography. An answer that doesn't
    /// read leaves the facts as they were.
    static func parseReleaseGroups(_ json: String, into facts: ArtistFacts) -> ArtistFacts {
        parseReleaseGroups(Data(json.utf8), into: facts)
    }

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
                                       firstReleaseDate: nonEmpty(group["first-release-date"] as? String))
        }
        .sorted { ($0.firstReleaseDate ?? "9999") < ($1.firstReleaseDate ?? "9999") }
        return filled
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    private static func sameTitle(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b else { return false }
        return a.compare(b, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) == .orderedSame
    }
}
