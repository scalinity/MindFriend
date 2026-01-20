import Foundation

// MARK: - Protocol

protocol VaultStoring: Actor {
    func listEntries() async throws -> [VaultEntry]
    func saveEntry(_ entry: VaultEntry) async throws
    func deleteEntry(_ id: UUID) async throws
    func getEntry(_ id: UUID) async throws -> VaultEntry
    func deleteAllEntries() async throws
    func entryCount() async -> Int
}

// MARK: - Implementation

/// Actor-isolated file storage service for encrypted vault entries.
/// Stores files in Application Support/MindFriend/Vault/ with backup exclusion.
actor VaultStorageService: VaultStoring {

    // MARK: - Constants

    private let fileExtension = "vaultentry"
    private let vaultDirectoryName = "Vault"
    private let appDirectoryName = "MindFriend"

    // MARK: - Dependencies

    private let encryptionService: VaultEncrypting
    private let fileManager: FileManager

    // MARK: - Cached State

    private var vaultDirectoryURL: URL?

    // MARK: - Initialization

    init(encryptionService: VaultEncrypting, fileManager: FileManager = .default) {
        self.encryptionService = encryptionService
        self.fileManager = fileManager
    }

    // MARK: - Public Interface

    /// Lists all vault entries, sorted by updatedAt (newest first)
    func listEntries() async throws -> [VaultEntry] {
        let directory = try await getVaultDirectory()

        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
        } catch {
            // Directory might not exist yet, return empty list
            return []
        }

        var entries: [VaultEntry] = []
        for fileURL in contents where fileURL.pathExtension == fileExtension {
            do {
                let entry = try await loadEntry(from: fileURL)
                entries.append(entry)
            } catch {
                // Log error but continue processing other files
                // Corrupted files are skipped
                print("[Vault] Failed to load entry from \(fileURL.lastPathComponent): \(error)")
            }
        }

        // Sort by updatedAt descending (newest first)
        return entries.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Saves (creates or updates) a vault entry
    func saveEntry(_ entry: VaultEntry) async throws {
        let directory = try await getVaultDirectory()
        let fileURL = directory.appendingPathComponent("\(entry.id.uuidString).\(fileExtension)")

        let encryptedData = try await encryptionService.encrypt(entry)

        // Atomic write: write to .tmp, then rename
        let tmpURL = fileURL.appendingPathExtension("tmp")

        do {
            try encryptedData.write(to: tmpURL, options: .atomic)

            // Remove existing file if it exists
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }

            // Move temp file to final location
            try fileManager.moveItem(at: tmpURL, to: fileURL)
        } catch {
            // Clean up temp file on failure
            try? fileManager.removeItem(at: tmpURL)
            throw VaultError.fileWriteFailed
        }
    }

    /// Deletes a vault entry by ID
    func deleteEntry(_ id: UUID) async throws {
        let directory = try await getVaultDirectory()
        let fileURL = directory.appendingPathComponent("\(id.uuidString).\(fileExtension)")

        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw VaultError.entryNotFound(id)
        }

        do {
            try fileManager.removeItem(at: fileURL)
        } catch {
            throw VaultError.fileWriteFailed
        }
    }

    /// Gets a single vault entry by ID
    func getEntry(_ id: UUID) async throws -> VaultEntry {
        let directory = try await getVaultDirectory()
        let fileURL = directory.appendingPathComponent("\(id.uuidString).\(fileExtension)")

        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw VaultError.entryNotFound(id)
        }

        return try await loadEntry(from: fileURL)
    }

    /// Deletes all vault entries (for vault reset)
    func deleteAllEntries() async throws {
        let directory = try await getVaultDirectory()

        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
        } catch {
            return // Nothing to delete
        }

        for fileURL in contents where fileURL.pathExtension == fileExtension {
            try? fileManager.removeItem(at: fileURL)
        }
    }

    /// Returns the number of entries in the vault
    func entryCount() async -> Int {
        guard let directory = try? await getVaultDirectory() else {
            return 0
        }

        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            return 0
        }

        return contents.filter { $0.pathExtension == fileExtension }.count
    }

    // MARK: - Private Helpers

    /// Gets or creates the vault directory with backup exclusion
    private func getVaultDirectory() async throws -> URL {
        // Return cached directory if available
        if let cached = vaultDirectoryURL {
            return cached
        }

        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let vaultDir = appSupport
            .appendingPathComponent(appDirectoryName, isDirectory: true)
            .appendingPathComponent(vaultDirectoryName, isDirectory: true)

        var isDirectory: ObjCBool = false
        if !fileManager.fileExists(atPath: vaultDir.path, isDirectory: &isDirectory) {
            do {
                try fileManager.createDirectory(
                    at: vaultDir,
                    withIntermediateDirectories: true,
                    attributes: nil
                )

                // Exclude directory from iCloud backup
                try excludeFromBackup(url: vaultDir)
            } catch {
                throw VaultError.directoryCreationFailed
            }
        } else if !isDirectory.boolValue {
            throw VaultError.directoryCreationFailed
        }

        vaultDirectoryURL = vaultDir
        return vaultDir
    }

    /// Loads and decrypts a vault entry from a file
    private func loadEntry(from url: URL) async throws -> VaultEntry {
        let encryptedData: Data
        do {
            encryptedData = try Data(contentsOf: url)
        } catch {
            throw VaultError.fileReadFailed
        }

        return try await encryptionService.decrypt(encryptedData)
    }

    /// Excludes a URL from iCloud/iTunes backup
    private func excludeFromBackup(url: URL) throws {
        var mutableURL = url
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try mutableURL.setResourceValues(resourceValues)
    }
}
