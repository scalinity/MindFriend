import Foundation
import Security
import CryptoKit

/// Secure storage service using Keychain for encryption keys and encrypted UserDefaults storage
final class SecureStorage {
    private let keychainService = "app.mindfriend.secure-storage"
    private let keyIdentifier = "encryption-key"
    private let keychainQueue = DispatchQueue(label: "app.mindfriend.secure-storage.keychain", qos: .userInitiated)
    private var cachedKey: SymmetricKey?

    enum SecureStorageError: Error {
        case encryptionFailed
        case decryptionFailed
        case keychainError(OSStatus)
        case invalidData
    }

    // MARK: - Encryption Key Management

    /// Get or create encryption key from Keychain (thread-safe)
    private func getOrCreateEncryptionKey() throws -> SymmetricKey {
        try keychainQueue.sync {
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
                // Key doesn't exist - this is expected, continue to create
            } catch {
                // Unexpected error - log and rethrow
                print("⚠️ Keychain load error: \(error)")
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

        // Delete any existing key first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keyIdentifier
        ]
        let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
        
        // Log if delete failed (except item not found, which is OK)
        if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
            print("⚠️ Keychain delete warning: \(deleteStatus)")
        }

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SecureStorageError.keychainError(status)
        }
    }

    // MARK: - Encryption/Decryption

    /// Encrypt data using AES-GCM
    func encrypt<T: Codable>(_ value: T) throws -> Data {
        let key = try getOrCreateEncryptionKey()
        let jsonData = try JSONEncoder().encode(value)

        let sealedBox = try AES.GCM.seal(jsonData, using: key)
        guard let combined = sealedBox.combined else {
            throw SecureStorageError.encryptionFailed
        }

        return combined
    }

    /// Decrypt data using AES-GCM
    func decrypt<T: Codable>(_ data: Data, as type: T.Type) throws -> T {
        let key = try getOrCreateEncryptionKey()

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

    /// Delete encryption key from Keychain (e.g., on logout)
    func deleteEncryptionKey() throws {
        try keychainQueue.sync {
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
