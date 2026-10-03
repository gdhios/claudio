import Foundation

/// The title as MusicBrainz indexes it: without the version tail a player
/// adds — "- Olympic Mix", "(Radio Edit)", "- Remastered 2015". With the
/// tail the index finds nothing (checked 2026-10-03 on "Am I Wrong -
/// Olympic Mix": nothing, then 32 recordings at score 100 without it), and
/// a version isn't another track for the cache either.
enum TrackTitle {
    private static let versionWords = [
        "mix", "remix", "edit", "version", "remaster", "remastered", "live", "mono", "stereo",
        "instrumental", "acoustic", "demo", "dub", "extended", "radio", "bonus track",
    ].joined(separator: "|")

    /// A dash, a parenthesis or a bracket opening the last segment, which
    /// holds one of the version words.
    private static let tail = try! NSRegularExpression(
        pattern: #"\s*(?:-\s*|[(\[])[^()\[\]]*\b(?:"# + versionWords + #")\b[^()\[\]]*[)\]]?\s*$"#,
        options: [.caseInsensitive])

    static func plain(_ title: String) -> String {
        let range = NSRange(title.startIndex..., in: title)
        let stripped = tail.stringByReplacingMatches(in: title, range: range, withTemplate: "")
        // Nothing left: the "version" was the title.
        return stripped.trimmingCharacters(in: .whitespaces).isEmpty ? title : stripped
    }
}
