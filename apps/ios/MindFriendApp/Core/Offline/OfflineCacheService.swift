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

    private let cacheDirectory: URL
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    // In-memory cache for frequently accessed items
    private var memoryCache: [String: CacheEntry] = [:]
    private let maxMemoryCacheSize = 50

    // MARK: - Initialization

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = caches.appendingPathComponent("MindFriend/OfflineCache", isDirectory: true)

        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Generic Cache Operations

    /// Cache data with a key
    func cache<T: Codable>(_ data: T, key: OfflineCacheKey) throws {
        let path = cacheDirectory.appendingPathComponent("\(key.rawValue).json")
        let encoded = try encoder.encode(data)
        try encoded.write(to: path, options: .atomic)

        // Update memory cache
        let entry = CacheEntry(
            data: encoded,
            timestamp: Date(),
            expiresAt: Date().addingTimeInterval(key.expirationInterval)
        )
        updateMemoryCache(key: key.rawValue, entry: entry)
    }

    /// Retrieve cached data
    func retrieve<T: Codable>(key: OfflineCacheKey, as type: T.Type) throws -> T? {
        // Check memory cache first
        if let entry = memoryCache[key.rawValue], !entry.isExpired {
            return try decoder.decode(type, from: entry.data)
        }

        // Fall back to disk
        let path = cacheDirectory.appendingPathComponent("\(key.rawValue).json")
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

    /// Check if cache exists and is valid
    func exists(key: OfflineCacheKey) -> Bool {
        // Check memory cache
        if let entry = memoryCache[key.rawValue], !entry.isExpired {
            return true
        }

        // Check disk
        let path = cacheDirectory.appendingPathComponent("\(key.rawValue).json")
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
        let path = cacheDirectory.appendingPathComponent("\(key.rawValue).json")
        try? fileManager.removeItem(at: path)
        memoryCache.removeValue(forKey: key.rawValue)
    }

    /// Invalidate all caches
    func invalidateAll() {
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        memoryCache.removeAll()
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
        guard fileManager.fileExists(atPath: cacheDirectory.path) else { return 0 }

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
        guard fileManager.fileExists(atPath: cacheDirectory.path) else { return 0 }

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

    /// Cache with automatic refresh if stale
    func getOrFetch<T: Codable>(
        key: OfflineCacheKey,
        as type: T.Type,
        fetch: () async throws -> T
    ) async throws -> T {
        // Try cache first
        if let cached: T = try? retrieve(key: key, as: type) {
            return cached
        }

        // Fetch fresh data
        let fresh = try await fetch()
        try? cache(fresh, key: key)
        return fresh
    }

    /// Cache with background refresh
    func getCachedOrRefresh<T: Codable>(
        key: OfflineCacheKey,
        as type: T.Type,
        forceRefresh: Bool = false,
        fetch: () async throws -> T
    ) async -> T? {
        // Return cached if available and not forcing refresh
        if !forceRefresh, let cached: T = try? retrieve(key: key, as: type) {
            // Schedule background refresh
            Task {
                if let fresh = try? await fetch() {
                    try? self.cache(fresh, key: key)
                }
            }
            return cached
        }

        // Fetch fresh data
        if let fresh = try? await fetch() {
            try? cache(fresh, key: key)
            return fresh
        }

        // Fall back to cached (even if expired)
        return try? retrieve(key: key, as: type)
    }
}
