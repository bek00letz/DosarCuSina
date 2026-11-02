import Foundation
import Security

/// The person's own AI keys, one per provider, kept only in this phone's Keychain
/// (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: never synced, never in a backup
/// restored to another phone). Keys come only from Settings: one path for everyone,
/// developers included, and never from the repository.
public enum KeychainManager {
    private static let serviceName = "com.dosarcusina.app"

    @discardableResult
    public static func saveAPIKey(_ key: String, for provider: AIProvider) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return false }
        deleteAPIKey(for: provider)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: provider.keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    public static func apiKey(for provider: AIProvider) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: provider.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let key = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    @discardableResult
    public static func deleteAPIKey(for provider: AIProvider) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: provider.keychainAccount,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// The Keychain as `AIProviderSettings` uses it.
    public struct Keys: AIKeyStoring {
        public init() {}
        public func key(for provider: AIProvider) -> String? { KeychainManager.apiKey(for: provider) }
        public func save(_ key: String, for provider: AIProvider) -> Bool { KeychainManager.saveAPIKey(key, for: provider) }
        public func delete(for provider: AIProvider) { KeychainManager.deleteAPIKey(for: provider) }
    }
}
