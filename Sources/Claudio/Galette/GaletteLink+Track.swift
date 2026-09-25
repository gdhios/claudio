import Foundation

extension GaletteLink {
    /// The Galette buttons a track gets, in order: « Artiste » whenever the
    /// artist is known, « Album » after it when the album is too. Names go as
    /// the player gives them, never split: « Earth, Wind & Fire » is one artist.
    ///
    /// A browser's track without an album is the exception. Its "artist" is
    /// the channel that posted the video, not a musician: the musician, when
    /// there is one, is the left part of an « Artiste – Titre » title, and
    /// gets the only button. With an album the site set real metadata —
    /// Spotify's web player, YouTube Music, Bandcamp — and the track reads
    /// like an app's.
    static func links(for track: NowPlayingTrack, playerIsBrowser: Bool) -> [GaletteLink] {
        if playerIsBrowser, track.album == nil {
            return artistName(inTitle: track.title).map { [.artist(name: $0)] } ?? []
        }
        guard let artist = track.artist else { return [] }
        guard let album = track.album else { return [.artist(name: artist)] }
        return [.artist(name: artist), .album(artist: artist, title: album)]
    }

    /// The artist of an « Artiste – Titre » title: what comes before its
    /// first separator — an en dash, an em dash, or a hyphen with a space on
    /// each side, since a hyphen alone sits inside a name (Jay-Z, lo-fi).
    /// `nil` without one, or with nothing on one side of it.
    static func artistName(inTitle title: String) -> String? {
        let characters = Array(title)
        guard let cut = characters.indices.first(where: { isSeparator(at: $0, in: characters) })
        else { return nil }
        let artist = String(characters[..<cut]).trimmingCharacters(in: .whitespacesAndNewlines)
        let rest = String(characters[(cut + 1)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return artist.isEmpty || rest.isEmpty ? nil : artist
    }

    private static func isSeparator(at index: Int, in characters: [Character]) -> Bool {
        switch characters[index] {
        case "–", "—":
            return true
        case "-":
            return index > characters.startIndex && index < characters.endIndex - 1
                && characters[index - 1].isWhitespace && characters[index + 1].isWhitespace
        default:
            return false
        }
    }
}
