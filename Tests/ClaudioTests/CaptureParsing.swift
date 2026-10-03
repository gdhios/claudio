import Foundation
@testable import Claudio

/// The captures the lookup tests replay are strings; the lookups read the
/// bytes a transport hands them. These read a capture as those bytes.
extension MusicBrainzLookup {
    static func parseSearch(_ json: String, playerAlbum: String?) -> TrackFacts? {
        parseSearch(Data(json.utf8), playerAlbum: playerAlbum)
    }

    static func parseReleaseGroup(_ json: String, into facts: TrackFacts) -> TrackFacts {
        parseReleaseGroup(Data(json.utf8), into: facts)
    }

    static func parseArtistSearch(_ json: String) -> ArtistFacts? {
        parseArtistSearch(Data(json.utf8))
    }

    static func parseArtist(_ json: String) -> ArtistFacts? {
        parseArtist(Data(json.utf8))
    }

    static func parseReleaseGroups(_ json: String, into facts: ArtistFacts) -> ArtistFacts {
        parseReleaseGroups(Data(json.utf8), into: facts)
    }
}

extension DeezerLookup {
    static func parseAlbumSearch(_ json: String, artist: String) -> Int? {
        parseAlbumSearch(Data(json.utf8), artist: artist)
    }

    static func parseAlbum(_ json: String) -> TrackFacts? {
        parseAlbum(Data(json.utf8))
    }
}
