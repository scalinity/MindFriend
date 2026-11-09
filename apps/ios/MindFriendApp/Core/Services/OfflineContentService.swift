//
//  OfflineContentService.swift
//  MindFriendApp
//
//  Main facade for offline functionality - coordinates all offline components
//

import Foundation
import Combine

/// Main service for offline functionality - acts as facade for all offline components
@MainActor
final class OfflineContentService: ObservableObject {

    // MARK: - Singleton

    static let shared = OfflineContentService()

    // MARK: - Published Properties

    /// Whether the device is currently online
    @Published private(set) var isOnline: Bool = true

    /// Current connection type
    @Published private(set) var connectionType: ConnectionType = .unknown

    /// Number of pending items to sync
    @Published private(set) var pendingSyncCount: Int = 0

    /// Total downloaded content size
    @Published private(set) var totalDownloadedSize: Int64 = 0

    /// Number of downloaded items
    @Published private(set) var downloadedItemCount: Int = 0

    /// Current storage limit
    @Published var storageLimit: Int64 = StorageLimitOption.default.bytes

    /// Whether currently syncing
    @Published private(set) var isSyncing: Bool = false

    /// Active download tasks
    @Published private(set) var activeDownloads: [DownloadTask] = []

    /// Last sync time
    @Published private(set) var lastSyncTime: Date?

    // MARK: - Component References

    private let connectivityMonitor = ConnectivityMonitor.shared
    private let downloadManager = DownloadManager.shared
    private let syncQueueManager = SyncQueueManager.shared
    private let storageManager = OfflineStorageManager.shared
    private let cacheService = OfflineCacheService.shared

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    private init() {
        setupBindings()
        connectivityMonitor.startMonitoring()
    }

    // MARK: - Setup

    private func setupBindings() {
        // Bind connectivity
        connectivityMonitor.$isConnected
            .assign(to: &$isOnline)

        connectivityMonitor.$connectionType
            .assign(to: &$connectionType)

        // Bind download manager
        downloadManager.$totalStorageUsed
            .assign(to: &$totalDownloadedSize)

        downloadManager.$downloads
            .map { $0.count }
            .assign(to: &$downloadedItemCount)

        downloadManager.$activeTasks
            .assign(to: &$activeDownloads)

        downloadManager.$storageLimit
            .assign(to: &$storageLimit)

        // Bind sync queue
        syncQueueManager.$pendingSyncCount
            .assign(to: &$pendingSyncCount)

        syncQueueManager.$isSyncing
            .assign(to: &$isSyncing)

        syncQueueManager.$lastSyncAt
            .assign(to: &$lastSyncTime)
    }

    /// Bind every offline component (storage, sync queue, downloads, cache) to
    /// the authenticated owner and account epoch and install the sync handlers.
    /// Call after user restoration, before any offline data is read or written.
    /// Handlers must treat `item.idempotencyKey` as an owner-scoped idempotency
    /// key: an item can be delivered again after a crash or a failed local save.
    func bindOfflineScope(
        userId: String,
        epoch: UInt64,
        moodHandler: @escaping (OfflineMoodEntry) async throws -> Void,
        questHandler: @escaping (OfflineQuestCompletion) async throws -> Void,
        exerciseHandler: @escaping (OfflineExerciseSession) async throws -> Void
    ) async throws {
        try await OfflineScope.shared.bind(
            userId: userId,
            epoch: epoch,
            moodHandler: moodHandler,
            questHandler: questHandler,
            exerciseHandler: exerciseHandler
        )
    }

    /// End the offline scope (logout / account switch). Unsynced work stays on disk.
    func unbindOfflineScope() {
        OfflineScope.shared.unbind()
    }

    // MARK: - Download Operations

    /// Download content for offline use
    func download(_ content: any DownloadableContent, binding: OfflineOwnerBinding) async throws {
        try await downloadManager.download(content, binding: binding)
    }

    /// Cancel a download
    func cancelDownload(taskId: UUID) {
        downloadManager.cancelDownload(taskId: taskId)
    }

    /// Pause a download
    func pauseDownload(taskId: UUID) {
        downloadManager.pauseDownload(taskId: taskId)
    }

    /// Resume a download
    func resumeDownload(taskId: UUID) {
        downloadManager.resumeDownload(taskId: taskId)
    }

    /// Delete downloaded content
    func deleteDownload(contentId: UUID, binding: OfflineOwnerBinding) async throws {
        try await downloadManager.deleteDownload(contentId: contentId, binding: binding)
    }

    /// Delete all downloads
    func deleteAllDownloads(binding: OfflineOwnerBinding) async throws {
        try await downloadManager.deleteAllDownloads(binding: binding)
    }

    /// Check if content is downloaded
    func isDownloaded(contentId: UUID) -> Bool {
        downloadManager.isDownloaded(contentId: contentId)
    }

    /// Get local file path for downloaded content
    func localPath(for contentId: UUID) -> URL? {
        downloadManager.localPath(for: contentId)
    }

    /// Get download progress for content
    func downloadProgress(for contentId: UUID) -> Double? {
        downloadManager.downloadProgress(for: contentId)
    }

    /// Get all downloaded content
    func getDownloadedContent() -> [DownloadedContent] {
        downloadManager.downloads
    }

    /// Mark content as accessed (for LRU tracking)
    func markContentAccessed(contentId: UUID) async {
        await downloadManager.markAsAccessed(contentId: contentId)
    }

    // MARK: - Offline Data Entry

    /// Save mood entry offline
    func saveMoodOffline(
        score: Int,
        anxiety: Int? = nil,
        energy: Int? = nil,
        notes: String? = nil,
        factors: [String]? = nil
    ) async throws {
        try await syncQueueManager.saveMoodOffline(
            score: score,
            anxiety: anxiety,
            energy: energy,
            notes: notes,
            factors: factors
        )
    }

    /// Save quest completion offline
    func saveQuestCompletionOffline(questId: UUID, questTitle: String? = nil) async throws {
        try await syncQueueManager.saveQuestCompletionOffline(
            questId: questId,
            questTitle: questTitle
        )
    }

    /// Save exercise session offline
    func saveExerciseSessionOffline(
        exerciseId: UUID,
        exerciseTitle: String? = nil,
        duration: Int
    ) async throws {
        try await syncQueueManager.saveExerciseSessionOffline(
            exerciseId: exerciseId,
            exerciseTitle: exerciseTitle,
            duration: duration
        )
    }

    // MARK: - Sync Operations

    /// Sync all pending data
    func syncNow() async {
        await syncQueueManager.syncNow()
    }

    /// Get sync queue details
    func getSyncQueue() -> OfflineSyncQueue {
        syncQueueManager.syncQueue
    }

    /// Clear sync queue (use with caution)
    func clearSyncQueue() async throws {
        try await syncQueueManager.clearQueue()
    }

    /// Retry failed sync items
    func retryFailedSyncs(binding: OfflineOwnerBinding) async throws {
        try await syncQueueManager.retryFailedItems(binding: binding)
    }

    // MARK: - Cache Operations

    /// Cache today's quest
    func cacheTodayQuest(_ quest: Quest, binding: OfflineOwnerBinding) async {
        await cacheService.cacheTodayQuest(quest, binding: binding)
    }

    /// Get cached today's quest
    func getCachedTodayQuest(binding: OfflineOwnerBinding) async -> Quest? {
        await cacheService.getCachedTodayQuest(binding: binding)
    }

    /// Cache mood history
    func cacheMoodHistory(_ moods: [MoodEntry], binding: OfflineOwnerBinding) async {
        await cacheService.cacheMoodHistory(moods, binding: binding)
    }

    /// Get cached mood history
    func getCachedMoodHistory(binding: OfflineOwnerBinding) async -> [MoodEntry]? {
        await cacheService.getCachedMoodHistory(binding: binding)
    }

    /// Cache exercise library
    func cacheExerciseLibrary(_ exercises: [Exercise], binding: OfflineOwnerBinding) async {
        await cacheService.cacheExerciseLibrary(exercises, binding: binding)
    }

    /// Get cached exercise library
    func getCachedExerciseLibrary(binding: OfflineOwnerBinding) async -> [Exercise]? {
        await cacheService.getCachedExerciseLibrary(binding: binding)
    }

    /// Cache user profile
    func cacheUserProfile(_ profile: UserProfile, binding: OfflineOwnerBinding) async {
        await cacheService.cacheUserProfile(profile, binding: binding)
    }

    /// Get cached user profile
    func getCachedUserProfile(binding: OfflineOwnerBinding) async -> UserProfile? {
        await cacheService.getCachedUserProfile(binding: binding)
    }

    /// Invalidate specific cache
    func invalidateCache(key: OfflineCacheKey, binding: OfflineOwnerBinding) async {
        await cacheService.invalidate(key: key, binding: binding)
    }

    /// Invalidate all caches
    func invalidateAllCaches(binding: OfflineOwnerBinding) async {
        await cacheService.invalidateAll(binding: binding)
    }

    // MARK: - Storage Management

    /// Get current storage info
    func getStorageInfo() async -> StorageInfo {
        await downloadManager.getStorageInfo()
    }

    /// Update storage limit
    func updateStorageLimit(_ option: StorageLimitOption, binding: OfflineOwnerBinding) async throws {
        try await downloadManager.updateStorageLimit(option.bytes, binding: binding)
    }

    /// Get download settings
    func getDownloadSettings() -> DownloadSettings {
        downloadManager.settings
    }

    /// Update download settings
    func updateDownloadSettings(_ settings: DownloadSettings, binding: OfflineOwnerBinding) async throws {
        try await downloadManager.updateSettings(settings, binding: binding)
    }

    /// Check if can download based on current settings
    func canDownload(wifiOnly: Bool? = nil) -> Bool {
        let useWifiOnly = wifiOnly ?? downloadManager.settings.wifiOnlyDownloads
        return connectivityMonitor.canDownload(wifiOnly: useWifiOnly)
    }

    // MARK: - Connectivity

    /// Get current connectivity state
    func getConnectivityState() -> ConnectivityState {
        ConnectivityState(from: connectivityMonitor)
    }

    /// Check connectivity status
    func checkConnectivity() {
        connectivityMonitor.checkConnectivity()
    }

    // MARK: - Feature Availability

    /// Check if a feature is available offline
    func isFeatureAvailableOffline(_ feature: OfflineFeature) -> Bool {
        switch feature {
        case .downloadedContent:
            return true
        case .moodCheckIn:
            return true // Will be synced later
        case .questCompletion:
            return true // Will be synced later
        case .exerciseTracking:
            return true // Will be synced later
        case .moodHistory:
            return true // Cached
        case .todayQuest:
            return true // Cached
        case .exerciseLibrary:
            return true // Cached
        case .aiChat:
            return false // Requires internet
        case .voiceMode:
            return false // Requires internet
        case .circles:
            return false // Requires internet
        case .profile:
            return true // Cached
        }
    }

    /// Get offline availability message for a feature
    func offlineMessage(for feature: OfflineFeature) -> String {
        if isFeatureAvailableOffline(feature) {
            return feature.offlineAvailableMessage
        } else {
            return feature.requiresInternetMessage
        }
    }

    // MARK: - Background Task Support

    /// Set background completion handler (call from AppDelegate)
    func setBackgroundCompletionHandler(_ handler: @escaping () -> Void) {
        downloadManager.backgroundCompletionHandler = handler
    }
}

// MARK: - Offline Feature

/// Features that may or may not be available offline
enum OfflineFeature {
    case downloadedContent
    case moodCheckIn
    case questCompletion
    case exerciseTracking
    case moodHistory
    case todayQuest
    case exerciseLibrary
    case aiChat
    case voiceMode
    case circles
    case profile

    var displayName: String {
        switch self {
        case .downloadedContent: return "Downloaded Content"
        case .moodCheckIn: return "Mood Check-in"
        case .questCompletion: return "Quest Completion"
        case .exerciseTracking: return "Exercise Tracking"
        case .moodHistory: return "Mood History"
        case .todayQuest: return "Today's Quest"
        case .exerciseLibrary: return "Exercise Library"
        case .aiChat: return "AI Chat"
        case .voiceMode: return "Voice Mode"
        case .circles: return "Circles"
        case .profile: return "Profile"
        }
    }

    var offlineAvailableMessage: String {
        switch self {
        case .moodCheckIn, .questCompletion, .exerciseTracking:
            return "Available offline (will sync when connected)"
        case .moodHistory, .todayQuest, .exerciseLibrary, .profile:
            return "Available offline (cached data)"
        case .downloadedContent:
            return "Available offline"
        default:
            return "Available offline"
        }
    }

    var requiresInternetMessage: String {
        switch self {
        case .aiChat:
            return "AI Chat requires an internet connection"
        case .voiceMode:
            return "Voice Mode requires an internet connection"
        case .circles:
            return "Circles require an internet connection"
        default:
            return "This feature requires an internet connection"
        }
    }

    var icon: String {
        switch self {
        case .downloadedContent: return "arrow.down.circle.fill"
        case .moodCheckIn: return "face.smiling"
        case .questCompletion: return "star.fill"
        case .exerciseTracking: return "figure.mind.and.body"
        case .moodHistory: return "chart.line.uptrend.xyaxis"
        case .todayQuest: return "target"
        case .exerciseLibrary: return "books.vertical"
        case .aiChat: return "bubble.left.and.bubble.right"
        case .voiceMode: return "waveform"
        case .circles: return "person.3"
        case .profile: return "person.circle"
        }
    }
}


// MARK: - Offline scope

/// Single owner of the offline account lifecycle. Binds and unbinds storage,
/// the sync queue, downloads and the cache together under one owner/epoch, and
/// unbinds synchronously so nothing outlives the account that created it.
@MainActor
final class OfflineScope {
    static let shared = OfflineScope()

    private(set) var binding: OfflineOwnerBinding?
    private var generation = 0
    private var requested: OfflineOwnerBinding?
    private var bindTask: Task<Void, Error>?
    private var teardownTask: Task<Void, Never>?
    private var highestRequestedEpoch: UInt64?

    init() {}

    func bind(
        userId: String,
        epoch: UInt64,
        moodHandler: @escaping (OfflineMoodEntry) async throws -> Void,
        questHandler: @escaping (OfflineQuestCompletion) async throws -> Void,
        exerciseHandler: @escaping (OfflineExerciseSession) async throws -> Void
    ) async throws {
        try Task.checkCancellation()
        let target = OfflineOwnerBinding(userId: userId, epoch: epoch)
        if requested == target {
            if let bindTask {
                try await bindTask.value
                try Task.checkCancellation()
                guard requested == target, binding == target else { throw SyncQueueError.lifecycleEnded }
                return
            }
            if binding == target { return }
        }
        if let highestRequestedEpoch, epoch <= highestRequestedEpoch { throw OfflineStorageError.staleEpoch }
        highestRequestedEpoch = epoch
        requested = target
        let task = Task { @MainActor in
            await self.awaitTeardown()
            guard self.requested == target else { throw SyncQueueError.lifecycleEnded }
            try await self.performBind(userId: userId, epoch: epoch, moodHandler: moodHandler,
                                       questHandler: questHandler, exerciseHandler: exerciseHandler)
        }
        bindTask = task
        do {
            try await task.value
            try Task.checkCancellation()
            guard requested == target, binding == target else { throw SyncQueueError.lifecycleEnded }
        } catch {
            if requested == target { bindTask = nil }
            throw error
        }
        if requested == target { bindTask = nil }
    }

    private func performBind(userId: String, epoch: UInt64,
        moodHandler: @escaping (OfflineMoodEntry) async throws -> Void,
        questHandler: @escaping (OfflineQuestCompletion) async throws -> Void,
        exerciseHandler: @escaping (OfflineExerciseSession) async throws -> Void) async throws {
        generation += 1
        let mine = generation
        var acquired: OfflineOwnerBinding?
        do {
            let storage = OfflineStorageManager.shared
            let bound = try await storage.bind(userId: userId, epoch: epoch)
            acquired = bound
            guard mine == generation else {
                throw SyncQueueError.lifecycleEnded
            }
            // Record an in-progress bind so synchronous logout can also invalidate it.
            binding = bound
            try await SyncQueueManager.shared.bind(
                userId: userId,
                epoch: epoch,
                moodSyncHandler: moodHandler,
                questSyncHandler: questHandler,
                exerciseSyncHandler: exerciseHandler
            )
            guard mine == generation else { throw SyncQueueError.lifecycleEnded }
            try await DownloadManager.shared.bind(bound)
            guard mine == generation else { throw SyncQueueError.lifecycleEnded }
            try await OfflineCacheService.shared.bind(bound)
            guard mine == generation else { throw SyncQueueError.lifecycleEnded }
            binding = bound
        } catch {
            if mine == generation, requested == OfflineOwnerBinding(userId: userId, epoch: epoch) { unbind() }
            if let acquired, requested != acquired {
                SyncQueueManager.shared.unbind(expected: acquired)
                DownloadManager.shared.unbind(expected: acquired)
                await OfflineCacheService.shared.unbind(acquired)
                await OfflineStorageManager.shared.unbind(acquired)
            }
            throw error
        }
    }

    /// Synchronous teardown, safe to call from logout before another account can sign in.
    func unbind() {
        generation += 1
        requested = nil
        bindTask?.cancel()
        bindTask = nil
        let ended = binding
        binding = nil
        SyncQueueManager.shared.unbind()
        DownloadManager.shared.unbind()
        if let ended {
            let previous = teardownTask
            teardownTask = Task {
                await previous?.value
                await OfflineCacheService.shared.unbind(ended)
                await OfflineStorageManager.shared.unbind(ended)
            }
        }
    }

    func awaitTeardown() async { await teardownTask?.value }
}
