import Foundation
import Security
import CryptoKit

/// Secure storage service using Keychain for encryption keys and encrypted UserDefaults storage
final class SecureStorage {
    private let keychainService: String
    private let keyIdentifier: String
    private static let keychainQueue = DispatchQueue(label: "app.mindfriend.secure-storage.keychain", qos: .userInitiated)
    private var cachedKey: SymmetricKey?

    init(keychainService: String = "app.mindfriend.secure-storage", keyIdentifier: String = "encryption-key") {
        self.keychainService = keychainService
        self.keyIdentifier = keyIdentifier
    }

    enum SecureStorageError: Error {
        case encryptionFailed
        case decryptionFailed
        case keychainError(OSStatus)
        case invalidData
    }

    // MARK: - Encryption Key Management

    /// Get or create encryption key from Keychain (thread-safe)
    private func encryptionKey(createIfMissing: Bool) throws -> SymmetricKey {
        try Self.keychainQueue.sync {
            // Check cache first (fast path)
            if let cached = cachedKey {
                return cached
            }
            
            // Try to load existing key
            do {
                let existingKey = try loadKeyFromKeychain()
                cachedKey = existingKey
                return existingKey
            } catch SecureStorageError.keychainError(let status) where status == errSecItemNotFound {
                guard createIfMissing else { throw SecureStorageError.keychainError(status) }
            } catch {
                // Unexpected error - log and rethrow
                #if DEBUG
                print("Keychain load error: \(error)")
                #endif
                throw error
            }

            // Generate new key
            let key = SymmetricKey(size: .bits256)
            try saveKeyToKeychain(key)
            cachedKey = key
            return key
        }
    }

    private func loadKeyFromKeychain() throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keyIdentifier,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            throw SecureStorageError.keychainError(status)
        }

        guard let keyData = result as? Data else {
            throw SecureStorageError.invalidData
        }

        return SymmetricKey(data: keyData)
    }

    private func saveKeyToKeychain(_ key: SymmetricKey) throws {
        let keyData = key.withUnsafeBytes { Data($0) }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keyIdentifier,
            kSecValueData as String: keyData,
            // ✅ SECURITY FIX: Use WhenUnlockedThisDeviceOnly for PHI protection
            // Keys only accessible when device unlocked (HIPAA compliance)
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecureStorageError.keychainError(status)
        }
    }

    // MARK: - Encryption/Decryption

    /// Encrypt data using AES-GCM
    func encrypt<T: Codable>(_ value: T) throws -> Data {
        let key = try encryptionKey(createIfMissing: true)
        let jsonData = try JSONEncoder().encode(value)

        let sealedBox = try AES.GCM.seal(jsonData, using: key)
        guard let combined = sealedBox.combined else {
            throw SecureStorageError.encryptionFailed
        }

        return combined
    }

    /// Decrypt data using AES-GCM
    func decrypt<T: Codable>(_ data: Data, as type: T.Type) throws -> T {
        let key = try encryptionKey(createIfMissing: false)

        let sealedBox = try AES.GCM.SealedBox(combined: data)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)

        return try JSONDecoder().decode(T.self, from: decryptedData)
    }

    // MARK: - Secure UserDefaults Storage

    /// Store encrypted value in UserDefaults
    func store<T: Codable>(_ value: T, forKey key: String, in userDefaults: UserDefaults = .standard) throws {
        let encryptedData = try encrypt(value)
        userDefaults.set(encryptedData, forKey: key)
    }

    /// Retrieve and decrypt value from UserDefaults
    func retrieve<T: Codable>(forKey key: String, as type: T.Type, from userDefaults: UserDefaults = .standard) throws -> T? {
        guard let encryptedData = userDefaults.data(forKey: key) else {
            return nil
        }

        return try decrypt(encryptedData, as: type)
    }

    /// Remove value from UserDefaults
    func remove(forKey key: String, from userDefaults: UserDefaults = .standard) {
        userDefaults.removeObject(forKey: key)
    }

    // MARK: - Keychain Cleanup

    /// Evict decrypted key material without losing retained encrypted records.
    func clearCachedKey() {
        Self.keychainQueue.sync { cachedKey = nil }
    }

    /// Delete only after the corresponding encrypted records have been deliberately deleted.
    func deleteEncryptionKey() throws {
        try Self.keychainQueue.sync {
            cachedKey = nil  // Clear cache
            
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: keyIdentifier
            ]

            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw SecureStorageError.keychainError(status)
            }
        }
    }
}
