import Foundation

/// What MusicBrainz knows of the track playing: the recording, the release
/// group it comes from — the album of origin rather than the compilation the
/// player happens to play — its type and its first release. Facts, never
/// guesses: the card shows them, and Claude reads them as the truth.
struct TrackFacts: Equatable, Sendable, Codable {
    var recordingID: String
    var releaseGroupID: String?
    var albumTitle: String?
    /// "Album", "Single", "EP"…, as MusicBrainz names it.
    var primaryType: String?
    /// "Compilation", "Live", "Soundtrack"…: what makes the release group
    /// something other than a plain one of its primary type.
    var secondaryTypes: [String]
    /// "1982-11-25", "1982-11" or "1982": MusicBrainz says what it knows,
    /// and so does the card.
    var firstReleaseDate: String?

    var year: String? {
        firstReleaseDate.map { String($0.prefix(4)) }
    }

    /// The type as one word, the secondary one when there is one: a
    /// compilation is a compilation before it is an album.
    func typeLabel(english: Bool) -> String? {
        guard let raw = secondaryTypes.first ?? primaryType else { return nil }
        return Self.typeName(raw, english: english)
    }

    /// A MusicBrainz type as one word of the interface's language, the raw
    /// name lowercased when it isn't a known one.
    static func typeName(_ raw: String, english: Bool) -> String {
        typeNames[raw.lowercased()].map { english ? $0.en : $0.fr } ?? raw.lowercased()
    }

    private static let typeNames: [String: (fr: String, en: String)] = [
        "album": ("album", "album"),
        "single": ("single", "single"),
        "ep": ("EP", "EP"),
        "broadcast": ("émission", "broadcast"),
        "other": ("autre", "other"),
        "compilation": ("compilation", "compilation"),
        "soundtrack": ("bande originale", "soundtrack"),
        "live": ("live", "live"),
        "remix": ("remix", "remix"),
        "demo": ("démo", "demo"),
        "dj-mix": ("DJ mix", "DJ mix"),
        "mixtape/street": ("mixtape", "mixtape"),
        "spokenword": ("parlé", "spoken word"),
        "interview": ("interview", "interview"),
        "audiobook": ("livre audio", "audiobook"),
        "audio drama": ("fiction audio", "audio drama"),
        "field recording": ("enregistrement de terrain", "field recording"),
    ]

    /// The line under the card: the album when it isn't the one the player
    /// named, the year, the type — whichever are known. `nil` when none is.
    func summary(playerAlbum: String?, english: Bool) -> String? {
        var parts: [String] = []
        if let albumTitle, !Self.sameTitle(albumTitle, playerAlbum) {
            parts.append(albumTitle)
        }
        if let year { parts.append(year) }
        if let type = typeLabel(english: english) { parts.append(type) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func sameTitle(_ a: String, _ b: String?) -> Bool {
        guard let b else { return false }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        return a.trimmingCharacters(in: .whitespaces)
            .compare(b.trimmingCharacters(in: .whitespaces), options: options) == .orderedSame
    }

    /// The block Claude reads after the track: one line per known fact, in
    /// French like every prompt, the source named so the system prompt's
    /// rule applies to it.
    var promptBlock: String {
        let fields: [(label: String, value: String?)] = [
            ("album d'origine", albumTitle),
            ("type", typeLabel(english: false)),
            ("première sortie", firstReleaseDate),
        ]
        let lines = fields.compactMap { field in field.value.map { "\(field.label) : \($0)" } }
        return (["<faits source=\"MusicBrainz\">"] + lines + ["</faits>"]).joined(separator: "\n")
    }
}
