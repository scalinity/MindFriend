import Foundation

// MARK: - Core Data Model

/// A local-only, encrypted journal entry stored in the Private Vault.
/// Never synced to cloud, never used in AI context.
struct VaultEntry: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String?
    var body: String
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String? = nil,
        body: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Display title: uses actual title or first 50 chars of body
    var displayTitle: String {
        if let title = title, !title.isEmpty {
            return title
        }
        let preview = body.prefix(50)
        return preview.count < body.count ? "\(preview)..." : String(preview)
    }
}

// MARK: - Errors

enum VaultError: LocalizedError, Equatable {
    case authenticationFailed
    case authenticationCancelled
    case authenticationUnavailable
    case passcodeNotSet
    case encryptionFailed
    case decryptionFailed
    case keyGenerationFailed
    case keyRetrievalFailed
    case keyNotFound
    case fileReadFailed
    case fileWriteFailed
    case directoryCreationFailed
    case entryNotFound(UUID)
    case invalidData
    case vaultLocked
    case emptyBody

    var errorDescription: String? {
        switch self {
        case .authenticationFailed:
            return "Biometric authentication failed. Please try again."
        case .authenticationCancelled:
            return "Authentication was cancelled."
        case .authenticationUnavailable:
            return "Biometric authentication is not available on this device."
        case .passcodeNotSet:
            return "Please set a device passcode in Settings to use Private Vault."
        case .encryptionFailed:
            return "Failed to secure your entry. Please try again."
        case .decryptionFailed:
            return "Failed to decrypt vault entry. The data may be corrupted."
        case .keyGenerationFailed:
            return "Failed to generate encryption key. Please try again."
        case .keyRetrievalFailed:
            return "Failed to access encryption key."
        case .keyNotFound:
            return "Encryption key not found. Vault must be reset."
        case .fileReadFailed:
            return "Failed to read vault entry file."
        case .fileWriteFailed:
            return "Failed to save entry. Check device storage."
        case .directoryCreationFailed:
            return "Failed to initialize vault storage."
        case .entryNotFound(let id):
            return "Vault entry not found: \(id)"
        case .invalidData:
            return "Invalid vault entry data."
        case .vaultLocked:
            return "Vault is locked. Please authenticate to access."
        case .emptyBody:
            return "Entry body cannot be empty."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .keyNotFound:
            return "Your vault entries cannot be recovered. Reset the vault to create new entries."
        case .fileWriteFailed:
            return "Free up some storage space and try again."
        case .authenticationUnavailable:
            return "This device does not support Face ID or Touch ID."
        case .passcodeNotSet:
            return "A device passcode is required for vault encryption."
        default:
            return nil
        }
    }
}

// MARK: - Encrypted File Format

/// Represents the encrypted vault data structure:
/// [nonce(12 bytes)][ciphertext(variable)][tag(16 bytes)]
struct EncryptedVaultData {
    static let nonceSize = 12
    static let tagSize = 16
    static let minimumSize = nonceSize + tagSize

    let nonce: Data       // 12 bytes - AES.GCM initialization vector
    let ciphertext: Data  // Variable length - encrypted JSON payload
    let tag: Data         // 16 bytes - GCM authentication tag

    /// Combines nonce, ciphertext, and tag into a single Data blob for storage
    var combined: Data {
        nonce + ciphertext + tag
    }

    init(nonce: Data, ciphertext: Data, tag: Data) {
        self.nonce = nonce
        self.ciphertext = ciphertext
        self.tag = tag
    }

    /// Parses combined encrypted data back into components
    init?(combined: Data) {
        guard combined.count > Self.minimumSize else { return nil }
        self.nonce = combined.prefix(Self.nonceSize)
        self.tag = combined.suffix(Self.tagSize)
        self.ciphertext = combined.dropFirst(Self.nonceSize).dropLast(Self.tagSize)
    }
}

// MARK: - Vault State

/// Tracks the current state of the vault
enum VaultState: Equatable {
    case locked
    case unlocked
    case keyMissing
    case unavailable(reason: String)
}

// MARK: - Vault Settings

/// User preferences for vault behavior
struct VaultSettings: Codable {
    var isEnabled: Bool = false
    var autoLockOnBackground: Bool = true
    var autoLockTimeoutSeconds: Int = 0 // 0 = immediate on background

    static let `default` = VaultSettings()
}
