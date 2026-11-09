//
//  OfflineOwnershipTests.swift
//  MindFriendAppTests
//
//  Owner/epoch binding, durability and race behaviour of the offline queue.
//

import XCTest
@testable import MindFriendApp

@MainActor
final class OfflineOwnershipTests: XCTestCase {
    private var root: URL!
    private let userA = "11111111-1111-1111-1111-111111111111"
    private let userB = "22222222-2222-2222-2222-222222222222"

    func testWholeScopeDuplicateStaleCancelledAndFreshRetryLifecycles() async throws {
        let scope = OfflineScope()
        let firstOwner = UUID().uuidString
        let secondOwner = UUID().uuidString
        let epoch = UInt64(Date().timeIntervalSince1970 * 1_000_000)
        let mood: (OfflineMoodEntry) async throws -> Void = { _ in }
        let quest: (OfflineQuestCompletion) async throws -> Void = { _ in }
        let exercise: (OfflineExerciseSession) async throws -> Void = { _ in }
        defer { scope.unbind() }

        async let first: Void = scope.bind(userId: firstOwner, epoch: epoch,
            moodHandler: mood, questHandler: quest, exerciseHandler: exercise)
        async let duplicate: Void = scope.bind(userId: firstOwner, epoch: epoch,
            moodHandler: mood, questHandler: quest, exerciseHandler: exercise)
        _ = try await (first, duplicate)
        XCTAssertEqual(scope.binding, OfflineOwnerBinding(userId: firstOwner, epoch: epoch))

        try await scope.bind(userId: secondOwner, epoch: epoch + 1,
            moodHandler: mood, questHandler: quest, exerciseHandler: exercise)
        let current = OfflineOwnerBinding(userId: secondOwner, epoch: epoch + 1)
        do {
            try await scope.bind(userId: firstOwner, epoch: epoch,
                moodHandler: mood, questHandler: quest, exerciseHandler: exercise)
            XCTFail("An older request must not displace the current scope")
        } catch { XCTAssertEqual(error as? OfflineStorageError, .staleEpoch) }
        XCTAssertEqual(scope.binding, current)
        XCTAssertEqual(SyncQueueManager.shared.currentBinding, current)
        let stored = await OfflineStorageManager.shared.currentBinding()
        XCTAssertEqual(stored, current)
        try await OfflineCacheService.shared.cache("Current owner's fixture", key: .userProfile, binding: current)

        let cancelled = Task { @MainActor in
            try await scope.bind(userId: firstOwner, epoch: epoch + 2,
                moodHandler: mood, questHandler: quest, exerciseHandler: exercise)
        }
        cancelled.cancel()
        do { try await cancelled.value; XCTFail("Cancelled caller") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(scope.binding, current)
        try await scope.bind(userId: firstOwner, epoch: epoch + 2,
            moodHandler: mood, questHandler: quest, exerciseHandler: exercise)
        scope.unbind()
        await scope.awaitTeardown()
        do {
            try await scope.bind(userId: firstOwner, epoch: epoch + 2,
                moodHandler: mood, questHandler: quest, exerciseHandler: exercise)
            XCTFail("An ended epoch cannot restart")
        } catch { XCTAssertEqual(error as? OfflineStorageError, .staleEpoch) }
        try await scope.bind(userId: firstOwner, epoch: epoch + 3,
            moodHandler: mood, questHandler: quest, exerciseHandler: exercise)
        scope.unbind()
        await scope.awaitTeardown()
        for owner in [firstOwner, secondOwner] {
            try await OfflineCacheService.shared.purgeUserCache(userId: owner)
            try await OfflineStorageManager.shared.deleteUserData(userId: owner)
        }
    }

    override func setUp() async throws {
        let base = ProcessInfo.processInfo.environment["TMPDIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
        root = base
            .appendingPathComponent("offline-ownership-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Default scheduler never fires on its own (sleeps "forever" until cancelled)
    /// so tests control retries explicitly.
    private let parked: (TimeInterval) async throws -> Void = { _ in try await Task.sleep(nanoseconds: 3_600_000_000_000) }

    private func makeManager(
        storage: OfflineStorageManager? = nil,
        sleep: ((TimeInterval) async throws -> Void)? = nil,
        autoSync: Bool = false
    ) -> (SyncQueueManager, OfflineStorageManager) {
        let storage = storage ?? OfflineStorageManager(rootDirectory: root)
        return (SyncQueueManager(storageManager: storage, isConnected: { true }, sleep: sleep ?? parked, autoSync: autoSync), storage)
    }

    private func metadataDir(_ user: String) -> URL { offlineRoot().appendingPathComponent("\(user)/Metadata") }
    private func breakDisk(_ user: String) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: metadataDir(user).path)
    }
    private func fixDisk(_ user: String) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: metadataDir(user).path)
    }

    private func bind(
        _ manager: SyncQueueManager,
        _ user: String,
        _ epoch: UInt64,
        mood: @escaping (OfflineMoodEntry) async throws -> Void = { _ in }
    ) async throws {
        try await manager.bind(
            userId: user, epoch: epoch,
            moodSyncHandler: mood,
            questSyncHandler: { _ in },
            exerciseSyncHandler: { _ in }
        )
    }

    private func offlineRoot() -> URL { root.appendingPathComponent("MindFriend/Offline") }

    // MARK: Identityless access

    func testUnboundStorageThrowsAndCreatesNoSharedFolder() async throws {
        let storage = OfflineStorageManager(rootDirectory: root)
        let ghost = OfflineOwnerBinding(userId: userA, epoch: 1)
        do {
            try await storage.saveMetadata(["x"], key: "k", binding: ghost)
            XCTFail("write without an owner must throw")
        } catch { XCTAssertEqual(error as? OfflineStorageError, .notBound) }
        do {
            _ = try await storage.loadMetadata(key: "k", as: [String].self, binding: ghost)
            XCTFail("read without an owner must throw")
        } catch { XCTAssertEqual(error as? OfflineStorageError, .notBound) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: offlineRoot().appendingPathComponent("shared").path))
    }

    func testUnboundQueueRejectsSaveWithoutEnqueuing() async throws {
        let (manager, _) = makeManager()
        do {
            try await manager.saveMoodOffline(score: 5)
            XCTFail("must throw before success")
        } catch { XCTAssertEqual(error as? SyncQueueError, .notBound) }
        XCTAssertEqual(manager.pendingSyncCount, 0)
    }

    func testRejectsPathTraversalUserIds() async throws {
        let storage = OfflineStorageManager(rootDirectory: root)
        for bad in ["", "..", "../x", "a/b", "a\\b", String(repeating: "a", count: 129)] {
            do {
                try await storage.bind(userId: bad, epoch: 1)
                XCTFail("accepted \(bad)")
            } catch { XCTAssertEqual(error as? OfflineStorageError, .invalidUserId) }
        }
    }

    // MARK: Epoch / binding immutability

    func testStaleBindingWriteIsRejectedAfterAccountSwitch() async throws {
        let storage = OfflineStorageManager(rootDirectory: root)
        let a = try await storage.bind(userId: userA, epoch: 1)
        _ = try await storage.bind(userId: userB, epoch: 2)
        do {
            try await storage.saveMetadata(["late"], key: "k", binding: a)
            XCTFail("late write from account A must not land")
        } catch { XCTAssertEqual(error as? OfflineStorageError, .staleBinding) }
        let b = await storage.currentBinding()
        XCTAssertEqual(b, OfflineOwnerBinding(userId: userB, epoch: 2))
    }

    func testEndedEpochCannotBeReboundAndOldUnbindCannotTearDownNewLifecycle() async throws {
        let storage = OfflineStorageManager(rootDirectory: root)
        let a1 = try await storage.bind(userId: userA, epoch: 1)
        await storage.unbind(a1)
        do {
            try await storage.bind(userId: userA, epoch: 1)
            XCTFail("reusing an ended epoch must fail")
        } catch { XCTAssertEqual(error as? OfflineStorageError, .staleEpoch) }

        let a2 = try await storage.bind(userId: userA, epoch: 2)
        await storage.unbind(a1)                     // late cleanup for the old epoch
        let current = await storage.currentBinding()
        XCTAssertEqual(current, a2)
    }

    // MARK: Durability

    func testSavedWorkSurvivesRestartAndIsInvisibleToOtherAccount() async throws {
        let (first, storage) = makeManager()
        try await bind(first, userA, 1)
        let id = try await first.saveMoodOffline(score: 7, notes: "private")
        first.unbind()
        XCTAssertEqual(first.pendingSyncCount, 0)
        XCTAssertTrue(first.syncQueue.isEmpty, "unbind drops in-memory data")

        // Another account on the same device never sees A's queue.
        try await bind(first, userB, 2)
        XCTAssertTrue(first.syncQueue.isEmpty)
        first.unbind()

        // "Relaunch": fresh manager and storage over the same disk.
        let (second, _) = makeManager(storage: OfflineStorageManager(rootDirectory: root))
        _ = storage
        try await bind(second, userA, 1)
        XCTAssertEqual(second.syncQueue.moodEntries.map(\.id), [id])
    }

    func testFailedWriteThrowsAndLeavesQueueUnchanged() async throws {
        let (manager, _) = makeManager()
        try await bind(manager, userA, 1)
        let metadata = offlineRoot().appendingPathComponent("\(userA)/Metadata")
        // A read-only Metadata directory makes every write fail.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: metadata.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: metadata.path) }

        do {
            try await manager.saveMoodOffline(score: 3)
            XCTFail("a save that cannot be made durable must throw")
        } catch {}
        XCTAssertEqual(manager.pendingSyncCount, 0)
        XCTAssertTrue(manager.syncQueue.moodEntries.isEmpty)
        XCTAssertNotNil(manager.persistenceError)
    }

    func testCorruptQueueIsQuarantinedNotSilentlyReset() async throws {
        let storage = OfflineStorageManager(rootDirectory: root)
        try await storage.bind(userId: userA, epoch: 1)
        let file = offlineRoot().appendingPathComponent("\(userA)/Metadata/sync_queue.json")
        try Data("{not json".utf8).write(to: file)
        let binding = await storage.currentBinding()!
        await storage.unbind(binding)

        let (manager, _) = makeManager(storage: storage)
        try await bind(manager, userA, 2)
        XCTAssertEqual(manager.quarantinedQueueURLs.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: manager.quarantinedQueueURLs[0].path))
        XCTAssertNotNil(manager.persistenceError)
        XCTAssertTrue(manager.syncQueue.isEmpty)
    }

    // MARK: Sync behaviour

    func testSyncMarksAndPrunesAndFailureKeepsItemWithAttempt() async throws {
        let (manager, _) = makeManager()
        var shouldFail = true
        try await bind(manager, userA, 1, mood: { _ in
            if shouldFail { throw URLError(.notConnectedToInternet) }
        })
        try await manager.saveMoodOffline(score: 4)
        await manager.syncNow()
        XCTAssertEqual(manager.pendingSyncCount, 1)
        XCTAssertEqual(manager.syncQueue.moodEntries.first?.syncAttempts, 1)
        XCTAssertNotNil(manager.syncQueue.moodEntries.first?.lastSyncError)
        XCTAssertNotEqual(manager.syncStatusMessage, "All changes synced")

        shouldFail = false
        await manager.syncNow()
        XCTAssertEqual(manager.pendingSyncCount, 0)
        XCTAssertTrue(manager.syncQueue.isEmpty)
        XCTAssertFalse(manager.isSyncing)
    }

    func testNonRetryableErrorStopsAutomaticRetry() async throws {
        let (manager, _) = makeManager()
        var calls = 0
        try await bind(manager, userA, 1, mood: { _ in
            calls += 1
            throw OfflineSyncHandlerError.nonRetryable("invalid")
        })
        try await manager.saveMoodOffline(score: 1)
        await manager.syncNow()
        await manager.syncNow()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(manager.getFailedItems().moods.count, 1)
    }

    func testSaveDuringInFlightSyncIsNotLostAndIDsStayStable() async throws {
        let (manager, _) = makeManager()
        let gate = Gate()
        try await bind(manager, userA, 1, mood: { _ in await gate.wait() })
        let first = try await manager.saveMoodOffline(score: 1)

        let syncing = Task { await manager.syncNow() }
        await gate.waitUntilEntered()
        let second = try await manager.saveMoodOffline(score: 2)   // arrives while handler is suspended
        await gate.release()
        await syncing.value

        // The item that arrived mid-pass is picked up by the same pass (not ignored).
        XCTAssertFalse(manager.syncQueue.moodEntries.contains { $0.id == first })
        XCTAssertFalse(manager.syncQueue.moodEntries.contains { $0.id == second })
        XCTAssertEqual(manager.pendingSyncCount, 0)
    }

    func testLateCompletionFromPreviousAccountCannotTouchNewAccount() async throws {
        let (manager, storage) = makeManager()
        let gate = Gate()
        try await bind(manager, userA, 1, mood: { _ in await gate.wait() })
        try await manager.saveMoodOffline(score: 1)

        let syncing = Task { await manager.syncNow() }
        await gate.waitUntilEntered()

        // Account switch while A's sync is suspended inside the handler.
        manager.unbind()
        try await bind(manager, userB, 2)
        let bItem = try await manager.saveMoodOffline(score: 9)
        await gate.release()
        await syncing.value

        XCTAssertEqual(manager.currentBinding?.userId, userB)
        XCTAssertEqual(manager.syncQueue.moodEntries.map(\.id), [bItem])
        XCTAssertFalse(manager.isSyncing)

        // B's persisted file only has B's item; A's folder still holds A's unsynced work.
        let bFile = try Data(contentsOf: offlineRoot().appendingPathComponent("\(userB)/Metadata/sync_queue.json"))
        let bQueue = try JSONDecoder.iso.decode(OfflineSyncQueue.self, from: bFile)
        XCTAssertEqual(bQueue.moodEntries.map(\.id), [bItem])
        let aFile = try Data(contentsOf: offlineRoot().appendingPathComponent("\(userA)/Metadata/sync_queue.json"))
        let aQueue = try JSONDecoder.iso.decode(OfflineSyncQueue.self, from: aFile)
        XCTAssertEqual(aQueue.totalPending, 1)
        _ = storage
    }


    // MARK: O01 - recovery copies survive logout and relaunch

    private func corruptThenBind(_ storage: OfflineStorageManager) async throws -> SyncQueueManager {
        let b = try await storage.bind(userId: userA, epoch: 1)
        try Data("{not json".utf8).write(to: metadataDir(userA).appendingPathComponent("sync_queue.json"))
        await storage.unbind(b)
        let (manager, _) = makeManager(storage: storage)
        try await bind(manager, userA, 2)
        return manager
    }

    func testQuarantineSurvivesLogoutPurgeWhenQueueFileAbsent() async throws {
        let storage = OfflineStorageManager(rootDirectory: root)
        let manager = try await corruptThenBind(storage)
        let copy = manager.quarantinedQueueURLs[0]
        XCTAssertTrue(manager.recoveryRequired)
        manager.unbind()
        try await Task.sleep(nanoseconds: 50_000_000)

        let outcome = try await storage.purgeUserData(userId: userA)   // live queue file is absent
        XCTAssertEqual(outcome, .preservedRecoveryCopies(count: 1))
        XCTAssertEqual(try Data(contentsOf: copy), Data("{not json".utf8), "the only copy is intact")
    }

    func testQuarantineSurvivesPurgeWithEmptyReplacementQueueAndShowsAfterRelaunch() async throws {
        let storage = OfflineStorageManager(rootDirectory: root)
        let manager = try await corruptThenBind(storage)
        manager.unbind()
        try await Task.sleep(nanoseconds: 50_000_000)
        // An empty (valid) replacement queue file exists next to the recovery copy.
        let empty = try JSONEncoder.iso.encode(OfflineSyncQueue())
        try empty.write(to: metadataDir(userA).appendingPathComponent("sync_queue.json"))

        let purged = try await storage.purgeUserData(userId: userA)
        XCTAssertEqual(purged, .preservedRecoveryCopies(count: 1))

        // Relaunch: recovery state is visible again and new work is refused.
        let (relaunched, _) = makeManager(storage: OfflineStorageManager(rootDirectory: root))
        try await bind(relaunched, userA, 1)
        XCTAssertEqual(relaunched.quarantinedQueueURLs.count, 1)
        XCTAssertEqual(relaunched.persistenceError as? SyncQueueError, .recoveryRequired)
        do {
            try await relaunched.saveMoodOffline(score: 1)
            XCTFail("no silent empty usable queue")
        } catch { XCTAssertEqual(error as? SyncQueueError, .recoveryRequired) }

        // An explicit decision unlocks the queue.
        try await relaunched.discardQuarantinedQueues()
        XCTAssertFalse(relaunched.recoveryRequired)
        try await relaunched.saveMoodOffline(score: 1)
        XCTAssertEqual(relaunched.pendingSyncCount, 1)
    }

    // MARK: O02 - every storage access carries and re-checks owner+epoch

    func testDelayedMoveFromOldAccountCannotTouchNewAccountSameContentID() async throws {
        let storage = OfflineStorageManager(rootDirectory: root)
        let a = try await storage.bind(userId: userA, epoch: 1)
        let contentId = UUID()
        let staged = root.appendingPathComponent("a-download.mp3")
        try Data("A-bytes".utf8).write(to: staged)

        // Account switch before A's completion resumes; B already owns the same content ID.
        let b = try await storage.bind(userId: userB, epoch: 2)
        let bSource = root.appendingPathComponent("b-download.mp3")
        try Data("B-bytes".utf8).write(to: bSource)
        let bFile = try await storage.moveToStorage(from: bSource, contentId: contentId, fileExtension: "mp3", binding: b)

        do {
            _ = try await storage.moveToStorage(from: staged, contentId: contentId, fileExtension: "mp3", binding: a)
            XCTFail("late A move must be rejected before any filesystem change")
        } catch { XCTAssertEqual(error as? OfflineStorageError, .staleBinding) }
        XCTAssertEqual(try Data(contentsOf: bFile), Data("B-bytes".utf8), "B's file is untouched")
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.path), "A's staged file was not consumed")

        // Late cleanup by A cannot remove B's file either.
        do { try await storage.removeStoredFile(at: bFile, binding: a); XCTFail() }
        catch { XCTAssertEqual(error as? OfflineStorageError, .staleBinding) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: bFile.path))
    }

    func testSameUserNewEpochRejectsOldEpochContentAndIndexWrites() async throws {
        let storage = OfflineStorageManager(rootDirectory: root)
        let old = try await storage.bind(userId: userA, epoch: 1)
        let fresh = try await storage.bind(userId: userA, epoch: 2)
        do { try await storage.saveContentIndex([], binding: old); XCTFail() }
        catch { XCTAssertEqual(error as? OfflineStorageError, .staleBinding) }
        do { _ = try await storage.totalStorageUsed(binding: old); XCTFail() }
        catch { XCTAssertEqual(error as? OfflineStorageError, .staleBinding) }
        try await storage.saveContentIndex([], binding: fresh)
    }

    func testCacheServiceIsScopedAndRejectsAccessBeforeIdentityAndStaleWrites() async throws {
        let cache = OfflineCacheService(rootDirectory: root)
        let a = OfflineOwnerBinding(userId: userA, epoch: 1)
        // Before identity: nothing reads or writes.
        do { try await cache.cache(["x"], key: .exerciseLibrary, binding: a); XCTFail() }
        catch { XCTAssertEqual(error as? OfflineStorageError, .notBound) }

        try await cache.bind(a)
        try await cache.cache(["A-data"], key: .exerciseLibrary, binding: a)

        let b = OfflineOwnerBinding(userId: userB, epoch: 2)
        try await cache.bind(b)
        let seenByB: [String]? = try await cache.retrieve(key: .exerciseLibrary, as: [String].self, binding: b)
        XCTAssertNil(seenByB, "B never sees A's cache")
        do { try await cache.cache(["late-A"], key: .exerciseLibrary, binding: a); XCTFail() }
        catch { XCTAssertEqual(error as? OfflineStorageError, .staleBinding) }
        let stillNil: [String]? = try await cache.retrieve(key: .exerciseLibrary, as: [String].self, binding: b)
        XCTAssertNil(stillNil)

        // Legacy unscoped files at the old root are never read.
        let legacy = root.appendingPathComponent("MindFriend/OfflineCache")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try JSONEncoder().encode(["legacy"]).write(to: legacy.appendingPathComponent("\(OfflineCacheKey.moodHistory.rawValue).json"))
        let viaB: [String]? = try await cache.retrieve(key: .moodHistory, as: [String].self, binding: b)
        XCTAssertNil(viaB)

        await cache.unbind(b)
        do { _ = try await cache.retrieve(key: .moodHistory, as: [String].self, binding: b) as [String]?; XCTFail() }
        catch { XCTAssertEqual(error as? OfflineStorageError, .notBound) }
        try await cache.purgeUserCache(userId: userB)
    }

    // MARK: O03 - accepted by the server, result not yet durable

    func testAcceptedThenDiskFailureIsNotSettledNotResentAndFlushesOnce() async throws {
        let (manager, _) = makeManager()
        var calls = 0
        try await bind(manager, userA, 1, mood: { [self] _ in calls += 1; breakDisk(userA) })
        try await manager.saveMoodOffline(score: 4)

        await manager.syncNow()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(manager.pendingSyncCount, 1, "not settled while the result is not durable")
        XCTAssertEqual(manager.unresolvedOutcomeCount, 1)
        XCTAssertNotEqual(manager.syncStatusMessage, "All changes synced")
        XCTAssertNotNil(manager.persistenceError)

        fixDisk(userA)
        await manager.syncNow()
        XCTAssertEqual(calls, 1, "the accepted item is never re-sent")
        XCTAssertEqual(manager.pendingSyncCount, 0)
        XCTAssertEqual(manager.unresolvedOutcomeCount, 0)

        // Relaunch: durable result, nothing replays.
        manager.unbind()
        let (relaunched, _) = makeManager(storage: OfflineStorageManager(rootDirectory: root))
        var relaunchCalls = 0
        try await bind(relaunched, userA, 1, mood: { _ in relaunchCalls += 1 })
        await relaunched.syncNow()
        XCTAssertTrue(relaunched.syncQueue.isEmpty)
        XCTAssertEqual(relaunchCalls, 0)
    }

    // MARK: O04 - permanent rejection survives a failed write

    func testNonRetryableOutcomeIsKeptAcrossDiskFailureAndNotRetried() async throws {
        let (manager, _) = makeManager()
        var calls = 0
        try await bind(manager, userA, 1, mood: { [self] _ in
            calls += 1
            breakDisk(userA)
            throw OfflineSyncHandlerError.nonRetryable("invalid entry")
        })
        try await manager.saveMoodOffline(score: 4)

        await manager.syncNow()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(manager.unresolvedOutcomeCount, 1)

        fixDisk(userA)
        await manager.syncNow()
        await manager.syncNow()
        XCTAssertEqual(calls, 1, "a rejected operation is never re-sent; only its status is saved")
        XCTAssertEqual(manager.unresolvedOutcomeCount, 0)
        XCTAssertEqual(manager.getFailedItems().moods.count, 1)
        XCTAssertEqual(manager.getFailedItems().moods.first?.lastSyncError, "invalid entry")
        XCTAssertTrue(manager.syncStatusMessage.contains("rejected"), manager.syncStatusMessage)
    }

    // MARK: O05 - bounded eventual processing

    func testTransientFailuresRetryWithCappedJitteredBackoffUntilSuccess() async throws {
        var delays: [TimeInterval] = []
        let (manager, _) = makeManager(sleep: { delays.append($0); await Task.yield() }, autoSync: true)
        var calls = 0
        try await bind(manager, userA, 1, mood: { _ in
            calls += 1
            if calls < 3 { throw URLError(.timedOut) }
        })
        try await manager.saveMoodOffline(score: 3)
        await manager.waitUntilIdle()

        XCTAssertEqual(calls, 3)
        XCTAssertEqual(manager.pendingSyncCount, 0)
        XCTAssertEqual(delays.count, 2)
        XCTAssertTrue((2.0...2.2).contains(delays[0]), "\(delays)")
        XCTAssertTrue((4.0...4.4).contains(delays[1]), "\(delays)")
    }

    func testWorkArrivingDuringAPassIsNotIgnored() async throws {
        let (manager, _) = makeManager(autoSync: true)
        var calls = 0
        var injected = false
        try await bind(manager, userA, 1, mood: { [unowned manager] _ in
            calls += 1
            if !injected {
                injected = true
                try await manager.saveMoodOffline(score: 9)
            }
        })
        try await manager.saveMoodOffline(score: 1)
        await manager.waitUntilIdle()
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(manager.pendingSyncCount, 0)
    }

    func testPermanentFailureIsNeverScheduledForRetry() async throws {
        var delays: [TimeInterval] = []
        let (manager, _) = makeManager(sleep: { delays.append($0) }, autoSync: true)
        var calls = 0
        try await bind(manager, userA, 1, mood: { _ in calls += 1; throw OfflineSyncHandlerError.nonRetryable("no") })
        try await manager.saveMoodOffline(score: 3)
        await manager.waitUntilIdle()
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(delays.isEmpty)
    }

    func testRetriesAreBoundedAndStopAtAttemptCap() async throws {
        var delays: [TimeInterval] = []
        let (manager, _) = makeManager(sleep: { delays.append($0); await Task.yield() }, autoSync: true)
        var calls = 0
        try await bind(manager, userA, 1, mood: { _ in calls += 1; throw URLError(.notConnectedToInternet) })
        try await manager.saveMoodOffline(score: 3)
        await manager.waitUntilIdle()
        XCTAssertEqual(calls, 5, "stops at the per-item attempt cap, no busy loop")
        XCTAssertLessThanOrEqual(delays.count, 8)
        XCTAssertTrue(delays.allSatisfy { $0 <= 60 })
    }

    func testUnbindCancelsScheduledRetry() async throws {
        let (manager, _) = makeManager(autoSync: true)       // parked scheduler
        var calls = 0
        try await bind(manager, userA, 1, mood: { _ in calls += 1; throw URLError(.timedOut) })
        try await manager.saveMoodOffline(score: 3)
        for _ in 0..<50 { await Task.yield() }
        manager.unbind()
        await manager.waitUntilIdle()
        XCTAssertEqual(calls, 1)
        XCTAssertTrue(manager.syncQueue.isEmpty)
    }

    // MARK: Logout preservation

    func testPurgePreservesUnsyncedQueueButRemovesOtherData() async throws {
        let (manager, storage) = makeManager()
        try await bind(manager, userA, 1)
        try await manager.saveMoodOffline(score: 2)
        let live = manager.currentBinding!
        try await storage.saveMetadata(["cache"], key: "mood_history", binding: live)
        manager.unbind()
        try await Task.sleep(nanoseconds: 50_000_000)   // let the storage unbind task run

        let outcome = try await storage.purgeUserData(userId: userA)
        XCTAssertEqual(outcome, .preservedUnsynced(pendingCount: 1))
        let dir = offlineRoot().appendingPathComponent("\(userA)/Metadata")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("sync_queue.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("mood_history.json").path))
    }

    func testPurgeRemovesEverythingWhenNothingUnsyncedAndRefusesWhileBound() async throws {
        let storage = OfflineStorageManager(rootDirectory: root)
        let binding = try await storage.bind(userId: userA, epoch: 1)
        do {
            try await storage.purgeUserData(userId: userA)
            XCTFail("must refuse while bound")
        } catch { XCTAssertEqual(error as? OfflineStorageError, .ownerIsBound) }
        await storage.unbind(binding)
        let outcome = try await storage.purgeUserData(userId: userA)
        XCTAssertEqual(outcome, .removedAll)
        XCTAssertFalse(FileManager.default.fileExists(atPath: offlineRoot().appendingPathComponent(userA).path))
    }
}

private extension JSONEncoder {
    static var iso: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

private extension JSONDecoder {
    static var iso: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}

/// Suspends a handler until released, so tests can interleave other work.
private actor Gate {
    private var entered = false
    private var released = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var enteredWaiter: CheckedContinuation<Void, Never>?

    func wait() async {
        entered = true
        enteredWaiter?.resume(); enteredWaiter = nil
        if released { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { enteredWaiter = $0 }
    }

    func release() {
        released = true
        waiter?.resume(); waiter = nil
    }
}
