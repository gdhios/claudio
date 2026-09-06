import Foundation

/// A free-form transform that already ran: its instruction, and when. Only
/// the instruction, the "what to do", is kept, never the source text or the
/// result.
struct RecentTransform: Codable, Equatable, Sendable {
    var instruction: String
    var date: Date
}

/// The latest free-form instructions, most recent first, no duplicates,
/// capped. A value type with no dependency on storage: it's what the tests
/// exercise.
struct RecentTransforms: Equatable, Sendable {
    /// Most recent first.
    private(set) var entries: [RecentTransform]

    init(_ entries: [RecentTransform] = []) { self.entries = entries }

    /// Adds an instruction to the front. Blank, it's ignored; already present
    /// (down to the character), it moves up with its new date instead of
    /// duplicating; beyond the cap, the oldest one drops off.
    func adding(_ instruction: String, at date: Date, limit: Int = 20) -> RecentTransforms {
        let trimmed = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return self }
        var kept = entries.filter { $0.instruction != trimmed }
        kept.insert(RecentTransform(instruction: trimmed, date: date), at: 0)
        return RecentTransforms(Array(kept.prefix(limit)))
    }

    func cleared() -> RecentTransforms { RecentTransforms() }
}

/// History of free-form instructions, to relaunch them with a single gesture
/// on the current selection. Persisted as JSON in the preferences; nothing
/// is sent anywhere. Modeled on `CostLedger`.
@MainActor
final class TransformHistory {
    static let shared = TransformHistory()

    private enum Key { static let entries = "history.recentTransforms" }

    private(set) var recents: RecentTransforms

    private let defaults: UserDefaults
    private let limit: Int

    init(defaults: UserDefaults = .standard, limit: Int = 20) {
        self.defaults = defaults
        self.limit = limit
        if let data = defaults.data(forKey: Key.entries),
           let stored = try? JSONDecoder().decode([RecentTransform].self, from: data) {
            recents = RecentTransforms(Array(stored.prefix(limit)))
        } else {
            recents = RecentTransforms()
        }
    }

    /// Records a free-form instruction that just succeeded. An empty or
    /// unchanged instruction writes nothing.
    func record(_ instruction: String, at date: Date = Date()) {
        let updated = recents.adding(instruction, at: date, limit: limit)
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
