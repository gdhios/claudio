import Foundation

/// The replacements applied to a transcript. Whole words and phrases only,
/// case ignored, accents kept, and the written form pasted exactly as typed:
/// a hit inside another word would corrupt a dictation that was right.
extension DictationVocabulary {
    /// The transcript with each heard phrase replaced by its written form.
    ///
    /// One pass over the text: a written form is never read again as another
    /// line's heard phrase, so the order of the lines changes nothing. Where
    /// two heard phrases start at the same word, the longer one wins. A
    /// transcript with nothing to replace comes back exactly as it came.
    func applyingReplacements(to transcript: String) -> String {
        // Tried in this order at each word: "claude code" is taken before
        // "claude" can be. Ties keep the order typed.
        let ordered = replacements.enumerated().sorted { lhs, rhs in
            lhs.element.heard.count != rhs.element.heard.count
                ? lhs.element.heard.count > rhs.element.heard.count
                : lhs.offset < rhs.offset
        }.map(\.element)
        guard !ordered.isEmpty, let expression = Self.expression(matching: ordered) else {
            return transcript
        }

        // Unicode writes "é" as one scalar or as "e" plus an accent, and the
        // pattern compares scalars: both sides are composed first.
        let text = transcript.precomposedStringWithCanonicalMapping
        let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { return transcript }

        var result = ""
        var cursor = text.startIndex
        for match in matches {
            // One capture group per replacement, in `ordered`'s order: the
            // group that took part names the line that matched.
            guard let range = Range(match.range, in: text),
                  let group = (1...ordered.count).first(where: { match.range(at: $0).location != NSNotFound })
            else { continue }
            result += text[cursor..<range.lowerBound]
            result += ordered[group - 1].written
            cursor = range.upperBound
        }
        result += text[cursor...]
        return result
    }

    /// Every heard phrase in a capture group of its own, between two edges
    /// that are neither letters nor digits: "claudio" is never found inside
    /// "claudiophile". `nil` if it can't compile, which escaped text doesn't
    /// cause — the transcript would then be left alone, not lost.
    private static func expression(matching replacements: [Replacement]) -> NSRegularExpression? {
        let alternatives = replacements
            .map { "(\(pattern(for: $0.heard)))" }
            .joined(separator: "|")
        let letter = "[\\p{L}\\p{M}\\p{N}]"
        return try? NSRegularExpression(pattern: "(?<!\(letter))(?:\(alternatives))(?!\(letter))",
                                        options: [.caseInsensitive])
    }

    /// A heard phrase as a pattern: its characters taken literally, any run
    /// of whitespace between its words, and either apostrophe for the other
    /// — the Settings editor may curl the one typed, and recognition writes
    /// whichever it likes.
    private static func pattern(for heard: String) -> String {
        heard.precomposedStringWithCanonicalMapping
            .split(whereSeparator: \.isWhitespace)
            .map { word in
                word.map { character in
                    apostrophes.contains(character)
                        ? "['’]"
                        : NSRegularExpression.escapedPattern(for: String(character))
                }.joined()
            }
            .joined(separator: "\\s+")
    }

    private static let apostrophes: Set<Character> = ["'", "’"]
}
