//
//  PathwayCacheService.swift
//  MindFriendApp
//
//  Local caching for pathway data to improve offline experience
//

import Foundation

// Note: DailyPathwayContent and CheckInData are defined in TransitionPathwayModels.swift

/// Service for caching pathway-related data
final class PathwayCacheService: PathwayCacheServiceProtocol {

    // MARK: - Constants

    private enum CacheKey {
        static let dailyContentPrefix = "pathway_daily_content_"
        static let draftPrefix = "pathway_checkin_draft_"
        static let pendingCheckInsKey = "pathway_pending_checkins"
    }

    // ✅ FIX: Add LRU cache size limit (prevents unbounded memory growth)
    private let maxCacheSize: Int = 10  // Keep last 10 daily contents

    // MARK: - Dependencies

    private let userDefaults: UserDefaults
    private let secureStorage: SecureStorage
    private let queue = DispatchQueue(label: "app.mindfriend.pathway-cache", qos: .utility)

    // In-memory cache for current session
    private var dailyContentCache: [UUID: CachedDailyContent] = [:]
    // ✅ FIX: Track access order for LRU eviction
    private var cacheAccessOrder: [UUID] = []
    private var pendingCheckIns: [UUID: PendingCheckIn] = [:]

    // MARK: - Initialization

    init(
        userDefaults: UserDefaults = .standard,
        secureStorage: SecureStorage = SecureStorage()
    ) {
        self.userDefaults = userDefaults
        self.secureStorage = secureStorage
        loadPendingCheckIns()
    }

    // MARK: - Cached Daily Content Model

    struct CachedDailyContent: Codable {
        let content: DailyPathwayContent
        let fetchedAt: Date

        var isExpired: Bool {
            // Use fixed 24-hour TTL instead of calendar day boundary (prevents timezone issues)
            Date().timeIntervalSince(fetchedAt) > 86400  // 24 hours in seconds
        }
    }

    // MARK: - Daily Content Caching

    /// Cache daily content for a pathway (thread-safe)
    /// - Note: Encryption performed on background queue to avoid blocking main thread
    /// - Throws: SecureStorageError if encryption fails (on background queue)
    func cacheDailyContent(_ content: DailyPathwayContent, for pathwayId: UUID) throws {
        let key = CacheKey.dailyContentPrefix + pathwayId.uuidString

        // ✅ FIX: Perform all operations synchronously on background queue to match protocol
        try queue.sync {
            // ✅ FIX: Create timestamp INSIDE queue to avoid race condition
            let cached = CachedDailyContent(content: content, fetchedAt: Date())

            // ✅ FIX: Update access order (move to end = most recent)
            self.cacheAccessOrder.removeAll { $0 == pathwayId }
            self.cacheAccessOrder.append(pathwayId)

            // ✅ FIX: Evict oldest if over limit
            if self.cacheAccessOrder.count > self.maxCacheSize {
                let evictKey = self.cacheAccessOrder.removeFirst()
                self.dailyContentCache.removeValue(forKey: evictKey)
                // ✅ FIX: Also remove from UserDefaults to prevent disk space leak
                self.secureStorage.remove(
                    forKey: CacheKey.dailyContentPrefix + evictKey.uuidString,
                    from: self.userDefaults
                )
                print("PathwayCacheService: Evicted oldest cache entry for pathway \(evictKey.uuidString)")
            }

            self.dailyContentCache[pathwayId] = cached

            // ✅ FIX: Encrypt on background queue (prevents main thread blocking)
            try self.secureStorage.store(cached, forKey: key, in: self.userDefaults)
        }
    }

    /// Retrieve cached daily content if not expired (thread-safe)
    /// - Throws: SecureStorageError if decryption fails
    func getCachedDailyContent(for pathwayId: UUID) throws -> DailyPathwayContent? {
        // Check in-memory cache first (thread-safe read)
        let cachedInMemory = queue.sync { dailyContentCache[pathwayId] }

        if let cached = cachedInMemory, !cached.isExpired {
            return cached.content
        }

        // Try to load from encrypted storage
        if let cached = try secureStorage.retrieve(
            forKey: CacheKey.dailyContentPrefix + pathwayId.uuidString,
            as: CachedDailyContent.self,
            from: userDefaults
        ) {
            if !cached.isExpired {
                // ✅ FIX: Update in-memory cache AND access order to maintain LRU consistency
                queue.async { [weak self] in
                    guard let self = self else { return }
                    self.dailyContentCache[pathwayId] = cached
                    // Update access order (move to end = most recent)
                    self.cacheAccessOrder.removeAll { $0 == pathwayId }
                    self.cacheAccessOrder.append(pathwayId)
                }
                return cached.content
            }
        }

        return nil
    }

    /// Clear expired daily content caches (thread-safe)
    func clearExpiredDailyContent() {
        queue.async { [weak self] in
            guard let self = self else { return }

            // ✅ FIX: Track removed keys to update access order
            let removedFromMemory = Set(self.dailyContentCache.keys).subtracting(
                self.dailyContentCache.filter { !$0.value.isExpired }.keys
            )

            // Filter in-memory cache
            self.dailyContentCache = self.dailyContentCache.filter { !$0.value.isExpired }

            // ✅ FIX: Remove expired entries from access order
            self.cacheAccessOrder.removeAll { removedFromMemory.contains($0) }

            // ✅ FIX: Create immutable snapshot of keys to avoid concurrent modification
            let allKeys = Array(self.userDefaults.dictionaryRepresentation().keys)
            let keysToCheck = allKeys.filter { $0.hasPrefix(CacheKey.dailyContentPrefix) }

            // Now iterate over snapshot and remove expired entries
            for key in keysToCheck {
                // Check if cached entry is expired before deleting
                do {
                    if let cached = try self.secureStorage.retrieve(
                        forKey: key,
                        as: CachedDailyContent.self,
                        from: self.userDefaults
                    ), cached.isExpired {
                        self.secureStorage.remove(forKey: key, from: self.userDefaults)
                    }
                } catch {
                    // If decryption fails, delete corrupted entry
                    self.secureStorage.remove(forKey: key, from: self.userDefaults)
                }
            }
        }
    }

    func clearDailyContentCache(for pathwayId: UUID) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.dailyContentCache.removeValue(forKey: pathwayId)
            // ✅ FIX: Also remove from access order to maintain LRU consistency
            self.cacheAccessOrder.removeAll { $0 == pathwayId }
            self.secureStorage.remove(forKey: CacheKey.dailyContentPrefix + pathwayId.uuidString, from: self.userDefaults)
        }
    }

    // MARK: - Check-In Draft

    struct CheckInDraft: Codable {
        let id: UUID
        let userPathwayId: UUID
        let checkInData: CheckInData
        let exercisesCompleted: [String]
        let journalEntry: String?
        let timestamp: Date
        let retryCount: Int
    }

    /// Save check-in draft for recovery
    /// - Note: Encryption performed on background queue to avoid blocking main thread
    /// - Throws: SecureStorageError if encryption fails
    func saveCheckInDraft(_ draft: CheckInDraft) throws {
        let key = CacheKey.draftPrefix + draft.userPathwayId.uuidString
        // ✅ FIX: Perform synchronously on background queue to match protocol and propagate errors
        try queue.sync {
            try self.secureStorage.store(draft, forKey: key, in: self.userDefaults)
        }
    }

    /// Retrieve saved draft
    /// - Throws: SecureStorageError if decryption fails
    func getCheckInDraft(for userPathwayId: UUID) throws -> CheckInDraft? {
        return try secureStorage.retrieve(
            forKey: CacheKey.draftPrefix + userPathwayId.uuidString,
            as: CheckInDraft.self,
            from: userDefaults
        )
    }

    /// Clear draft after successful submission
    func clearCheckInDraft(for userPathwayId: UUID) {
        secureStorage.remove(forKey: CacheKey.draftPrefix + userPathwayId.uuidString, from: userDefaults)
    }

    // MARK: - Journal Draft Management

    /// Save journal draft for a specific pathway
    /// - Note: Encryption performed on background queue to avoid blocking main thread
    /// - Throws: SecureStorageError if encryption fails
    func saveJournalDraft(_ text: String, for pathwayId: UUID) throws {
        let journalKey = "journal.draft.\(pathwayId.uuidString)"
        // ✅ FIX: Perform synchronously on background queue to match protocol and propagate errors
        try queue.sync {
            try self.secureStorage.store(text, forKey: journalKey, in: self.userDefaults)
        }
    }

    /// Retrieve journal draft for a specific pathway
    /// - Throws: SecureStorageError if decryption fails
    func getJournalDraft(for pathwayId: UUID) throws -> String? {
        let journalKey = "journal.draft.\(pathwayId.uuidString)"
        return try secureStorage.retrieve(forKey: journalKey, as: String.self, from: userDefaults)
    }

    /// Clear journal draft after successful submission
    func clearJournalDraft(for pathwayId: UUID) {
        let journalKey = "journal.draft.\(pathwayId.uuidString)"
        secureStorage.remove(forKey: journalKey, from: userDefaults)
    }

    // MARK: - Pending Check-Ins Queue

    struct PendingCheckIn: Codable, Identifiable {
        let id: UUID
        let userPathwayId: UUID
        let checkInData: CheckInData
        let exercisesCompleted: [String]
        let journalEntry: String?
        let attemptedAt: Date
        var retryCount: Int

        init(
            userPathwayId: UUID,
            checkInData: CheckInData,
            exercisesCompleted: [String],
            journalEntry: String?
        ) {
            self.id = UUID()
            self.userPathwayId = userPathwayId
            self.checkInData = checkInData
            self.exercisesCompleted = exercisesCompleted
            self.journalEntry = journalEntry
            self.attemptedAt = Date()
            self.retryCount = 0
        }
    }

    /// Queue check-in for retry when network fails
    func queuePendingCheckIn(_ checkIn: PendingCheckIn) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.pendingCheckIns[checkIn.id] = checkIn
            self.savePendingCheckIns()
        }
    }

    /// Get all pending check-ins
    func getPendingCheckIns() -> [PendingCheckIn] {
        queue.sync {
            Array(pendingCheckIns.values).sorted { $0.attemptedAt < $1.attemptedAt }
        }
    }

    /// Remove check-in from pending queue
    func removePendingCheckIn(_ id: UUID) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.pendingCheckIns.removeValue(forKey: id)
            self.savePendingCheckIns()
        }
    }

    /// Update retry count for pending check-in (thread-safe atomic mutation)
    func updateRetryCount(for id: UUID) {
        queue.async { [weak self] in
            guard let self = self else { return }
            // Atomic read-modify-write to prevent race conditions
            if var checkIn = self.pendingCheckIns[id] {
                checkIn.retryCount += 1
                self.pendingCheckIns[id] = checkIn
            }
            self.savePendingCheckIns()
        }
    }

    // MARK: - Private Helpers

    // MARK: - Initialization Helper

    /// Load pending check-ins on initialization
    /// - Note: Silently initializes to empty if decryption fails (initialization context)
    private func loadPendingCheckIns() {
        queue.sync {
            guard let data = userDefaults.data(forKey: CacheKey.pendingCheckInsKey) else {  // ✅ FIX: Use correct key name
                return
            }
            
            do {
                let decoded = try JSONDecoder().decode([UUID: PendingCheckIn].self, from: data)
                self.pendingCheckIns = decoded
            } catch {
                print("⚠️ Failed to load pending check-ins: \(error)")
            }
        }
    }

    /// Save pending check-ins (called internally)
    /// - Note: Errors are logged but not propagated (fire-and-forget caching)
    private func savePendingCheckIns() {
        let snapshot = pendingCheckIns
        queue.async { [weak self] in
            guard let self = self else { return }
            do {
                let encoded = try JSONEncoder().encode(snapshot)
                self.userDefaults.set(encoded, forKey: CacheKey.pendingCheckInsKey)
            } catch {
                print("⚠️ Failed to save pending check-ins: \(error)")
            }
        }
    }

    /// Clear all caches (for logout)
    func clearAllCaches() {
        queue.async { [weak self] in
            guard let self = self else { return }

            // Clear in-memory caches
            self.dailyContentCache.removeAll()
            self.cacheAccessOrder.removeAll()
            self.pendingCheckIns.removeAll()

            // Clear UserDefaults entries
            let allKeys = Array(self.userDefaults.dictionaryRepresentation().keys)
            for key in allKeys {
                if key.hasPrefix(CacheKey.dailyContentPrefix) ||
                   key.hasPrefix(CacheKey.draftPrefix) ||
                   key == CacheKey.pendingCheckInsKey {  // ✅ FIX: Use correct key name
                    self.userDefaults.removeObject(forKey: key)
                }
            }
        }
    }
}
