import Foundation

extension NowPlayingTrack {
    /// The track as a prompt reads it, between `tag` tags: one line per field
    /// the player gave, and none for the others — a line saying a field is
    /// unknown would invite a guess. Whether it's paused isn't said: it
    /// changes nothing to what the track is.
    ///
    /// One shape for every prompt that hears about the track: "What's
    /// playing?" asks about it, the custom action gets it as context.
    func promptBlock(tag: String) -> String {
        let fields: [(label: String, value: String?)] = [
            ("titre", title),
            ("artiste", artist),
            ("album", album),
            ("lecteur", appName),
        ]
        let lines = fields.compactMap { field in field.value.map { "\(field.label) : \($0)" } }
        return (["<\(tag)>"] + lines + ["</\(tag)>"]).joined(separator: "\n")
    }
}
