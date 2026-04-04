import Foundation
import CryptoKit
import Combine

/// Manages message encryption/decryption for mentorship communications
@MainActor
final class MentorshipEncryptionService: ObservableObject {

    private let dataService: MentorshipDataService

    nonisolated init(dataService: MentorshipDataService) {
        self.dataService = dataService
    }

    // MARK: - Encryption Keys
    
    /// Generate a new encryption key for message
    func generateEncryptionKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }
    
    /// Get or create encryption key for a match.
    /// Prefers Keychain-stored random key; falls back to deriveEncryptionKey for backward compatibility.
    func getOrCreateKey(for matchId: UUID, userId: UUID) throws -> SymmetricKey {
        // Try loading existing random key from Keychain
        if let existing = try retrieveKeyFromKeychain(for: matchId) {
            return existing
        }
        // Generate a new random key and store it
        let key = generateEncryptionKey()
        try storeKeyInKeychain(key, for: matchId)
        return key
    }

    /// Derive encryption key from user ID and match ID.
    /// Deprecated: Uses predictable public UUIDs with a zero-byte default salt.
    /// Kept only for backward compatibility when decrypting legacy messages.
    @available(*, deprecated, message: "Use getOrCreateKey(for:userId:) instead — derives from predictable UUIDs")
    func deriveEncryptionKey(
        userId: UUID,
        matchId: UUID,
        salt: Data? = nil
    ) -> SymmetricKey {
        let input = (userId.uuidString + matchId.uuidString).data(using: .utf8) ?? Data()
        let saltData = salt ?? Data(repeating: 0, count: 16)

        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: input),
            salt: saltData,
            info: Data("mentorship-encryption".utf8),
            outputByteCount: 32
        )

        return derivedKey
    }
    
    // MARK: - Encryption/Decryption
    
    /// Encrypt message content
    /// The returned ciphertext has the 16-byte GCM authentication tag appended.
    func encryptMessage(
        _ content: String,
        using key: SymmetricKey
    ) throws -> (ciphertext: Data, nonce: Data) {
        guard let plaintext = content.data(using: .utf8) else {
            throw EncryptionError.invalidInput
        }

        let sealedBox = try AES.GCM.seal(plaintext, using: key)
        let nonce = sealedBox.nonce.withUnsafeBytes({ Data($0) })

        // Append GCM tag (16 bytes) to ciphertext so decrypt can extract it
        var ciphertextWithTag = sealedBox.ciphertext
        ciphertextWithTag.append(sealedBox.tag)

        return (ciphertext: ciphertextWithTag, nonce: nonce)
    }

    /// Decrypt message content
    /// Expects ciphertext with the 16-byte GCM authentication tag appended.
    func decryptMessage(
        ciphertext: Data,
        nonce: Data,
        using key: SymmetricKey
    ) throws -> String {
        do {
            guard let nonceValue = try? AES.GCM.Nonce(data: nonce) else {
                throw EncryptionError.invalidNonce
            }

            // GCM tag is always 16 bytes, appended at the end of ciphertext
            let tagLength = 16
            guard ciphertext.count >= tagLength else {
                throw EncryptionError.decryptionFailed
            }

            let rawCiphertext = ciphertext.prefix(ciphertext.count - tagLength)
            let tag = ciphertext.suffix(tagLength)

            let sealedBox = try AES.GCM.SealedBox(nonce: nonceValue, ciphertext: rawCiphertext, tag: tag)
            let plaintext = try AES.GCM.open(sealedBox, using: key)

            guard let message = String(data: plaintext, encoding: .utf8) else {
                throw EncryptionError.decodingFailed
            }

            return message
        } catch {
            if error is EncryptionError {
                throw error
            }
            throw EncryptionError.decryptionFailed
        }
    }
    
    // MARK: - Key Management
    
    /// Store encryption key in Keychain
    func storeKeyInKeychain(
        _ key: SymmetricKey,
        for matchId: UUID
    ) throws {
        let keyData = key.withUnsafeBytes { Data($0) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "mentorship-\(matchId.uuidString)",
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        
        // Delete existing key if present
        SecItemDelete(query as CFDictionary)
        
        // Add new key
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw EncryptionError.keychainError(status)
        }
    }
    
    /// Retrieve encryption key from Keychain
    func retrieveKeyFromKeychain(for matchId: UUID) throws -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "mentorship-\(matchId.uuidString)",
            kSecReturnData as String: true,
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return nil
            }
            throw EncryptionError.keychainError(status)
        }
        
        guard let keyData = result as? Data else {
            throw EncryptionError.invalidKeyData
        }
        
        return SymmetricKey(data: keyData)
    }
    
    /// Delete encryption key from Keychain
    func deleteKeyFromKeychain(for matchId: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "mentorship-\(matchId.uuidString)",
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw EncryptionError.keychainError(status)
        }
    }
    
    // MARK: - Hashing & Verification
    
    /// Generate hash of message for integrity verification
    func hashMessage(_ content: String) -> String {
        guard let data = content.data(using: .utf8) else { return "" }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02hhx", $0) }.joined()
    }
    
    /// Verify message hash
    func verifyMessageHash(_ content: String, hash: String) -> Bool {
        return hashMessage(content) == hash
    }
    
    // MARK: - Encryption Error
    
    enum EncryptionError: LocalizedError {
        case invalidInput
        case encryptionFailed
        case decryptionFailed
        case invalidNonce
        case decodingFailed
        case keychainError(OSStatus)
        case invalidKeyData
        
        var errorDescription: String? {
            switch self {
            case .invalidInput:
                return "Invalid message input"
            case .encryptionFailed:
                return "Failed to encrypt message"
            case .decryptionFailed:
                return "Failed to decrypt message"
            case .invalidNonce:
                return "Invalid encryption nonce"
            case .decodingFailed:
                return "Failed to decode decrypted message"
            case .keychainError(let status):
                return "Keychain error: \(status)"
            case .invalidKeyData:
                return "Invalid key data from keychain"
            }
        }
    }
}

// MARK: - Encryption Wrapper

/// Wrapper for encrypted message data
struct EncryptedMessage: Codable {
    let messageId: UUID
    let ciphertext: Data
    let nonce: Data
    let hash: String
    let encryptedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case ciphertext
        case nonce
        case hash
        case encryptedAt = "encrypted_at"
    }
}

// MARK: - Encryption Context

/// Context for encryption/decryption operations
struct EncryptionContext {
    let matchId: UUID
    let userId: UUID
    let messageId: UUID
    let timestamp: Date
}
