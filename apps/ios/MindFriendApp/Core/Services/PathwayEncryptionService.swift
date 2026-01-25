import Foundation

/// Service for encrypting/decrypting sensitive data before network transmission
/// Uses local SecureStorage for end-to-end encryption
final class PathwayEncryptionService: PathwayEncryptionServiceProtocol {
    private let secureStorage: SecureStorage

    init(secureStorage: SecureStorage = SecureStorage()) {
        self.secureStorage = secureStorage
    }

    // MARK: - String Encryption

    /// Encrypt a string (e.g., journal entry, notes) and return base64-encoded ciphertext
    func encryptString(_ text: String?) throws -> String? {
        guard let text = text, !text.isEmpty else {
            return nil
        }

        let encryptedData = try secureStorage.encrypt(text)
        return encryptedData.base64EncodedString()
    }

    /// Decrypt a base64-encoded ciphertext back to string
    func decryptString(_ base64Encrypted: String?) throws -> String? {
        guard let base64Encrypted = base64Encrypted,
              !base64Encrypted.isEmpty,
              let encryptedData = Data(base64Encoded: base64Encrypted) else {
            return nil
        }

        return try secureStorage.decrypt(encryptedData, as: String.self)
    }

    // MARK: - JSON Encryption

    /// Encrypt any Codable value and return base64-encoded ciphertext
    func encryptJSON<T: Codable>(_ value: T?) throws -> String? {
        guard let value = value else {
            return nil
        }

        let encryptedData = try secureStorage.encrypt(value)
        return encryptedData.base64EncodedString()
    }

    /// Decrypt base64-encoded ciphertext back to Codable value
    func decryptJSON<T: Codable>(_ base64Encrypted: String?, as type: T.Type) throws -> T? {
        guard let base64Encrypted = base64Encrypted,
              !base64Encrypted.isEmpty,
              let encryptedData = Data(base64Encoded: base64Encrypted) else {
            return nil
        }

        return try secureStorage.decrypt(encryptedData, as: type)
    }
}
