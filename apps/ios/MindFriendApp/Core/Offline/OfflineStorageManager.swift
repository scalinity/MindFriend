//
//  OfflineStorageManager.swift
//  MindFriendApp
//
//  Manages local file storage for offline content
//

import Foundation
import CryptoKit

/// Immutable identity of one bound offline lifecycle.
///
/// A binding is the pair of authenticated owner and account epoch. Work started
/// under a binding must present it back to storage so late completions from a
/// previous account (or a previous login of the same account) are rejected.
struct OfflineOwnerBinding: Hashable, Sendable {
    let userId: String
    let epoch: UInt64
}

enum OfflineStorageError: Error, Equatable, LocalizedError {
    /// No authenticated owner is bound; identityless storage is never used.
    case notBound
    /// The caller's binding is no longer the current lifecycle.
    case staleBinding
    /// The requested epoch is not newer than a lifecycle that already ended.
    case staleEpoch
    case invalidUserId
    /// The owner is the live bound owner, so its files cannot be removed.
    case ownerIsBound

    var errorDescription: String? {
        switch self {
        case .notBound: return "Offline storage is not available until you are signed in."
        case .staleBinding: return "Offline storage changed accounts; the operation was discarded."
        case .staleEpoch: return "Offline storage rejected an out-of-date sign-in."
        case .invalidUserId: return "Offline storage rejected an invalid account identifier."
        case .ownerIsBound: return "Offline data for the signed-in account cannot be removed."
        }
    }
}

/// Result of removing an account's local offline data.
enum OfflinePurgeOutcome: Equatable, Sendable {
    case removedAll
    case nothingToRemove
    /// Unsynced queued work was kept (the queue file only); everything else removed.
    case preservedUnsynced(pendingCount: Int)
    /// The queue file exists but could not be read; it was kept untouched.
    case preservedUnreadableQueue
    /// No live queue work, but quarantined recovery copies of an unreadable queue were kept.
    case preservedRecoveryCopies(count: Int)
}

/// Manages file storage for downloaded offline content
actor OfflineStorageManager {

    // MARK: - Singleton

    static let shared = OfflineStorageManager()

    // MARK: - Properties

    private let fileManager = FileManager.default
    private let appSupportDirectory: URL
    private var binding: OfflineOwnerBinding?
    private var highestEpoch: UInt64?

    private static let rootComponent = "MindFriend/Offline"
    private static let legacySharedComponent = "shared"

    private func userDirectory(for userId: String) -> URL {
        appSupportDirectory
            .appendingPathComponent(Self.rootComponent, isDirectory: true)
            .appendingPathComponent(userId, isDirectory: true)
    }

    /// Resolves the directory for the caller's binding. EVERY account-scoped
    /// read or write goes through here with the owner/epoch the caller captured
    /// when its work started, and it is checked synchronously inside the actor
    /// immediately before the filesystem touch, so a task resuming after an
    /// account change can never reach the new account's folder. Never falls
    /// back to a shared directory.
    private func requireBase(for expected: OfflineOwnerBinding) throws -> URL {
        guard let live = binding else { throw OfflineStorageError.notBound }
        guard live == expected else { throw OfflineStorageError.staleBinding }
        return userDirectory(for: live.userId)
    }

    private func contentDir(_ base: URL) -> URL { base.appendingPathComponent("Content", isDirectory: true) }
    private func metadataDir(_ base: URL) -> URL { base.appendingPathComponent("Metadata", isDirectory: true) }
    private func tempDir(_ base: URL) -> URL { base.appendingPathComponent("Temp", isDirectory: true) }

    // MARK: - Initialization

    init() {
        // Use Application Support directory for durability (not cleared like Caches)
        appSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }

    /// Test/embedding seam: roots storage in a caller-provided directory.
    init(rootDirectory: URL) {
        appSupportDirectory = rootDirectory
    }

    // MARK: - Binding

    static func isValidUserId(_ userId: String) -> Bool {
        guard !userId.isEmpty, userId.count <= 128 else { return false }
        return userId.unicodeScalars.allSatisfy {
            ($0.value >= 0x30 && $0.value <= 0x39) || ($0.value >= 0x41 && $0.value <= 0x5A)
                || ($0.value >= 0x61 && $0.value <= 0x7A) || $0 == "-" || $0 == "_"
        }
    }

    /// Bind storage to an authenticated owner and account epoch. Call after user
    /// restoration and before any user data is loaded.
    ///
    /// Re-binding the identical owner/epoch is idempotent. A different binding
    /// must carry a strictly greater epoch than every previous lifecycle; that
    /// supersedes the old binding, so its late tasks fail with `staleBinding`.
    @discardableResult
    func bind(userId: String, epoch: UInt64) throws -> OfflineOwnerBinding {
        guard Self.isValidUserId(userId) else { throw OfflineStorageError.invalidUserId }
        let requested = OfflineOwnerBinding(userId: userId, epoch: epoch)
        if binding == requested { return requested }
        if let highestEpoch, epoch <= highestEpoch { throw OfflineStorageError.staleEpoch }

        let base = userDirectory(for: userId)
        for directory in [base, contentDir(base), metadataDir(base), tempDir(base)] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        binding = requested
        highestEpoch = epoch
        return requested
    }

    /// End the lifecycle. Only the live binding can unbind, so a late logout
    /// cleanup for an old epoch cannot tear down a newer sign-in.
    func unbind(_ expected: OfflineOwnerBinding) {
        guard binding == expected else { return }
        binding = nil
    }

    func currentBinding() -> OfflineOwnerBinding? { binding }

    func getCurrentUserId() -> String? { binding?.userId }

    /// True when a pre-binding identityless folder from an older build exists.
    /// It is never read implicitly and never deleted without a user decision.
    func hasLegacySharedData() -> Bool {
        let legacy = appSupportDirectory
            .appendingPathComponent(Self.rootComponent, isDirectory: true)
            .appendingPathComponent(Self.legacySharedComponent, isDirectory: true)
        return fileManager.fileExists(atPath: legacy.path)
    }

    // MARK: - Removal

    /// Logout cleanup: remove an account's local offline data but keep unsynced
    /// queued work (the queue file) so it is not silently destroyed. The
    /// owner stays segregated by user directory, so it is never visible to
    /// another account. Refuses while that owner is the live binding.
    @discardableResult
    func purgeUserData(userId: String) throws -> OfflinePurgeOutcome {
        guard Self.isValidUserId(userId) else { throw OfflineStorageError.invalidUserId }
        if binding?.userId == userId { throw OfflineStorageError.ownerIsBound }
        let base = userDirectory(for: userId)
        guard fileManager.fileExists(atPath: base.path) else { return .nothingToRemove }

        // Everything belonging to the sync queue is irreplaceable user work or
        // its only recovery copy: the live queue file (when unsynced items or
        // unreadable) AND any quarantined `.corrupt-*` copies, even when the
        // live queue file is absent or an empty replacement.
        let queuePrefix = "\(OfflineCacheKey.syncQueue.rawValue).json"
        let metadata = metadataDir(base)
        let names = (try? fileManager.contentsOfDirectory(atPath: metadata.path)) ?? []
        let quarantined = names.filter { $0.hasPrefix("\(queuePrefix).corrupt-") }

        var preserved: OfflinePurgeOutcome?
        let queueFile = metadata.appendingPathComponent(queuePrefix)
        if fileManager.fileExists(atPath: queueFile.path) {
            do {
                let data = try Data(contentsOf: queueFile)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let queue = try decoder.decode(OfflineSyncQueue.self, from: data)
                if queue.hasPendingItems { preserved = .preservedUnsynced(pendingCount: queue.totalPending) }
            } catch {
                preserved = .preservedUnreadableQueue
            }
        }
        if preserved == nil, !quarantined.isEmpty {
            preserved = .preservedRecoveryCopies(count: quarantined.count)
        }

        guard let preserved else {
            try fileManager.removeItem(at: base)
            return .removedAll
        }

        // Keep only the queue file and recovery copies.
        for entry in try fileManager.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)
        where entry.lastPathComponent != "Metadata" {
            try fileManager.removeItem(at: entry)
        }
        for entry in try fileManager.contentsOfDirectory(at: metadata, includingPropertiesForKeys: nil)
        where !entry.lastPathComponent.hasPrefix(queuePrefix) {
            try fileManager.removeItem(at: entry)
        }
        return preserved
    }

    /// Explicit, user-confirmed discard of ALL of an account's local data,
    /// including unsynced work. Refuses while the owner is bound.
    func deleteUserData(userId: String) throws {
        guard Self.isValidUserId(userId) else { throw OfflineStorageError.invalidUserId }
        if binding?.userId == userId { throw OfflineStorageError.ownerIsBound }
        let directory = userDirectory(for: userId)
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
    }

    // MARK: - Directory Management

    /// Get the base directory URL
    func getBaseDirectory(binding: OfflineOwnerBinding) throws -> URL {
        try requireBase(for: binding)
    }

    /// Get the content directory URL
    func getContentDirectory(binding: OfflineOwnerBinding) throws -> URL {
        contentDir(try requireBase(for: binding))
    }

    // MARK: - File Operations

    /// Move a downloaded file from temp location to permanent storage.
    /// The binding is verified before anything is removed or moved.
    func moveToStorage(
        from tempLocation: URL,
        contentId: UUID,
        fileExtension: String,
        binding: OfflineOwnerBinding
    ) throws -> URL {
        let contentDirectory = contentDir(try requireBase(for: binding))
        try fileManager.createDirectory(at: contentDirectory, withIntermediateDirectories: true)
        let fileName = "\(contentId.uuidString).\(fileExtension)"
        let destination = contentDirectory.appendingPathComponent(fileName)

        // Remove existing file if present
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        // Move file to storage
        try fileManager.moveItem(at: tempLocation, to: destination)

        // Set file protection
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: destination.path
        )

        return destination
    }

    /// Copy a file to temp directory for download resumption
    func copyToTemp(from source: URL, taskId: UUID, binding: OfflineOwnerBinding) throws -> URL {
        let directory = tempDir(try requireBase(for: binding))
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("\(taskId.uuidString).tmp")

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        try fileManager.copyItem(at: source, to: destination)
        return destination
    }

    /// Get the local file path for content
    func localPath(for contentId: UUID, fileExtension: String, binding: OfflineOwnerBinding) throws -> URL {
        let fileName = "\(contentId.uuidString).\(fileExtension)"
        return contentDir(try requireBase(for: binding)).appendingPathComponent(fileName)
    }

    /// Check if content file exists locally
    func fileExists(for contentId: UUID, fileExtension: String, binding: OfflineOwnerBinding) throws -> Bool {
        let path = try localPath(for: contentId, fileExtension: fileExtension, binding: binding)
        return fileManager.fileExists(atPath: path.path)
    }

    /// Delete a content file
    func deleteFile(for contentId: UUID, fileExtension: String, binding: OfflineOwnerBinding) throws {
        let path = try localPath(for: contentId, fileExtension: fileExtension, binding: binding)
        if fileManager.fileExists(atPath: path.path) {
            try fileManager.removeItem(at: path)
        }
    }

    /// Remove a file this binding previously moved into its own content folder.
    /// Refuses (leaves the file) if the lifecycle has ended, so a late cleanup
    /// can never delete a newer lifecycle's file with the same content ID.
    func removeStoredFile(at url: URL, binding: OfflineOwnerBinding) throws {
        let contentDirectory = contentDir(try requireBase(for: binding))
        guard url.deletingLastPathComponent().standardizedFileURL == contentDirectory.standardizedFileURL else {
            throw OfflineStorageError.staleBinding
        }
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    /// Delete all content files
    func deleteAllContent(binding: OfflineOwnerBinding) throws {
        let directory = contentDir(try requireBase(for: binding))
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    /// Clean up temporary files
    func cleanupTempFiles(binding: OfflineOwnerBinding) throws {
        let directory = tempDir(try requireBase(for: binding))
        if fileManager.fileExists(atPath: directory.path) {
            let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            for file in contents {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    // MARK: - File Size Operations

    /// Get the size of a specific file
    func fileSize(for contentId: UUID, fileExtension: String, binding: OfflineOwnerBinding) throws -> Int64 {
        let path = try localPath(for: contentId, fileExtension: fileExtension, binding: binding)
        let attributes = try fileManager.attributesOfItem(atPath: path.path)
        return attributes[.size] as? Int64 ?? 0
    }

    /// Get total size of all downloaded content
    func totalStorageUsed(binding: OfflineOwnerBinding) throws -> Int64 {
        let directory = contentDir(try requireBase(for: binding))
        guard fileManager.fileExists(atPath: directory.path) else { return 0 }

        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: .skipsHiddenFiles
        )

        return try contents.reduce(0) { total, url in
            let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
            return total + Int64(resourceValues.fileSize ?? 0)
        }
    }

    /// Get available device storage
    func availableDeviceStorage() throws -> Int64 {
        let resourceValues = try URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return resourceValues.volumeAvailableCapacityForImportantUsage ?? 0
    }

    /// Check if there's enough space for a download
    func hasEnoughSpace(for bytes: Int64, currentLimit: Int64, binding: OfflineOwnerBinding) throws -> Bool {
        let currentUsage = try totalStorageUsed(binding: binding)
        let availableInLimit = currentLimit - currentUsage
        let deviceAvailable = try availableDeviceStorage()

        // Must fit within both user limit and device storage
        return bytes <= availableInLimit && bytes <= deviceAvailable
    }

    // MARK: - Checksum Verification

    /// Calculate SHA-256 checksum of a file
    func calculateChecksum(for url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Verify file integrity using checksum
    func verifyChecksum(for contentId: UUID, fileExtension: String, expectedChecksum: String, binding: OfflineOwnerBinding) throws -> Bool {
        let path = try localPath(for: contentId, fileExtension: fileExtension, binding: binding)
        let actualChecksum = try calculateChecksum(for: path)
        return actualChecksum == expectedChecksum
    }

    // MARK: - Metadata Storage

    /// Save metadata to disk atomically. The caller's captured binding is
    /// verified inside the actor immediately before the write.
    func saveMetadata<T: Codable>(_ data: T, key: String, binding: OfflineOwnerBinding) throws {
        let directory = metadataDir(try requireBase(for: binding))
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("\(key).json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(data)
        // Atomic replace: write a sibling temp file, then rename over the target.
        // Staying in the same directory keeps the rename atomic and independent
        // of any system temporary directory.
        let staging = directory.appendingPathComponent(".\(key).json.\(UUID().uuidString).tmp")
        do {
            #if os(iOS)
            try encoded.write(to: staging, options: [.completeFileProtectionUntilFirstUserAuthentication])
            #else
            try encoded.write(to: staging)
            #endif
            if rename(staging.path, path.path) != 0 {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    /// Load metadata from disk. Returns nil only when the file does not exist;
    /// unreadable or undecodable data throws so callers never mistake
    /// corruption for an empty state.
    func loadMetadata<T: Codable>(key: String, as type: T.Type, binding: OfflineOwnerBinding) throws -> T? {
        let path = metadataDir(try requireBase(for: binding)).appendingPathComponent("\(key).json")
        guard fileManager.fileExists(atPath: path.path) else { return nil }
        let data = try Data(contentsOf: path)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    /// Move an unreadable metadata file aside (same owner folder) so it is kept
    /// for recovery and a fresh state can start without silent loss.
    @discardableResult
    func quarantineMetadata(key: String, binding: OfflineOwnerBinding) throws -> URL? {
        let directory = metadataDir(try requireBase(for: binding))
        let path = directory.appendingPathComponent("\(key).json")
        guard fileManager.fileExists(atPath: path.path) else { return nil }
        let stamp = Int(Date().timeIntervalSince1970)
        var target = directory.appendingPathComponent("\(key).json.corrupt-\(stamp)")
        var suffix = 1
        while fileManager.fileExists(atPath: target.path) {
            target = directory.appendingPathComponent("\(key).json.corrupt-\(stamp)-\(suffix)")
            suffix += 1
        }
        try fileManager.moveItem(at: path, to: target)
        return target
    }

    /// Quarantined recovery copies for a key, oldest name first. Survives relaunch.
    func quarantinedMetadata(key: String, binding: OfflineOwnerBinding) throws -> [URL] {
        let directory = metadataDir(try requireBase(for: binding))
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        let prefix = "\(key).json.corrupt-"
        return try fileManager.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(prefix) }
            .sorted()
            .map { directory.appendingPathComponent($0) }
    }

    /// Permanently delete quarantined recovery copies. Only call after an
    /// explicit user decision (export or discard).
    func deleteQuarantinedMetadata(key: String, binding: OfflineOwnerBinding) throws {
        for url in try quarantinedMetadata(key: key, binding: binding) {
            try fileManager.removeItem(at: url)
        }
    }

    /// Delete metadata
    func deleteMetadata(key: String, binding: OfflineOwnerBinding) throws {
        let path = metadataDir(try requireBase(for: binding)).appendingPathComponent("\(key).json")
        if fileManager.fileExists(atPath: path.path) {
            try fileManager.removeItem(at: path)
        }
    }

    // MARK: - Content Index

    /// Save the downloaded content index
    func saveContentIndex(_ content: [DownloadedContent], binding: OfflineOwnerBinding) throws {
        try saveMetadata(content, key: OfflineCacheKey.downloadedContentIndex.rawValue, binding: binding)
    }

    /// Load the downloaded content index
    func loadContentIndex(binding: OfflineOwnerBinding) throws -> [DownloadedContent] {
        try loadMetadata(key: OfflineCacheKey.downloadedContentIndex.rawValue, as: [DownloadedContent].self, binding: binding) ?? []
    }

    // MARK: - LRU Eviction

    /// Get content sorted by last accessed time (oldest first)
    func getContentByLRU(_ content: [DownloadedContent]) -> [DownloadedContent] {
        content.sorted { $0.lastAccessedAt < $1.lastAccessedAt }
    }

    /// Evict content to free up space
    func evictOldContent(
        from content: inout [DownloadedContent],
        toFreeBytes: Int64,
        binding: OfflineOwnerBinding
    ) throws -> [UUID] {
        var freedBytes: Int64 = 0
        var evictedIds: [UUID] = []

        let sorted = getContentByLRU(content)

        for item in sorted {
            guard freedBytes < toFreeBytes else { break }

            // Get file extension from the local path
            let fileExtension = item.localFilePath.pathExtension

            // Delete the file
            try deleteFile(for: item.id, fileExtension: fileExtension, binding: binding)

            freedBytes += item.fileSize
            evictedIds.append(item.id)
        }

        // Remove evicted items from the array
        content.removeAll { evictedIds.contains($0.id) }

        return evictedIds
    }

    // MARK: - Utility

    /// List all files in the content directory
    func listContentFiles(binding: OfflineOwnerBinding) throws -> [URL] {
        let directory = contentDir(try requireBase(for: binding))
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        return try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
            options: .skipsHiddenFiles
        )
    }

    /// Get file attributes
    func getFileAttributes(for url: URL) throws -> [FileAttributeKey: Any] {
        try fileManager.attributesOfItem(atPath: url.path)
    }
}

// MARK: - Storage Info

/// Information about current storage usage
struct StorageInfo: Equatable {
    let used: Int64
    let limit: Int64
    let deviceAvailable: Int64
    let itemCount: Int

    var usedFormatted: String {
        ByteCountFormatter.string(fromByteCount: used, countStyle: .file)
    }

    var limitFormatted: String {
        ByteCountFormatter.string(fromByteCount: limit, countStyle: .file)
    }

    var deviceAvailableFormatted: String {
        ByteCountFormatter.string(fromByteCount: deviceAvailable, countStyle: .file)
    }

    var usagePercentage: Double {
        guard limit > 0 else { return 0 }
        return Double(used) / Double(limit)
    }

    var isNearLimit: Bool {
        usagePercentage >= 0.9
    }

    var isOverLimit: Bool {
        used >= limit
    }

    var availableInLimit: Int64 {
        max(0, limit - used)
    }

    var availableInLimitFormatted: String {
        ByteCountFormatter.string(fromByteCount: availableInLimit, countStyle: .file)
    }
}
