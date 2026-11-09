//
//  OfflineCacheService.swift
//  MindFriendApp
//
//  Thread-safe caching service for offline data using Swift actors
//

import Foundation

/// Thread-safe cache service for offline data access
actor OfflineCacheService {

    // MARK: - Singleton

    static let shared = OfflineCacheService()

    // MARK: - Properties

    /// Parent of all per-account cache folders. The legacy unscoped files that
    /// older builds wrote directly into `OfflineCache/` are never read,
    /// migrated or attributed to an account.
    private let cacheRoot: URL
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private var binding: OfflineOwnerBinding?
    private var highestEpoch: UInt64?

    // In-memory cache for frequently accessed items (current binding only)
    private var memoryCache: [String: CacheEntry] = [:]
    private let maxMemoryCacheSize = 50

    // MARK: - Initialization

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.init(rootDirectory: caches)
    }

    /// Test/embedding seam: roots the cache under a caller-provided directory.
    init(rootDirectory: URL) {
        cacheRoot = rootDirectory.appendingPathComponent("MindFriend/OfflineCache/accounts", isDirectory: true)

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Binding

    /// Bind the cache to the account lifecycle (use the binding returned by
    /// `OfflineStorageManager.bind`). Until then every read and write fails with
    /// `notBound`; there is no shared or identityless directory.
    func bind(_ newBinding: OfflineOwnerBinding) throws {
        guard OfflineStorageManager.isValidUserId(newBinding.userId) else { throw OfflineStorageError.invalidUserId }
        if binding == newBinding { return }
        if let highestEpoch, newBinding.epoch <= highestEpoch { throw OfflineStorageError.staleEpoch }
        let directory = directory(for: newBinding.userId)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        // Set file protection to complete until first unlock for data-at-rest protection
        try? (directory as NSURL).setResourceValue(
            URLFileProtection.completeUntilFirstUserAuthentication,
            forKey: .fileProtectionKey
        )
        memoryCache.removeAll()
        binding = newBinding
        highestEpoch = newBinding.epoch
    }

    /// End the lifecycle; only the live binding can unbind. Disk files remain
    /// until `purgeUserCache` (they are a regenerable cache).
    func unbind(_ expected: OfflineOwnerBinding) {
        guard binding == expected else { return }
        binding = nil
        memoryCache.removeAll()
    }

    func currentBinding() -> OfflineOwnerBinding? { binding }

    /// Remove an account's cache folder (logout). Refuses while that account is bound.
    func purgeUserCache(userId: String) throws {
        guard OfflineStorageManager.isValidUserId(userId) else { throw OfflineStorageError.invalidUserId }
        if binding?.userId == userId { throw OfflineStorageError.ownerIsBound }
        let directory = directory(for: userId)
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
    }

    private func directory(for userId: String) -> URL {
        cacheRoot.appendingPathComponent(userId, isDirectory: true)
    }

    /// Verify the caller's captured binding against the live one, inside the
    /// actor, immediately before touching memory or disk.
    private func requireDirectory(_ expected: OfflineOwnerBinding) throws -> URL {
        guard let live = binding else { throw OfflineStorageError.notBound }
        guard live == expected else { throw OfflineStorageError.staleBinding }
        return directory(for: live.userId)
    }

    private func liveBinding() throws -> OfflineOwnerBinding {
        guard let binding else { throw OfflineStorageError.notBound }
        return binding
    }

    /// Clear all cached data for the bound account
    func clearAll() throws {
        let directory = try requireDirectory(try liveBinding())
        memoryCache.removeAll()
        try? fileManager.removeItem(at: directory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - Generic Cache Operations

    /// Cache data with a key. Pass the binding captured when the work began.
    func cache<T: Codable>(_ data: T, key: OfflineCacheKey, binding expected: OfflineOwnerBinding) throws {
        let directory = try requireDirectory(expected)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("\(key.rawValue).json")
        let encoded = try encoder.encode(data)
        // Same-directory temp file + rename: atomic without a system temp dir.
        let staging = directory.appendingPathComponent(".\(key.rawValue).\(UUID().uuidString).tmp")
        do {
            try encoded.write(to: staging)
            if rename(staging.path, path.path) != 0 {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }

        // Update memory cache
        let entry = CacheEntry(
            data: encoded,
            timestamp: Date(),
            expiresAt: Date().addingTimeInterval(key.expirationInterval)
        )
        updateMemoryCache(key: key.rawValue, entry: entry)
    }

    /// Cache for the live account. Prefer the `binding:` form from tasks that
    /// span suspension points; this form cannot detect an account change that
    /// happened before the call.
    func cache<T: Codable>(_ data: T, key: OfflineCacheKey) throws {
        try cache(data, key: key, binding: try liveBinding())
    }

    /// Retrieve cached data
    func retrieve<T: Codable>(key: OfflineCacheKey, as type: T.Type, binding expected: OfflineOwnerBinding) throws -> T? {
        let directory = try requireDirectory(expected)
        // Check memory cache first
        if let entry = memoryCache[key.rawValue], !entry.isExpired {
            return try decoder.decode(type, from: entry.data)
        }

        // Fall back to disk
        let path = directory.appendingPathComponent("\(key.rawValue).json")
        guard fileManager.fileExists(atPath: path.path) else { return nil }

        let data = try Data(contentsOf: path)

        // Check file modification date for expiration
        let attributes = try fileManager.attributesOfItem(atPath: path.path)
        if let modDate = attributes[.modificationDate] as? Date {
            let expiresAt = modDate.addingTimeInterval(key.expirationInterval)
            if Date() > expiresAt && key.expirationInterval != .infinity {
                // Cache expired, remove it
                try? fileManager.removeItem(at: path)
                return nil
            }
        }

        // Update memory cache
        let entry = CacheEntry(
            data: data,
            timestamp: Date(),
            expiresAt: Date().addingTimeInterval(key.expirationInterval)
        )
        updateMemoryCache(key: key.rawValue, entry: entry)

        return try decoder.decode(type, from: data)
    }

    func retrieve<T: Codable>(key: OfflineCacheKey, as type: T.Type) throws -> T? {
        try retrieve(key: key, as: type, binding: try liveBinding())
    }

    /// Check if cache exists and is valid
    func exists(key: OfflineCacheKey) -> Bool {
        guard let binding, let directory = try? requireDirectory(binding) else { return false }
        // Check memory cache
        if let entry = memoryCache[key.rawValue], !entry.isExpired {
            return true
        }

        // Check disk
        let path = directory.appendingPathComponent("\(key.rawValue).json")
        guard fileManager.fileExists(atPath: path.path) else { return false }

        // Check expiration
        if let attributes = try? fileManager.attributesOfItem(atPath: path.path),
           let modDate = attributes[.modificationDate] as? Date {
            let expiresAt = modDate.addingTimeInterval(key.expirationInterval)
            if Date() > expiresAt && key.expirationInterval != .infinity {
                return false
            }
        }

        return true
    }

    /// Invalidate a specific cache
    func invalidate(key: OfflineCacheKey) {
        guard let binding, let directory = try? requireDirectory(binding) else { return }
        let path = directory.appendingPathComponent("\(key.rawValue).json")
        try? fileManager.removeItem(at: path)
        memoryCache.removeValue(forKey: key.rawValue)
    }

    /// Invalidate all caches for the bound account
    func invalidateAll() {
        memoryCache.removeAll()
        guard let binding, let directory = try? requireDirectory(binding) else { return }
        try? fileManager.removeItem(at: directory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - Memory Cache Management

    private func updateMemoryCache(key: String, entry: CacheEntry) {
        // Evict old entries if needed
        if memoryCache.count >= maxMemoryCacheSize {
            // Remove oldest entries
            let sortedKeys = memoryCache.sorted { $0.value.timestamp < $1.value.timestamp }
            let keysToRemove = sortedKeys.prefix(10).map { $0.key }
            for k in keysToRemove {
                memoryCache.removeValue(forKey: k)
            }
        }

        memoryCache[key] = entry
    }

    /// Clear memory cache only (keeps disk cache)
    func clearMemoryCache() {
        memoryCache.removeAll()
    }

    // MARK: - Specific Cache Methods

    /// Cache today's quest
    func cacheTodayQuest(_ quest: Quest) async {
        try? cache(quest, key: .todayQuest)
    }

    /// Get cached today's quest
    func getCachedTodayQuest() async -> Quest? {
        try? retrieve(key: .todayQuest, as: Quest.self)
    }

    /// Cache mood history
    func cacheMoodHistory(_ moods: [MoodEntry]) async {
        try? cache(moods, key: .moodHistory)
    }

    /// Get cached mood history
    func getCachedMoodHistory() async -> [MoodEntry]? {
        try? retrieve(key: .moodHistory, as: [MoodEntry].self)
    }

    /// Cache exercise library
    func cacheExerciseLibrary(_ exercises: [Exercise]) async {
        try? cache(exercises, key: .exerciseLibrary)
    }

    /// Get cached exercise library
    func getCachedExerciseLibrary() async -> [Exercise]? {
        try? retrieve(key: .exerciseLibrary, as: [Exercise].self)
    }

    /// Cache user profile
    func cacheUserProfile(_ profile: UserProfile) async {
        try? cache(profile, key: .userProfile)
    }

    /// Get cached user profile
    func getCachedUserProfile() async -> UserProfile? {
        try? retrieve(key: .userProfile, as: UserProfile.self)
    }

    /// Cache program progress
    func cacheProgramProgress(_ progress: [ProgramEnrollment]) async {
        try? cache(progress, key: .programProgress)
    }

    /// Get cached program progress
    func getCachedProgramProgress() async -> [ProgramEnrollment]? {
        try? retrieve(key: .programProgress, as: [ProgramEnrollment].self)
    }

    // MARK: - Cache Info

    /// Get total cache size
    func getCacheSize() async -> Int64 {
        guard let binding, let cacheDirectory = try? requireDirectory(binding),
              fileManager.fileExists(atPath: cacheDirectory.path) else { return 0 }

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: [.fileSizeKey],
                options: .skipsHiddenFiles
            )

            return try contents.reduce(0) { total, url in
                let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
                return total + Int64(resourceValues.fileSize ?? 0)
            }
        } catch {
            return 0
        }
    }

    /// Get cache item count
    func getCacheItemCount() async -> Int {
        guard let binding, let cacheDirectory = try? requireDirectory(binding),
              fileManager.fileExists(atPath: cacheDirectory.path) else { return 0 }

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            return contents.count
        } catch {
            return 0
        }
    }
}

// MARK: - Cache Entry

/// Internal structure for memory cache entries
private struct CacheEntry {
    let data: Data
    let timestamp: Date
    let expiresAt: Date

    var isExpired: Bool {
        Date() > expiresAt
    }
}

// MARK: - Convenience Extensions

extension OfflineCacheService {

    /// Cache with automatic refresh if stale. The account binding is captured
    /// before any suspension, so a fetch that finishes after an account change
    /// cannot be written into the new account's cache.
    func getOrFetch<T: Codable>(
        key: OfflineCacheKey,
        as type: T.Type,
        fetch: () async throws -> T
    ) async throws -> T {
        let binding = try liveBinding()
        // Try cache first
        if let cached: T = try? retrieve(key: key, as: type, binding: binding) {
            return cached
        }

        // Fetch fresh data
        let fresh = try await fetch()
        try? cache(fresh, key: key, binding: binding)
        return fresh
    }

    /// Cache with background refresh (binding captured up front, see `getOrFetch`)
    func getCachedOrRefresh<T: Codable>(
        key: OfflineCacheKey,
        as type: T.Type,
        forceRefresh: Bool = false,
        fetch: @escaping () async throws -> T
    ) async -> T? {
        guard let binding = try? liveBinding() else { return nil }
        // Return cached if available and not forcing refresh
        if !forceRefresh, let cached: T = try? retrieve(key: key, as: type, binding: binding) {
            // Schedule background refresh
            Task {
                if let fresh = try? await fetch() {
                    try? self.cache(fresh, key: key, binding: binding)
                }
            }
            return cached
        }

        // Fetch fresh data
        if let fresh = try? await fetch() {
            try? cache(fresh, key: key, binding: binding)
            return fresh
        }

        // Fall back to cached (even if expired)
        return try? retrieve(key: key, as: type, binding: binding)
    }
}
