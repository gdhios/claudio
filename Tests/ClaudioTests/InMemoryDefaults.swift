import Foundation

/// UserDefaults as a test has them: a dictionary in memory, gone with the
/// instance. A suite made with `UserDefaults(suiteName:)` lands in
/// ~/Library/Preferences, and `removePersistentDomain(forName:)` does not
/// take it back out: `cfprefsd` leaves an empty plist behind, and writes it
/// again if the file is deleted under it. Only never reaching it leaves
/// nothing.
///
/// Every typed accessor (`integer(forKey:)`, `set(_: Int, forKey:)`, …)
/// goes through the three overrides below, so the coercions the tests lean
/// on stay Foundation's own. A value no property list can hold is refused
/// here as the real store would refuse it.
final class InMemoryDefaults: UserDefaults, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Any] = [:]

    /// The suite is never written to: a plist under this name after a test
    /// run means a write slipped past the overrides.
    init() {
        super.init(suiteName: "ClaudioTests.inMemory")!
    }

    override func object(forKey key: String) -> Any? {
        lock.withLock { values[key] }
    }

    override func set(_ value: Any?, forKey key: String) {
        guard let value else { return removeObject(forKey: key) }
        precondition(PropertyListSerialization.propertyList(value, isValidFor: .binary),
                     "UserDefaults only holds property list values: \(key)")
        lock.withLock { values[key] = value }
    }

    override func removeObject(forKey key: String) {
        lock.withLock { values[key] = nil }
    }
}
