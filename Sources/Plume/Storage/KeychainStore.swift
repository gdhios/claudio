import Foundation
import Security

enum KeychainStore {
    static func loadAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.keychainService,
            kSecAttrAccount as String: Constants.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else { return nil }
        return key
    }

    static func saveAPIKey(_ key: String) {
        deleteAPIKey()
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.keychainService,
            kSecAttrAccount as String: Constants.keychainAccount,
            kSecValueData as String: Data(key.utf8)
        ]
        _ = SecItemAdd(attributes as CFDictionary, nil)
    }

    static func deleteAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.keychainService,
            kSecAttrAccount as String: Constants.keychainAccount
        ]
        _ = SecItemDelete(query as CFDictionary)
    }

    /// Clé effective : la variable d'environnement (pratique en dev) prime sur le Trousseau.
    static func currentAPIKey() -> String? {
        if let env = ProcessInfo.processInfo.environment[Constants.apiKeyEnvVar],
           !env.trimmingCharacters(in: .whitespaces).isEmpty {
            return env
        }
        return loadAPIKey()
    }
}
