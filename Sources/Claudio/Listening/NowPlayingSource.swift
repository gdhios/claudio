import Foundation

/// Where "What's playing?" learns what plays. Injected like `MediaPlayback`:
/// a test scripts the track and when the answer comes, and nothing in a test
/// or a preview ever reads the machine it runs on.
@MainActor
struct NowPlayingSource {
    /// The track the Now Playing widget shows, `nil` when nothing plays or
    /// the player couldn't be read in time.
    var current: @MainActor () async -> NowPlayingTrack?

    /// Loads MediaRemote inside `osascript` and prints what it knows of the
    /// track as one JSON object. A value MediaRemote doesn't have comes out
    /// `undefined`, which `JSON.stringify` leaves out: a missing field is
    /// simply absent. Nothing here sends a command.
    static let script = """
        \(MediaRemote.jxaPrelude)
        const R = $.NSClassFromString('MRNowPlayingRequest');
        const info = R.localNowPlayingItem.nowPlayingInfo;
        const v = k => ObjC.unwrap(info.valueForKey(k));
        JSON.stringify({
          title: v('kMRMediaRemoteNowPlayingInfoTitle'),
          artist: v('kMRMediaRemoteNowPlayingInfoArtist'),
          album: v('kMRMediaRemoteNowPlayingInfoAlbum'),
          duration: v('kMRMediaRemoteNowPlayingInfoDuration'),
          playing: R.localIsPlaying,
          app: ObjC.unwrap(R.localNowPlayingPlayerPath.client.displayName),
          bundle: ObjC.unwrap(R.localNowPlayingPlayerPath.client.bundleIdentifier)
        });
        """

    /// A read takes a tenth of a second. Past this one it is abandoned and
    /// counts as nothing playing: the panel says so rather than waiting.
    static let timeout: TimeInterval = 2

    /// The player as `osascript` reads it. A preview never reads: it must
    /// render the same screen on every machine.
    static let system = NowPlayingSource {
        guard !PreviewRun.isActive,
              let printed = await JXAScript.run(script, timeout: timeout) else { return nil }
        return NowPlayingTrack(printed: printed)
    }
}
