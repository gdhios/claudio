import Foundation

/// Deezer, behind MusicBrainz: a community base lags on new releases,
/// Deezer's public API has them the day they come out, without a key.
/// Asked only when MusicBrainz had nothing and the player named the
/// album: the album by artist and title, then its record. Its terms want
/// a non-commercial use, which Claudio is. Pure functions over URLs and
/// JSON; the cadence and the budget are the service's.
enum DeezerLookup {
    static let baseURL = URL(string: "https://api.deezer.com/")!
    static let searchLimit = 5

    /// Deezer's own query syntax: quoted fields, no boolean words.
    static func albumSearchURL(artist: String, album: String) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent("search/album"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: "artist:\(quoted(artist)) album:\(quoted(TrackTitle.plain(album)))"),
            URLQueryItem(name: "limit", value: String(searchLimit)),
        ]
        return components.url!
    }

    static func albumURL(id: Int) -> URL {
        baseURL.appendingPathComponent("album/\(id)")
    }

    /// Quotes inside a quoted field break the query: they go.
    private static func quoted(_ text: String) -> String {
        "\"\(text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\"", with: ""))\""
    }

    /// The first album credited to the artist asked for — a namesake's
    /// isn't this one — in the order Deezer ranks them.
    static func parseAlbumSearch(_ json: String, artist: String) -> Int? {
        parseAlbumSearch(Data(json.utf8), artist: artist)
    }

    static func parseAlbumSearch(_ data: Data, artist: String) -> Int? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let albums = root["data"] as? [[String: Any]] else { return nil }
        let match = albums.first { album in
            let credited = (album["artist"] as? [String: Any])?["name"] as? String ?? ""
            return credited.compare(artist, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) == .orderedSame
        }
        return match?["id"] as? Int
    }

    /// The album's record as the card's facts, in MusicBrainz's words so
    /// the card speaks one language, and marked as Deezer's.
    static func parseAlbum(_ json: String) -> TrackFacts? {
        parseAlbum(Data(json.utf8))
    }

    static func parseAlbum(_ data: Data) -> TrackFacts? {
        guard let album = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              album["id"] is Int, let title = album["title"] as? String else { return nil }
        let (primary, secondary) = types(of: album["record_type"] as? String)
        let date = album["release_date"] as? String
        return TrackFacts(recordingID: "", releaseGroupID: nil, albumTitle: title,
                          primaryType: primary, secondaryTypes: secondary,
                          firstReleaseDate: (date?.isEmpty ?? true) ? nil : date,
                          origin: .deezer)
    }

    private static func types(of record: String?) -> (String?, [String]) {
        switch record?.lowercased() {
        case "album": ("Album", [])
        case "single": ("Single", [])
        case "ep": ("EP", [])
        case "compile": ("Album", ["Compilation"])
        default: (nil, [])
        }
    }
}
