//
//  OfflineModels.swift
//  MindFriendApp
//
//  Core data models for offline mode functionality
//

import Foundation

// MARK: - Content Types

/// Types of content that can be downloaded for offline use
enum OfflineContentType: String, Codable, CaseIterable {
    case exercise
    case sleepStory
    case soundscape
    case programModule

    var displayName: String {
        switch self {
        case .exercise: return "Exercise"
        case .sleepStory: return "Sleep Story"
        case .soundscape: return "Soundscape"
        case .programModule: return "Program Module"
        }
    }

    var icon: String {
        switch self {
        case .exercise: return "figure.mind.and.body"
        case .sleepStory: return "moon.stars.fill"
        case .soundscape: return "waveform"
        case .programModule: return "book.fill"
        }
    }
}

// MARK: - Download State

/// Status of a download task
enum DownloadStatus: String, Codable {
    case queued
    case downloading
    case paused
    case completed
    case failed
    case cancelled

    var displayName: String {
        switch self {
        case .queued: return "Waiting"
        case .downloading: return "Downloading"
        case .paused: return "Paused"
        case .completed: return "Downloaded"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    var isActive: Bool {
        self == .queued || self == .downloading
    }
}

// MARK: - Downloaded Content

/// Represents content that has been downloaded and stored locally
struct DownloadedContent: Identifiable, Codable, Equatable {
    let id: UUID
    let contentType: OfflineContentType
    let title: String
    let subtitle: String?
    let localFilePath: URL
    let originalUrl: URL
    let fileSize: Int64
    let checksum: String?
    let downloadedAt: Date
    var lastAccessedAt: Date
    var playCount: Int
    let metadata: DownloadedContentMetadata?

    /// Human-readable file size
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    /// Time since download
    var downloadedAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: downloadedAt, relativeTo: Date())
    }

    static func == (lhs: DownloadedContent, rhs: DownloadedContent) -> Bool {
        lhs.id == rhs.id
    }
}

/// Additional metadata for downloaded content
struct DownloadedContentMetadata: Codable {
    let duration: TimeInterval?
    let artist: String?
    let category: String?
    let imageUrl: URL?
    let premiumOnly: Bool
    let programId: UUID?
    let dayNumber: Int?
}

// MARK: - Download Task

/// Represents an active or pending download operation
struct DownloadTask: Identifiable, Codable {
    let id: UUID
    let contentId: UUID
    let contentType: OfflineContentType
    let title: String
    let remoteUrl: URL
    let estimatedSize: Int64
    var status: DownloadStatus
    var progress: Double
    var bytesDownloaded: Int64
    var errorMessage: String?
    let createdAt: Date
    var resumeData: Data?

    init(
        id: UUID = UUID(),
        contentId: UUID,
        contentType: OfflineContentType,
        title: String,
        remoteUrl: URL,
        estimatedSize: Int64,
        status: DownloadStatus = .queued,
        progress: Double = 0,
        bytesDownloaded: Int64 = 0,
        errorMessage: String? = nil,
        createdAt: Date = Date(),
        resumeData: Data? = nil
    ) {
        self.id = id
        self.contentId = contentId
        self.contentType = contentType
        self.title = title
        self.remoteUrl = remoteUrl
        self.estimatedSize = estimatedSize
        self.status = status
        self.progress = progress
        self.bytesDownloaded = bytesDownloaded
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.resumeData = resumeData
    }

    /// Human-readable estimated size
    var formattedEstimatedSize: String {
        ByteCountFormatter.string(fromByteCount: estimatedSize, countStyle: .file)
    }

    /// Progress percentage (0-100)
    var progressPercentage: Int {
        Int(progress * 100)
    }
}

// MARK: - Offline Sync Items

/// Mood entry created while offline, pending sync
struct OfflineMoodEntry: Identifiable, Codable {
    let id: UUID
    let moodScore: Int
    let anxietyLevel: Int?
    let energyLevel: Int?
    let notes: String?
    let factors: [String]?
    let createdAt: Date
    var synced: Bool
    var syncAttempts: Int
    var lastSyncError: String?

    init(
        id: UUID = UUID(),
        moodScore: Int,
        anxietyLevel: Int? = nil,
        energyLevel: Int? = nil,
        notes: String? = nil,
        factors: [String]? = nil,
        createdAt: Date = Date(),
        synced: Bool = false,
        syncAttempts: Int = 0,
        lastSyncError: String? = nil
    ) {
        self.id = id
        self.moodScore = moodScore
        self.anxietyLevel = anxietyLevel
        self.energyLevel = energyLevel
        self.notes = notes
        self.factors = factors
        self.createdAt = createdAt
        self.synced = synced
        self.syncAttempts = syncAttempts
        self.lastSyncError = lastSyncError
    }
}

/// Quest completion recorded while offline, pending sync
struct OfflineQuestCompletion: Identifiable, Codable {
    let id: UUID
    let questId: UUID
    let questTitle: String?
    let completedAt: Date
    var synced: Bool
    var syncAttempts: Int
    var lastSyncError: String?

    init(
        id: UUID = UUID(),
        questId: UUID,
        questTitle: String? = nil,
        completedAt: Date = Date(),
        synced: Bool = false,
        syncAttempts: Int = 0,
        lastSyncError: String? = nil
    ) {
        self.id = id
        self.questId = questId
        self.questTitle = questTitle
        self.completedAt = completedAt
        self.synced = synced
        self.syncAttempts = syncAttempts
        self.lastSyncError = lastSyncError
    }
}

/// Exercise session recorded while offline, pending sync
struct OfflineExerciseSession: Identifiable, Codable {
    let id: UUID
    let exerciseId: UUID
    let exerciseTitle: String?
    let durationSeconds: Int
    let completedAt: Date
    var synced: Bool
    var syncAttempts: Int
    var lastSyncError: String?

    init(
        id: UUID = UUID(),
        exerciseId: UUID,
        exerciseTitle: String? = nil,
        durationSeconds: Int,
        completedAt: Date = Date(),
        synced: Bool = false,
        syncAttempts: Int = 0,
        lastSyncError: String? = nil
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.exerciseTitle = exerciseTitle
        self.durationSeconds = durationSeconds
        self.completedAt = completedAt
        self.synced = synced
        self.syncAttempts = syncAttempts
        self.lastSyncError = lastSyncError
    }
}

// MARK: - Sync Queue

/// Queue of all offline entries waiting to be synced
struct OfflineSyncQueue: Codable {
    var moodEntries: [OfflineMoodEntry]
    var questCompletions: [OfflineQuestCompletion]
    var exerciseSessions: [OfflineExerciseSession]
    var lastSyncAttempt: Date?
    var lastSuccessfulSync: Date?

    init(
        moodEntries: [OfflineMoodEntry] = [],
        questCompletions: [OfflineQuestCompletion] = [],
        exerciseSessions: [OfflineExerciseSession] = [],
        lastSyncAttempt: Date? = nil,
        lastSuccessfulSync: Date? = nil
    ) {
        self.moodEntries = moodEntries
        self.questCompletions = questCompletions
        self.exerciseSessions = exerciseSessions
        self.lastSyncAttempt = lastSyncAttempt
        self.lastSuccessfulSync = lastSuccessfulSync
    }

    /// Total count of pending (unsynced) items
    var totalPending: Int {
        pendingMoodEntries + pendingQuestCompletions + pendingExerciseSessions
    }

    var pendingMoodEntries: Int {
        moodEntries.filter { !$0.synced }.count
    }

    var pendingQuestCompletions: Int {
        questCompletions.filter { !$0.synced }.count
    }

    var pendingExerciseSessions: Int {
        exerciseSessions.filter { !$0.synced }.count
    }

    var isEmpty: Bool {
        moodEntries.isEmpty && questCompletions.isEmpty && exerciseSessions.isEmpty
    }

    var hasPendingItems: Bool {
        totalPending > 0
    }

    /// Remove all synced items from the queue
    mutating func pruneSyncedItems() {
        moodEntries.removeAll { $0.synced }
        questCompletions.removeAll { $0.synced }
        exerciseSessions.removeAll { $0.synced }
    }
}

// MARK: - Storage Configuration

/// Available storage limit options
enum StorageLimitOption: Int64, CaseIterable, Identifiable {
    case small = 268435456      // 256 MB
    case medium = 536870912     // 512 MB
    case large = 1073741824     // 1 GB
    case extraLarge = 2147483648 // 2 GB

    var id: Int64 { rawValue }

    var displayName: String {
        switch self {
        case .small: return "256 MB"
        case .medium: return "512 MB"
        case .large: return "1 GB"
        case .extraLarge: return "2 GB"
        }
    }

    var bytes: Int64 { rawValue }

    static var `default`: StorageLimitOption { .medium }
}

// MARK: - Connectivity

/// Types of network connection
enum ConnectionType: String, Codable {
    case wifi
    case cellular
    case ethernet
    case unknown
    case none

    var isConnected: Bool {
        self != .none
    }

    var displayName: String {
        switch self {
        case .wifi: return "Wi-Fi"
        case .cellular: return "Cellular"
        case .ethernet: return "Ethernet"
        case .unknown: return "Connected"
        case .none: return "Offline"
        }
    }

    var icon: String {
        switch self {
        case .wifi: return "wifi"
        case .cellular: return "antenna.radiowaves.left.and.right"
        case .ethernet: return "cable.connector"
        case .unknown: return "network"
        case .none: return "wifi.slash"
        }
    }
}

// MARK: - Downloadable Content Protocol

/// Protocol for content that can be downloaded for offline use
protocol DownloadableContent {
    var id: UUID { get }
    var title: String { get }
    var subtitle: String? { get }
    var audioUrl: URL { get }
    var estimatedSize: Int64 { get }
    var offlineContentType: OfflineContentType { get }
    var duration: TimeInterval? { get }
    var imageUrl: URL? { get }
    var isPremium: Bool { get }
}

// MARK: - Download Progress

/// Progress information for a download
struct DownloadProgress {
    let taskId: UUID
    let contentId: UUID
    let bytesDownloaded: Int64
    let totalBytes: Int64
    let progress: Double
    let estimatedTimeRemaining: TimeInterval?

    var formattedProgress: String {
        let downloaded = ByteCountFormatter.string(fromByteCount: bytesDownloaded, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        return "\(downloaded) / \(total)"
    }

    var progressPercentage: Int {
        Int(progress * 100)
    }
}

// MARK: - Download Settings

/// User preferences for download behavior
struct DownloadSettings: Codable {
    var wifiOnlyDownloads: Bool
    var autoDeleteUnused: Bool
    var autoDeleteAfterDays: Int
    var storageLimit: Int64
    var downloadQuality: DownloadQuality
    var autoDownloadQuestContent: Bool
    var autoDownloadFavorites: Bool

    static var `default`: DownloadSettings {
        DownloadSettings(
            wifiOnlyDownloads: true,
            autoDeleteUnused: false,
            autoDeleteAfterDays: 30,
            storageLimit: StorageLimitOption.default.bytes,
            downloadQuality: .standard,
            autoDownloadQuestContent: false,
            autoDownloadFavorites: false
        )
    }
}

/// Download quality options
enum DownloadQuality: String, Codable, CaseIterable {
    case standard
    case high

    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .high: return "High Quality"
        }
    }

    var description: String {
        switch self {
        case .standard: return "Smaller file size, good quality"
        case .high: return "Larger file size, best quality"
        }
    }
}

// MARK: - Errors

/// Errors that can occur during offline operations
enum OfflineError: LocalizedError {
    case storageLimitExceeded
    case downloadFailed(Error)
    case fileNotFound
    case checksumMismatch
    case syncFailed(Error)
    case networkUnavailable
    case contentExpired
    case insufficientStorage
    case invalidContent
    case authenticationRequired

    var errorDescription: String? {
        switch self {
        case .storageLimitExceeded:
            return "Storage limit reached. Delete some downloads to make room."
        case .downloadFailed(let error):
            return "Download failed: \(error.localizedDescription)"
        case .fileNotFound:
            return "Downloaded file not found."
        case .checksumMismatch:
            return "Downloaded file may be corrupted. Please try downloading again."
        case .syncFailed(let error):
            return "Sync failed: \(error.localizedDescription)"
        case .networkUnavailable:
            return "No network connection available."
        case .contentExpired:
            return "This content has expired. Please download it again."
        case .insufficientStorage:
            return "Not enough storage space on device."
        case .invalidContent:
            return "Invalid content format."
        case .authenticationRequired:
            return "Please sign in to download content."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .storageLimitExceeded:
            return "Go to Settings > Downloads to manage your storage."
        case .downloadFailed:
            return "Check your internet connection and try again."
        case .fileNotFound:
            return "Try downloading the content again."
        case .checksumMismatch:
            return "Delete the corrupted file and download again."
        case .syncFailed:
            return "Your changes will sync when connection is restored."
        case .networkUnavailable:
            return "Connect to the internet to continue."
        case .contentExpired:
            return "Download the content again to access it offline."
        case .insufficientStorage:
            return "Free up space on your device or reduce the storage limit."
        case .invalidContent:
            return "Contact support if this issue persists."
        case .authenticationRequired:
            return "Sign in to your account to download content."
        }
    }
}

// MARK: - Cache Keys

/// Keys used for caching various types of data
enum OfflineCacheKey: String {
    case todayQuest = "today_quest"
    case moodHistory = "mood_history"
    case exerciseLibrary = "exercise_library"
    case userProfile = "user_profile"
    case programProgress = "program_progress"
    case safetyPlan = "safety_plan"
    case downloadedContentIndex = "downloaded_content_index"
    case syncQueue = "sync_queue"
    case downloadSettings = "download_settings"

    var expirationInterval: TimeInterval {
        switch self {
        case .todayQuest:
            return 24 * 60 * 60 // 24 hours
        case .moodHistory:
            return 7 * 24 * 60 * 60 // 7 days
        case .exerciseLibrary:
            return 7 * 24 * 60 * 60 // 7 days
        case .userProfile:
            return 24 * 60 * 60 // 24 hours
        case .programProgress:
            return 24 * 60 * 60 // 24 hours
        case .safetyPlan, .downloadedContentIndex, .syncQueue, .downloadSettings:
            return .infinity // Never expires
        }
    }
}
