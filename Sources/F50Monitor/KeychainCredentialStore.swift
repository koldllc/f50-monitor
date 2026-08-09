import Foundation
import Security

enum KeychainCredentialStore {
    private static let service = "com.f50.monitor.credentials"
    private static let legacyService = "com.f50.statusbar.credentials"

    private static func loadFromService(_ serviceName: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func load(account: String) -> String? {
        if let current = loadFromService(service, account: account) {
            return current
        }
        if let legacy = loadFromService(legacyService, account: account) {
            save(legacy, account: account)
            return legacy
        }
        return nil
    }

    @discardableResult
    static func save(_ value: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let data = Data(value.utf8)
        let attributes = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            return SecItemAdd(newItem as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    static func loadMigratingLegacyValue(
        account: String,
        legacyDefaultsKey: String,
        defaults: UserDefaults = .standard,
        fallback: String = F50Configuration.defaultCredential
    ) -> String {
        if let stored = load(account: account) {
            defaults.removeObject(forKey: legacyDefaultsKey)
            return stored
        }

        let value = defaults.string(forKey: legacyDefaultsKey) ?? fallback
        if save(value, account: account) {
            defaults.removeObject(forKey: legacyDefaultsKey)
        }
        return value
    }
}
