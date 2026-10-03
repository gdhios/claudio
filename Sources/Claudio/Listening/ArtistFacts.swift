import Foundation

/// What MusicBrainz knows of an artist, read before the long text is
/// written: who they are, and the dated list of their albums and EPs. The
/// list is what keeps Claude honest on a catalogue he half remembers: he
/// may cite from it, and nothing else.
struct ArtistFacts: Equatable, Sendable, Codable {
    struct Release: Equatable, Sendable, Codable {
        var id: String
        var title: String
        /// "Album" or "EP", as MusicBrainz names it.
        var primaryType: String?
        var secondaryTypes: [String]
        var firstReleaseDate: String?

        var year: String? { firstReleaseDate?.year }
    }

    var artistID: String
    var name: String
    /// "Person", "Group", "Orchestra"…, as MusicBrainz names it.
    var type: String? = nil
    var country: String? = nil
    /// A person's birth, a group's formation: MusicBrainz says what it knows.
    var beginDate: String? = nil
    var endDate: String? = nil
    var disambiguation: String? = nil
    /// Albums and EPs, the plain ones, by first release.
    var releases: [Release] = []

    /// The block Claude reads after the subject, in French like every
    /// prompt: who, from where, since when, and the dated list — the
    /// source named so the system prompt's rule applies to it.
    var promptBlock: String {
        PromptBlock.make("artiste", attributes: "source=\"MusicBrainz\"", fields: [
            ("nom", name),
            ("précision", disambiguation?.nonEmpty),
            ("type", type.map(Self.typeName)),
            ("pays", country),
            (beginLabel, beginDate),
            ("fin", endDate),
        ], more: discography)
    }

    /// The dated list, under its own heading; nothing without a release.
    private var discography: [String] {
        guard !releases.isEmpty else { return [] }
        return ["discographie (albums et EP, par première sortie) :"] + releases.map { release in
            let type = release.primaryType.map { TrackFacts.typeName($0, english: false) } ?? "sortie"
            return "- \(release.year ?? "sans date") · \(type) · \(release.title)"
        }
    }

    private var beginLabel: String {
        switch type?.lowercased() {
        case "person": "naissance"
        case "group", "orchestra", "choir": "formation"
        default: "début"
        }
    }

    private static func typeName(_ raw: String) -> String {
        switch raw.lowercased() {
        case "person": "personne"
        case "group": "groupe"
        case "orchestra": "orchestre"
        case "choir": "chœur"
        case "character": "personnage"
        case "other": "autre"
        default: raw.lowercased()
        }
    }
}
