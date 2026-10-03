import Foundation

/// The few shapes a setting takes, read and written one way everywhere.
extension UserDefaults {
    /// A switch, `fallback` until the user flips it.
    func flag(_ key: String, default fallback: Bool = true) -> Bool {
        object(forKey: key) as? Bool ?? fallback
    }

    /// A stored choice. Missing, or written by another version: `fallback`.
    func choice<Value: RawRepresentable>(_ key: String, default fallback: Value) -> Value
    where Value.RawValue == String {
        string(forKey: key).flatMap(Value.init(rawValue:)) ?? fallback
    }

    /// A text that only counts when it says something: `nil` when blank.
    func nonBlankString(_ key: String) -> String? {
        let value = string(forKey: key)
        return value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? value : nil
    }

    /// Stores the text, or removes the key when it is blank, so whatever
    /// the code supplies instead (a default prompt) follows app updates.
    func setNonBlank(_ text: String?, forKey key: String) {
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            set(text, forKey: key)
        } else {
            removeObject(forKey: key)
        }
    }
}
