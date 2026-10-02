import Foundation

/// What "Tell me more" is about: an album or an artist, with the facts in
/// hand — the card's and MusicBrainz's, or those a `claudio://music` link
/// from Galette carries. Facts only, never a text written upstream.
struct MusicSubject: Hashable, Sendable {
    enum Kind: String, Sendable {
        case album, artist
    }

    var kind: Kind
    var artist: String
    /// The album's title; `nil` for an artist.
    var title: String? = nil
    /// MusicBrainz's id of the release group, or of the artist.
    var mbid: String? = nil
    var firstReleaseDate: String? = nil
    /// "Album", "Single"…, as MusicBrainz names it.
    var type: String? = nil
    var label: String? = nil
    var country: String? = nil

    /// The album of the track playing: the one of origin when MusicBrainz
    /// said, the player's otherwise. `nil` without an album or an artist.
    static func album(of track: NowPlayingTrack, facts: TrackFacts?) -> MusicSubject? {
        guard let artist = track.artist, let title = facts?.albumTitle ?? track.album else { return nil }
        return MusicSubject(kind: .album, artist: artist, title: title,
                            mbid: facts?.releaseGroupID,
                            firstReleaseDate: facts?.firstReleaseDate,
                            type: facts?.primaryType)
    }

    static func artist(of track: NowPlayingTrack) -> MusicSubject? {
        guard let artist = track.artist else { return nil }
        return MusicSubject(kind: .artist, artist: artist)
    }

    /// The card a link opens on: the album over its artist, or the artist
    /// alone, from Galette.
    var card: NowPlayingTrack {
        switch kind {
        case .album: NowPlayingTrack(title: title ?? artist, artist: artist, appName: "Galette")
        case .artist: NowPlayingTrack(title: artist, appName: "Galette")
        }
    }

    /// The album's facts as the card shows them: a link that names the
    /// release group gets its year, type and cover like a listening does.
    var facts: TrackFacts? {
        guard kind == .album, mbid != nil || firstReleaseDate != nil else { return nil }
        return TrackFacts(recordingID: "", releaseGroupID: mbid, albumTitle: title,
                          primaryType: type, secondaryTypes: [], firstReleaseDate: firstReleaseDate)
    }

    /// What the pill on the card says.
    var buttonTitle: String {
        switch kind {
        case .album: loc("Sur l'album", en: "About the album")
        case .artist: loc("Sur l'artiste", en: "About the artist")
        }
    }

    /// Claude's block, in French like every prompt: the facts in hand, and
    /// only them.
    var promptBlock: String {
        let fields: [(label: String, value: String?)] = [
            ("artiste", artist),
            ("album", title),
            ("première sortie", firstReleaseDate),
            ("type", type.map { TrackFacts.typeName($0, english: false) }),
            ("label", label),
            ("pays", country),
            ("mbid", mbid),
        ]
        let lines = fields.compactMap { field in field.value.map { "\(field.label) : \($0)" } }
        let genre = kind == .album ? "album" : "artiste"
        return (["<sujet genre=\"\(genre)\">"] + lines + ["</sujet>"]).joined(separator: "\n")
    }
}
