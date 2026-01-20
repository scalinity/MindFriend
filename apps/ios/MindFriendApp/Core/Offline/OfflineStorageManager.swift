//
//  OfflineStorageManager.swift
//  MindFriendApp
//
//  Manages local file storage for offline content
//

import Foundation
import CryptoKit

/// Manages file storage for downloaded offline content
actor OfflineStorageManager {

    // MARK: - Singleton

    static let shared = OfflineStorageManager()

    // MARK: - Properties

    private let fileManager = FileManager.default
    private let appSupportDirectory: URL
    private var currentUserId: String?

    private var baseDirectory: URL {
        guard let userId = currentUserId else {
            // Fallback to shared directory (should only happen before login)
            return appSupportDirectory.appendingPathComponent("MindFriend/Offline/shared", isDirectory: true)
        }
        return appSupportDirectory.appendingPathComponent("MindFriend/Offline/\(userId)", isDirectory: true)
    }

    private var contentDirectory: URL {
        baseDirectory.appendingPathComponent("Content", isDirectory: true)
    }

    private var metadataDirectory: URL {
        baseDirectory.appendingPathComponent("Metadata", isDirectory: true)
    }

    private var tempDirectory: URL {
        baseDirectory.appendingPathComponent("Temp", isDirectory: true)
    }

    // MARK: - Initialization

    init() {
        // Use Application Support directory for durability (not cleared like Caches)
        appSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }

    // MARK: - User Management

    /// Set the current user ID - MUST be called after login before any storage operations
    func setCurrentUser(_ userId: String) {
        self.currentUserId = userId
        createDirectoriesIfNeeded()
    }

    /// Clear user ID on logout
    func clearCurrentUser() {
        self.currentUserId = nil
    }

    /// Get current user ID
    func getCurrentUserId() -> String? {
        currentUserId
    }

    /// Delete all data for a specific user (for logout cleanup)
    func deleteUserData(userId: String) throws {
        let userDirectory = appSupportDirectory.appendingPathComponent("MindFriend/Offline/\(userId)", isDirectory: true)
        if fileManager.fileExists(atPath: userDirectory.path) {
            try fileManager.removeItem(at: userDirectory)
        }
    }

    /// Delete all offline data for current user
    func deleteCurrentUserData() throws {
        guard let userId = currentUserId else { return }
        try deleteUserData(userId: userId)
    }

    // MARK: - Directory Management

    private func createDirectoriesIfNeeded() {
        let directories = [baseDirectory, contentDirectory, metadataDirectory, tempDirectory]
        for directory in directories {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    /// Get the base directory URL
    func getBaseDirectory() -> URL {
        baseDirectory
    }

    /// Get the content directory URL
    func getContentDirectory() -> URL {
        contentDirectory
    }

    // MARK: - File Operations

    /// Move a downloaded file from temp location to permanent storage
    func moveToStorage(
        from tempLocation: URL,
        contentId: UUID,
        fileExtension: String
    ) throws -> URL {
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
    func copyToTemp(from source: URL, taskId: UUID) throws -> URL {
        let destination = tempDirectory.appendingPathComponent("\(taskId.uuidString).tmp")

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        try fileManager.copyItem(at: source, to: destination)
        return destination
    }

    /// Get the local file path for content
    func localPath(for contentId: UUID, fileExtension: String) -> URL {
        let fileName = "\(contentId.uuidString).\(fileExtension)"
        return contentDirectory.appendingPathComponent(fileName)
    }

    /// Check if content file exists locally
    func fileExists(for contentId: UUID, fileExtension: String) -> Bool {
        let path = localPath(for: contentId, fileExtension: fileExtension)
        return fileManager.fileExists(atPath: path.path)
    }

    /// Delete a content file
    func deleteFile(for contentId: UUID, fileExtension: String) throws {
        let path = localPath(for: contentId, fileExtension: fileExtension)
        if fileManager.fileExists(atPath: path.path) {
            try fileManager.removeItem(at: path)
        }
    }

    /// Delete all content files
    func deleteAllContent() throws {
        if fileManager.fileExists(atPath: contentDirectory.path) {
            try fileManager.removeItem(at: contentDirectory)
            try fileManager.createDirectory(at: contentDirectory, withIntermediateDirectories: true)
        }
    }

    /// Clean up temporary files
    func cleanupTempFiles() throws {
        if fileManager.fileExists(atPath: tempDirectory.path) {
            let contents = try fileManager.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil)
            for file in contents {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    // MARK: - File Size Operations

    /// Get the size of a specific file
    func fileSize(for contentId: UUID, fileExtension: String) throws -> Int64 {
        let path = localPath(for: contentId, fileExtension: fileExtension)
        let attributes = try fileManager.attributesOfItem(atPath: path.path)
        return attributes[.size] as? Int64 ?? 0
    }

    /// Get total size of all downloaded content
    func totalStorageUsed() throws -> Int64 {
        guard fileManager.fileExists(atPath: contentDirectory.path) else { return 0 }

        let contents = try fileManager.contentsOfDirectory(
            at: contentDirectory,
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
    func hasEnoughSpace(for bytes: Int64, currentLimit: Int64) throws -> Bool {
        let currentUsage = try totalStorageUsed()
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
    func verifyChecksum(for contentId: UUID, fileExtension: String, expectedChecksum: String) throws -> Bool {
        let path = localPath(for: contentId, fileExtension: fileExtension)
        let actualChecksum = try calculateChecksum(for: path)
        return actualChecksum == expectedChecksum
    }

    // MARK: - Metadata Storage

    /// Save metadata to disk
    func saveMetadata<T: Codable>(_ data: T, key: String) throws {
        let path = metadataDirectory.appendingPathComponent("\(key).json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(data)
        try encoded.write(to: path, options: .atomic)
    }

    /// Load metadata from disk
    func loadMetadata<T: Codable>(key: String, as type: T.Type) throws -> T? {
        let path = metadataDirectory.appendingPathComponent("\(key).json")
        guard fileManager.fileExists(atPath: path.path) else { return nil }
        let data = try Data(contentsOf: path)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    /// Delete metadata
    func deleteMetadata(key: String) throws {
        let path = metadataDirectory.appendingPathComponent("\(key).json")
        if fileManager.fileExists(atPath: path.path) {
            try fileManager.removeItem(at: path)
        }
    }

    // MARK: - Content Index

    /// Save the downloaded content index
    func saveContentIndex(_ content: [DownloadedContent]) throws {
        try saveMetadata(content, key: OfflineCacheKey.downloadedContentIndex.rawValue)
    }

    /// Load the downloaded content index
    func loadContentIndex() throws -> [DownloadedContent] {
        try loadMetadata(key: OfflineCacheKey.downloadedContentIndex.rawValue, as: [DownloadedContent].self) ?? []
    }

    // MARK: - LRU Eviction

    /// Get content sorted by last accessed time (oldest first)
    func getContentByLRU(_ content: [DownloadedContent]) -> [DownloadedContent] {
        content.sorted { $0.lastAccessedAt < $1.lastAccessedAt }
    }

    /// Evict content to free up space
    func evictOldContent(
        from content: inout [DownloadedContent],
        toFreeBytes: Int64
    ) throws -> [UUID] {
        var freedBytes: Int64 = 0
        var evictedIds: [UUID] = []

        let sorted = getContentByLRU(content)

        for item in sorted {
            guard freedBytes < toFreeBytes else { break }

            // Get file extension from the local path
            let fileExtension = item.localFilePath.pathExtension

            // Delete the file
            try deleteFile(for: item.id, fileExtension: fileExtension)

            freedBytes += item.fileSize
            evictedIds.append(item.id)
        }

        // Remove evicted items from the array
        content.removeAll { evictedIds.contains($0.id) }

        return evictedIds
    }

    // MARK: - Utility

    /// List all files in the content directory
    func listContentFiles() throws -> [URL] {
        guard fileManager.fileExists(atPath: contentDirectory.path) else { return [] }
        return try fileManager.contentsOfDirectory(
            at: contentDirectory,
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
