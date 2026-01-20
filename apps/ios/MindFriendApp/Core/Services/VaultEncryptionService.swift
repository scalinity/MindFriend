import CryptoKit
import Foundation

// MARK: - Protocol

protocol VaultEncrypting: Actor {
    func encrypt(_ entry: VaultEntry) async throws -> Data
    func decrypt(_ data: Data) async throws -> VaultEntry
    func generateKey() async throws
    func deleteKey() async throws
    func keyExists() async -> Bool
}

// MARK: - Implementation

/// Actor-isolated encryption service using AES.GCM 256-bit encryption.
/// Key is stored in Keychain with device-only accessibility (no backup/sync).
actor VaultEncryptionService: VaultEncrypting {

    // MARK: - Constants

    private let keychainService = "com.mindfriend.vault"
    private let keychainAccount = "encryption-key"

    // MARK: - Cached State

    /// Cache key in memory after first retrieval for performance
    private var cachedKey: SymmetricKey?

    // MARK: - Public Interface

    /// Encrypts a VaultEntry to a Data blob containing nonce + ciphertext + tag
    func encrypt(_ entry: VaultEntry) async throws -> Data {
        let key = try await getOrCreateKey()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let plaintext = try encoder.encode(entry)

        guard let sealedBox = try? AES.GCM.seal(plaintext, using: key) else {
            throw VaultError.encryptionFailed
        }

        let encrypted = EncryptedVaultData(
            nonce: sealedBox.nonce.withUnsafeBytes { Data($0) },
            ciphertext: sealedBox.ciphertext,
            tag: sealedBox.tag
        )

        return encrypted.combined
    }

    /// Decrypts a Data blob back to a VaultEntry
    func decrypt(_ data: Data) async throws -> VaultEntry {
        let key = try await getKey()

        guard let encrypted = EncryptedVaultData(combined: data) else {
            throw VaultError.invalidData
        }

        guard let nonce = try? AES.GCM.Nonce(data: encrypted.nonce) else {
            throw VaultError.invalidData
        }

        guard let sealedBox = try? AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: encrypted.ciphertext,
            tag: encrypted.tag
        ) else {
            throw VaultError.invalidData
        }

        guard let plaintext = try? AES.GCM.open(sealedBox, using: key) else {
            throw VaultError.decryptionFailed
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(VaultEntry.self, from: plaintext)
        } catch {
            throw VaultError.invalidData
        }
    }

    /// Generates a new 256-bit AES encryption key and stores it in Keychain
    func generateKey() async throws {
        let key = SymmetricKey(size: .bits256)
        try saveKeyToKeychain(key)
        cachedKey = key
    }

    /// Deletes the encryption key from Keychain (for vault reset)
    func deleteKey() async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw VaultError.keyRetrievalFailed
        }

        cachedKey = nil
    }

    /// Checks if an encryption key exists in Keychain
    func keyExists() async -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: false
        ]

        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    // MARK: - Private Helpers

    /// Gets existing key or creates one if none exists
    private func getOrCreateKey() async throws -> SymmetricKey {
        if let cached = cachedKey {
            return cached
        }

        if await keyExists() {
            let key = try retrieveKeyFromKeychain()
            cachedKey = key
            return key
        } else {
            try await generateKey()
            guard let key = cachedKey else {
                throw VaultError.keyGenerationFailed
            }
            return key
        }
    }

    /// Gets existing key, throws if none exists
    private func getKey() async throws -> SymmetricKey {
        if let cached = cachedKey {
            return cached
        }

        guard await keyExists() else {
            throw VaultError.keyNotFound
        }

        let key = try retrieveKeyFromKeychain()
        cachedKey = key
        return key
    }

    /// Retrieves the encryption key from Keychain
    private func retrieveKeyFromKeychain() throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let keyData = result as? Data else {
            throw VaultError.keyRetrievalFailed
        }

        return SymmetricKey(data: keyData)
    }

    /// Saves the encryption key to Keychain with device-only accessibility
    private func saveKeyToKeychain(_ key: SymmetricKey) throws {
        let keyData = key.withUnsafeBytes { Data($0) }

        // Delete any existing key first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add the new key
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: keyData
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw VaultError.keyGenerationFailed
        }
    }
}
