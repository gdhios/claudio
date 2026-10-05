import Foundation

/// The Ulanzi clocks, as a JSON list. No clock is the off switch: until one
/// is added, nothing about a clock is ever sent anywhere.
extension AppSettings {
    static let ulanziClocksKey = "ulanziClocks"
    /// The one address the first version kept, read once, to migrate.
    static let ulanziAddressKey = "ulanziURL"

    /// The clocks, in the order Settings shows them. An entry that can't be
    /// read, its address above all, is left out, and the list is not
    /// written again for it. The first time, the one address the first
    /// version kept becomes the first clock.
    static func ulanziClocks(in defaults: UserDefaults = .standard) -> [UlanziClock] {
        if defaults.object(forKey: ulanziClocksKey) == nil {
            migrateUlanziAddress(in: defaults)
        }
        guard let data = defaults.data(forKey: ulanziClocksKey),
              let entries = try? JSONDecoder().decode([StoredUlanziClock].self, from: data) else { return [] }
        var seen = Set<UUID>()
        return entries.compactMap(\.clock).filter { seen.insert($0.id).inserted }
    }

    /// No clock removes the key rather than storing an empty list.
    static func setUlanziClocks(_ clocks: [UlanziClock], in defaults: UserDefaults = .standard) {
        guard !clocks.isEmpty, let data = try? JSONEncoder().encode(clocks) else {
            return defaults.removeObject(forKey: ulanziClocksKey)
        }
        defaults.set(data, forKey: ulanziClocksKey)
    }

    /// The address of the first version, made a clock called "Ulanzi" with
    /// both roles, as it had them; its key goes, so a list emptied later
    /// stays empty. An address nobody could call makes nothing.
    private static func migrateUlanziAddress(in defaults: UserDefaults) {
        guard let stored = defaults.string(forKey: ulanziAddressKey),
              let address = normalizedUlanziURL(stored) else { return }
        let clock = UlanziClock(name: UlanziClock.firstName, address: address, face: true, alerts: true)
        setUlanziClocks([clock], in: defaults)
        defaults.removeObject(forKey: ulanziAddressKey)
    }
}

/// One entry of the list as stored: the clock, its address read by the rule
/// every typed address follows, or nil when it can't be read.
private struct StoredUlanziClock: Decodable {
    let clock: UlanziClock?

    init(from decoder: Decoder) throws {
        guard var readable = try? UlanziClock(from: decoder),
              let address = AppSettings.normalizedUlanziURL(readable.address.absoluteString) else {
            self.clock = nil
            return
        }
        readable.address = address
        self.clock = readable
    }
}
