import Foundation

/// How the music code reads the text a player or a base hands over.
extension String {
    /// `nil` for an empty field as for a missing one: MusicBrainz and
    /// Deezer send "" for what they don't know.
    var nonEmpty: String? { isEmpty ? nil : self }

    /// The same name whatever its case, accents or width: "Été" is "ETE",
    /// and a full-width title is its plain self.
    func isSameName(as other: String) -> Bool {
        compare(other, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) == .orderedSame
    }

    /// The year a release date starts with: "1982-11-25", "1982-11" and
    /// "1982" all give "1982".
    var year: String { String(prefix(4)) }
}
