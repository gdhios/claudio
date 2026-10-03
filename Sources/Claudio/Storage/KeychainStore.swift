import Foundation
import Security

enum KeychainStore {
    /// The one item Claudio keeps: the API key.
    private static var item: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Constants.keychainService,
         kSecAttrAccount as String: Constants.keychainAccount]
    }

    static func loadAPIKey() -> String? {
        var query = item
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else { return nil }
        return key
    }

    /// `false` when the Keychain refused the key (locked, access denied):
    /// Settings must not then say it is saved.
    static func saveAPIKey(_ key: String) -> Bool {
        deleteAPIKey()
        var attributes = item
        attributes[kSecValueData as String] = Data(key.utf8)
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func deleteAPIKey() {
        SecItemDelete(item as CFDictionary)
    }

    /// Effective key: the environment variable (handy in dev) takes priority over the Keychain.
    static func currentAPIKey() -> String? {
        if let env = ProcessInfo.processInfo.environment[Constants.apiKeyEnvVar],
           !env.trimmingCharacters(in: .whitespaces).isEmpty {
            return env
        }
        return loadAPIKey()
    }
}
