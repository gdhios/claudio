import Foundation

/// What "Tell me more" is about: the track playing, its album or its
/// artist, with the facts in hand — the card's and MusicBrainz's, or those
/// a `claudio://music` link from Galette carries (an album or an artist:
/// a link has no track). Facts only, never a text written upstream.
struct MusicSubject: Hashable, Sendable {
    enum Kind: String, Sendable {
        case album, artist, track
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
    /// The artist's MusicBrainz id, when the recording search gave it.
    var artistID: String? = nil
    /// The title playing when the subject was built from the card: what
    /// the text is about for a track, what anchors it for the others.
    var track: String? = nil

    /// The artist's id wherever the subject got it: a link that names the
    /// artist carries it as `mbid`; an album's subject as `artistID`.
    var artistMBID: String? {
        kind == .artist ? mbid ?? artistID : artistID
    }

    /// The album of the track playing: the one of origin when MusicBrainz
    /// said, the player's otherwise. `nil` without an album or an artist.
    static func album(of track: NowPlayingTrack, facts: TrackFacts?) -> MusicSubject? {
        guard let artist = track.artist, let title = facts?.albumTitle ?? track.album else { return nil }
        return MusicSubject(kind: .album, artist: artist, title: title,
                            mbid: facts?.releaseGroupID,
                            firstReleaseDate: facts?.firstReleaseDate,
                            type: facts?.primaryType,
                            artistID: facts?.artistID,
                            track: track.title)
    }

    static func artist(of track: NowPlayingTrack, facts: TrackFacts? = nil) -> MusicSubject? {
        guard let artist = track.artist else { return nil }
        return MusicSubject(kind: .artist, artist: artist, artistID: facts?.artistID, track: track.title)
    }

    /// The track itself: Claude knows a title where an album means little
    /// (Guillaume, 2026-10-03). The album and its facts come as context.
    static func track(of track: NowPlayingTrack, facts: TrackFacts?) -> MusicSubject? {
        guard let artist = track.artist else { return nil }
        return MusicSubject(kind: .track, artist: artist, title: facts?.albumTitle ?? track.album,
                            mbid: facts?.releaseGroupID,
                            firstReleaseDate: facts?.firstReleaseDate,
                            type: facts?.primaryType,
                            artistID: facts?.artistID,
                            track: track.title)
    }

    /// The card a link opens on: the album over its artist, or the artist
    /// alone, from Galette.
    var card: NowPlayingTrack {
        switch kind {
        case .album: NowPlayingTrack(title: title ?? artist, artist: artist, appName: "Galette")
        case .artist: NowPlayingTrack(title: artist, appName: "Galette")
        case .track: NowPlayingTrack(title: track ?? artist, artist: artist, album: title, appName: "Galette")
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
        case .track: loc("Sur le morceau", en: "About the track")
        }
    }

    /// The row of the "Search in Claude" menu.
    var searchTitle: String {
        switch kind {
        case .album: loc("L'album", en: "The album")
        case .artist: loc("L'artiste", en: "The artist")
        case .track: loc("Le morceau", en: "The track")
        }
    }

    /// Claude's block, in French like every prompt: the facts in hand, and
    /// only them. The track playing opens it: the text's subject for a
    /// track, its anchor for an album or an artist.
    var promptBlock: String {
        let fields: [(label: String, value: String?)] = [
            ("morceau", track),
            ("artiste", artist),
            ("album", title),
            ("première sortie", firstReleaseDate),
            ("type", type.map { TrackFacts.typeName($0, english: false) }),
            ("label", label),
            ("pays", country),
            ("mbid", mbid),
        ]
        let lines = fields.compactMap { field in field.value.map { "\(field.label) : \($0)" } }
        let genre = switch kind {
        case .album: "album"
        case .artist: "artiste"
        case .track: "morceau"
        }
        return (["<sujet genre=\"\(genre)\">"] + lines + ["</sujet>"]).joined(separator: "\n")
    }
}
