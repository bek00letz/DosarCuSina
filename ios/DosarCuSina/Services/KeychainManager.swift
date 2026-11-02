import Foundation
import Security

/// Secure Keychain Manager for storing sensitive user credentials (e.g., Gemini API key)
/// Ensures zero plain-text storage and zero leaks in public repositories.
public enum KeychainManager {
    private static let serviceName = "com.dosarcusina.app"
    private static let geminiAccountKey = "gemini_api_key"
    
    // MARK: - Save API Key
    @discardableResult
    public static func saveGeminiAPIKey(_ key: String) -> Bool {
        guard let data = key.data(using: .utf8) else { return false }
        
        // Remove existing item if present
        deleteGeminiAPIKey()
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: geminiAccountKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    // MARK: - Retrieve API Key
    public static func getGeminiAPIKey() -> String? {
        // 1. Check user-provided key in Keychain first (Priority 1)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: geminiAccountKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess, let data = dataTypeRef as? Data, let key = String(data: data, encoding: .utf8) {
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        
        // 2. Fallback to Info.plist (populated via local Config.xcconfig for developers)
        if let configKey = Bundle.main.infoDictionary?["GEMINI_API_KEY"] as? String {
            let trimmed = configKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !trimmed.contains("YOUR_GEMINI_API_KEY") {
                return trimmed
            }
        }
        
        return nil
    }
    
    // MARK: - Delete API Key
    @discardableResult
    public static func deleteGeminiAPIKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: geminiAccountKey
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    // MARK: - Check Status
    public static var hasConfiguredAPIKey: Bool {
        getGeminiAPIKey() != nil
    }
}
