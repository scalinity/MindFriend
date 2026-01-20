import Foundation
import Security
import CryptoKit
import OSLog

/// Service for encrypting and decrypting sensitive integration data (OAuth tokens)
/// Uses AES-256-GCM for encryption with keys derived from device hardware
final class EncryptionService {
    static let shared = EncryptionService()

    private let logger = Logger(subsystem: "com.mindfriend", category: "Encryption")
    private let keychainService = "com.mindfriend.integrations"

    // MARK: - Key Management

    /// Generates or retrieves the encryption key from Keychain
    private func getOrCreateKey() -> SymmetricKey? {
        // Try to retrieve existing key
        if let existingKeyData = retrieveKeyFromKeychain(),
           let existingKey = try? SymmetricKey(data: existingKeyData) {
            return existingKey
        }

        // Generate new key
        let newKey = SymmetricKey(size: .bits256)

        // Store in Keychain
        let keyData = Data(newKey.withUnsafeBytes { Data($0) })

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "integration_encryption_key",
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        // Delete any existing key first
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Failed to store encryption key: \(status)")
            return nil
        }

        logger.info("Created new encryption key")
        return newKey
    }

    private func retrieveKeyFromKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "integration_encryption_key",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return data
    }

    // MARK: - Encryption

    /// Encrypts data using AES-256-GCM
    /// - Parameter data: Plain text data to encrypt
    /// - Returns: Encrypted data with authentication tag prepended, or nil on failure
    func encrypt(_ data: Data) -> Data? {
        guard let key = getOrCreateKey() else {
            logger.error("Failed to get encryption key")
            return nil
        }

        do {
            let sealedBox = try AES.GCM.seal(data, using: key)

            // Combine ciphertext and authentication tag
            guard let combined = sealedBox.combined else {
                logger.error("Failed to create sealed box")
                return nil
            }

            return combined
        } catch {
            logger.error("Encryption failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Encrypts a string using AES-256-GCM
    /// - Parameter string: Plain text string to encrypt
    /// - Returns: Base64-encoded encrypted data, or nil on failure
    func encryptString(_ string: String) -> String? {
        guard let data = string.data(using: .utf8) else {
            logger.error("Failed to encode string to data")
            return nil
        }

        guard let encryptedData = encrypt(data) else {
            return nil
        }

        return encryptedData.base64EncodedString()
    }

    // MARK: - Decryption

    /// Decrypts data using AES-256-GCM
    /// - Parameter encryptedData: Encrypted data with authentication tag
    /// - Returns: Decrypted data, or nil on failure
    func decrypt(_ encryptedData: Data) -> Data? {
        guard let key = getOrCreateKey() else {
            logger.error("Failed to get encryption key")
            return nil
        }

        do {
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            return decryptedData
        } catch {
            logger.error("Decryption failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Decrypts a base64-encoded encrypted string
    /// - Parameter encryptedBase64: Base64-encoded encrypted data
    /// - Returns: Decrypted string, or nil on failure
    func decryptString(_ encryptedBase64: String) -> String? {
        guard let encryptedData = Data(base64Encoded: encryptedBase64) else {
            logger.error("Failed to decode base64 data")
            return nil
        }

        guard let decryptedData = decrypt(encryptedData) else {
            return nil
        }

        return String(data: decryptedData, encoding: .utf8)
    }

    // MARK: - Token Encryption

    /// Encrypts and stores OAuth token in Keychain
    /// - Parameters:
    ///   - token: The OAuth token to store
    ///   - integrationType: The integration type for key isolation
    /// - Returns: True if successful, false otherwise
    func storeOAuthToken(_ token: OAuthToken, for integrationType: IntegrationType) -> Bool {
        guard let tokenData = try? JSONEncoder().encode(token),
              let encryptedData = encrypt(tokenData) else {
            logger.error("Failed to encrypt OAuth token for \(integrationType.rawValue)")
            return false
        }

        let account = "oauth_token_\(integrationType.rawValue)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: encryptedData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        // Delete any existing token first
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Failed to store OAuth token: \(status)")
            return false
        }

        logger.info("Stored OAuth token for \(integrationType.rawValue)")
        return true
    }

    /// Retrieves and decrypts OAuth token from Keychain
    /// - Parameter integrationType: The integration type
    /// - Returns: Decrypted OAuth token, or nil if not found or failed
    func retrieveOAuthToken(for integrationType: IntegrationType) -> OAuthToken? {
        let account = "oauth_token_\(integrationType.rawValue)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let encryptedData = result as? Data,
              let decryptedData = decrypt(encryptedData),
              let token = try? JSONDecoder().decode(OAuthToken.self, from: decryptedData) else {
            return nil
        }

        return token
    }

    /// Deletes OAuth token from Keychain
    /// - Parameter integrationType: The integration type
    /// - Returns: True if successful, false otherwise
    func deleteOAuthToken(for integrationType: IntegrationType) -> Bool {
        let account = "oauth_token_\(integrationType.rawValue)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)

        if status == errSecSuccess || status == errSecItemNotFound {
            logger.info("Deleted OAuth token for \(integrationType.rawValue)")
            return true
        }

        logger.error("Failed to delete OAuth token: \(status)")
        return false
    }

    // MARK: - State Encryption

    /// Stores OAuth state for PKCE validation
    func storeOAuthState(_ state: OAuthState) -> Bool {
        guard let stateData = try? JSONEncoder().encode(state),
              let encryptedData = encrypt(stateData) else {
            logger.error("Failed to encrypt OAuth state")
            return false
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "oauth_state_\(state.integrationType.rawValue)",
            kSecValueData as String: encryptedData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)

        return status == errSecSuccess
    }

    /// Retrieves and validates OAuth state
    func retrieveOAuthState(for integrationType: IntegrationType) -> OAuthState? {
        let account = "oauth_state_\(integrationType.rawValue)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let encryptedData = result as? Data,
              let decryptedData = decrypt(encryptedData),
              let state = try? JSONDecoder().decode(OAuthState.self, from: decryptedData) else {
            return nil
        }

        // Clean up expired state
        if state.isExpired {
            deleteOAuthState(for: integrationType)
            return nil
        }

        return state
    }

    func deleteOAuthState(for integrationType: IntegrationType) {
        let account = "oauth_state_\(integrationType.rawValue)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Developer API Key Encryption

    /// Stores developer API key
    func storeDeveloperAPIKey(_ apiKey: String, for userId: UUID) -> Bool {
        guard let encryptedData = encryptString(apiKey) else {
            return false
        }

        let account = "dev_api_key_\(userId.uuidString)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: encryptedData.data(using: .utf8) ?? Data(),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)

        return status == errSecSuccess
    }

    /// Retrieves developer API key
    func retrieveDeveloperAPIKey(for userId: UUID) -> String? {
        let account = "dev_api_key_\(userId.uuidString)"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let encryptedData = result as? Data,
              let base64 = String(data: encryptedData, encoding: .utf8) else {
            return nil
        }

        return decryptString(base64)
    }
}
