//
//  SyncQueueManager.swift
//  MindFriendApp
//
//  Manages queuing and syncing of offline data entries
//

import Foundation
import Combine

/// Manages offline data entries and syncs them when connectivity returns
@MainActor
final class SyncQueueManager: ObservableObject {

    // MARK: - Singleton

    static let shared = SyncQueueManager()

    // MARK: - Published Properties

    /// Current sync queue
    @Published private(set) var syncQueue: OfflineSyncQueue = OfflineSyncQueue()

    /// Number of pending items to sync
    @Published private(set) var pendingSyncCount: Int = 0

    /// Whether currently syncing
    @Published private(set) var isSyncing: Bool = false

    /// Last successful sync time
    @Published private(set) var lastSyncAt: Date?

    /// Current sync status message
    @Published private(set) var syncStatusMessage: String = ""

    /// Sync error if any
    @Published private(set) var syncError: Error?

    // MARK: - Private Properties

    private let storageManager = OfflineStorageManager.shared
    private let connectivityMonitor = ConnectivityMonitor.shared
    private var cancellables = Set<AnyCancellable>()

    private let maxRetryAttempts = 5
    private let baseRetryDelay: TimeInterval = 2.0

    // MARK: - Dependencies (injected via configure)

    private var moodSyncHandler: ((OfflineMoodEntry) async throws -> Void)?
    private var questSyncHandler: ((OfflineQuestCompletion) async throws -> Void)?
    private var exerciseSyncHandler: ((OfflineExerciseSession) async throws -> Void)?

    // MARK: - Initialization

    private init() {
        Task {
            await loadQueue()
        }
        setupConnectivityObserver()
    }

    // MARK: - Configuration

    /// Configure sync handlers for each data type
    func configure(
        moodSyncHandler: @escaping (OfflineMoodEntry) async throws -> Void,
        questSyncHandler: @escaping (OfflineQuestCompletion) async throws -> Void,
        exerciseSyncHandler: @escaping (OfflineExerciseSession) async throws -> Void
    ) {
        self.moodSyncHandler = moodSyncHandler
        self.questSyncHandler = questSyncHandler
        self.exerciseSyncHandler = exerciseSyncHandler
    }

    // MARK: - Setup

    private func setupConnectivityObserver() {
        connectivityMonitor.onConnectivityRestored = { [weak self] in
            await self?.syncPendingData()
        }
    }

    // MARK: - Queue Operations

    /// Save a mood entry for later sync
    func saveMoodOffline(
        score: Int,
        anxiety: Int? = nil,
        energy: Int? = nil,
        notes: String? = nil,
        factors: [String]? = nil
    ) async {
        let entry = OfflineMoodEntry(
            moodScore: score,
            anxietyLevel: anxiety,
            energyLevel: energy,
            notes: notes,
            factors: factors
        )

        syncQueue.moodEntries.append(entry)
        await saveQueue()
        updatePendingCount()
    }

    /// Save a quest completion for later sync
    func saveQuestCompletionOffline(questId: UUID, questTitle: String? = nil) async {
        let completion = OfflineQuestCompletion(
            questId: questId,
            questTitle: questTitle
        )

        syncQueue.questCompletions.append(completion)
        await saveQueue()
        updatePendingCount()
    }

    /// Save an exercise session for later sync
    func saveExerciseSessionOffline(
        exerciseId: UUID,
        exerciseTitle: String? = nil,
        duration: Int
    ) async {
        let session = OfflineExerciseSession(
            exerciseId: exerciseId,
            exerciseTitle: exerciseTitle,
            durationSeconds: duration
        )

        syncQueue.exerciseSessions.append(session)
        await saveQueue()
        updatePendingCount()
    }

    // MARK: - Sync Operations

    /// Sync all pending data
    func syncPendingData() async {
        guard connectivityMonitor.isConnected else {
            syncStatusMessage = "Waiting for connection..."
            return
        }

        guard !isSyncing else { return }
        guard syncQueue.hasPendingItems else {
            syncStatusMessage = "All changes synced"
            return
        }

        isSyncing = true
        syncError = nil
        syncQueue.lastSyncAttempt = Date()

        defer {
            isSyncing = false
            updatePendingCount()
            Task {
                await saveQueue()
            }
        }

        var successCount = 0
        var failureCount = 0

        // Sync mood entries
        for i in syncQueue.moodEntries.indices where !syncQueue.moodEntries[i].synced {
            syncStatusMessage = "Syncing mood entries..."

            let result = await syncMoodEntry(index: i)
            if result {
                successCount += 1
            } else {
                failureCount += 1
            }
        }

        // Sync quest completions
        for i in syncQueue.questCompletions.indices where !syncQueue.questCompletions[i].synced {
            syncStatusMessage = "Syncing quest completions..."

            let result = await syncQuestCompletion(index: i)
            if result {
                successCount += 1
            } else {
                failureCount += 1
            }
        }

        // Sync exercise sessions
        for i in syncQueue.exerciseSessions.indices where !syncQueue.exerciseSessions[i].synced {
            syncStatusMessage = "Syncing exercise sessions..."

            let result = await syncExerciseSession(index: i)
            if result {
                successCount += 1
            } else {
                failureCount += 1
            }
        }

        // Clean up synced items
        syncQueue.pruneSyncedItems()

        // Update status
        if failureCount == 0 {
            lastSyncAt = Date()
            syncQueue.lastSuccessfulSync = Date()
            syncStatusMessage = successCount > 0 ? "All changes synced" : "Up to date"
        } else {
            syncStatusMessage = "\(failureCount) items failed to sync"
        }
    }

    /// Force sync now (user initiated)
    func syncNow() async {
        await syncPendingData()
    }

    // MARK: - Individual Sync Methods

    private func syncMoodEntry(index: Int) async -> Bool {
        guard let handler = moodSyncHandler else {
            print("Mood sync handler not configured")
            return false
        }

        var entry = syncQueue.moodEntries[index]

        guard entry.syncAttempts < maxRetryAttempts else {
            return false
        }

        entry.syncAttempts += 1

        do {
            try await handler(entry)
            syncQueue.moodEntries[index].synced = true
            syncQueue.moodEntries[index].syncAttempts = entry.syncAttempts
            return true
        } catch {
            syncQueue.moodEntries[index].lastSyncError = error.localizedDescription
            syncQueue.moodEntries[index].syncAttempts = entry.syncAttempts

            // Apply exponential backoff delay before next attempt
            if entry.syncAttempts < maxRetryAttempts {
                let delay = calculateBackoffDelay(attempt: entry.syncAttempts)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            return false
        }
    }

    private func syncQuestCompletion(index: Int) async -> Bool {
        guard let handler = questSyncHandler else {
            print("Quest sync handler not configured")
            return false
        }

        var completion = syncQueue.questCompletions[index]

        guard completion.syncAttempts < maxRetryAttempts else {
            return false
        }

        completion.syncAttempts += 1

        do {
            try await handler(completion)
            syncQueue.questCompletions[index].synced = true
            syncQueue.questCompletions[index].syncAttempts = completion.syncAttempts
            return true
        } catch {
            syncQueue.questCompletions[index].lastSyncError = error.localizedDescription
            syncQueue.questCompletions[index].syncAttempts = completion.syncAttempts

            if completion.syncAttempts < maxRetryAttempts {
                let delay = calculateBackoffDelay(attempt: completion.syncAttempts)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            return false
        }
    }

    private func syncExerciseSession(index: Int) async -> Bool {
        guard let handler = exerciseSyncHandler else {
            print("Exercise sync handler not configured")
            return false
        }

        var session = syncQueue.exerciseSessions[index]

        guard session.syncAttempts < maxRetryAttempts else {
            return false
        }

        session.syncAttempts += 1

        do {
            try await handler(session)
            syncQueue.exerciseSessions[index].synced = true
            syncQueue.exerciseSessions[index].syncAttempts = session.syncAttempts
            return true
        } catch {
            syncQueue.exerciseSessions[index].lastSyncError = error.localizedDescription
            syncQueue.exerciseSessions[index].syncAttempts = session.syncAttempts

            if session.syncAttempts < maxRetryAttempts {
                let delay = calculateBackoffDelay(attempt: session.syncAttempts)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }

            return false
        }
    }

    // MARK: - Backoff Calculation

    private func calculateBackoffDelay(attempt: Int) -> TimeInterval {
        // Exponential backoff with jitter: baseDelay * 2^attempt + random jitter
        let exponentialDelay = baseRetryDelay * pow(2.0, Double(attempt - 1))
        let jitter = Double.random(in: 0...1) * exponentialDelay * 0.1
        return min(exponentialDelay + jitter, 60.0) // Cap at 60 seconds
    }

    // MARK: - Persistence

    private func loadQueue() async {
        if let loaded: OfflineSyncQueue = try? await storageManager.loadMetadata(
            key: OfflineCacheKey.syncQueue.rawValue,
            as: OfflineSyncQueue.self
        ) {
            syncQueue = loaded
            updatePendingCount()

            if let lastSync = loaded.lastSuccessfulSync {
                lastSyncAt = lastSync
            }
        }
    }

    private func saveQueue() async {
        try? await storageManager.saveMetadata(syncQueue, key: OfflineCacheKey.syncQueue.rawValue)
    }

    private func updatePendingCount() {
        pendingSyncCount = syncQueue.totalPending
    }

    // MARK: - Queue Management

    /// Clear all pending items (use with caution)
    func clearQueue() async {
        syncQueue = OfflineSyncQueue()
        await saveQueue()
        updatePendingCount()
    }

    /// Clear all state on logout - clears queue without syncing
    func clearOnLogout() async {
        isSyncing = false
        syncQueue = OfflineSyncQueue()
        pendingSyncCount = 0
        lastSyncAt = nil
        syncStatusMessage = ""
        syncError = nil
        // Note: persisted queue will be deleted by OfflineStorageManager.deleteCurrentUserData()
    }

    /// Remove a specific mood entry from the queue
    func removeMoodEntry(id: UUID) async {
        syncQueue.moodEntries.removeAll { $0.id == id }
        await saveQueue()
        updatePendingCount()
    }

    /// Remove a specific quest completion from the queue
    func removeQuestCompletion(id: UUID) async {
        syncQueue.questCompletions.removeAll { $0.id == id }
        await saveQueue()
        updatePendingCount()
    }

    /// Remove a specific exercise session from the queue
    func removeExerciseSession(id: UUID) async {
        syncQueue.exerciseSessions.removeAll { $0.id == id }
        await saveQueue()
        updatePendingCount()
    }

    /// Get failed items that need attention
    func getFailedItems() -> (moods: [OfflineMoodEntry], quests: [OfflineQuestCompletion], exercises: [OfflineExerciseSession]) {
        let failedMoods = syncQueue.moodEntries.filter { $0.syncAttempts >= maxRetryAttempts && !$0.synced }
        let failedQuests = syncQueue.questCompletions.filter { $0.syncAttempts >= maxRetryAttempts && !$0.synced }
        let failedExercises = syncQueue.exerciseSessions.filter { $0.syncAttempts >= maxRetryAttempts && !$0.synced }

        return (failedMoods, failedQuests, failedExercises)
    }

    /// Retry failed items (reset attempt count)
    func retryFailedItems() async {
        for i in syncQueue.moodEntries.indices {
            if syncQueue.moodEntries[i].syncAttempts >= maxRetryAttempts {
                syncQueue.moodEntries[i].syncAttempts = 0
                syncQueue.moodEntries[i].lastSyncError = nil
            }
        }

        for i in syncQueue.questCompletions.indices {
            if syncQueue.questCompletions[i].syncAttempts >= maxRetryAttempts {
                syncQueue.questCompletions[i].syncAttempts = 0
                syncQueue.questCompletions[i].lastSyncError = nil
            }
        }

        for i in syncQueue.exerciseSessions.indices {
            if syncQueue.exerciseSessions[i].syncAttempts >= maxRetryAttempts {
                syncQueue.exerciseSessions[i].syncAttempts = 0
                syncQueue.exerciseSessions[i].lastSyncError = nil
            }
        }

        await saveQueue()
        await syncPendingData()
    }
}

// MARK: - Sync Status

/// Represents the current sync status
enum SyncStatus: Equatable {
    case idle
    case syncing(progress: Int, total: Int)
    case completed(count: Int)
    case failed(message: String)
    case offline(pendingCount: Int)

    var displayMessage: String {
        switch self {
        case .idle:
            return "Up to date"
        case .syncing(let progress, let total):
            return "Syncing \(progress) of \(total)..."
        case .completed(let count):
            return count > 0 ? "\(count) items synced" : "All synced"
        case .failed(let message):
            return message
        case .offline(let pendingCount):
            return "\(pendingCount) items pending sync"
        }
    }

    var icon: String {
        switch self {
        case .idle:
            return "checkmark.circle.fill"
        case .syncing:
            return "arrow.triangle.2.circlepath"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .offline:
            return "wifi.slash"
        }
    }
}
