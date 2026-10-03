import Foundation

/// The track macOS's Now Playing widget shows, as its player describes it:
/// raw metadata, never corrected here. A browser gives the video's title and
/// the channel's name as the artist; the card shows them as they are, and it
/// is Claude who works out the song from them.
struct NowPlayingTrack: Sendable, Equatable {
    var title: String
    var artist: String?
    var album: String?
    /// The player's name as macOS displays it: "Spotify", "Safari".
    var appName: String?
    var bundleID: String?
    /// `false` when the player says it's paused. Paused, the track is still
    /// the widget's, and the panel still answers.
    var isPlaying: Bool

    init(title: String,
         artist: String? = nil,
         album: String? = nil,
         appName: String? = nil,
         bundleID: String? = nil,
         isPlaying: Bool = true) {
        self.title = title
        self.artist = artist
        self.album = album
        self.appName = appName
        self.bundleID = bundleID
        self.isPlaying = isPlaying
    }

    /// Reads what `NowPlayingSource.script` printed: one JSON object, whose
    /// fields the player didn't give are simply absent. `nil` means nothing
    /// is playing — no title, or an answer that doesn't read. The duration
    /// it also prints isn't kept: nothing reads it.
    ///
    /// Each field is read on its own: a value of a type some later macOS
    /// gives instead drops that field, not the whole track.
    init?(printed output: String) {
        guard let data = output.trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8),
              let fields = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        func text(_ key: String) -> String? {
            (fields[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        }
        // A player that played something once can stay the Now Playing
        // client with nothing in it: without a title there is no track.
        guard let title = text("title") else { return nil }
        self.init(title: title,
                  artist: text("artist"),
                  album: text("album"),
                  appName: text("app"),
                  bundleID: text("bundle"),
                  // The card only says "paused" when the player does.
                  isPlaying: fields["playing"] as? Bool ?? true)
    }

    /// The same track, whatever the player is doing with it: paused or
    /// playing, a read finds the card it left, cover and facts included.
    /// The app's name goes with its bundle id.
    static func == (lhs: NowPlayingTrack, rhs: NowPlayingTrack) -> Bool {
        lhs.title == rhs.title && lhs.artist == rhs.artist && lhs.album == rhs.album
            && lhs.bundleID == rhs.bundleID
    }

    /// The player's name for the button that brings it forward: only when
    /// macOS gave the app behind the track. A card from a link has none.
    var playerName: String? {
        guard bundleID != nil else { return nil }
        return appName
    }

    /// What ⌘C copies: the track the way one would write it to someone.
    var copyLine: String {
        guard let artist else { return title }
        return "\(title) — \(artist)"
    }
}
