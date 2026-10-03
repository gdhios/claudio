@testable import Claudio

/// The track the tests play: a city-pop single on Spotify, every field a
/// player gives filled in, a Japanese title and all.
extension NowPlayingTrack {
    static let sample = NowPlayingTrack(title: "真夜中のジョーク", artist: "間宮貴子", album: "LOVE TRIP",
                                        appName: "Spotify", bundleID: "com.spotify.client")

    /// The same track, paused: still the widget's, and equal to `sample`,
    /// since a track's equality leaves the pause out.
    static let samplePaused: NowPlayingTrack = {
        var track = sample
        track.isPlaying = false
        return track
    }()
}
