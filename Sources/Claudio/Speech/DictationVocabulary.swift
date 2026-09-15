import Foundation

/// The speaker's own words — names, brands, jargon — that on-device
/// recognition spells its own way, as typed in Settings › Dictation. A pure
/// value read from plain text, like `DictationCleanup`'s prompt, so the
/// format is tested without a microphone or a model.
///
/// One entry per line. A plain line is a term: `Okonoma`. A line with an
/// arrow, `→` or `->`, is a replacement: `l'a pas compris → Lapacompris`,
/// whose written side is a term too. Blank lines are skipped and whitespace
/// trimmed; a line that can't be read — a side left empty, two arrows — is
/// dropped rather than guessed at, since a guess ends up pasted.
struct DictationVocabulary: Equatable, Sendable {
    /// What the recognizer writes, and what should be written instead.
    struct Replacement: Equatable, Sendable {
        let heard: String
        let written: String
    }

    /// Every spelling to keep, once each, in the order typed: the plain
    /// lines and the written side of each replacement. Recognition is biased
    /// towards them, and the cleanup prompt lists them.
    let terms: [String]
    /// In the order typed.
    let replacements: [Replacement]

    static let empty = DictationVocabulary(parsing: "")

    init(parsing text: String) {
        var terms: [String] = []
        var replacements: [Replacement] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let entry = line.trimmingCharacters(in: .whitespaces)
            guard !entry.isEmpty else { continue }
            let arrows = entry.ranges(of: "→") + entry.ranges(of: "->")
            switch arrows.count {
            case 0:
                terms.append(entry)
            case 1:
                let heard = entry[..<arrows[0].lowerBound].trimmingCharacters(in: .whitespaces)
                let written = entry[arrows[0].upperBound...].trimmingCharacters(in: .whitespaces)
                guard !heard.isEmpty, !written.isEmpty else { continue }
                replacements.append(Replacement(heard: heard, written: written))
                terms.append(written)
            default:
                continue
            }
        }
        var seen = Set<String>()
        self.terms = terms.filter { seen.insert($0).inserted }
        self.replacements = replacements
    }
}
