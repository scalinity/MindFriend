//
//  HealthSampleStatusTests.swift
//  MindFriendAppTests
//
//  Offline tests for Apple Health sample status and the deliberate sync opt-out.
//  Everything is injected: no HealthKit data, permission prompt, account or network is used.
//

import XCTest
@testable import MindFriendApp

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

@MainActor
private final class FakeHealth {
    struct WritePlan { var gate: Gate? = nil; var fail = false }

    var owner: UUID?
    var permission: HealthKitService.PermissionRequestState = .completed
    /// What the account says. Missing entries read as `.noRecord`.
    var remote: [UUID: HealthRemoteConnection] = [:]
    var forcedRemote: HealthRemoteConnection?
    var writes: [(credential: HealthCredential, connected: Bool)] = []
    var uploads: [(payload: BiometricSyncPayload, credential: HealthCredential)] = []
    var requestCalls = 0
    var collectCalls = 0
    var failWrites = false
    var writePlan: [WritePlan] = []
    var uploadFails = false
    var collectResult: Result<HealthCollection, Error> = .success(HealthCollection(summaries: [], workouts: []))
    var collectGate: Gate?
    var requestGate: Gate?
    var uploadGate: Gate?
    var shouldContinueAfterGate: Bool?
    var now = Date(timeIntervalSince1970: 1_800_000_000)

    static func token(_ owner: UUID) -> String { "token-\(owner.uuidString.prefix(4))" }

    func dependencies(_ optOut: HealthSyncOptOut) -> HealthKitServiceDependencies {
        HealthKitServiceDependencies(
            isAvailable: { true },
            permissionState: { [unowned self] in self.permission },
            requestPermission: { [unowned self] in
                self.requestCalls += 1
                if let gate = self.requestGate { await gate.wait() }
            },
            collect: { [unowned self] _, _, shouldContinue in
                self.collectCalls += 1
                if let gate = self.collectGate { await gate.wait() }
                self.shouldContinueAfterGate = shouldContinue()
                return try self.collectResult.get()
            },
            currentCredential: { [unowned self] in
                self.owner.map { HealthCredential(owner: $0, accessToken: Self.token($0)) }
            },
            fetchConnection: { [unowned self] owner in self.forcedRemote ?? self.remote[owner] ?? .noRecord },
            writeConnection: { [unowned self] credential, connected in
                let plan = self.writePlan.isEmpty ? WritePlan() : self.writePlan.removeFirst()
                if let gate = plan.gate { await gate.wait() }
                if plan.fail || self.failWrites { throw URLError(.notConnectedToInternet) }
                self.writes.append((credential, connected))
                self.remote[credential.owner] = connected ? .connected : .disconnected
            },
            upload: { [unowned self] payload, credential in
                if let gate = self.uploadGate { await gate.wait() }
                if self.uploadFails { throw HealthHTTPStatusError(status: 500) }
                self.uploads.append((payload, credential))
            },
            now: { [unowned self] in self.now },
            optOut: optOut
        )
    }
}

@MainActor
final class HealthSampleStatusTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var fake: FakeHealth!
    private let ownerA = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let ownerB = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

    override func setUp() async throws {
        suiteName = "HealthSampleStatusTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        fake = FakeHealth()
        fake.owner = ownerA
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    /// A new service instance over the same stores (a relaunch).
    private func makeService() -> HealthKitService {
        HealthKitService(dependencies: fake.dependencies(HealthSyncOptOut(defaults: defaults)))
    }

    private func samples(steps: Int?, mindful: Int? = nil) -> HealthCollection {
        var day = BiometricSyncPayload.DailySummaryPayload(date: "2026-11-06")
        day.stepsCount = steps
        day.mindfulMinutes = mindful
        let blank = BiometricSyncPayload.DailySummaryPayload(date: "2026-11-05")
        return HealthCollection(summaries: [blank, day], workouts: [])
    }

    private func expectThrows<T>(_ work: () async throws -> T, _ check: (Error) -> Bool = { _ in true },
                                 file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await work()
            XCTFail("expected an error", file: file, line: line)
        } catch {
            XCTAssertTrue(check(error), "unexpected error \(error)", file: file, line: line)
        }
    }

    // MARK: P05 - disconnect is an opt-out that refresh never undoes

    func testCompletedRequestThenDisconnectStaysPausedAfterRefreshAndRelaunch() async throws {
        let first = makeService()
        try await first.connect()
        XCTAssertTrue(first.isSyncEnabled)
        XCTAssertEqual(fake.writes.last?.connected, true)

        await first.disconnect()
        XCTAssertTrue(first.syncPaused)
        XCTAssertFalse(first.isSyncEnabled)
        XCTAssertTrue(first.hasCompletedPermissionRequest, "Apple's request state is independent of the opt-out")
        XCTAssertEqual(fake.writes.last?.connected, false)

        // Status refresh must not reconnect (the bug: it upserted connected=true).
        await first.checkAuthorizationStatus()
        XCTAssertTrue(first.syncPaused)

        // Relaunch: a brand-new service over the same stores.
        let upsertsBefore = fake.writes.count
        let second = makeService()
        await second.checkAuthorizationStatus()
        XCTAssertTrue(second.hasCompletedPermissionRequest)
        XCTAssertTrue(second.syncPaused)
        XCTAssertFalse(fake.writes.dropFirst(upsertsBefore).contains { $0.connected }, "a refresh wrote connected=true")
        await expectThrows({ try await second.syncBiometrics(days: 7) }) { ($0 as? HealthSyncError) == .paused }
        XCTAssertTrue(fake.uploads.isEmpty)

        // Only an explicit Connect resumes syncing.
        fake.collectResult = .success(samples(steps: 4000))
        try await second.connect()
        XCTAssertFalse(second.syncPaused)
        XCTAssertEqual(fake.writes.last?.connected, true)
        try await second.syncBiometrics(days: 7)
        XCTAssertEqual(fake.uploads.count, 1)
    }

    func testRefreshOnlyEverWritesDisconnectedAndMirrorsAnAccountDisconnect() async {
        // A disconnect recorded on the account (another device) pauses this device without a local decision.
        fake.remote[ownerA] = .disconnected
        let service = makeService()
        await service.checkAuthorizationStatus()
        XCTAssertTrue(service.syncPaused)
        XCTAssertFalse(fake.writes.contains { $0.connected })

        // A fresh account whose Apple request is not complete is recorded as not connected, never connected.
        fake.owner = ownerB
        fake.permission = .requestNeeded
        let fresh = makeService()
        await fresh.checkAuthorizationStatus()
        XCTAssertFalse(fresh.hasCompletedPermissionRequest)
        XCTAssertFalse(fake.writes.contains { $0.connected })

        // A device with a completed request and no opt-out is left untouched by a refresh.
        fake.owner = UUID()
        fake.permission = .completed
        let upserts = fake.writes.count
        await makeService().checkAuthorizationStatus()
        XCTAssertEqual(fake.writes.count, upserts)
    }

    func testFailedAcknowledgementKeepsLocalPauseAndExposesTheFailure() async throws {
        let service = makeService()
        try await service.connect()
        fake.failWrites = true
        await service.disconnect()
        XCTAssertTrue(service.syncPaused, "the local pause must survive a failed acknowledgement")
        XCTAssertNotNil(service.connectionError, "the failure must not be swallowed")
        await expectThrows({ try await service.syncBiometrics(days: 7) }) { ($0 as? HealthSyncError) == .paused }

        let relaunched = makeService()
        await relaunched.checkAuthorizationStatus()
        XCTAssertTrue(relaunched.syncPaused)

        // A failed reconnect acknowledgement does not resume syncing.
        await expectThrows({ try await relaunched.connect() })
        XCTAssertTrue(relaunched.syncPaused)
        XCTAssertFalse(relaunched.isSyncEnabled)
    }

    func testOptOutIsPerAccount() async throws {
        let service = makeService()
        try await service.connect()
        await service.disconnect()
        XCTAssertTrue(service.syncPaused)

        fake.owner = ownerB
        await service.checkAuthorizationStatus()
        XCTAssertFalse(service.syncPaused, "another account does not inherit the opt-out")
        XCTAssertNil(service.lastQueryOutcome)
    }

    // MARK: P04 - nil vs zero, samples vs failure

    func testNoRecentDataIsNotUploadedOrReportedAsDenial() async throws {
        let service = makeService()
        try await service.connect()
        fake.collectResult = .success(samples(steps: nil)) // every field nil
        try await service.syncBiometrics(days: 7)

        let outcome = try XCTUnwrap(service.lastQueryOutcome)
        XCTAssertEqual(outcome.status, .noRecentData)
        XCTAssertEqual(outcome.statusText, "No recent data available")
        XCTAssertEqual(outcome.checkedAt, fake.now)
        XCTAssertEqual(outcome.interval.end, fake.now)
        XCTAssertEqual(HealthQueryOutcome.sourceName, "Apple Health (HealthKit)")
        XCTAssertTrue(fake.uploads.isEmpty, "blank summaries must not be uploaded as observed data")
        XCTAssertNil(service.lastSyncDate, "nothing was synced")
        XCTAssertTrue(service.hasCompletedPermissionRequest, "permission state is independent of the query outcome")
    }

    func testGenuineZeroIsAvailableDataAndBlankDaysAreNotUploaded() async throws {
        let service = makeService()
        try await service.connect()
        fake.collectResult = .success(samples(steps: 0))
        try await service.syncBiometrics(days: 7)

        XCTAssertEqual(service.lastQueryOutcome?.status, .samplesAvailable)
        XCTAssertEqual(service.lastQueryOutcome?.daysWithSamples, 1)
        let payload = try XCTUnwrap(fake.uploads.first?.payload)
        XCTAssertEqual(payload.dailySummaries.map(\.date), ["2026-11-06"])
        XCTAssertEqual(payload.dailySummaries.first?.stepsCount, 0)
        XCTAssertEqual(service.lastSyncDate, fake.now)
    }

    func testWorkoutsAloneAndMindfulZeroCountAsSamples() {
        let workout = BiometricSyncPayload.WorkoutPayload(
            healthkitUuid: "w1", workoutType: "walking", startTime: "2026-11-06T10:00:00Z",
            endTime: "2026-11-06T10:30:00Z", durationMinutes: 30
        )
        let interval = DateInterval(start: fake.now.addingTimeInterval(-86_400), end: fake.now)
        let onlyWorkout = HealthQueryOutcome.evaluate(HealthCollection(summaries: [], workouts: [workout]), interval: interval, checkedAt: fake.now)
        XCTAssertEqual(onlyWorkout.status, .samplesAvailable)
        XCTAssertEqual(onlyWorkout.workoutCount, 1)
        XCTAssertNotNil(HealthQueryOutcome.uploadPayload(HealthCollection(summaries: [], workouts: [workout])))

        let mindfulZero = HealthQueryOutcome.evaluate(samples(steps: nil, mindful: 0), interval: interval, checkedAt: fake.now)
        XCTAssertEqual(mindfulZero.status, .samplesAvailable)

        let blank = HealthQueryOutcome.evaluate(samples(steps: nil), interval: interval, checkedAt: fake.now)
        XCTAssertEqual(blank.status, .noRecentData)
        XCTAssertNil(HealthQueryOutcome.uploadPayload(samples(steps: nil)))
    }

    func testQueryErrorIsAFailureNeverEmpty() async throws {
        let service = makeService()
        try await service.connect()
        fake.collectResult = .failure(NSError(domain: "HealthKit", code: 7, userInfo: [NSLocalizedDescriptionKey: "boom"]))
        await expectThrows({ try await service.syncBiometrics(days: 7) })

        let outcome = try XCTUnwrap(service.lastQueryOutcome)
        XCTAssertEqual(outcome.status, .queryFailed)
        XCTAssertNotEqual(outcome.status, .noRecentData)
        XCTAssertEqual(outcome.failureDescription, "boom")
        XCTAssertNotNil(service.syncError)
        XCTAssertTrue(fake.uploads.isEmpty)
        XCTAssertNil(service.lastSyncDate)
    }

    // MARK: Running work vs pause and owner changes

    func testDisconnectDuringQueryStopsTheSyncBeforeUpload() async throws {
        let service = makeService()
        try await service.connect()
        fake.collectResult = .success(samples(steps: 900))
        let gate = Gate()
        fake.collectGate = gate

        let running = Task { @MainActor in try await service.syncBiometrics(days: 7) }
        await gate.waitUntilEntered()
        await service.disconnect()
        await gate.release()

        do { try await running.value; XCTFail("a paused sync must not complete") }
        catch { XCTAssertTrue(error is CancellationError, "\(error)") }
        XCTAssertEqual(fake.shouldContinueAfterGate, false, "the running query is told to stop")
        XCTAssertTrue(fake.uploads.isEmpty, "nothing may be uploaded after Disconnect")
        XCTAssertNil(service.lastSyncDate)
        XCTAssertNil(service.lastQueryOutcome)
        XCTAssertFalse(service.isSyncing)
    }

    func testSignOutAndReturnToTheSameOwnerCancelsTheEarlierQuery() async throws {
        let service = makeService()
        try await service.connect()
        fake.collectResult = .success(samples(steps: 900))
        let gate = Gate()
        fake.collectGate = gate
        let running = Task { @MainActor in try await service.syncBiometrics(days: 7) }
        await gate.waitUntilEntered()
        service.ownerDidChange(nil)
        service.ownerDidChange(ownerA)
        await gate.release()
        do { try await running.value; XCTFail("The previous account epoch must stay cancelled") }
        catch { XCTAssertTrue(error is CancellationError, "\(error)") }
        XCTAssertTrue(fake.uploads.isEmpty)
        XCTAssertNil(service.lastSyncDate)
        XCTAssertNil(service.lastQueryOutcome)
        XCTAssertFalse(service.isSyncing)
    }

    func testOwnerChangeDuringUploadIgnoresTheOldOwnersResult() async throws {
        let service = makeService()
        try await service.connect()
        fake.collectResult = .success(samples(steps: 1200))
        let gate = Gate()
        fake.uploadGate = gate

        let running = Task { @MainActor in try await service.syncBiometrics(days: 7) }
        await gate.waitUntilEntered()
        fake.owner = ownerB
        service.ownerDidChange(ownerB)
        await gate.release()

        do { try await running.value; XCTFail("the old owner's sync must not complete into the new account") }
        catch { XCTAssertTrue(error is CancellationError, "\(error)") }
        XCTAssertNil(service.lastSyncDate, "a late callback must not publish for the new owner")
        XCTAssertNil(service.lastQueryOutcome)
        XCTAssertNil(service.syncError)
        XCTAssertFalse(service.isSyncing)
        XCTAssertEqual(fake.uploads.map(\.credential.owner), [ownerA], "the upload that had already started belongs to the old owner only")
        XCTAssertEqual(fake.uploads.first?.credential.accessToken, FakeHealth.token(ownerA), "the write used the token captured for A, not the ambient B session")
    }

    func testOwnerChangeDuringQueryNeverUploads() async throws {
        let service = makeService()
        try await service.connect()
        fake.collectResult = .success(samples(steps: 1200))
        let gate = Gate()
        fake.collectGate = gate

        let running = Task { @MainActor in try await service.syncBiometrics(days: 7) }
        await gate.waitUntilEntered()
        fake.owner = nil
        service.ownerDidChange(nil)
        await gate.release()

        do { try await running.value; XCTFail("must not complete after sign-out") }
        catch { XCTAssertTrue(error is CancellationError, "\(error)") }
        XCTAssertTrue(fake.uploads.isEmpty)
    }

    // MARK: H-R01 - writes are bound to the captured credential

    func testOwnerSwitchWithoutWiringStillCancelsAndNeverUploads() async throws {
        let service = makeService()
        try await service.connect()
        fake.collectResult = .success(samples(steps: 800))
        let gate = Gate()
        fake.collectGate = gate

        let running = Task { @MainActor in try await service.syncBiometrics(days: 7) }
        await gate.waitUntilEntered()
        fake.owner = ownerB                       // account switch; ownerDidChange was NOT called
        await gate.release()

        do { try await running.value; XCTFail("old samples must not be sent for the new account") }
        catch { XCTAssertTrue(error is CancellationError, "\(error)") }
        XCTAssertTrue(fake.uploads.isEmpty)
        XCTAssertNil(service.lastQueryOutcome)
        XCTAssertNil(service.lastSyncDate)
    }

    func testBoundWritesCarryOnlyTheCapturedCredential() async throws {
        let credentialA = HealthCredential(owner: ownerA, accessToken: "token-for-A")
        var seen: [URLRequest] = []
        var status = 200
        let writes = HealthBoundWrites(baseURL: URL(string: "https://example.invalid")!, apiKey: "anon-key", send: { request in
            seen.append(request)
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        })
        var day = BiometricSyncPayload.DailySummaryPayload(date: "2026-11-06")
        day.stepsCount = 0
        let payload = BiometricSyncPayload(dailySummaries: [day], workouts: [])

        try await writes.upload(payload, credential: credentialA)
        let upload = try XCTUnwrap(seen.last)
        XCTAssertEqual(upload.url?.absoluteString, "https://example.invalid/functions/v1/sync-biometrics")
        XCTAssertEqual(upload.httpMethod, "POST")
        XCTAssertEqual(upload.value(forHTTPHeaderField: "Authorization"), "Bearer token-for-A")
        XCTAssertEqual(upload.value(forHTTPHeaderField: "apikey"), "anon-key")
        let decoded = try JSONDecoder().decode(BiometricSyncPayload.self, from: try XCTUnwrap(upload.httpBody))
        XCTAssertEqual(decoded.dailySummaries.first?.stepsCount, 0)

        try await writes.writeConnection(connected: false, credential: credentialA)
        let connection = try XCTUnwrap(seen.last)
        XCTAssertEqual(connection.url?.path, "/rest/v1/healthkit_connections")
        XCTAssertEqual(connection.url?.query, "on_conflict=user_id")
        XCTAssertEqual(connection.value(forHTTPHeaderField: "Authorization"), "Bearer token-for-A")
        XCTAssertEqual(connection.value(forHTTPHeaderField: "Prefer"), "resolution=merge-duplicates,return=minimal")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(connection.httpBody)) as? [String: Any])
        XCTAssertEqual(body["user_id"] as? String, ownerA.uuidString)
        XCTAssertEqual(body["is_connected"] as? Bool, false)

        // Failures are bounded categories, never a remote body.
        status = 401
        do { try await writes.upload(payload, credential: credentialA); XCTFail() }
        catch { XCTAssertEqual(HealthOperationError.classify(error), .auth) }
        status = 503
        do { try await writes.writeConnection(connected: true, credential: credentialA); XCTFail() }
        catch { XCTAssertEqual(HealthOperationError.classify(error), .server) }
        status = 422
        do { try await writes.upload(payload, credential: credentialA); XCTFail() }
        catch { XCTAssertEqual(HealthOperationError.classify(error), .rejected) }
        XCTAssertEqual(HealthOperationError.classify(URLError(.timedOut)), .network)
        XCTAssertFalse(credentialA.description.contains("token-for-A"), "the token must never be printed")
    }

    // MARK: H-R03 - the account setting is resolved before any query, failing closed

    func testFreshInstanceHonorsARemoteDisconnectWithoutAnExplicitRefresh() async throws {
        fake.remote[ownerA] = .disconnected
        let service = makeService()
        service.ownerDidChange(ownerA)
        fake.permission = .completed
        // No checkAuthorizationStatus() call: syncBiometrics must still resolve the account setting.
        await expectThrows({ try await service.syncBiometrics(days: 7) }) { ($0 as? HealthSyncError) == .paused }
        XCTAssertEqual(fake.collectCalls, 0, "nothing may be queried for a disconnected account")
        XCTAssertTrue(fake.uploads.isEmpty)
        XCTAssertEqual(defaults.object(forKey: "healthkit.syncPaused.\(ownerA.uuidString.lowercased())") as? Bool, true)
    }

    func testUnknownOrMissingAccountSettingFailsClosed() async {
        let service = makeService()
        fake.forcedRemote = .unknown
        await expectThrows({ try await service.syncBiometrics(days: 7) }) { ($0 as? HealthSyncError) == .connectionUnknown }
        fake.forcedRemote = .noRecord
        await expectThrows({ try await service.syncBiometrics(days: 7) }) { ($0 as? HealthSyncError) == .notConnected }
        XCTAssertEqual(fake.collectCalls, 0)
        XCTAssertTrue(fake.uploads.isEmpty)
        XCTAssertTrue(service.hasCompletedPermissionRequest == false || !service.isSyncing)
    }

    func testRemoteDisconnectFromAnotherDeviceStopsAnExplicitlyConnectedDevice() async throws {
        let service = makeService()
        fake.collectResult = .success(samples(steps: 10))
        try await service.connect()
        try await service.syncBiometrics(days: 7)
        XCTAssertEqual(fake.uploads.count, 1)
        fake.remote[ownerA] = .disconnected          // disconnected elsewhere
        await expectThrows({ try await service.syncBiometrics(days: 7) }) { ($0 as? HealthSyncError) == .paused }
        XCTAssertEqual(fake.uploads.count, 1)
        XCTAssertTrue(service.syncPaused)
    }

    func testOverlappingSyncDoesNotRunTwiceAndLateErrorDoesNotOverwriteAPause() async throws {
        let service = makeService()
        try await service.connect()
        fake.collectResult = .success(samples(steps: 5))
        fake.uploadFails = true
        let gate = Gate()
        fake.uploadGate = gate

        let first = Task { @MainActor in try await service.syncBiometrics(days: 7) }
        await gate.waitUntilEntered()
        try await service.syncBiometrics(days: 7)       // overlapping call: returns without a second pass
        XCTAssertEqual(fake.collectCalls, 1)

        await service.disconnect()                      // newer deliberate choice while the upload is in flight
        await gate.release()
        do { try await first.value; XCTFail("the failed upload must surface to its own caller") }
        catch { XCTAssertTrue(error is HealthKitError, "\(error)") }
        XCTAssertNil(service.syncError, "a late error from a superseded sync must not overwrite the newer state")
        XCTAssertTrue(service.syncPaused)
        XCTAssertNil(service.lastSyncDate)
    }

    // MARK: H-R02 - only the newest deliberate choice wins

    func testConnectThenDisconnectDuringTheAccountWriteLeavesItPaused() async throws {
        let service = makeService()
        let gate = Gate()
        fake.writePlan = [.init(gate: gate)]           // the connect write is held at the account
        let connecting = Task { @MainActor in try await service.connect() }
        await gate.waitUntilEntered()
        let disconnecting = Task { @MainActor in await service.disconnect() }
        for _ in 0..<100 where !service.syncPaused { await Task.yield() }
        XCTAssertTrue(service.syncPaused, "the newer choice pauses locally while its account write is queued")
        await gate.release()
        await disconnecting.value

        do { try await connecting.value; XCTFail("the older connect must not win") }
        catch { XCTAssertTrue(error is CancellationError, "\(error)") }
        XCTAssertTrue(service.syncPaused)
        XCTAssertEqual(fake.writes.last?.connected, false, "the account ends up disconnected (writes are serialized)")
        XCTAssertEqual(fake.remote[ownerA], .disconnected)
        let relaunched = makeService()
        await relaunched.checkAuthorizationStatus()
        XCTAssertTrue(relaunched.syncPaused)
    }

    func testDisconnectThenConnectLetsTheNewerConnectWinAndIgnoresTheOlderFailure() async throws {
        let service = makeService()
        try await service.connect()
        let gate = Gate()
        fake.writePlan = [.init(gate: gate, fail: true)]   // the disconnect acknowledgement fails late
        let disconnecting = Task { @MainActor in await service.disconnect() }
        await gate.waitUntilEntered()
        XCTAssertTrue(service.syncPaused, "the local pause is immediate")
        let reconnecting = Task { @MainActor in try await service.connect() }
        await gate.release()
        await disconnecting.value
        try await reconnecting.value

        XCTAssertFalse(service.syncPaused, "the newer explicit Connect re-enables")
        XCTAssertNil(service.connectionError, "the older failure must not publish over the newer choice")
        XCTAssertEqual(fake.remote[ownerA], .connected)
        let relaunched = makeService()
        await relaunched.checkAuthorizationStatus()
        XCTAssertFalse(relaunched.syncPaused)
    }

    func testOwnerSwitchDuringThePromptNeverEnablesTheNewAccount() async throws {
        let service = makeService()
        let gate = Gate()
        fake.requestGate = gate
        let connecting = Task { @MainActor in try await service.connect() }
        await gate.waitUntilEntered()
        fake.owner = ownerB
        service.ownerDidChange(ownerB)
        await gate.release()

        do { try await connecting.value; XCTFail("a connect started for A must not complete for B") }
        catch { XCTAssertTrue(error is CancellationError, "\(error)") }
        XCTAssertTrue(fake.writes.isEmpty, "no account write may be made")
        XCTAssertNil(defaults.object(forKey: "healthkit.syncPaused.\(ownerB.uuidString.lowercased())"))
        XCTAssertNil(defaults.object(forKey: "healthkit.syncPaused.\(ownerA.uuidString.lowercased())"))
    }

    func testOwnerSwitchDuringTheAccountWriteDoesNotClearTheOldOwnersOptOut() async throws {
        let service = makeService()
        try await service.connect()
        await service.disconnect()
        let gate = Gate()
        fake.writePlan = [.init(gate: gate)]
        let reconnecting = Task { @MainActor in try await service.connect() }
        await gate.waitUntilEntered()
        fake.owner = ownerB
        service.ownerDidChange(ownerB)
        await gate.release()

        do { try await reconnecting.value; XCTFail("a late reconnect must not complete") }
        catch { XCTAssertTrue(error is CancellationError, "\(error)") }
        XCTAssertEqual(defaults.object(forKey: "healthkit.syncPaused.\(ownerA.uuidString.lowercased())") as? Bool, true,
                       "A's deliberate opt-out must survive a late reconnect")
        XCTAssertFalse(service.syncPaused, "B is unaffected")
    }

    func testLateDisconnectFailureForAnOldOwnerDoesNotSurfaceOnTheNewOwner() async throws {
        let service = makeService()
        try await service.connect()
        let gate = Gate()
        fake.writePlan = [.init(gate: gate, fail: true)]
        let disconnecting = Task { @MainActor in await service.disconnect() }
        await gate.waitUntilEntered()
        fake.owner = ownerB
        service.ownerDidChange(ownerB)
        await gate.release()
        await disconnecting.value
        XCTAssertFalse(service.syncPaused)
        XCTAssertNil(service.connectionError)
        XCTAssertEqual(defaults.object(forKey: "healthkit.syncPaused.\(ownerA.uuidString.lowercased())") as? Bool, true)
    }
}
