//
//  DownloadManager.swift
//  MindFriendApp
//
//  Manages content downloads with URLSession background transfers
//

import Foundation
import Combine

/// Manages downloading content for offline use with background transfer support
@MainActor
final class DownloadManager: NSObject, ObservableObject {

    // MARK: - Singleton

    static let shared = DownloadManager()

    // MARK: - Published Properties

    /// List of all downloaded content
    @Published private(set) var downloads: [DownloadedContent] = []

    /// Currently active download tasks
    @Published private(set) var activeTasks: [DownloadTask] = []

    /// Total storage used by downloads
    @Published private(set) var totalStorageUsed: Int64 = 0

    /// Current storage limit
    @Published var storageLimit: Int64 = StorageLimitOption.default.bytes

    /// Download settings
    @Published var settings: DownloadSettings = .default

    /// Whether downloads are currently paused
    @Published private(set) var isPaused: Bool = false

    // MARK: - Private Properties

    private var urlSession: URLSession!
    private var backgroundTaskMap: [Int: UUID] = [:] // URLSessionTask.taskIdentifier -> DownloadTask.id
    private let storageManager = OfflineStorageManager.shared
    private var cancellables = Set<AnyCancellable>()

    private static let backgroundSessionIdentifier = "com.mindfriend.downloads"

    // MARK: - Callbacks

    /// Called when a download completes
    var onDownloadComplete: ((UUID) -> Void)?

    /// Called when a download fails
    var onDownloadFailed: ((UUID, Error) -> Void)?

    /// Background completion handler from AppDelegate
    var backgroundCompletionHandler: (() -> Void)?

    // MARK: - Initialization

    private override init() {
        super.init()

        // Configure background session
        let config = URLSessionConfiguration.background(withIdentifier: Self.backgroundSessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.allowsCellularAccess = true

        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        // Load persisted data
        Task {
            await loadPersistedData()
        }

        // Observe connectivity for WiFi-only setting
        setupConnectivityObserver()
    }

    // MARK: - Setup

    private func setupConnectivityObserver() {
        ConnectivityMonitor.shared.$connectionType
            .sink { [weak self] connectionType in
                self?.handleConnectionChange(connectionType)
            }
            .store(in: &cancellables)
    }

    private func handleConnectionChange(_ connectionType: ConnectionType) {
        guard settings.wifiOnlyDownloads else { return }

        if connectionType == .cellular {
            // Pause downloads on cellular if WiFi-only is enabled
            pauseAllDownloads()
        } else if connectionType == .wifi && isPaused {
            // Resume downloads when back on WiFi
            resumeAllDownloads()
        }
    }

    // MARK: - Download Operations

    /// Start downloading content
    func download(_ content: any DownloadableContent) async throws {
        // Check if already downloaded
        guard !isDownloaded(contentId: content.id) else {
            throw OfflineError.invalidContent
        }

        // Check if already downloading
        guard !activeTasks.contains(where: { $0.contentId == content.id }) else {
            return
        }

        // Check storage limit
        let hasSpace = try await storageManager.hasEnoughSpace(
            for: content.estimatedSize,
            currentLimit: storageLimit
        )
        guard hasSpace else {
            throw OfflineError.storageLimitExceeded
        }

        // Check WiFi-only setting
        if settings.wifiOnlyDownloads && !ConnectivityMonitor.shared.canDownload(wifiOnly: true) {
            throw OfflineError.networkUnavailable
        }

        // Create download task
        let task = DownloadTask(
            contentId: content.id,
            contentType: content.offlineContentType,
            title: content.title,
            remoteUrl: content.audioUrl,
            estimatedSize: content.estimatedSize,
            status: .queued
        )

        activeTasks.append(task)
        await saveActiveTasks()

        // Start the download
        let downloadTask = urlSession.downloadTask(with: content.audioUrl)
        backgroundTaskMap[downloadTask.taskIdentifier] = task.id
        downloadTask.resume()

        updateTaskStatus(task.id, status: .downloading)
    }

    /// Cancel a download
    func cancelDownload(taskId: UUID) {
        // Find and cancel the URLSession task
        urlSession.getAllTasks { [weak self] tasks in
            guard let self = self else { return }

            // Find the task identifier for this download task ID
            if let taskIdentifier = self.backgroundTaskMap.first(where: { $0.value == taskId })?.key,
               let task = tasks.first(where: { $0.taskIdentifier == taskIdentifier }) {
                task.cancel()

                Task { @MainActor in
                    self.activeTasks.removeAll { $0.id == taskId }
                    // Remove using the correct key (taskIdentifier), not taskId.hashValue
                    self.backgroundTaskMap.removeValue(forKey: taskIdentifier)
                    await self.saveActiveTasks()
                }
            } else {
                // Task not found in map, just clean up activeTasks
                Task { @MainActor in
                    self.activeTasks.removeAll { $0.id == taskId }
                    await self.saveActiveTasks()
                }
            }
        }
    }

    /// Pause a download
    func pauseDownload(taskId: UUID) {
        urlSession.getAllTasks { [weak self] tasks in
            guard let self = self else { return }

            if let taskIdentifier = self.backgroundTaskMap.first(where: { $0.value == taskId })?.key,
               let downloadTask = tasks.first(where: { $0.taskIdentifier == taskIdentifier }) as? URLSessionDownloadTask {

                downloadTask.cancel(byProducingResumeData: { resumeData in
                    Task { @MainActor in
                        if let index = self.activeTasks.firstIndex(where: { $0.id == taskId }) {
                            self.activeTasks[index].status = .paused
                            self.activeTasks[index].resumeData = resumeData
                        }
                        await self.saveActiveTasks()
                    }
                })
            }
        }
    }

    /// Resume a paused download
    func resumeDownload(taskId: UUID) {
        guard let index = activeTasks.firstIndex(where: { $0.id == taskId }),
              activeTasks[index].status == .paused else {
            return
        }

        let task = activeTasks[index]

        let downloadTask: URLSessionDownloadTask
        if let resumeData = task.resumeData {
            downloadTask = urlSession.downloadTask(withResumeData: resumeData)
        } else {
            downloadTask = urlSession.downloadTask(with: task.remoteUrl)
        }

        backgroundTaskMap[downloadTask.taskIdentifier] = task.id
        downloadTask.resume()

        activeTasks[index].status = .downloading
        activeTasks[index].resumeData = nil

        Task {
            await saveActiveTasks()
        }
    }

    /// Pause all downloads
    func pauseAllDownloads() {
        isPaused = true
        for task in activeTasks where task.status == .downloading {
            pauseDownload(taskId: task.id)
        }
    }

    /// Resume all downloads
    func resumeAllDownloads() {
        isPaused = false
        for task in activeTasks where task.status == .paused {
            resumeDownload(taskId: task.id)
        }
    }

    // MARK: - Delete Operations

    /// Delete a downloaded content
    func deleteDownload(contentId: UUID) async throws {
        guard let download = downloads.first(where: { $0.id == contentId }) else {
            return
        }

        let fileExtension = download.localFilePath.pathExtension
        try await storageManager.deleteFile(for: contentId, fileExtension: fileExtension)

        downloads.removeAll { $0.id == contentId }
        await saveDownloads()
        await updateStorageUsed()
    }

    /// Delete all downloads
    func deleteAllDownloads() async throws {
        try await storageManager.deleteAllContent()
        downloads.removeAll()
        await saveDownloads()
        await updateStorageUsed()
    }

    /// Clear all state on logout - cancels downloads and resets state
    func clearOnLogout() async {
        // Cancel all active downloads
        urlSession.getAllTasks { [weak self] tasks in
            for task in tasks {
                task.cancel()
            }
            Task { @MainActor in
                self?.backgroundTaskMap.removeAll()
            }
        }

        // Clear in-memory state
        downloads.removeAll()
        activeTasks.removeAll()
        totalStorageUsed = 0

        // Note: File cleanup is handled by OfflineStorageManager.deleteCurrentUserData()
    }

    // MARK: - Query Methods

    /// Check if content is downloaded
    func isDownloaded(contentId: UUID) -> Bool {
        downloads.contains { $0.id == contentId }
    }

    /// Get local file path for downloaded content
    func localPath(for contentId: UUID) -> URL? {
        downloads.first { $0.id == contentId }?.localFilePath
    }

    /// Get download progress for content
    func downloadProgress(for contentId: UUID) -> Double? {
        activeTasks.first { $0.contentId == contentId }?.progress
    }

    /// Get download task for content
    func downloadTask(for contentId: UUID) -> DownloadTask? {
        activeTasks.first { $0.contentId == contentId }
    }

    /// Update last accessed time for content
    func markAsAccessed(contentId: UUID) async {
        guard let index = downloads.firstIndex(where: { $0.id == contentId }) else { return }
        downloads[index].lastAccessedAt = Date()
        downloads[index].playCount += 1
        await saveDownloads()
    }

    // MARK: - Storage Management

    /// Get current storage info
    func getStorageInfo() async -> StorageInfo {
        let used = totalStorageUsed
        let deviceAvailable = (try? await storageManager.availableDeviceStorage()) ?? 0

        return StorageInfo(
            used: used,
            limit: storageLimit,
            deviceAvailable: deviceAvailable,
            itemCount: downloads.count
        )
    }

    /// Update storage limit
    func updateStorageLimit(_ newLimit: Int64) async {
        storageLimit = newLimit
        settings.storageLimit = newLimit

        // If over limit, offer to delete content (handled by UI)
        await updateStorageUsed()
    }

    /// Auto-evict old content if needed to fit new download
    func autoEvictIfNeeded(forBytes bytes: Int64) async throws -> [UUID] {
        guard settings.autoDeleteUnused else { return [] }

        let currentUsage = try await storageManager.totalStorageUsed()
        let neededSpace = bytes - (storageLimit - currentUsage)

        guard neededSpace > 0 else { return [] }

        var mutableDownloads = downloads
        let evictedIds = try await storageManager.evictOldContent(
            from: &mutableDownloads,
            toFreeBytes: neededSpace
        )

        downloads = mutableDownloads
        await saveDownloads()
        await updateStorageUsed()

        return evictedIds
    }

    // MARK: - Private Helpers

    private func updateTaskStatus(_ taskId: UUID, status: DownloadStatus, error: Error? = nil) {
        guard let index = activeTasks.firstIndex(where: { $0.id == taskId }) else { return }
        activeTasks[index].status = status
        if let error = error {
            activeTasks[index].errorMessage = error.localizedDescription
        }

        Task {
            await saveActiveTasks()
        }
    }

    private func updateTaskProgress(_ taskId: UUID, bytesDownloaded: Int64, totalBytes: Int64) {
        guard let index = activeTasks.firstIndex(where: { $0.id == taskId }) else { return }
        activeTasks[index].bytesDownloaded = bytesDownloaded
        activeTasks[index].progress = totalBytes > 0 ? Double(bytesDownloaded) / Double(totalBytes) : 0
    }

    private func updateStorageUsed() async {
        totalStorageUsed = (try? await storageManager.totalStorageUsed()) ?? 0
    }

    // MARK: - Persistence

    private func loadPersistedData() async {
        // Load downloads
        if let loaded = try? await storageManager.loadContentIndex() {
            downloads = loaded
        }

        // Load active tasks
        if let tasks: [DownloadTask] = try? await storageManager.loadMetadata(
            key: "active_download_tasks",
            as: [DownloadTask].self
        ) {
            // Restore only paused tasks, others should be re-queued
            activeTasks = tasks.filter { $0.status == .paused }
        }

        // Load settings
        if let loadedSettings: DownloadSettings = try? await storageManager.loadMetadata(
            key: OfflineCacheKey.downloadSettings.rawValue,
            as: DownloadSettings.self
        ) {
            settings = loadedSettings
            storageLimit = loadedSettings.storageLimit
        }

        await updateStorageUsed()
    }

    private func saveDownloads() async {
        try? await storageManager.saveContentIndex(downloads)
    }

    private func saveActiveTasks() async {
        try? await storageManager.saveMetadata(activeTasks, key: "active_download_tasks")
    }

    func saveSettings() async {
        try? await storageManager.saveMetadata(settings, key: OfflineCacheKey.downloadSettings.rawValue)
    }
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        Task { @MainActor in
            await handleDownloadCompletion(
                taskIdentifier: downloadTask.taskIdentifier,
                location: location
            )
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        Task { @MainActor in
            guard let taskId = backgroundTaskMap[downloadTask.taskIdentifier] else { return }
            updateTaskProgress(taskId, bytesDownloaded: totalBytesWritten, totalBytes: totalBytesExpectedToWrite)
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        Task { @MainActor in
            guard let taskId = backgroundTaskMap[task.taskIdentifier] else { return }

            if let error = error {
                // Check if it's a cancellation (user initiated)
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                    // Don't report cancelled downloads as failures
                    return
                }

                updateTaskStatus(taskId, status: .failed, error: error)
                onDownloadFailed?(taskId, error)
            }

            backgroundTaskMap.removeValue(forKey: task.taskIdentifier)
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            backgroundCompletionHandler?()
            backgroundCompletionHandler = nil
        }
    }

    // MARK: - Download Completion Handler

    private func handleDownloadCompletion(taskIdentifier: Int, location: URL) async {
        guard let taskId = backgroundTaskMap[taskIdentifier],
              let task = activeTasks.first(where: { $0.id == taskId }) else {
            return
        }

        do {
            // Move file to permanent storage
            let fileExtension = task.remoteUrl.pathExtension.isEmpty ? "mp3" : task.remoteUrl.pathExtension
            let destination = try await storageManager.moveToStorage(
                from: location,
                contentId: task.contentId,
                fileExtension: fileExtension
            )

            // Get actual file size
            let fileSize = try await storageManager.fileSize(for: task.contentId, fileExtension: fileExtension)

            // Create downloaded content record
            let downloaded = DownloadedContent(
                id: task.contentId,
                contentType: task.contentType,
                title: task.title,
                subtitle: nil,
                localFilePath: destination,
                originalUrl: task.remoteUrl,
                fileSize: fileSize,
                checksum: nil,
                downloadedAt: Date(),
                lastAccessedAt: Date(),
                playCount: 0,
                metadata: nil
            )

            // Update state
            downloads.append(downloaded)
            activeTasks.removeAll { $0.id == taskId }
            backgroundTaskMap.removeValue(forKey: taskIdentifier)

            await saveDownloads()
            await saveActiveTasks()
            await updateStorageUsed()

            onDownloadComplete?(task.contentId)

        } catch {
            updateTaskStatus(taskId, status: .failed, error: error)
            onDownloadFailed?(taskId, error)
        }
    }
}

// MARK: - URLSessionDelegate

extension DownloadManager: URLSessionDelegate {

    nonisolated func urlSession(
        _ session: URLSession,
        didBecomeInvalidWithError error: Error?
    ) {
        if let error = error {
            print("URLSession became invalid: \(error.localizedDescription)")
        }
    }
}
