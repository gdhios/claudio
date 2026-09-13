import Foundation

/// A dictation that already happened: what was heard, what the cleanup pass
/// made of it, in which language and when. The audio is never kept — only
/// these four fields ever exist.
struct RecentDictation: Codable, Equatable, Sendable {
    var date: Date
    /// BCP-47 identifier, a `DictationLanguage.rawValue`. Kept as text rather
    /// than as the enum so a history written by a version that knows one more
    /// language still decodes here.
    var language: String
    /// The transcript, as the engine returned it. Always present: it is the
    /// one thing a failed cleanup can't take away.
    var raw: String
    /// The cleaned-up text, absent when the "Raw" model is picked or the
    /// cleanup pass failed.
    var cleaned: String?

    init(date: Date, language: String, raw: String, cleaned: String? = nil) {
        self.date = date
        self.language = language
        self.raw = raw
        self.cleaned = cleaned
    }

    init(date: Date, language: DictationLanguage, raw: String, cleaned: String? = nil) {
        self.init(date: date, language: language.rawValue, raw: raw, cleaned: cleaned)
    }
}

/// The latest dictations, most recent first, capped. A value type with no
/// dependency on storage: it's what the tests exercise. Unlike the custom
/// instructions, nothing is de-duplicated here — saying the same sentence
/// twice is two dictations.
struct RecentDictations: Equatable, Sendable {
    /// Most recent first.
    private(set) var entries: [RecentDictation]

    init(_ entries: [RecentDictation] = []) { self.entries = entries }

    /// Adds a dictation to the front. A blank transcript is ignored (a short
    /// press, a silence); text is stored trimmed, and a blank cleaned version
    /// is stored as none at all. Beyond the cap, the oldest one drops off.
    func adding(_ dictation: RecentDictation, limit: Int = 50) -> RecentDictations {
        let raw = dictation.raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return self }
        let cleaned = dictation.cleaned?.trimmingCharacters(in: .whitespacesAndNewlines)
        var kept = entries
        kept.insert(RecentDictation(date: dictation.date,
                                    language: dictation.language,
                                    raw: raw,
                                    cleaned: (cleaned?.isEmpty == false) ? cleaned : nil),
                    at: 0)
        return RecentDictations(Array(kept.prefix(limit)))
    }

    func cleared() -> RecentDictations { RecentDictations() }
}

/// History of dictations, shown in Settings so a text can be copied back
/// after the fact. Persisted as JSON in the preferences; nothing is sent
/// anywhere, and no audio is ever written. Modeled on `TransformHistory`.
@MainActor
final class DictationHistory {
    static let shared = DictationHistory()

    private enum Key { static let entries = "dictationHistory" }

    private(set) var recents: RecentDictations

    private let defaults: UserDefaults
    private let limit: Int

    init(defaults: UserDefaults = .standard, limit: Int = 50) {
        self.defaults = defaults
        self.limit = limit
        if let data = defaults.data(forKey: Key.entries),
           let stored = try? JSONDecoder().decode([RecentDictation].self, from: data) {
            recents = RecentDictations(Array(stored.prefix(limit)))
        } else {
            recents = RecentDictations()
        }
    }

    /// Records a dictation that produced text, whether or not it was cleaned
    /// up and whether or not it made it into the target app. A blank
    /// transcript writes nothing.
    func record(raw: String,
                cleaned: String?,
                language: DictationLanguage,
                at date: Date = Date()) {
        let updated = recents.adding(RecentDictation(date: date,
                                                     language: language,
                                                     raw: raw,
                                                     cleaned: cleaned),
                                     limit: limit)
        guard updated != recents else { return }
        recents = updated
        persist()
    }

    /// Forgets the whole history.
    func clear() {
        guard !recents.entries.isEmpty else { return }
        recents = recents.cleared()
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(recents.entries) {
            defaults.set(data, forKey: Key.entries)
        }
    }
}
