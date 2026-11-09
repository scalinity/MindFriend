//
//  SyncQueueManager.swift
//  MindFriendApp
//
//  Manages queuing and syncing of offline data entries
//
//  Ownership model: the queue only exists inside a bound lifecycle
//  (`bind(userId:epoch:...)` ... `unbind()`). The owner and epoch of a
//  lifecycle never change; every task captures its lifecycle and re-checks
//  it after each suspension, and every storage call carries the captured
//  owner/epoch, so nothing started for one account can read, write or
//  publish into another.
//
//  Delivery contract (IMPORTANT for the parent's backend handlers): a handler
//  may be invoked more than once for the same item (crash after the server
//  accepted it but before the local result was saved). The item's stable `id`
//  (`idempotencyKey`) is the only identity that survives replays; the
//  server operation MUST be an owner-scoped idempotent upsert keyed by it.
//  The manager itself never re-sends an item whose accepted/rejected outcome
//  is already known in this process, even if recording it on disk failed.
//

import Foundation
import Combine

/// Errors surfaced by `SyncQueueManager`.
enum SyncQueueError: Error, Equatable, LocalizedError {
    /// No authenticated owner is bound. Nothing was saved.
    case notBound
    /// The account lifecycle ended while the operation was in flight.
    case lifecycleEnded
    /// A bind request carried an epoch that is not newer than the live lifecycle.
    case staleEpoch
    /// An unreadable queue was quarantined. The recovery copies must be
    /// exported or discarded by an explicit user decision before new work is
    /// accepted, so an empty replacement queue never silently masks lost work.
    case recoveryRequired

    var errorDescription: String? {
        switch self {
        case .notBound: return "Offline sync is not available until you are signed in."
        case .lifecycleEnded: return "The account changed before the operation finished."
        case .staleEpoch: return "Offline sync rejected an out-of-date sign-in."
        case .recoveryRequired: return "Some saved offline entries could not be read and were set aside for recovery."
        }
    }
}

/// A sync handler may throw this to stop automatic retry of one item
/// (validation / ownership / auth failures that retrying cannot fix).
enum OfflineSyncHandlerError: Error, Equatable, LocalizedError {
    case nonRetryable(String)

    var errorDescription: String? {
        switch self {
        case .nonRetryable(let reason): return reason
        }
    }
}

/// Stable identity a backend handler must use as its idempotency key.
protocol OfflineSyncIdentifiable {
    var id: UUID { get }
}

extension OfflineSyncIdentifiable {
    var idempotencyKey: String { id.uuidString.lowercased() }
}

extension OfflineMoodEntry: OfflineSyncIdentifiable {}
extension OfflineQuestCompletion: OfflineSyncIdentifiable {}
extension OfflineExerciseSession: OfflineSyncIdentifiable {}

/// Manages offline data entries and syncs them when connectivity returns
@MainActor
final class SyncQueueManager: ObservableObject {

    // MARK: - Singleton

    static let shared = SyncQueueManager()

    // MARK: - Published Properties

    /// The durable queue (always equal to what was last written to disk).
    /// Empty while unbound.
    @Published private(set) var syncQueue: OfflineSyncQueue = OfflineSyncQueue()

    /// Number of items not yet durably settled (includes items the server
    /// accepted whose result could not yet be saved on this device).
    @Published private(set) var pendingSyncCount: Int = 0

    /// Items whose server outcome (accepted / rejected) is known but not yet
    /// durably recorded. They are never re-sent; only their result is saved.
    @Published private(set) var unresolvedOutcomeCount: Int = 0

    /// Whether currently syncing
    @Published private(set) var isSyncing: Bool = false

    /// Last successful sync time
    @Published private(set) var lastSyncAt: Date?

    /// Current sync status message
    @Published private(set) var syncStatusMessage: String = ""

    /// Sync error if any
    @Published private(set) var syncError: Error?

    /// Last local persistence failure (a save that could not be made durable).
    @Published private(set) var persistenceError: Error?

    /// Quarantined copies of an unreadable queue. Non-empty means recovery is
    /// required; this survives logout and relaunch because it is derived from
    /// the files on disk at every bind.
    @Published private(set) var quarantinedQueueURLs: [URL] = []

    /// Whether new work is blocked pending an explicit recovery decision.
    var recoveryRequired: Bool { !quarantinedQueueURLs.isEmpty }

    /// Whether a lifecycle is currently bound.
    var isBound: Bool { lifecycle != nil }

    /// The live owner/epoch, if bound.
    var currentBinding: OfflineOwnerBinding? { lifecycle?.binding }

    // MARK: - Types

    struct Handlers {
        let mood: (OfflineMoodEntry) async throws -> Void
        let quest: (OfflineQuestCompletion) async throws -> Void
        let exercise: (OfflineExerciseSession) async throws -> Void
    }

    /// One immutable bound lifecycle. `generation` distinguishes lifecycles
    /// even if the same owner/epoch were ever presented twice.
    private struct Lifecycle {
        let binding: OfflineOwnerBinding
        let generation: Int
        let handlers: Handlers
    }

    private enum ItemKind { case mood, quest, exercise }
    private struct ItemRef: Hashable { let kind: ItemKind; let id: UUID }

    private enum ResolvedOutcome {
        case accepted
        case rejected(String)
    }

    private struct PassResult {
        var synced = 0
        var transientFailures = 0
        var rejected = 0
        var interrupted = false
    }

    private enum ItemOutcome { case synced, accepted, rejected, transient, skipped, interrupted }

    // MARK: - Private Properties

    private let storageManager: OfflineStorageManager
    private let connectivityMonitor: ConnectivityMonitor
    private let isConnectedProvider: @MainActor () -> Bool
    private let sleep: (TimeInterval) async throws -> Void
    private let autoSync: Bool

    private let maxRetryAttempts = 5
    private let baseRetryDelay: TimeInterval = 2.0
    /// Consecutive failing passes after which the scheduler stops until a new
    /// trigger (new work, foreground, connectivity, bind) arrives.
    private let maxConsecutiveFailingPasses = 8

    private var lifecycle: Lifecycle?
    private var generationCounter = 0
    private var pendingBindGeneration: Int?
    private var syncTask: Task<PassResult?, Never>?
    private var retryTask: Task<Void, Never>?
    private var autoSyncTask: Task<Void, Never>?
    private var retryToken = 0
    private var consecutiveFailingPasses = 0
    private var rerunRequested = false
    private var ownsConnectivityCallback = false
    private var unresolved: [ItemRef: ResolvedOutcome] = [:]

    // Serializes every queue mutation so no copy of the queue is held across an await
    private var gateBusy = false
    private var gateWaiters: [CheckedContinuation<Void, Never>] = []

    // MARK: - Initialization

    /// No I/O at init: the queue is loaded only by `bind`, after authenticated
    /// user restoration, so it can never be read from an identityless location.
    private init() {
        storageManager = OfflineStorageManager.shared
        connectivityMonitor = ConnectivityMonitor.shared
        isConnectedProvider = { ConnectivityMonitor.shared.isConnected }
        sleep = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }
        autoSync = true
    }

    /// Test seam with injectable storage, connectivity, clock and scheduling.
    init(
        storageManager: OfflineStorageManager,
        connectivityMonitor: ConnectivityMonitor? = nil,
        isConnected: @escaping @MainActor () -> Bool,
        sleep: @escaping (TimeInterval) async throws -> Void = { try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) },
        autoSync: Bool = false
    ) {
        self.storageManager = storageManager
        self.connectivityMonitor = connectivityMonitor ?? ConnectivityMonitor.shared
        self.isConnectedProvider = isConnected
        self.sleep = sleep
        self.autoSync = autoSync
    }

    // MARK: - Lifecycle

    /// Bind the queue to an authenticated owner and account epoch, then load
    /// that owner's persisted queue. Call after user restoration, before any
    /// user data is shown. Binding the same owner/epoch again is a no-op.
    /// A different binding must carry a strictly greater epoch and replaces the
    /// previous lifecycle (whose in-flight work is cancelled and discarded).
    func bind(
        userId: String,
        epoch: UInt64,
        moodSyncHandler: @escaping (OfflineMoodEntry) async throws -> Void,
        questSyncHandler: @escaping (OfflineQuestCompletion) async throws -> Void,
        exerciseSyncHandler: @escaping (OfflineExerciseSession) async throws -> Void
    ) async throws {
        let requested = OfflineOwnerBinding(userId: userId, epoch: epoch)
        if let current = lifecycle {
            if current.binding == requested { return }
            guard epoch > current.binding.epoch else { throw SyncQueueError.staleEpoch }
            endLifecycle()
        }

        generationCounter += 1
        let generation = generationCounter
        pendingBindGeneration = generation

        let storageBinding = try await storageManager.bind(userId: userId, epoch: epoch)

        // Another bind/unbind may have run while storage was binding.
        guard pendingBindGeneration == generation, lifecycle == nil else {
            await storageManager.unbind(storageBinding)
            throw SyncQueueError.lifecycleEnded
        }

        var loaded = OfflineSyncQueue()
        var loadError: Error?
        do {
            loaded = try await storageManager.loadMetadata(
                key: OfflineCacheKey.syncQueue.rawValue,
                as: OfflineSyncQueue.self,
                binding: storageBinding
            ) ?? OfflineSyncQueue()
        } catch OfflineStorageError.staleBinding {
            throw SyncQueueError.lifecycleEnded
        } catch {
            // Unreadable queue: keep the bytes for recovery, never overwrite silently.
            loadError = error
            try await storageManager.quarantineMetadata(
                key: OfflineCacheKey.syncQueue.rawValue,
                binding: storageBinding
            )
        }

        // Recovery copies (from this or any earlier launch) block new work until
        // the user decides; derived from disk so it survives relaunch.
        let copies = try await storageManager.quarantinedMetadata(
            key: OfflineCacheKey.syncQueue.rawValue,
            binding: storageBinding
        )

        guard pendingBindGeneration == generation, lifecycle == nil else {
            await storageManager.unbind(storageBinding)
            throw SyncQueueError.lifecycleEnded
        }

        lifecycle = Lifecycle(
            binding: storageBinding,
            generation: generation,
            handlers: Handlers(mood: moodSyncHandler, quest: questSyncHandler, exercise: exerciseSyncHandler)
        )
        pendingBindGeneration = nil
        syncQueue = loaded
        quarantinedQueueURLs = copies
        persistenceError = loadError ?? (copies.isEmpty ? nil : SyncQueueError.recoveryRequired)
        lastSyncAt = loaded.lastSuccessfulSync
        updatePendingCount()
        installConnectivityObserver(generation: generation)
        requestSync()
    }

    /// End the current lifecycle immediately (safe to call from logout before
    /// another account can sign in). Cancels in-flight sync and scheduled
    /// retries, drops handlers and in-memory data, and detaches observers.
    /// Persisted unsynced work and recovery copies are left on disk under their
    /// owner; they are NOT deleted here.
    func unbind(expected: OfflineOwnerBinding? = nil) {
        if let expected, lifecycle?.binding != expected { return }
        let ended = lifecycle?.binding
        endLifecycle()
        if let ended {
            Task { await storageManager.unbind(ended) }
        }
    }

    private func endLifecycle() {
        generationCounter += 1          // invalidates every captured lifecycle
        pendingBindGeneration = nil
        syncTask?.cancel()
        syncTask = nil
        retryTask?.cancel()
        retryTask = nil
        autoSyncTask?.cancel()
        autoSyncTask = nil
        retryToken += 1
        consecutiveFailingPasses = 0
        rerunRequested = false
        if ownsConnectivityCallback {
            connectivityMonitor.onConnectivityRestored = nil
            ownsConnectivityCallback = false
        }
        lifecycle = nil
        unresolved.removeAll()
        unresolvedOutcomeCount = 0
        syncQueue = OfflineSyncQueue()
        pendingSyncCount = 0
        isSyncing = false
        lastSyncAt = nil
        syncStatusMessage = ""
        syncError = nil
        persistenceError = nil
        quarantinedQueueURLs = []
    }

    private func installConnectivityObserver(generation: Int) {
        ownsConnectivityCallback = true
        connectivityMonitor.onConnectivityRestored = { [weak self] in
            await self?.syncIfCurrent(generation: generation)
        }
    }

    private func syncIfCurrent(generation: Int) async {
        guard lifecycle?.generation == generation else { return }
        consecutiveFailingPasses = 0
        await syncPendingData()
    }

    /// Call when the app returns to the foreground.
    func applicationDidBecomeActive() {
        consecutiveFailingPasses = 0
        requestSync()
    }

    private func requestSync() {
        guard autoSync, lifecycle != nil else { return }
        autoSyncTask = Task { [weak self] in await self?.syncPendingData() }
    }

    private func requireLifecycle() throws -> Lifecycle {
        guard let lifecycle else { throw SyncQueueError.notBound }
        return lifecycle
    }

    private func isCurrent(_ lc: Lifecycle) -> Bool {
        lifecycle?.generation == lc.generation
    }

    // MARK: - Recovery

    /// Permanently delete the quarantined recovery copies. Call only after the
    /// user has exported them or explicitly chosen to discard them.
    func discardQuarantinedQueues() async throws {
        let lc = try requireLifecycle()
        await acquireGate()
        defer { releaseGate() }
        guard isCurrent(lc) else { throw SyncQueueError.lifecycleEnded }
        do {
            try await storageManager.deleteQuarantinedMetadata(
                key: OfflineCacheKey.syncQueue.rawValue,
                binding: lc.binding
            )
        } catch OfflineStorageError.staleBinding {
            throw SyncQueueError.lifecycleEnded
        }
        guard isCurrent(lc) else { throw SyncQueueError.lifecycleEnded }
        quarantinedQueueURLs = []
        if persistenceError as? SyncQueueError == .recoveryRequired { persistenceError = nil }
    }

    // MARK: - Mutation gate

    private func acquireGate() async {
        if gateBusy {
            await withCheckedContinuation { gateWaiters.append($0) }
        } else {
            gateBusy = true
        }
    }

    private func releaseGate() {
        if gateWaiters.isEmpty {
            gateBusy = false
        } else {
            gateWaiters.removeFirst().resume()
        }
    }

    /// Apply a change to a COPY of the queue, make it durable, and only then
    /// publish it. A failed or cancelled write throws and leaves the visible
    /// queue unchanged, so callers can never be told "saved" for lost work.
    private func mutate<T>(allowDuringRecovery: Bool = false, _ change: (inout OfflineSyncQueue) throws -> T) async throws -> T {
        let lc = try requireLifecycle()
        await acquireGate()
        defer { releaseGate() }
        guard isCurrent(lc) else { throw SyncQueueError.lifecycleEnded }
        if recoveryRequired && !allowDuringRecovery { throw SyncQueueError.recoveryRequired }
        try Task.checkCancellation()

        var next = syncQueue
        let result = try change(&next)
        do {
            try await persist(next, for: lc)
        } catch {
            if isCurrent(lc) { persistenceError = error }
            throw error
        }
        guard isCurrent(lc) else { throw SyncQueueError.lifecycleEnded }
        syncQueue = next
        persistenceError = recoveryRequired ? SyncQueueError.recoveryRequired : nil
        updatePendingCount()
        return result
    }

    private func persist(_ queue: OfflineSyncQueue, for lc: Lifecycle) async throws {
        do {
            try await storageManager.saveMetadata(
                queue,
                key: OfflineCacheKey.syncQueue.rawValue,
                binding: lc.binding
            )
        } catch OfflineStorageError.staleBinding {
            throw SyncQueueError.lifecycleEnded
        }
    }

    // MARK: - Queue Operations

    /// Save a mood entry for later sync. Returns the stable item ID once the
    /// entry is durably on disk; throws (and enqueues nothing) otherwise.
    @discardableResult
    func saveMoodOffline(
        score: Int,
        anxiety: Int? = nil,
        energy: Int? = nil,
        notes: String? = nil,
        factors: [String]? = nil
    ) async throws -> UUID {
        let entry = OfflineMoodEntry(
            moodScore: score,
            anxietyLevel: anxiety,
            energyLevel: energy,
            notes: notes,
            factors: factors
        )
        try await mutate { $0.moodEntries.append(entry) }
        newEligibleWork()
        return entry.id
    }

    /// Save a quest completion for later sync
    @discardableResult
    func saveQuestCompletionOffline(questId: UUID, questTitle: String? = nil) async throws -> UUID {
        let completion = OfflineQuestCompletion(
            questId: questId,
            questTitle: questTitle
        )
        try await mutate { $0.questCompletions.append(completion) }
        newEligibleWork()
        return completion.id
    }

    /// Save an exercise session for later sync
    @discardableResult
    func saveExerciseSessionOffline(
        exerciseId: UUID,
        exerciseTitle: String? = nil,
        duration: Int
    ) async throws -> UUID {
        let session = OfflineExerciseSession(
            exerciseId: exerciseId,
            exerciseTitle: exerciseTitle,
            durationSeconds: duration
        )
        try await mutate { $0.exerciseSessions.append(session) }
        newEligibleWork()
        return session.id
    }

    private func newEligibleWork() {
        consecutiveFailingPasses = 0
        if isSyncing { rerunRequested = true } else { requestSync() }
    }

    // MARK: - Sync Operations

    /// Sync all pending data. Runs inside the current lifecycle only; unbind
    /// cancels it. Work that arrives while a pass is running is picked up by
    /// that same call, and transient failures schedule a bounded, jittered,
    /// capped retry.
    func syncPendingData() async {
        guard let lc = lifecycle else { return }

        guard isConnectedProvider() else {
            syncStatusMessage = "Waiting for connection..."
            return
        }

        if isSyncing {
            rerunRequested = true
            return
        }
        guard hasUnfinishedWork else {
            syncStatusMessage = syncQueue.hasPendingItems ? pendingStatusMessage() : "All changes synced"
            return
        }

        retryTask?.cancel()
        retryTask = nil
        isSyncing = true
        syncError = nil

        var last = PassResult()
        repeat {
            rerunRequested = false
            let task = Task { @MainActor [weak self] () -> PassResult? in
                guard let self else { return nil }
                return await self.runSync(lc)
            }
            syncTask = task
            let result = await task.value
            guard isCurrent(lc) else { return }
            last = result ?? last
        } while rerunRequested && isCurrent(lc) && !last.interrupted

        guard isCurrent(lc) else { return }
        syncTask = nil
        isSyncing = false
        updatePendingCount()
        scheduleRetryIfNeeded(lc, last)
    }

    /// Eligible = not settled, not exhausted/rejected, outcome not already known.
    private var hasUnfinishedWork: Bool {
        !unresolved.isEmpty || !eligibleRefs(excluding: []).isEmpty
    }

    private func eligibleRefs(excluding visited: Set<ItemRef>) -> [ItemRef] {
        var refs: [ItemRef] = []
        let limit = maxRetryAttempts
        refs += syncQueue.moodEntries.filter { !$0.synced && $0.syncAttempts < limit }.map { ItemRef(kind: .mood, id: $0.id) }
        refs += syncQueue.questCompletions.filter { !$0.synced && $0.syncAttempts < limit }.map { ItemRef(kind: .quest, id: $0.id) }
        refs += syncQueue.exerciseSessions.filter { !$0.synced && $0.syncAttempts < limit }.map { ItemRef(kind: .exercise, id: $0.id) }
        return refs.filter { !visited.contains($0) && unresolved[$0] == nil }
    }

    private func runSync(_ lc: Lifecycle) async -> PassResult {
        var result = PassResult()
        var visited = Set<ItemRef>()

        // Record any outcomes that are already known; never re-send those items.
        _ = await flushUnresolved(lc)

        // Re-snapshot until no new eligible item remains, so work enqueued
        // during the pass is not ignored.
        var rounds = 0
        while rounds < 50 {
            rounds += 1
            guard isCurrent(lc), !Task.isCancelled else { result.interrupted = true; break }
            let refs = eligibleRefs(excluding: visited)
            if refs.isEmpty { break }
            for ref in refs {
                visited.insert(ref)
                guard isCurrent(lc), !Task.isCancelled else { result.interrupted = true; break }
                switch await syncItem(ref, lc) {
                case .synced, .accepted: result.synced += 1
                case .rejected: result.rejected += 1
                case .transient: result.transientFailures += 1
                case .skipped: break
                case .interrupted: result.interrupted = true
                }
                if result.interrupted { break }
            }
            if result.interrupted { break }
        }

        guard isCurrent(lc), !result.interrupted else { result.interrupted = true; return result }

        let flushed = await flushUnresolved(lc)

        // Prune and record the outcome only if it can be made durable.
        await acquireGate()
        defer { releaseGate() }
        guard isCurrent(lc) else { result.interrupted = true; return result }

        var next = syncQueue
        next.lastSyncAttempt = Date()
        next.pruneSyncedItems()
        let settled = result.transientFailures == 0 && unresolved.isEmpty && !next.hasPendingItems
        if settled { next.lastSuccessfulSync = Date() }
        var persisted = true
        if !recoveryRequired || next.isEmpty == syncQueue.isEmpty {
            do {
                try await persist(next, for: lc)
            } catch {
                persisted = false
                if isCurrent(lc) { persistenceError = error }
            }
        }
        guard isCurrent(lc) else { result.interrupted = true; return result }

        if persisted {
            syncQueue = next
            if !recoveryRequired { persistenceError = nil }
        }
        updatePendingCount()

        if !unresolved.isEmpty || !flushed || !persisted {
            syncStatusMessage = "Sent, but this device could not save the result yet"
        } else if result.transientFailures > 0 {
            syncStatusMessage = "\(result.transientFailures) items failed to sync and will be retried"
        } else if syncQueue.hasPendingItems {
            syncStatusMessage = pendingStatusMessage()
        } else {
            lastSyncAt = syncQueue.lastSuccessfulSync
            syncStatusMessage = result.synced > 0 ? "All changes synced" : "Up to date"
        }
        return result
    }

    private func pendingStatusMessage() -> String {
        let failed = getFailedItems()
        let count = failed.moods.count + failed.quests.count + failed.exercises.count
        return count > 0
            ? "\(count) items were rejected or could not be sent and need attention"
            : "\(syncQueue.totalPending) items pending sync"
    }

    // MARK: - Retry scheduling

    private func scheduleRetryIfNeeded(_ lc: Lifecycle, _ result: PassResult) {
        guard isCurrent(lc), !result.interrupted else { return }
        // Only transient failures and unrecorded outcomes are retryable;
        // rejected / exhausted items are never re-sent automatically.
        let needsRetry = result.transientFailures > 0 || !unresolved.isEmpty
        guard needsRetry else {
            consecutiveFailingPasses = 0
            return
        }
        consecutiveFailingPasses += 1
        guard consecutiveFailingPasses <= maxConsecutiveFailingPasses else { return }
        guard hasUnfinishedWork else { return }

        let delay = calculateBackoffDelay(attempt: consecutiveFailingPasses)
        retryToken += 1
        let token = retryToken
        retryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do { try await self.sleep(delay) } catch { return }
            guard self.retryToken == token, self.isCurrent(lc), !Task.isCancelled else { return }
            self.retryTask = nil
            await self.syncPendingData()
        }
    }

    /// Test hook: wait until no retry is scheduled or running.
    func waitUntilIdle() async {
        while true {
            if let a = autoSyncTask { await a.value; if autoSyncTask == a { autoSyncTask = nil }; continue }
            if let t = syncTask { _ = await t.value; if syncTask == t { syncTask = nil }; continue }
            if let r = retryTask { await r.value; continue }
            return
        }
    }

    // MARK: - Per-item sync

    /// Sync exactly one item by stable ID, re-resolving it after every suspension.
    private func syncItem(_ ref: ItemRef, _ lc: Lifecycle) async -> ItemOutcome {
        switch ref.kind {
        case .mood:
            syncStatusMessage = "Syncing mood entries..."
            return await attempt(
                ref, lc,
                find: { $0.moodEntries.first { $0.id == ref.id } },
                synced: { $0.synced }, attempts: { $0.syncAttempts },
                bump: { q, n in if let i = q.moodEntries.firstIndex(where: { $0.id == ref.id }) { q.moodEntries[i].syncAttempts = n } },
                fail: { q, n, err in if let i = q.moodEntries.firstIndex(where: { $0.id == ref.id }) { q.moodEntries[i].syncAttempts = n; q.moodEntries[i].lastSyncError = err } },
                send: lc.handlers.mood
            )
        case .quest:
            syncStatusMessage = "Syncing quest completions..."
            return await attempt(
                ref, lc,
                find: { $0.questCompletions.first { $0.id == ref.id } },
                synced: { $0.synced }, attempts: { $0.syncAttempts },
                bump: { q, n in if let i = q.questCompletions.firstIndex(where: { $0.id == ref.id }) { q.questCompletions[i].syncAttempts = n } },
                fail: { q, n, err in if let i = q.questCompletions.firstIndex(where: { $0.id == ref.id }) { q.questCompletions[i].syncAttempts = n; q.questCompletions[i].lastSyncError = err } },
                send: lc.handlers.quest
            )
        case .exercise:
            syncStatusMessage = "Syncing exercise sessions..."
            return await attempt(
                ref, lc,
                find: { $0.exerciseSessions.first { $0.id == ref.id } },
                synced: { $0.synced }, attempts: { $0.syncAttempts },
                bump: { q, n in if let i = q.exerciseSessions.firstIndex(where: { $0.id == ref.id }) { q.exerciseSessions[i].syncAttempts = n } },
                fail: { q, n, err in if let i = q.exerciseSessions.firstIndex(where: { $0.id == ref.id }) { q.exerciseSessions[i].syncAttempts = n; q.exerciseSessions[i].lastSyncError = err } },
                send: lc.handlers.exercise
            )
        }
    }

    private func attempt<Item>(
        _ ref: ItemRef,
        _ lc: Lifecycle,
        find: (OfflineSyncQueue) -> Item?,
        synced: (Item) -> Bool,
        attempts: (Item) -> Int,
        bump: @escaping (inout OfflineSyncQueue, Int) -> Void,
        fail: @escaping (inout OfflineSyncQueue, Int, String?) -> Void,
        send: (Item) async throws -> Void
    ) async -> ItemOutcome {
        // Re-resolve by ID against the live queue.
        guard isCurrent(lc), unresolved[ref] == nil, let item = find(syncQueue), !synced(item) else { return .skipped }
        let used = attempts(item)
        guard used < maxRetryAttempts else { return .skipped }
        let nextAttempt = used + 1

        // Record the attempt durably BEFORE sending. If it cannot be recorded, do not send.
        do {
            try await mutate(allowDuringRecovery: true) { bump(&$0, nextAttempt) }
        } catch {
            return isCurrent(lc) ? .transient : .interrupted
        }
        guard isCurrent(lc), !Task.isCancelled, let fresh = find(syncQueue), !synced(fresh) else { return .interrupted }

        do {
            try await send(fresh)
        } catch {
            guard isCurrent(lc) else { return .interrupted }
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                return .interrupted
            }
            syncError = error
            if let handlerError = error as? OfflineSyncHandlerError {
                // Permanent rejection. Remember it even if recording fails, so
                // the rejected operation is never retried; only the status is re-saved.
                let message = handlerError.localizedDescription
                unresolved[ref] = .rejected(message)
                unresolvedOutcomeCount = unresolved.count
                _ = await flushUnresolved(lc)
                return isCurrent(lc) ? .rejected : .interrupted
            }
            let message = error.localizedDescription
            try? await mutate(allowDuringRecovery: true) { fail(&$0, nextAttempt, message) }
            return isCurrent(lc) ? .transient : .interrupted
        }

        // The server accepted the item. Remember that even if recording it on
        // disk fails: the handler is never called again for this item in this
        // lifecycle; only the local result is retried, and nothing claims
        // "synced" until it is durable.
        guard isCurrent(lc) else { return .interrupted }
        unresolved[ref] = .accepted
        unresolvedOutcomeCount = unresolved.count
        let recorded = await flushUnresolved(lc)
        guard isCurrent(lc) else { return .interrupted }
        return recorded ? .synced : .accepted
    }

    /// Durably record every known-but-unrecorded outcome without calling any handler.
    @discardableResult
    private func flushUnresolved(_ lc: Lifecycle) async -> Bool {
        guard !unresolved.isEmpty else { return true }
        await acquireGate()
        defer { releaseGate() }
        guard isCurrent(lc) else { return false }

        let applying = unresolved
        var next = syncQueue
        let limit = maxRetryAttempts
        for (ref, outcome) in applying {
            switch (ref.kind, outcome) {
            case (.mood, .accepted):
                if let i = next.moodEntries.firstIndex(where: { $0.id == ref.id }) { next.moodEntries[i].synced = true; next.moodEntries[i].lastSyncError = nil }
            case (.mood, .rejected(let m)):
                if let i = next.moodEntries.firstIndex(where: { $0.id == ref.id }) { next.moodEntries[i].syncAttempts = limit; next.moodEntries[i].lastSyncError = m }
            case (.quest, .accepted):
                if let i = next.questCompletions.firstIndex(where: { $0.id == ref.id }) { next.questCompletions[i].synced = true; next.questCompletions[i].lastSyncError = nil }
            case (.quest, .rejected(let m)):
                if let i = next.questCompletions.firstIndex(where: { $0.id == ref.id }) { next.questCompletions[i].syncAttempts = limit; next.questCompletions[i].lastSyncError = m }
            case (.exercise, .accepted):
                if let i = next.exerciseSessions.firstIndex(where: { $0.id == ref.id }) { next.exerciseSessions[i].synced = true; next.exerciseSessions[i].lastSyncError = nil }
            case (.exercise, .rejected(let m)):
                if let i = next.exerciseSessions.firstIndex(where: { $0.id == ref.id }) { next.exerciseSessions[i].syncAttempts = limit; next.exerciseSessions[i].lastSyncError = m }
            }
        }
        do {
            try await persist(next, for: lc)
        } catch {
            if isCurrent(lc) { persistenceError = error }
            return false
        }
        guard isCurrent(lc) else { return false }
        syncQueue = next
        for key in applying.keys { unresolved.removeValue(forKey: key) }
        unresolvedOutcomeCount = unresolved.count
        persistenceError = recoveryRequired ? SyncQueueError.recoveryRequired : nil
        updatePendingCount()
        return true
    }

    /// Force sync now (user initiated)
    func syncNow() async {
        consecutiveFailingPasses = 0
        await syncPendingData()
    }

    // MARK: - Backoff Calculation

    /// Capped exponential backoff with jitter (base 2s, x2 per failing pass, max 60s).
    func calculateBackoffDelay(attempt: Int) -> TimeInterval {
        let exponentialDelay = baseRetryDelay * pow(2.0, Double(max(attempt, 1) - 1))
        let jitter = Double.random(in: 0...1) * exponentialDelay * 0.1
        return min(exponentialDelay + jitter, 60.0)
    }

    private func updatePendingCount() {
        pendingSyncCount = syncQueue.totalPending
    }

    // MARK: - Queue Management

    /// Explicit, user-initiated discard of all queued work for the bound owner.
    /// Never called implicitly on logout.
    func clearQueue() async throws {
        try await mutate { $0 = OfflineSyncQueue() }
        unresolved.removeAll()
        unresolvedOutcomeCount = 0
    }

    /// Remove a specific mood entry from the queue
    func removeMoodEntry(id: UUID) async throws {
        try await mutate { $0.moodEntries.removeAll { $0.id == id } }
    }

    /// Remove a specific quest completion from the queue
    func removeQuestCompletion(id: UUID) async throws {
        try await mutate { $0.questCompletions.removeAll { $0.id == id } }
    }

    /// Remove a specific exercise session from the queue
    func removeExerciseSession(id: UUID) async throws {
        try await mutate { $0.exerciseSessions.removeAll { $0.id == id } }
    }

    /// Get failed items that need attention
    func getFailedItems() -> (moods: [OfflineMoodEntry], quests: [OfflineQuestCompletion], exercises: [OfflineExerciseSession]) {
        let failedMoods = syncQueue.moodEntries.filter { $0.syncAttempts >= maxRetryAttempts && !$0.synced }
        let failedQuests = syncQueue.questCompletions.filter { $0.syncAttempts >= maxRetryAttempts && !$0.synced }
        let failedExercises = syncQueue.exerciseSessions.filter { $0.syncAttempts >= maxRetryAttempts && !$0.synced }

        return (failedMoods, failedQuests, failedExercises)
    }

    /// Retry failed items (reset attempt count). Items whose outcome is known
    /// but unrecorded are left alone; only user-visible failures are re-armed.
    func retryFailedItems(binding: OfflineOwnerBinding) async throws {
        guard lifecycle?.binding == binding else { throw SyncQueueError.lifecycleEnded }
        let limit = maxRetryAttempts
        let skip = Set(unresolved.keys.map(\.id))
        try await mutate { queue in
            for i in queue.moodEntries.indices where queue.moodEntries[i].syncAttempts >= limit && !skip.contains(queue.moodEntries[i].id) {
                queue.moodEntries[i].syncAttempts = 0
                queue.moodEntries[i].lastSyncError = nil
            }
            for i in queue.questCompletions.indices where queue.questCompletions[i].syncAttempts >= limit && !skip.contains(queue.questCompletions[i].id) {
                queue.questCompletions[i].syncAttempts = 0
                queue.questCompletions[i].lastSyncError = nil
            }
            for i in queue.exerciseSessions.indices where queue.exerciseSessions[i].syncAttempts >= limit && !skip.contains(queue.exerciseSessions[i].id) {
                queue.exerciseSessions[i].syncAttempts = 0
                queue.exerciseSessions[i].lastSyncError = nil
            }
        }
        consecutiveFailingPasses = 0
        await syncPendingData()
    }
}

// MARK: - Sync Status

/// Represents the current sync status
enum QueueSyncStatus: Equatable {
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
