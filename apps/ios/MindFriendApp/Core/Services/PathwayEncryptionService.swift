import Foundation

/// Service for encrypting/decrypting sensitive data before network transmission
/// Uses local SecureStorage for end-to-end encryption
final class PathwayEncryptionService: PathwayEncryptionServiceProtocol {
    private let legacyStorage: SecureStorage
    private let storageForUser: (UUID) -> SecureStorage
    private let ownerLock = NSLock()
    private var userId: UUID?

    private struct Envelope: Codable {
        let version: Int
        let userId: UUID
        let ciphertext: Data
    }

    enum EncryptionError: Error {
        case accountUnavailable
        case wrongAccount
    }

    init(
        secureStorage: SecureStorage = SecureStorage(),
        userId: UUID? = nil,
        storageForUser: @escaping (UUID) -> SecureStorage = {
            SecureStorage(keyIdentifier: "pathway.\($0.uuidString.lowercased())")
        }
    ) {
        self.legacyStorage = secureStorage
        self.userId = userId
        self.storageForUser = storageForUser
    }

    func setCurrentUser(_ userId: UUID?) {
        ownerLock.lock()
        self.userId = userId
        ownerLock.unlock()
        legacyStorage.clearCachedKey()
    }

    private func currentUser() throws -> UUID {
        ownerLock.lock()
        defer { ownerLock.unlock() }
        guard let userId else { throw EncryptionError.accountUnavailable }
        return userId
    }

    private func encrypt<T: Codable>(_ value: T) throws -> String {
        let owner = try currentUser()
        let ciphertext = try storageForUser(owner).encrypt(value)
        guard try currentUser() == owner else { throw EncryptionError.wrongAccount }
        return try JSONEncoder().encode(Envelope(version: 2, userId: owner, ciphertext: ciphertext)).base64EncodedString()
    }

    private func decrypt<T: Codable>(_ data: Data, as type: T.Type) throws -> T {
        let owner = try currentUser()
        let result: T
        if let envelope = try? JSONDecoder().decode(Envelope.self, from: data) {
            guard envelope.version == 2, envelope.userId == owner else { throw EncryptionError.wrongAccount }
            result = try storageForUser(owner).decrypt(envelope.ciphertext, as: type)
        } else {
            // Existing backend journals used this installation key. Keep it for those
            // owner-authorized records; new records always use an account-specific key.
            result = try legacyStorage.decrypt(data, as: type)
        }
        guard try currentUser() == owner else { throw EncryptionError.wrongAccount }
        return result
    }

    // MARK: - String Encryption

    /// Encrypt a string (e.g., journal entry, notes) and return base64-encoded ciphertext
    func encryptString(_ text: String?) throws -> String? {
        guard let text = text, !text.isEmpty else {
            return nil
        }

        return try encrypt(text)
    }

    /// Decrypt a base64-encoded ciphertext back to string
    func decryptString(_ base64Encrypted: String?) throws -> String? {
        guard let base64Encrypted = base64Encrypted,
              !base64Encrypted.isEmpty,
              let encryptedData = Data(base64Encoded: base64Encrypted) else {
            return nil
        }

        return try decrypt(encryptedData, as: String.self)
    }

    // MARK: - JSON Encryption

    /// Encrypt any Codable value and return base64-encoded ciphertext
    func encryptJSON<T: Codable>(_ value: T?) throws -> String? {
        guard let value = value else {
            return nil
        }

        return try encrypt(value)
    }

    /// Decrypt base64-encoded ciphertext back to Codable value
    func decryptJSON<T: Codable>(_ base64Encrypted: String?, as type: T.Type) throws -> T? {
        guard let base64Encrypted = base64Encrypted,
              !base64Encrypted.isEmpty,
              let encryptedData = Data(base64Encoded: base64Encrypted) else {
            return nil
        }

        return try decrypt(encryptedData, as: type)
    }
}
