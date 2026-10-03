import Foundation

/// A capped list kept as JSON in the preferences: what both histories
/// persist. A list that can't be read starts over empty.
struct StoredList<Entry: Codable> {
    let defaults: UserDefaults
    let key: String
    let limit: Int

    func load() -> [Entry] {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return Array(stored.prefix(limit))
    }

    func save(_ entries: [Entry]) {
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: key)
        }
    }
}
