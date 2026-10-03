import AppKit

/// Where the card's cover comes from: the player itself, asked beside the
/// card and never waited for. Injected like `NowPlayingSource`: a test hands
/// back an image or nothing, and when; a preview draws its own.
@MainActor
struct ArtworkSource {
    /// The cover of the track, `nil` when the player has none to give, when
    /// it can't be reached, or past the budget.
    var image: @MainActor (NowPlayingTrack) async -> NSImage?

    /// The player's own cover: Spotify's, by the URL its dictionary exposes,
    /// fetched from its CDN. Nothing else is asked of anyone.
    static let system = ArtworkSource { track in
        guard !PreviewRun.isActive,
              let script = LocalArtwork.script(for: track),
              let printed = await JXAScript.run(script, timeout: LocalArtwork.readTimeout),
              let url = LocalArtwork.url(printed: printed) else { return nil }
        return await LocalArtwork.fetch(url)
    }
}

/// The cover as the player knows it. MediaRemote names the cover (an
/// identifier, a MIME type, a size) but doesn't hand over its bytes: only
/// the player can. Spotify's dictionary gives the URL of the track's cover;
/// Apple Music's gives raw picture bytes, which this doesn't read yet.
enum LocalArtwork {
    static let spotifyBundleID = "com.spotify.client"

    /// A read takes a tenth of a second; past this the cover is given up.
    static let readTimeout: TimeInterval = 2
    /// The image comes from the player's CDN, a few tens of kilobytes.
    static let fetchTimeout: TimeInterval = 4

    /// The script that prints the cover's URL, for a player whose dictionary
    /// has one: Spotify. `nil` for any other, and for none named. Spotify
    /// is asked only if it already runs: naming it never launches it.
    static func script(for track: NowPlayingTrack) -> String? {
        guard track.bundleID == spotifyBundleID else { return nil }
        return """
            const spotify = Application('Spotify');
            spotify.running() ? spotify.currentTrack().artworkUrl() : '';
            """
    }

    /// What the script printed, as a URL: one over https, or nothing. An
    /// empty line, "missing value" and a plain word give nothing.
    static func url(printed: String) -> URL? {
        let text = printed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), url.scheme == "https", url.host != nil else { return nil }
        return url
    }

    /// Cached: the same track asked again shows its cover at once, offline
    /// too. A response that isn't an image is nothing.
    static func fetch(_ url: URL, userAgent: String? = nil) async -> NSImage? {
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad,
                                 timeoutInterval: fetchTimeout)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        if let userAgent { request.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              response.isSuccessful else { return nil }
        return NSImage(data: data)
    }
}
