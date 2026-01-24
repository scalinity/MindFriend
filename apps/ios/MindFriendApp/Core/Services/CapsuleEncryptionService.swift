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
/// SECURITY: Master key is randomly generated (NOT derived from user ID)
/// Keys stored in device-only Keychain (no iCloud sync for security)
class CapsuleEncryptionService {

    // MARK: - Constants

    private enum KeychainKeys {
        static let masterKey = "com.mindfriend.capsule.master.key"
        static let capsuleKeyPrefix = "com.mindfriend.capsule.key."
        static let service = "com.mindfriend.timecapsule"
    }

    // MARK: - Types

    /// Metadata for HMAC signature verification
    struct CapsuleMetadata {
        let title: String?
        let theme: String?
        let createdAt: Date
        let deliverAt: Date

        /// Serialize metadata for HMAC signing
        func serialize() -> String {
            let titleStr = title ?? ""
            let themeStr = theme ?? ""
            let createdStr = ISO8601DateFormatter().string(from: createdAt)
            let deliverStr = ISO8601DateFormatter().string(from: deliverAt)
            return "\(titleStr)|\(themeStr)|\(createdStr)|\(deliverStr)"
        }
    }

    // MARK: - Errors

    enum EncryptionError: LocalizedError {
        case invalidContent
        case encryptionFailed
        case decryptionFailed
        case keyGenerationFailed
        case keychainStoreFailed
        case keychainRetrieveFailed
        case invalidKeyId
        case signatureVerificationFailed

        var errorDescription: String? {
            switch self {
            case .invalidContent:
                return "Content is invalid or empty"
            case .encryptionFailed:
                return "Failed to encrypt content. Please try again."
            case .decryptionFailed:
                return "Failed to decrypt capsule content"
            case .keyGenerationFailed:
                return "Failed to generate secure encryption key"
            case .keychainStoreFailed:
                return "Failed to securely store encryption key"
            case .keychainRetrieveFailed:
                return "Failed to retrieve encryption key. Capsules can only be opened on this device."
            case .invalidKeyId:
                return "Invalid encryption key identifier"
            case .signatureVerificationFailed:
                return "Capsule metadata has been tampered with"
            }
        }
    }

    // MARK: - Public API

    /// Encrypt content with AES-256-GCM
    /// - Parameter content: Plaintext content to encrypt
    /// - Returns: Tuple of (encrypted data, key ID)
    /// - Throws: EncryptionError if encryption fails
    func encrypt(content: String) throws -> (encrypted: Data, keyId: String) {
        guard !content.isEmpty else {
            throw EncryptionError.invalidContent
        }

        guard let contentData = content.data(using: .utf8) else {
            throw EncryptionError.invalidContent
        }

        // Get or create master key
        let masterKey = try getMasterKey()

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
    func decrypt(encrypted: Data, keyId: String) throws -> String {
        // Get master key
        let masterKey = try getMasterKey()

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

    /// Sign capsule metadata with HMAC-SHA256
    /// SECURITY: Prevents database administrators from tampering with metadata
    /// - Parameters:
    ///   - metadata: Capsule metadata to sign
    ///   - keyId: Encryption key identifier
    /// - Returns: Base64-encoded HMAC signature
    /// - Throws: EncryptionError if signing fails
    func signMetadata(_ metadata: CapsuleMetadata, keyId: String) throws -> String {
        // Retrieve capsule key
        let encryptedKey = try retrieveEncryptedKey(keyId: keyId)
        let masterKey = try getMasterKey()
        let keySealedBox = try AES.GCM.SealedBox(combined: encryptedKey)
        let capsuleKeyData = try AES.GCM.open(keySealedBox, using: masterKey)
        let capsuleKey = SymmetricKey(data: capsuleKeyData)

        // Create HMAC signature
        let metadataString = metadata.serialize()
        guard let metadataData = metadataString.data(using: .utf8) else {
            throw EncryptionError.encryptionFailed
        }

        let signature = HMAC<SHA256>.authenticationCode(for: metadataData, using: capsuleKey)
        return Data(signature).base64EncodedString()
    }

    /// Verify capsule metadata signature
    /// SECURITY: Detects if database administrator tampered with metadata
    /// - Parameters:
    ///   - metadata: Capsule metadata to verify
    ///   - signature: Base64-encoded HMAC signature
    ///   - keyId: Encryption key identifier
    /// - Returns: True if signature is valid, false otherwise
    /// - Throws: EncryptionError if verification fails due to key retrieval issues
    func verifyMetadata(_ metadata: CapsuleMetadata, signature: String, keyId: String) throws -> Bool {
        // Retrieve capsule key
        let encryptedKey = try retrieveEncryptedKey(keyId: keyId)
        let masterKey = try getMasterKey()
        let keySealedBox = try AES.GCM.SealedBox(combined: encryptedKey)
        let capsuleKeyData = try AES.GCM.open(keySealedBox, using: masterKey)
        let capsuleKey = SymmetricKey(data: capsuleKeyData)

        // Recompute HMAC signature
        let metadataString = metadata.serialize()
        guard let metadataData = metadataString.data(using: .utf8) else {
            return false
        }

        let expectedSignature = HMAC<SHA256>.authenticationCode(for: metadataData, using: capsuleKey)
        guard let providedSignature = Data(base64Encoded: signature) else {
            return false
        }

        // Constant-time comparison of signatures
        return secureCompare(Data(expectedSignature), providedSignature)
    }

    // MARK: - Master Key Management

    /// Get or create master key (randomly generated, NOT derived from user ID)
    /// SECURITY FIX: Master key is now truly random, not derived from predictable user ID
    private func getMasterKey() throws -> SymmetricKey {
        // Try to retrieve existing master key
        if let existingKey = try? retrieveMasterKeyFromKeychain() {
            return existingKey
        }

        // Generate NEW random 256-bit master key
        let masterKey = SymmetricKey(size: .bits256)

        // Store in device-only Keychain (no iCloud sync)
        try storeMasterKeyInKeychain(masterKey)

        return masterKey
    }

    /// Store master key in Keychain (device-only, no iCloud sync)
    private func storeMasterKeyInKeychain(_ key: SymmetricKey) throws {
        let keyData = key.withUnsafeBytes { Data($0) }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainKeys.service,
            kSecAttrAccount as String: KeychainKeys.masterKey,
            kSecValueData as String: keyData,
            kSecAttrSynchronizable as String: false, // SECURITY: No iCloud sync
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly // Device-only
        ]

        // Delete existing item if present
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw EncryptionError.keychainStoreFailed
        }
    }

    /// Retrieve master key from Keychain
    private func retrieveMasterKeyFromKeychain() throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainKeys.service,
            kSecAttrAccount as String: KeychainKeys.masterKey,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let keyData = result as? Data else {
            throw EncryptionError.keychainRetrieveFailed
        }

        return SymmetricKey(data: keyData)
    }

    // MARK: - Keychain Operations

    /// Store encrypted capsule key in Keychain (device-only, no iCloud sync)
    /// SECURITY FIX: Disabled iCloud sync to prevent attack surface expansion
    private func storeEncryptedKey(_ encryptedKey: Data, keyId: String) throws {
        let account = KeychainKeys.capsuleKeyPrefix + keyId

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainKeys.service,
            kSecAttrAccount as String: account,
            kSecValueData as String: encryptedKey,
            kSecAttrSynchronizable as String: false, // SECURITY: No iCloud sync
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly // Device-only
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
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            throw EncryptionError.keychainRetrieveFailed
        }

        return data
    }

    // MARK: - Utility

    /// Delete encryption key from Keychain (for capsule deletion)
    func deleteKey(keyId: String) throws {
        let account = KeychainKeys.capsuleKeyPrefix + keyId

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainKeys.service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)

        // Ignore error if item doesn't exist
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw EncryptionError.keychainStoreFailed
        }
    }

    /// Constant-time comparison of two Data objects
    /// SECURITY: Prevents timing attacks by comparing all bytes regardless of differences
    /// - Parameters:
    ///   - lhs: First data to compare
    ///   - rhs: Second data to compare
    /// - Returns: True if data is identical, false otherwise
    private func secureCompare(_ lhs: Data, _ rhs: Data) -> Bool {
        // Different lengths = not equal (but still compare to prevent short-circuit)
        guard lhs.count == rhs.count else {
            return false
        }

        // XOR all bytes and accumulate result
        var result: UInt8 = 0
        for (byte1, byte2) in zip(lhs, rhs) {
            result |= byte1 ^ byte2
        }

        // result == 0 means all bytes matched
        return result == 0
    }

    /// Constant-time string comparison
    /// SECURITY: Prevents timing attacks when comparing key IDs or other sensitive strings
    /// - Parameters:
    ///   - lhs: First string to compare
    ///   - rhs: Second string to compare
    /// - Returns: True if strings are identical, false otherwise
    private func secureCompareStrings(_ lhs: String, _ rhs: String) -> Bool {
        guard let lhsData = lhs.data(using: .utf8),
              let rhsData = rhs.data(using: .utf8) else {
            return false
        }
        return secureCompare(lhsData, rhsData)
    }
}

// MARK: - Base64 Helpers

extension CapsuleEncryptionService {
    /// Encrypt and return base64-encoded string (for API transport)
    func encryptToBase64(content: String) throws -> (encrypted: String, keyId: String) {
        let result = try encrypt(content: content)
        let base64 = result.encrypted.base64EncodedString()
        return (base64, result.keyId)
    }

    /// Decrypt from base64-encoded string
    func decryptFromBase64(encrypted: String, keyId: String) throws -> String {
        guard let data = Data(base64Encoded: encrypted) else {
            throw EncryptionError.decryptionFailed
        }
        return try decrypt(encrypted: data, keyId: keyId)
    }
}
