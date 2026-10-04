import Foundation

/// Whether a model's answer is a cleanup of the transcript, or something
/// else: an answer to it. A cleanup keeps the speaker's words — it adds
/// punctuation and takes hesitations away — so most of its words were said.
/// "Je suis prêt à nettoyer ta transcription… Envoie-moi le texte" shares
/// almost none with what was dictated. When that happens the transcript is
/// pasted instead: raw, but the speaker's.
///
/// A pure value, tested without a model. Only the cleanup output goes
/// through it: a translation or a structured prompt is meant to differ.
enum CleanupPlausibility {

    /// Below this many words, an answer is never judged: "trois" cleaned up
    /// into "3" shares no word with what was said, and is still right. The
    /// answers this is for run to a sentence or more.
    static let minimumWords = 6

    /// The share of the answer's words that must have been said.
    static let minimumShare = 0.5

    static func isCleanup(_ cleaned: String, of raw: String) -> Bool {
        let answer = words(in: cleaned)
        guard answer.count >= minimumWords else { return true }
        let said = Set(words(in: raw))
        // A figure was said in words ("douze" comes back "12"): digits
        // count as said, or a dictation of numbers would be thrown away.
        let kept = answer.filter { said.contains($0) || $0.allSatisfy(\.isNumber) }.count
        return Double(kept) / Double(answer.count) >= minimumShare
    }

    /// Lowercased, accents folded, split on anything that isn't a letter or
    /// a digit: "C'est" and "c est" are the same two words.
    static func words(in text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }
}
