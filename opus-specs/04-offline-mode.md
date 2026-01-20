# Offline Mode with Downloadable Content

> Remove the connectivity barrier so mental health support is always available.

**Priority:** P0 - Critical
**Effort:** Medium (4-5 weeks)
**Impact:** Removes major friction point; enables use in more contexts

---

## 1. Overview

### 1.1 What It Does

Enables users to download exercises, meditations, sleep content, and program modules for use without internet connectivity. Core app features work offline with sync when back online.

### 1.2 Why It Exists

- **Friction Removal:** Mental health needs don't pause when offline
- **Accessibility:** Travel, rural areas, data-limited users, privacy-conscious users
- **Competitor Parity:** Calm and Headspace have robust offline libraries
- **Current Gap:** MindFriend has NO offline capability for content

### 1.3 Success Metrics

| Metric                    | Target                               | Measurement                      |
| ------------------------- | ------------------------------------ | -------------------------------- |
| Content downloaded        | 40% of active users download 1+ item | Analytics                        |
| Offline sessions          | 10% of content plays are offline     | Analytics                        |
| Download completion rate  | 95%+                                 | Completed / Started downloads    |
| Offline data sync success | 99%+                                 | Synced / Offline entries created |

---

## 2. User Stories

| Persona          | Need                       | Story                                                                                          |
| ---------------- | -------------------------- | ---------------------------------------------------------------------------------------------- |
| **Traveler**     | In-flight meditation       | "As someone who travels, I want to download meditations so I can use them on planes."          |
| **Commuter**     | Subway breathing exercises | "As a subway commuter, I want exercises available offline since I have no signal underground." |
| **Rural User**   | Unreliable connectivity    | "As someone with spotty internet, I want content downloaded so it always works."               |
| **Privacy User** | Local-only option          | "As someone privacy-conscious, I want to know my content plays locally."                       |

---

## 3. Functional Requirements

### 3.1 Downloadable Content Types

| ID    | Requirement                                      | Priority |
| ----- | ------------------------------------------------ | -------- |
| DC-01 | Download individual exercises (audio)            | Must     |
| DC-02 | Download sleep stories                           | Must     |
| DC-03 | Download soundscapes                             | Must     |
| DC-04 | Download program modules (for enrolled programs) | Should   |
| DC-05 | Download entire exercise categories (batch)      | Should   |
| DC-06 | Download "My Favorites" playlist                 | Should   |
| DC-07 | Download quest-related content for today         | Could    |

### 3.2 Download Management

| ID    | Requirement                                   | Priority |
| ----- | --------------------------------------------- | -------- |
| DM-01 | Show download progress with percentage        | Must     |
| DM-02 | Allow canceling in-progress downloads         | Must     |
| DM-03 | Resume interrupted downloads                  | Should   |
| DM-04 | Queue multiple downloads                      | Must     |
| DM-05 | Background downloads when app is backgrounded | Should   |
| DM-06 | WiFi-only download option                     | Must     |
| DM-07 | Download quality options (standard/high)      | Could    |

### 3.3 Storage Management

| ID    | Requirement                                         | Priority |
| ----- | --------------------------------------------------- | -------- |
| SM-01 | Show total downloaded content size                  | Must     |
| SM-02 | Show per-item storage size                          | Must     |
| SM-03 | Delete individual downloads                         | Must     |
| SM-04 | Delete all downloads at once                        | Must     |
| SM-05 | Set maximum storage limit (default 500MB)           | Should   |
| SM-06 | Auto-delete old/unused downloads when limit reached | Could    |
| SM-07 | Warn when device storage is low                     | Must     |

### 3.4 Offline Functionality

| ID    | Requirement                                    | Priority |
| ----- | ---------------------------------------------- | -------- |
| OF-01 | Play downloaded content without internet       | Must     |
| OF-02 | Log mood entries offline (sync later)          | Must     |
| OF-03 | Complete quests offline (sync later)           | Must     |
| OF-04 | View mood history offline (cached)             | Should   |
| OF-05 | View today's quest offline (cached)            | Must     |
| OF-06 | Clear offline indicator when connected         | Must     |
| OF-07 | Chat shows "requires internet" message offline | Must     |

### 3.5 Sync Behavior

| ID    | Requirement                                  | Priority |
| ----- | -------------------------------------------- | -------- |
| SY-01 | Automatically sync when connectivity returns | Must     |
| SY-02 | Show sync status indicator                   | Should   |
| SY-03 | Handle sync conflicts gracefully             | Must     |
| SY-04 | Retry failed syncs with exponential backoff  | Must     |
| SY-05 | Background sync when app is backgrounded     | Should   |
| SY-06 | Manual "sync now" option                     | Should   |

---

## 4. Technical Requirements

### 4.1 Data Models

```swift
// MARK: - Offline Storage Models

struct DownloadedContent: Identifiable, Codable {
    let id: UUID // Same as content ID
    let contentType: OfflineContentType
    let title: String
    let localFilePath: URL
    let originalUrl: URL
    let fileSize: Int64 // bytes
    let downloadedAt: Date
    var lastAccessedAt: Date
    var playCount: Int

    enum OfflineContentType: String, Codable {
        case exercise
        case sleepStory
        case soundscape
        case programModule
    }
}

struct DownloadTask: Identifiable {
    let id: UUID
    let contentId: UUID
    let contentType: DownloadedContent.OfflineContentType
    let title: String
    let remoteUrl: URL
    let estimatedSize: Int64
    var status: DownloadStatus
    var progress: Double // 0.0 - 1.0
    var error: Error?

    enum DownloadStatus {
        case queued
        case downloading
        case paused
        case completed
        case failed
    }
}

struct OfflineMoodEntry: Identifiable, Codable {
    let id: UUID
    let moodScore: Int
    let anxietyLevel: Int?
    let energyLevel: Int?
    let notes: String?
    let createdAt: Date
    var synced: Bool
}

struct OfflineQuestCompletion: Identifiable, Codable {
    let id: UUID
    let questId: UUID
    let completedAt: Date
    var synced: Bool
}

struct OfflineExerciseSession: Identifiable, Codable {
    let id: UUID
    let exerciseId: UUID
    let durationSeconds: Int
    let completedAt: Date
    var synced: Bool
}

struct OfflineSyncQueue: Codable {
    var moodEntries: [OfflineMoodEntry]
    var questCompletions: [OfflineQuestCompletion]
    var exerciseSessions: [OfflineExerciseSession]

    var totalPending: Int {
        moodEntries.filter { !$0.synced }.count +
        questCompletions.filter { !$0.synced }.count +
        exerciseSessions.filter { !$0.synced }.count
    }
}
```

### 4.2 Download Manager Service

```swift
// MARK: - DownloadManager

import Foundation
import Combine

@MainActor
class DownloadManager: ObservableObject {
    static let shared = DownloadManager()

    @Published var downloads: [DownloadedContent] = []
    @Published var activeTasks: [DownloadTask] = []
    @Published var totalStorageUsed: Int64 = 0
    @Published var maxStorageLimit: Int64 = 500 * 1024 * 1024 // 500MB default

    private let fileManager = FileManager.default
    private let downloadsDirectory: URL
    private var urlSession: URLSession!
    private var backgroundTasks: [URLSessionDownloadTask: UUID] = [:]

    private init() {
        // Create downloads directory
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        downloadsDirectory = appSupport.appendingPathComponent("OfflineContent", isDirectory: true)

        try? fileManager.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)

        // Configure background session
        let config = URLSessionConfiguration.background(withIdentifier: "com.mindfriend.downloads")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        loadDownloads()
    }

    // MARK: - Download Operations

    func download(content: any DownloadableContent) async throws {
        guard !isDownloaded(contentId: content.id) else { return }
        guard totalStorageUsed + content.estimatedSize <= maxStorageLimit else {
            throw DownloadError.storageLimitExceeded
        }

        let task = DownloadTask(
            id: UUID(),
            contentId: content.id,
            contentType: content.offlineContentType,
            title: content.title,
            remoteUrl: content.audioUrl,
            estimatedSize: content.estimatedSize,
            status: .queued,
            progress: 0
        )

        activeTasks.append(task)

        let downloadTask = urlSession.downloadTask(with: content.audioUrl)
        backgroundTasks[downloadTask] = task.id
        downloadTask.resume()

        updateTaskStatus(task.id, status: .downloading)
    }

    func cancelDownload(taskId: UUID) {
        if let (task, _) = backgroundTasks.first(where: { $0.value == taskId }) {
            task.cancel()
        }
        activeTasks.removeAll { $0.id == taskId }
    }

    func deleteDownload(contentId: UUID) throws {
        guard let download = downloads.first(where: { $0.id == contentId }) else { return }

        try fileManager.removeItem(at: download.localFilePath)
        downloads.removeAll { $0.id == contentId }
        saveDownloads()
        updateStorageUsed()
    }

    func deleteAllDownloads() throws {
        for download in downloads {
            try? fileManager.removeItem(at: download.localFilePath)
        }
        downloads.removeAll()
        saveDownloads()
        updateStorageUsed()
    }

    // MARK: - Query Methods

    func isDownloaded(contentId: UUID) -> Bool {
        downloads.contains { $0.id == contentId }
    }

    func localPath(for contentId: UUID) -> URL? {
        downloads.first { $0.id == contentId }?.localFilePath
    }

    func downloadProgress(for contentId: UUID) -> Double? {
        activeTasks.first { $0.contentId == contentId }?.progress
    }

    // MARK: - Storage Management

    private func updateStorageUsed() {
        totalStorageUsed = downloads.reduce(0) { $0 + $1.fileSize }
    }

    // MARK: - Persistence

    private func loadDownloads() {
        let metadataPath = downloadsDirectory.appendingPathComponent("metadata.json")
        guard let data = try? Data(contentsOf: metadataPath),
              let loaded = try? JSONDecoder().decode([DownloadedContent].self, from: data) else {
            return
        }
        downloads = loaded.filter { fileManager.fileExists(atPath: $0.localFilePath.path) }
        updateStorageUsed()
    }

    private func saveDownloads() {
        let metadataPath = downloadsDirectory.appendingPathComponent("metadata.json")
        guard let data = try? JSONEncoder().encode(downloads) else { return }
        try? data.write(to: metadataPath)
    }
}

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let taskId = backgroundTasks[downloadTask],
              let task = activeTasks.first(where: { $0.id == taskId }) else { return }

        let fileName = "\(task.contentId.uuidString).\(task.remoteUrl.pathExtension)"
        let destination = downloadsDirectory.appendingPathComponent(fileName)

        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: location, to: destination)

            let attributes = try fileManager.attributesOfItem(atPath: destination.path)
            let fileSize = attributes[.size] as? Int64 ?? 0

            let downloaded = DownloadedContent(
                id: task.contentId,
                contentType: task.contentType,
                title: task.title,
                localFilePath: destination,
                originalUrl: task.remoteUrl,
                fileSize: fileSize,
                downloadedAt: Date(),
                lastAccessedAt: Date(),
                playCount: 0
            )

            Task { @MainActor in
                downloads.append(downloaded)
                activeTasks.removeAll { $0.id == taskId }
                saveDownloads()
                updateStorageUsed()
            }
        } catch {
            Task { @MainActor in
                updateTaskStatus(taskId, status: .failed, error: error)
            }
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let taskId = backgroundTasks[downloadTask] else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)

        Task { @MainActor in
            if let index = activeTasks.firstIndex(where: { $0.id == taskId }) {
                activeTasks[index].progress = progress
            }
        }
    }
}

// MARK: - Errors

enum DownloadError: LocalizedError {
    case storageLimitExceeded
    case downloadFailed(Error)
    case fileNotFound

    var errorDescription: String? {
        switch self {
        case .storageLimitExceeded:
            return "Storage limit reached. Delete some downloads to make room."
        case .downloadFailed(let error):
            return "Download failed: \(error.localizedDescription)"
        case .fileNotFound:
            return "Downloaded file not found."
        }
    }
}
```

### 4.3 Offline Sync Service

```swift
// MARK: - OfflineSyncService

import Foundation
import Network

@MainActor
class OfflineSyncService: ObservableObject {
    static let shared = OfflineSyncService()

    @Published var isOnline = true
    @Published var pendingSyncCount = 0
    @Published var lastSyncAt: Date?
    @Published var isSyncing = false

    private let monitor = NWPathMonitor()
    private var syncQueue: OfflineSyncQueue
    private let dataService: SupabaseDataService

    private let queuePath: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("offline_sync_queue.json")
    }()

    private init() {
        dataService = SupabaseDataService.shared
        syncQueue = OfflineSyncQueue(moodEntries: [], questCompletions: [], exerciseSessions: [])
        loadQueue()

        // Monitor connectivity
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = path.status == .satisfied
                if path.status == .satisfied {
                    await self?.syncPendingData()
                }
            }
        }
        monitor.start(queue: .global())
    }

    // MARK: - Offline Data Entry

    func saveMoodOffline(score: Int, anxiety: Int?, energy: Int?, notes: String?) {
        let entry = OfflineMoodEntry(
            id: UUID(),
            moodScore: score,
            anxietyLevel: anxiety,
            energyLevel: energy,
            notes: notes,
            createdAt: Date(),
            synced: false
        )
        syncQueue.moodEntries.append(entry)
        saveQueue()
        updatePendingCount()
    }

    func saveQuestCompletionOffline(questId: UUID) {
        let completion = OfflineQuestCompletion(
            id: UUID(),
            questId: questId,
            completedAt: Date(),
            synced: false
        )
        syncQueue.questCompletions.append(completion)
        saveQueue()
        updatePendingCount()
    }

    func saveExerciseSessionOffline(exerciseId: UUID, duration: Int) {
        let session = OfflineExerciseSession(
            id: UUID(),
            exerciseId: exerciseId,
            durationSeconds: duration,
            completedAt: Date(),
            synced: false
        )
        syncQueue.exerciseSessions.append(session)
        saveQueue()
        updatePendingCount()
    }

    // MARK: - Sync

    func syncPendingData() async {
        guard isOnline, !isSyncing else { return }
        isSyncing = true

        defer {
            isSyncing = false
            updatePendingCount()
        }

        // Sync mood entries
        for i in syncQueue.moodEntries.indices where !syncQueue.moodEntries[i].synced {
            let entry = syncQueue.moodEntries[i]
            do {
                try await dataService.logMood(
                    score: entry.moodScore,
                    anxiety: entry.anxietyLevel,
                    energy: entry.energyLevel,
                    notes: entry.notes
                )
                syncQueue.moodEntries[i].synced = true
            } catch {
                print("Failed to sync mood entry: \(error)")
            }
        }

        // Sync quest completions
        for i in syncQueue.questCompletions.indices where !syncQueue.questCompletions[i].synced {
            let completion = syncQueue.questCompletions[i]
            do {
                try await dataService.completeQuest(questId: completion.questId)
                syncQueue.questCompletions[i].synced = true
            } catch {
                print("Failed to sync quest completion: \(error)")
            }
        }

        // Sync exercise sessions
        for i in syncQueue.exerciseSessions.indices where !syncQueue.exerciseSessions[i].synced {
            let session = syncQueue.exerciseSessions[i]
            do {
                try await dataService.logExerciseSession(
                    exerciseId: session.exerciseId,
                    duration: session.durationSeconds
                )
                syncQueue.exerciseSessions[i].synced = true
            } catch {
                print("Failed to sync exercise session: \(error)")
            }
        }

        // Clean up synced items
        syncQueue.moodEntries.removeAll { $0.synced }
        syncQueue.questCompletions.removeAll { $0.synced }
        syncQueue.exerciseSessions.removeAll { $0.synced }

        saveQueue()
        lastSyncAt = Date()
    }

    // MARK: - Persistence

    private func loadQueue() {
        guard let data = try? Data(contentsOf: queuePath),
              let loaded = try? JSONDecoder().decode(OfflineSyncQueue.self, from: data) else {
            return
        }
        syncQueue = loaded
        updatePendingCount()
    }

    private func saveQueue() {
        guard let data = try? JSONEncoder().encode(syncQueue) else { return }
        try? data.write(to: queuePath)
    }

    private func updatePendingCount() {
        pendingSyncCount = syncQueue.totalPending
    }
}
```

### 4.4 Offline Cache Service

```swift
// MARK: - OfflineCacheService

import Foundation

actor OfflineCacheService {
    static let shared = OfflineCacheService()

    private let cacheDirectory: URL
    private let fileManager = FileManager.default

    private init() {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = caches.appendingPathComponent("OfflineCache", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Cache Operations

    func cache<T: Codable>(_ data: T, key: String) throws {
        let path = cacheDirectory.appendingPathComponent("\(key).json")
        let encoded = try JSONEncoder().encode(data)
        try encoded.write(to: path)
    }

    func retrieve<T: Codable>(key: String, as type: T.Type) throws -> T? {
        let path = cacheDirectory.appendingPathComponent("\(key).json")
        guard fileManager.fileExists(atPath: path.path) else { return nil }
        let data = try Data(contentsOf: path)
        return try JSONDecoder().decode(type, from: data)
    }

    func invalidate(key: String) {
        let path = cacheDirectory.appendingPathComponent("\(key).json")
        try? fileManager.removeItem(at: path)
    }

    func invalidateAll() {
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Specific Caches

    func cacheTodayQuest(_ quest: Quest) async throws {
        try cache(quest, key: "today_quest")
    }

    func getCachedTodayQuest() async throws -> Quest? {
        try retrieve(key: "today_quest", as: Quest.self)
    }

    func cacheMoodHistory(_ moods: [MoodEntry]) async throws {
        try cache(moods, key: "mood_history")
    }

    func getCachedMoodHistory() async throws -> [MoodEntry]? {
        try retrieve(key: "mood_history", as: [MoodEntry].self)
    }

    func cacheExerciseLibrary(_ exercises: [Exercise]) async throws {
        try cache(exercises, key: "exercise_library")
    }

    func getCachedExerciseLibrary() async throws -> [Exercise]? {
        try retrieve(key: "exercise_library", as: [Exercise].self)
    }
}
```

---

## 5. UI/UX Specifications

### 5.1 Download Button States

```
Available for Download:
┌────────────────────────────────┐
│ ⬇️ 4.2 MB                      │
│ [Download]                     │
└────────────────────────────────┘

Downloading:
┌────────────────────────────────┐
│ ████████░░░░ 67%               │
│ [Cancel]                       │
└────────────────────────────────┘

Downloaded:
┌────────────────────────────────┐
│ ✓ Downloaded • 4.2 MB          │
│ [Remove]                       │
└────────────────────────────────┘
```

### 5.2 Downloads Management Screen

```
┌─────────────────────────────────┐
│ ← Downloads                     │
├─────────────────────────────────┤
│                                 │
│ Storage Used                    │
│ ┌─────────────────────────────┐ │
│ │ ████████████░░░░ 312 MB     │ │
│ │ of 500 MB limit             │ │
│ │ [Change Limit]              │ │
│ └─────────────────────────────┘ │
│                                 │
│ Download Settings               │
│ ┌─────────────────────────────┐ │
│ │ WiFi only              [•]  │ │
│ │ Auto-delete unused     [ ]  │ │
│ └─────────────────────────────┘ │
│                                 │
│ Downloaded Content              │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ 🧘 Morning Meditation       │ │
│ │ Exercise • 12.4 MB          │ │
│ │ Downloaded 3 days ago       │ │
│ │                    [Delete] │ │
│ ├─────────────────────────────┤ │
│ │ 🌧️ Rainy Night             │ │
│ │ Sleep Story • 45.2 MB       │ │
│ │ Downloaded 1 week ago       │ │
│ │                    [Delete] │ │
│ ├─────────────────────────────┤ │
│ │ 🌊 Ocean Waves              │ │
│ │ Soundscape • 8.1 MB         │ │
│ │ Downloaded yesterday        │ │
│ │                    [Delete] │ │
│ └─────────────────────────────┘ │
│                                 │
│ [Delete All Downloads]          │
│                                 │
└─────────────────────────────────┘
```

### 5.3 Offline Indicator

```
┌─────────────────────────────────┐
│ ⚡ Offline                      │
│ ─────────────────────────────── │
│ Some features require internet  │
│                                 │
│ Available offline:              │
│ ✓ Downloaded content            │
│ ✓ Mood check-in (syncs later)   │
│ ✓ Quest completion              │
│                                 │
│ Requires internet:              │
│ ✗ AI Chat                       │
│ ✗ Voice mode                    │
│ ✗ Circle updates                │
│                                 │
│ [View Downloaded Content]       │
└─────────────────────────────────┘
```

### 5.4 Sync Status Banner

```
┌─────────────────────────────────┐
│ ↻ 3 items pending sync          │
│   Will sync when online         │
└─────────────────────────────────┘

(When online and syncing:)
┌─────────────────────────────────┐
│ ↻ Syncing... 2 of 3             │
└─────────────────────────────────┘

(Sync complete:)
┌─────────────────────────────────┐
│ ✓ All changes synced            │
└─────────────────────────────────┘
```

---

## 6. Acceptance Criteria

### 6.1 Downloads

- [ ] User can download individual exercises, stories, soundscapes
- [ ] Download progress shows percentage
- [ ] User can cancel in-progress downloads
- [ ] Downloads continue in background
- [ ] WiFi-only option is respected
- [ ] Downloaded content shows checkmark indicator

### 6.2 Storage

- [ ] Total storage used is displayed accurately
- [ ] User can delete individual downloads
- [ ] User can delete all downloads
- [ ] Storage limit is enforced (500MB default)
- [ ] Warning shows when device storage is low

### 6.3 Offline Playback

- [ ] Downloaded content plays without internet
- [ ] Audio quality matches downloaded quality
- [ ] Play count is tracked offline
- [ ] Content library shows which items are available offline

### 6.4 Offline Data Entry

- [ ] Mood can be logged offline
- [ ] Quest can be completed offline
- [ ] Exercise session can be recorded offline
- [ ] Offline entries show pending sync indicator

### 6.5 Sync

- [ ] Data syncs automatically when connectivity returns
- [ ] Sync conflicts are resolved (server wins for conflicts)
- [ ] Failed syncs retry with backoff
- [ ] Sync status is visible to user

### 6.6 Offline UI

- [ ] Offline banner appears when no connectivity
- [ ] Features requiring internet show clear message
- [ ] Today's quest is cached and viewable offline
- [ ] Mood history is cached and viewable offline

---

## 7. Edge Cases & Error Handling

| Scenario                               | Behavior                                          |
| -------------------------------------- | ------------------------------------------------- |
| Download interrupted                   | Resume on next attempt; partial file preserved    |
| Storage full during download           | Cancel download; show storage management prompt   |
| Offline for 30+ days                   | Prompt to sync before content expires             |
| Sync conflict (mood at same time)      | Server version wins; notify user                  |
| Downloaded file corrupted              | Detect via checksum; auto-redownload              |
| App deleted and reinstalled            | Downloads lost; sync queue preserved if backed up |
| Multiple offline mood entries          | Sync all with original timestamps                 |
| Downloaded content updated server-side | Notify user; offer to re-download                 |

---

## 8. Security Considerations

| Area                | Requirement                                  |
| ------------------- | -------------------------------------------- |
| Downloaded Files    | Encrypted at rest using iOS Data Protection  |
| Signed URLs         | Use time-limited signed URLs for downloads   |
| Offline Data        | Encrypted in device storage                  |
| Sync Authentication | Refresh token before sync if expired         |
| File Integrity      | Checksum verification on download completion |

---

## 9. Performance Requirements

| Metric                       | Target                           |
| ---------------------------- | -------------------------------- |
| Download speed               | Utilize full available bandwidth |
| Background download impact   | < 5% battery per 100MB           |
| Offline playback start       | < 500ms                          |
| Sync time                    | < 5 seconds for 10 items         |
| Storage calculation          | < 1 second                       |
| App launch with offline data | No impact on launch time         |

---

## 10. Dependencies

### 10.1 Internal

| Dependency           | Reason                         |
| -------------------- | ------------------------------ |
| Audio Player Service | Playback of downloaded content |
| Mood Service         | Offline mood entry             |
| Quest Service        | Offline quest completion       |
| Exercise Service     | Offline session logging        |

### 10.2 System

| Dependency            | Reason                 |
| --------------------- | ---------------------- |
| URLSession Background | Background downloads   |
| NWPathMonitor         | Connectivity detection |
| FileManager           | Local file storage     |
| Data Protection       | File encryption        |

---

## 11. Rollout Plan

### Phase 1: Foundation (Week 1-2)

- Download manager infrastructure
- Storage management
- Basic download/delete functionality

### Phase 2: Offline Playback (Week 3)

- Content playback from local files
- Offline indicator UI
- Feature availability messaging

### Phase 3: Offline Data (Week 4)

- Offline mood logging
- Offline quest completion
- Sync queue implementation

### Phase 4: Polish (Week 5)

- Background downloads
- Sync status UI
- Storage warnings
- WiFi-only option
