//
//  CapsuleEncryptionService.swift
//  MindFriendApp
//
//  Client-side AES-256-GCM encryption for time capsules
//  Keys stored in iOS Keychain with iCloud sync
//

import Foundation
import CryptoKit
import Security

/// Handles encryption/decryption of time capsule content
/// Uses AES-256-GCM with per-capsule keys encrypted by user master key
class CapsuleEncryptionService {

    // MARK: - Constants

    private enum KeychainKeys {
        static let masterKeySalt = "com.mindfriend.capsule.master.salt"
        static let capsuleKeyPrefix = "com.mindfriend.capsule.key."
        static let service = "com.mindfriend.timecapsule"
    }

    private enum Constants {
        static let masterKeyInfo = "capsule-master-key"
        static let saltSize = 32
    }

    // MARK: - Errors

    enum EncryptionError: LocalizedError {
        case invalidContent
        case encryptionFailed
        case decryptionFailed
        case keyDerivationFailed
        case keychainStoreFailed
        case keychainRetrieveFailed
        case userIdUnavailable
        case invalidKeyId

        var errorDescription: String? {
            switch self {
            case .invalidContent:
                return "Content is invalid or empty"
            case .encryptionFailed:
                return "Failed to encrypt content. Please try again."
            case .decryptionFailed:
                return "Failed to decrypt capsule content"
            case .keyDerivationFailed:
                return "Failed to derive encryption key"
            case .keychainStoreFailed:
                return "Failed to securely store encryption key"
            case .keychainRetrieveFailed:
                return "Failed to retrieve encryption key. Enable iCloud Keychain to sync capsules across devices."
            case .userIdUnavailable:
                return "User authentication required"
            case .invalidKeyId:
                return "Invalid encryption key identifier"
            }
        }
    }

    // MARK: - Dependencies

    private let userIdProvider: () async -> String?

    init(userIdProvider: @escaping () async -> String?) {
        self.userIdProvider = userIdProvider
    }

    // MARK: - Public API

    /// Encrypt content with AES-256-GCM
    /// - Parameter content: Plaintext content to encrypt
    /// - Returns: Tuple of (encrypted data, key ID)
    /// - Throws: EncryptionError if encryption fails
    func encrypt(content: String) async throws -> (encrypted: Data, keyId: String) {
        guard !content.isEmpty else {
            throw EncryptionError.invalidContent
        }

        guard let contentData = content.data(using: .utf8) else {
            throw EncryptionError.invalidContent
        }

        // Get or create master key
        let masterKey = try await getMasterKey()

        // Generate per-capsule encryption key
        let capsuleKey = SymmetricKey(size: .bits256)

        // Encrypt content with capsule key
        let nonce = AES.GCM.Nonce()
        let sealedContent = try AES.GCM.seal(contentData, using: capsuleKey, nonce: nonce)

        guard let encryptedContent = sealedContent.combined else {
            throw EncryptionError.encryptionFailed
        }

        // Encrypt capsule key with master key
        let capsuleKeyData = capsuleKey.withUnsafeBytes { Data($0) }
        let keyNonce = AES.GCM.Nonce()
        let sealedKey = try AES.GCM.seal(capsuleKeyData, using: masterKey, nonce: keyNonce)

        guard let encryptedKey = sealedKey.combined else {
            throw EncryptionError.encryptionFailed
        }

        // Store encrypted key in Keychain with iCloud sync
        let keyId = UUID().uuidString
        try storeEncryptedKey(encryptedKey, keyId: keyId)

        return (encryptedContent, keyId)
    }

    /// Decrypt content
    /// - Parameters:
    ///   - encrypted: Encrypted data
    ///   - keyId: Encryption key identifier
    /// - Returns: Decrypted plaintext content
    /// - Throws: EncryptionError if decryption fails
    func decrypt(encrypted: Data, keyId: String) async throws -> String {
        // Get master key
        let masterKey = try await getMasterKey()

        // Retrieve and decrypt capsule key
        let encryptedKey = try retrieveEncryptedKey(keyId: keyId)

        let keySealedBox = try AES.GCM.SealedBox(combined: encryptedKey)
        let capsuleKeyData = try AES.GCM.open(keySealedBox, using: masterKey)
        let capsuleKey = SymmetricKey(data: capsuleKeyData)

        // Decrypt content
        let sealedBox = try AES.GCM.SealedBox(combined: encrypted)
        let decryptedData = try AES.GCM.open(sealedBox, using: capsuleKey)

        guard let content = String(data: decryptedData, encoding: .utf8) else {
            throw EncryptionError.decryptionFailed
        }

        return content
    }

    // MARK: - Master Key Management

    /// Get or create master key derived from stable user ID
    private func getMasterKey() async throws -> SymmetricKey {
        guard let userId = await userIdProvider() else {
            throw EncryptionError.userIdUnavailable
        }

        // Get or create salt
        let salt = try getOrCreateSalt()

        // Derive master key from user ID + salt
        return try deriveMasterKey(from: userId, salt: salt)
    }

    /// Derive master key using HKDF from stable user ID
    private func deriveMasterKey(from userId: String, salt: Data) throws -> SymmetricKey {
        guard let inputKeyData = userId.data(using: .utf8) else {
            throw EncryptionError.keyDerivationFailed
        }

        let inputKey = SymmetricKey(data: inputKeyData)

        guard let info = Constants.masterKeyInfo.data(using: .utf8) else {
            throw EncryptionError.keyDerivationFailed
        }

        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: inputKey,
            salt: salt,
            info: info,
            outputByteCount: 32
        )
    }

    // MARK: - Keychain Operations

    /// Store encrypted capsule key in Keychain with iCloud sync
    private func storeEncryptedKey(_ encryptedKey: Data, keyId: String) throws {
        let account = KeychainKeys.capsuleKeyPrefix + keyId

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainKeys.service,
            kSecAttrAccount as String: account,
            kSecValueData as String: encryptedKey,
            kSecAttrSynchronizable as String: true, // Enable iCloud Keychain sync
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock // Security: available after first unlock
        ]

        // Delete existing item if present
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw EncryptionError.keychainStoreFailed
        }
    }

    /// Retrieve encrypted capsule key from Keychain
    private func retrieveEncryptedKey(keyId: String) throws -> Data {
        let account = KeychainKeys.capsuleKeyPrefix + keyId

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainKeys.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny // Search both local and synced
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            throw EncryptionError.keychainRetrieveFailed
        }

        return data
    }

    /// Get or create salt for master key derivation
    private func getOrCreateSalt() throws -> Data {
        // Try to retrieve existing salt
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainKeys.service,
            kSecAttrAccount as String: KeychainKeys.masterKeySalt,
            kSecReturnData as String: true,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]

        var result: AnyObject?
        var status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let existingSalt = result as? Data {
            return existingSalt
        }

        // Create new salt
        var salt = Data(count: Constants.saltSize)
        let result2 = salt.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, Constants.saltSize, ptr.baseAddress!)
        }

        guard result2 == errSecSuccess else {
            throw EncryptionError.keyDerivationFailed
        }

        // Store salt in Keychain with iCloud sync
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainKeys.service,
            kSecAttrAccount as String: KeychainKeys.masterKeySalt,
            kSecValueData as String: salt,
            kSecAttrSynchronizable as String: true,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock // Security: available after first unlock
        ]

        status = SecItemAdd(addQuery as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw EncryptionError.keychainStoreFailed
        }

        return salt
    }

    // MARK: - Utility

    /// Delete encryption key from Keychain (for capsule deletion)
    func deleteKey(keyId: String) throws {
        let account = KeychainKeys.capsuleKeyPrefix + keyId

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainKeys.service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]

        let status = SecItemDelete(query as CFDictionary)

        // Ignore error if item doesn't exist
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw EncryptionError.keychainStoreFailed
        }
    }
}

// MARK: - Base64 Helpers

extension CapsuleEncryptionService {
    /// Encrypt and return base64-encoded string (for API transport)
    func encryptToBase64(content: String) async throws -> (encrypted: String, keyId: String) {
        let result = try await encrypt(content: content)
        let base64 = result.encrypted.base64EncodedString()
        return (base64, result.keyId)
    }

    /// Decrypt from base64-encoded string
    func decryptFromBase64(encrypted: String, keyId: String) async throws -> String {
        guard let data = Data(base64Encoded: encrypted) else {
            throw EncryptionError.decryptionFailed
        }
        return try await decrypt(encrypted: data, keyId: keyId)
    }
}
