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
    @Published private(set) var settings: DownloadSettings = .default

    /// Whether downloads are currently paused
    @Published private(set) var isPaused: Bool = false

    /// Last local persistence / load failure for the bound account.
    @Published private(set) var persistenceError: Error?

    /// Whether an account is bound (downloads state is loaded and usable).
    var isBound: Bool { binding != nil }

    // MARK: - Private Properties

    private var urlSession: URLSession!
    private var pendingDownloads: [UUID: UUID] = [:]
    private var sessionGeneration = UUID()
    private var backgroundTaskMap: [Int: UUID] = [:] // URLSessionTask.taskIdentifier -> DownloadTask.id
    private let storageManager = OfflineStorageManager.shared
    /// The account lifecycle this manager serves. Nil until `bind` finishes
    /// loading that account's state; there is no initial or fallback I/O.
    private var binding: OfflineOwnerBinding?
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

        // Observe connectivity for WiFi-only setting
        setupConnectivityObserver()
    }

    // MARK: - Account lifecycle

    private func requireBinding() throws -> OfflineOwnerBinding {
        guard let binding else { throw OfflineStorageError.notBound }
        return binding
    }

    /// Bind to an authenticated owner/epoch (already bound in storage) and load
    /// that account's downloads, tasks and settings. Nothing is read before
    /// this succeeds. Re-binding the same binding is a no-op.
    func bind(_ newBinding: OfflineOwnerBinding) async throws {
        if binding == newBinding { return }
        if binding != nil { unbind() }
        let generation = sessionGeneration
        let loaded = try await loadPersistedData(newBinding)
        // Another unbind/bind may have happened while loading.
        guard generation == sessionGeneration, binding == nil else { throw CancellationError() }
        binding = newBinding
        downloads = loaded.downloads
        activeTasks = loaded.tasks
        settings = loaded.settings ?? .default
        storageLimit = settings.storageLimit
        persistenceError = loaded.error
        await updateStorageUsed()
    }

    /// End the lifecycle synchronously (logout / account switch): invalidate
    /// every in-flight task, cancel transfers, drop in-memory state. Files stay
    /// on disk under their owner.
    func unbind(expected: OfflineOwnerBinding? = nil) {
        if let expected, binding != expected { return }
        sessionGeneration = UUID()
        binding = nil
        pendingDownloads.removeAll()
        backgroundTaskMap.removeAll()
        downloads.removeAll()
        activeTasks.removeAll()
        totalStorageUsed = 0
        persistenceError = nil
        isPaused = false
        settings = .default
        storageLimit = settings.storageLimit
        // Cancel transfers that outlive this lifecycle, but never ones the next
        // lifecycle has registered in the meantime.
        urlSession.getAllTasks { [weak self] tasks in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let live = Set(self.backgroundTaskMap.keys)
                for task in tasks where !live.contains(task.taskIdentifier) { task.cancel() }
            }
        }
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
    func download(_ content: any DownloadableContent, binding expected: OfflineOwnerBinding) async throws {
        let binding = try requireBinding()
        guard binding == expected else { throw OfflineStorageError.staleBinding }
        // Check if already downloaded
        guard !isDownloaded(contentId: content.id) else {
            throw OfflineError.invalidContent
        }

        // Check if already downloading
        guard pendingDownloads[content.id] == nil,
              !activeTasks.contains(where: { $0.contentId == content.id && $0.status != .failed }) else { return }
        // Reserve before storage checks or signing can suspend; failed entries permit manual retry.
        let reservation = UUID()
        let generation = sessionGeneration
        pendingDownloads[content.id] = reservation
        defer {
            if pendingDownloads[content.id] == reservation { pendingDownloads.removeValue(forKey: content.id) }
        }
        activeTasks.removeAll { $0.contentId == content.id && $0.status == .failed }

        // Check storage limit
        let hasSpace = try await storageManager.hasEnoughSpace(
            for: content.estimatedSize,
            currentLimit: storageLimit,
            binding: binding
        )
        try Task.checkCancellation()
        guard generation == sessionGeneration else { throw CancellationError() }
        guard hasSpace else {
            throw OfflineError.storageLimitExceeded
        }

        // Check WiFi-only setting
        if settings.wifiOnlyDownloads && !ConnectivityMonitor.shared.canDownload(wifiOnly: true) {
            throw OfflineError.networkUnavailable
        }

        let accessURL = try await SupabaseStorageMedia.resolve(content.audioUrl)
        try Task.checkCancellation()
        guard generation == sessionGeneration else { throw CancellationError() }
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
        if Task.isCancelled {
            cancelDownload(taskId: task.id)
            throw CancellationError()
        }
        guard generation == sessionGeneration, activeTasks.contains(where: { $0.id == task.id }) else {
            throw CancellationError()
        }

        // Start the download
        let downloadTask = urlSession.downloadTask(with: accessURL)
        backgroundTaskMap[downloadTask.taskIdentifier] = task.id
        downloadTask.resume()

        updateTaskStatus(task.id, status: .downloading)
    }

    /// Cancel a download
    func cancelDownload(taskId: UUID) {
        let identifiers = Set(backgroundTaskMap.filter { $0.value == taskId }.map(\.key))
        activeTasks.removeAll { $0.id == taskId }
        backgroundTaskMap = backgroundTaskMap.filter { $0.value != taskId }
        urlSession.getAllTasks { tasks in
            for task in tasks where identifiers.contains(task.taskIdentifier) { task.cancel() }
        }
        Task { await saveActiveTasks() }
    }

    /// Pause a download
    func pauseDownload(taskId: UUID) {
        // Capture MainActor-isolated data before entering non-isolated closure
        let taskMap = self.backgroundTaskMap

        urlSession.getAllTasks { [weak self] tasks in
            guard let self = self else { return }

            Task { @MainActor [weak self] in
                if let taskIdentifier = taskMap.first(where: { $0.value == taskId })?.key,
                   let downloadTask = tasks.first(where: { $0.taskIdentifier == taskIdentifier }) as? URLSessionDownloadTask {

                    downloadTask.cancel(byProducingResumeData: { resumeData in
                        Task { @MainActor in
                            if let index = self?.activeTasks.firstIndex(where: { $0.id == taskId }) {
                                self?.activeTasks[index].status = .paused
                                self?.activeTasks[index].resumeData = resumeData
                            }
                            await self?.saveActiveTasks()
                        }
                    })
                }
            }
        }
    }

    /// Resume a paused download
    func resumeDownload(taskId: UUID) {
        guard let index = activeTasks.firstIndex(where: { $0.id == taskId }),
              [.paused, .failed].contains(activeTasks[index].status) else {
            return
        }

        let task = activeTasks[index]
        let generation = sessionGeneration

        activeTasks[index].status = .queued
        Task {
            do {
                let url = try await SupabaseStorageMedia.resolve(task.remoteUrl)
                try Task.checkCancellation()
                guard generation == sessionGeneration else { return }
                guard let currentIndex = activeTasks.firstIndex(where: { $0.id == task.id }),
                      activeTasks[currentIndex].status == .queued else { return }
                let downloadTask: URLSessionDownloadTask
                if SupabaseStorageMedia.privateObject(in: task.remoteUrl) == nil, let resumeData = task.resumeData {
                    downloadTask = urlSession.downloadTask(withResumeData: resumeData)
                } else {
                    downloadTask = urlSession.downloadTask(with: url)
                }
                backgroundTaskMap[downloadTask.taskIdentifier] = task.id
                activeTasks[currentIndex].status = .downloading
                activeTasks[currentIndex].resumeData = nil
                downloadTask.resume()
                await saveActiveTasks()
            } catch {
                guard generation == sessionGeneration, !Task.isCancelled else { return }
                updateTaskStatus(task.id, status: .failed, error: error)
            }
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
    func deleteDownload(contentId: UUID, binding expected: OfflineOwnerBinding) async throws {
        guard let download = downloads.first(where: { $0.id == contentId }) else {
            return
        }

        let binding = try requireBinding()
        guard binding == expected else { throw OfflineStorageError.staleBinding }
        let generation = sessionGeneration
        let fileExtension = download.localFilePath.pathExtension
        try await storageManager.deleteFile(for: contentId, fileExtension: fileExtension, binding: binding)
        guard generation == sessionGeneration else { throw CancellationError() }

        downloads.removeAll { $0.id == contentId }
        await saveDownloads()
        await updateStorageUsed()
    }

    /// Delete all downloads
    func deleteAllDownloads(binding expected: OfflineOwnerBinding) async throws {
        let binding = try requireBinding()
        guard binding == expected else { throw OfflineStorageError.staleBinding }
        let generation = sessionGeneration
        try await storageManager.deleteAllContent(binding: binding)
        guard generation == sessionGeneration else { throw CancellationError() }
        downloads.removeAll()
        await saveDownloads()
        await updateStorageUsed()
    }

    /// Clear all state on logout. Equivalent to `unbind()`; kept for callers that
    /// await it. Never touches files.
    func clearOnLogout() async {
        unbind()
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
    func updateStorageLimit(_ newLimit: Int64, binding: OfflineOwnerBinding) async throws {
        var next = settings
        next.storageLimit = newLimit
        try await updateSettings(next, binding: binding)
    }

    func updateSettings(_ next: DownloadSettings, binding expected: OfflineOwnerBinding) async throws {
        guard binding == expected else { throw OfflineStorageError.staleBinding }
        let generation = sessionGeneration
        do {
            try await storageManager.saveMetadata(next, key: OfflineCacheKey.downloadSettings.rawValue, binding: expected)
        } catch {
            recordPersistenceFailure(error, generation)
            throw error
        }
        guard generation == sessionGeneration, binding == expected else { throw CancellationError() }
        settings = next
        storageLimit = next.storageLimit
        await updateStorageUsed()
    }

    /// Auto-evict old content if needed to fit new download
    func autoEvictIfNeeded(forBytes bytes: Int64) async throws -> [UUID] {
        guard settings.autoDeleteUnused else { return [] }

        let binding = try requireBinding()
        let generation = sessionGeneration
        let currentUsage = try await storageManager.totalStorageUsed(binding: binding)
        guard generation == sessionGeneration else { throw CancellationError() }
        let neededSpace = bytes - (storageLimit - currentUsage)

        guard neededSpace > 0 else { return [] }

        var mutableDownloads = downloads
        let evictedIds = try await storageManager.evictOldContent(
            from: &mutableDownloads,
            toFreeBytes: neededSpace,
            binding: binding
        )
        guard generation == sessionGeneration else { throw CancellationError() }

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
        let generation = sessionGeneration
        guard let binding else { totalStorageUsed = 0; return }
        let total = (try? await storageManager.totalStorageUsed(binding: binding)) ?? 0
        guard generation == sessionGeneration else { return }
        totalStorageUsed = total
    }

    // MARK: - Persistence

    private struct LoadedState {
        var downloads: [DownloadedContent] = []
        var tasks: [DownloadTask] = []
        var settings: DownloadSettings?
        var error: Error?
    }

    /// Load one account's state. A missing file is empty state; an unreadable
    /// file is quarantined (kept for recovery) and surfaced, never silently reset.
    private func loadPersistedData(_ binding: OfflineOwnerBinding) async throws -> LoadedState {
        var state = LoadedState()

        func load<T: Codable>(_ key: String, _ type: T.Type) async throws -> T? {
            do {
                return try await storageManager.loadMetadata(key: key, as: type, binding: binding)
            } catch let error as OfflineStorageError {
                throw error                      // notBound / stale: the lifecycle is gone
            } catch {
                state.error = error
                try await storageManager.quarantineMetadata(key: key, binding: binding)
                return nil
            }
        }

        state.downloads = try await load(OfflineCacheKey.downloadedContentIndex.rawValue, [DownloadedContent].self) ?? []
        // Restore only paused tasks, others should be re-queued
        state.tasks = (try await load("active_download_tasks", [DownloadTask].self) ?? []).filter { $0.status == .paused }
        state.settings = try await load(OfflineCacheKey.downloadSettings.rawValue, DownloadSettings.self)
        return state
    }

    /// Persist best-effort, but with the owner/epoch and the data captured
    /// together, synchronously, so a late write can never land in another
    /// account. Failures are surfaced in `persistenceError`.
    private func saveDownloads() async {
        guard let binding else { return }
        let snapshot = downloads
        let generation = sessionGeneration
        do { try await storageManager.saveContentIndex(snapshot, binding: binding) }
        catch { recordPersistenceFailure(error, generation) }
    }

    private func saveActiveTasks() async {
        guard let binding else { return }
        let snapshot = activeTasks
        let generation = sessionGeneration
        do { try await storageManager.saveMetadata(snapshot, key: "active_download_tasks", binding: binding) }
        catch { recordPersistenceFailure(error, generation) }
    }

    private func recordPersistenceFailure(_ error: Error, _ generation: UUID) {
        // A stale-binding rejection is the guard working, not a failure to show.
        if error as? OfflineStorageError == .staleBinding { return }
        guard generation == sessionGeneration else { return }
        persistenceError = error
    }
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode
        guard let status, (200..<300).contains(status) else {
            let error = URLError(status == 401 || status == 403 ? .userAuthenticationRequired : .badServerResponse)
            Task { @MainActor in
                failDownload(taskIdentifier: downloadTask.taskIdentifier, error: error)
            }
            return
        }
        // CRITICAL: The system deletes the temp file at `location` when this method returns.
        // We must copy it synchronously before dispatching to MainActor.
        let tempCopy = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(location.pathExtension)
        do {
            try FileManager.default.copyItem(at: location, to: tempCopy)
        } catch {
            Task { @MainActor in
                failDownload(taskIdentifier: downloadTask.taskIdentifier, error: error)
            }
            return
        }

        Task { @MainActor in
            await handleDownloadCompletion(
                taskIdentifier: downloadTask.taskIdentifier,
                location: tempCopy
            )
            // Clean up our temp copy after processing
            try? FileManager.default.removeItem(at: tempCopy)
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
            guard backgroundTaskMap[task.taskIdentifier] != nil else { return }

            // Successful completion is finalized by didFinishDownloadingTo, including HTTP validation.
            guard let error else { return }
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                backgroundTaskMap.removeValue(forKey: task.taskIdentifier)
                return
            }
            failDownload(taskIdentifier: task.taskIdentifier, error: error)
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            backgroundCompletionHandler?()
            backgroundCompletionHandler = nil
        }
    }

    // MARK: - Download Completion Handler

    private func failDownload(taskIdentifier: Int, error: Error) {
        guard let taskID = backgroundTaskMap.removeValue(forKey: taskIdentifier),
              activeTasks.contains(where: { $0.id == taskID }) else { return }
        updateTaskStatus(taskID, status: .failed, error: error)
        onDownloadFailed?(taskID, error)
    }

    private func handleDownloadCompletion(taskIdentifier: Int, location: URL) async {
        guard let binding,
              let taskId = backgroundTaskMap[taskIdentifier],
              let task = activeTasks.first(where: { $0.id == taskId && $0.status == .downloading }) else {
            return
        }

        // Owner/epoch captured together with the generation; storage verifies
        // the binding BEFORE it removes or moves anything, so a completion that
        // resumes after an account change cannot touch the new account's files.
        let generation = sessionGeneration
        var movedFile: URL?
        do {
            // Move file to permanent storage
            let fileExtension = task.remoteUrl.pathExtension.isEmpty ? "mp3" : task.remoteUrl.pathExtension
            let destination = try await storageManager.moveToStorage(
                from: location,
                contentId: task.contentId,
                fileExtension: fileExtension,
                binding: binding
            )

            movedFile = destination
            guard generation == sessionGeneration else {
                try? await storageManager.removeStoredFile(at: destination, binding: binding)
                return
            }

            // Get actual file size
            let fileSize = try await storageManager.fileSize(for: task.contentId, fileExtension: fileExtension, binding: binding)

            guard generation == sessionGeneration, activeTasks.contains(where: { $0.id == taskId && $0.status == .downloading }) else {
                try? await storageManager.removeStoredFile(at: destination, binding: binding)
                return
            }

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
            guard generation == sessionGeneration else { return }
            await saveActiveTasks()
            guard generation == sessionGeneration else { return }
            await updateStorageUsed()

            guard generation == sessionGeneration else { return }
            onDownloadComplete?(task.contentId)

        } catch {
            guard generation == sessionGeneration else {
                // Only removes a file this stale binding itself placed, and only
                // while that binding is still live; otherwise it is left alone.
                if let movedFile { try? await storageManager.removeStoredFile(at: movedFile, binding: binding) }
                return
            }
            failDownload(taskIdentifier: taskIdentifier, error: error)
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
