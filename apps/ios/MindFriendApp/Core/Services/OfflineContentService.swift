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

    /// Configure sync handlers (call this during app initialization)
    func configureSyncHandlers(
        moodHandler: @escaping (OfflineMoodEntry) async throws -> Void,
        questHandler: @escaping (OfflineQuestCompletion) async throws -> Void,
        exerciseHandler: @escaping (OfflineExerciseSession) async throws -> Void
    ) {
        syncQueueManager.configure(
            moodSyncHandler: moodHandler,
            questSyncHandler: questHandler,
            exerciseSyncHandler: exerciseHandler
        )
    }

    // MARK: - Download Operations

    /// Download content for offline use
    func download(_ content: any DownloadableContent) async throws {
        try await downloadManager.download(content)
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
    func deleteDownload(contentId: UUID) async throws {
        try await downloadManager.deleteDownload(contentId: contentId)
    }

    /// Delete all downloads
    func deleteAllDownloads() async throws {
        try await downloadManager.deleteAllDownloads()
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
    ) async {
        await syncQueueManager.saveMoodOffline(
            score: score,
            anxiety: anxiety,
            energy: energy,
            notes: notes,
            factors: factors
        )
    }

    /// Save quest completion offline
    func saveQuestCompletionOffline(questId: UUID, questTitle: String? = nil) async {
        await syncQueueManager.saveQuestCompletionOffline(
            questId: questId,
            questTitle: questTitle
        )
    }

    /// Save exercise session offline
    func saveExerciseSessionOffline(
        exerciseId: UUID,
        exerciseTitle: String? = nil,
        duration: Int
    ) async {
        await syncQueueManager.saveExerciseSessionOffline(
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
    func clearSyncQueue() async {
        await syncQueueManager.clearQueue()
    }

    /// Retry failed sync items
    func retryFailedSyncs() async {
        await syncQueueManager.retryFailedItems()
    }

    // MARK: - Cache Operations

    /// Cache today's quest
    func cacheTodayQuest(_ quest: Quest) async {
        await cacheService.cacheTodayQuest(quest)
    }

    /// Get cached today's quest
    func getCachedTodayQuest() async -> Quest? {
        await cacheService.getCachedTodayQuest()
    }

    /// Cache mood history
    func cacheMoodHistory(_ moods: [MoodEntry]) async {
        await cacheService.cacheMoodHistory(moods)
    }

    /// Get cached mood history
    func getCachedMoodHistory() async -> [MoodEntry]? {
        await cacheService.getCachedMoodHistory()
    }

    /// Cache exercise library
    func cacheExerciseLibrary(_ exercises: [Exercise]) async {
        await cacheService.cacheExerciseLibrary(exercises)
    }

    /// Get cached exercise library
    func getCachedExerciseLibrary() async -> [Exercise]? {
        await cacheService.getCachedExerciseLibrary()
    }

    /// Cache user profile
    func cacheUserProfile(_ profile: UserProfile) async {
        await cacheService.cacheUserProfile(profile)
    }

    /// Get cached user profile
    func getCachedUserProfile() async -> UserProfile? {
        await cacheService.getCachedUserProfile()
    }

    /// Invalidate specific cache
    func invalidateCache(key: OfflineCacheKey) async {
        await cacheService.invalidate(key: key)
    }

    /// Invalidate all caches
    func invalidateAllCaches() async {
        await cacheService.invalidateAll()
    }

    // MARK: - Storage Management

    /// Get current storage info
    func getStorageInfo() async -> StorageInfo {
        await downloadManager.getStorageInfo()
    }

    /// Update storage limit
    func updateStorageLimit(_ option: StorageLimitOption) async {
        await downloadManager.updateStorageLimit(option.bytes)
        await downloadManager.saveSettings()
    }

    /// Get download settings
    func getDownloadSettings() -> DownloadSettings {
        downloadManager.settings
    }

    /// Update download settings
    func updateDownloadSettings(_ settings: DownloadSettings) async {
        downloadManager.settings = settings
        await downloadManager.saveSettings()
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
