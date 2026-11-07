import XCTest
@testable import MindFriendApp

@MainActor
final class SupportStepReminderTests: XCTestCase {
    private func make(_ io: FaultyJournalIO, _ reminders: ReminderFixture, owner: UUID = UUID()) async throws -> SupportSessionCoordinator {
        let coordinator = SupportSessionCoordinator(repository: SupportSessionRepository(identity: .init(ownerID: owner), io: io), reminders: reminders)
        try await coordinator.load()
        return coordinator
    }

    private func savedStep(_ coordinator: SupportSessionCoordinator) async throws -> SupportActivity {
        let activity = try await coordinator.start(.chooseStepV1, origin: .today)
        try await coordinator.chooseStep(activity.id, choice: .saveForLater, text: "Synthetic saved step")
        return try XCTUnwrap(coordinator.journal.activities[activity.id])
    }

    func testScheduleAcknowledgementIsLocalAndReplacementKeepsOneIdentifier() async throws {
        let fixture = ReminderFixture(), coordinator = try await make(FaultyJournalIO(), fixture)
        let activity = try await savedStep(coordinator), intents = coordinator.journal.intents
        let at = Date().addingTimeInterval(3_600)
        try await coordinator.setReminder(activity.id, at: at, timeZoneIdentifier: "America/New_York")
        XCTAssertEqual(coordinator.journal.activities[activity.id]?.step?.reminderState, .scheduled)
        XCTAssertEqual(coordinator.journal.activities[activity.id]?.step?.reminderTimeZoneIdentifier, "America/New_York")
        XCTAssertEqual(coordinator.journal.intents, intents, "Device notifications must not create cloud work")
        try await coordinator.setReminder(activity.id, at: at.addingTimeInterval(600), timeZoneIdentifier: "Asia/Tokyo")
        XCTAssertEqual(fixture.requests.count, 1)
        XCTAssertEqual(fixture.requests[activity.id], at.addingTimeInterval(600))
    }

    func testReminderNeverEntersLaterResumeOrFinishMutations() async throws {
        let fixture = ReminderFixture(), coordinator = try await make(FaultyJournalIO(), fixture)
        let activity = try await savedStep(coordinator), at = Date().addingTimeInterval(3_600)
        try await coordinator.setReminder(activity.id, at: at, timeZoneIdentifier: "America/New_York")
        try await coordinator.resume(activity.id, origin: .today)
        let journal = try await coordinator.repository.currentJournal(epoch: coordinator.identity.epochID)
        guard case .checkpointActivity(_, _, _, let step) = journal.intents.last?.payload else { return XCTFail("Resume intent") }
        XCTAssertNil(step?.reminderAt)
        XCTAssertNil(step?.reminderTimeZoneIdentifier)
        XCTAssertNil(step?.reminderState)
        XCTAssertEqual(journal.activities[activity.id]?.step?.reminderAt, at)
        try await coordinator.chooseStep(activity.id, choice: .didIt, text: nil)
        let ended = try await coordinator.repository.currentJournal(epoch: coordinator.identity.epochID)
        guard case .finishActivity(_, _, _, let finishedStep, _) = ended.intents.last?.payload else { return XCTFail("Finish intent") }
        XCTAssertNil(finishedStep?.reminderAt)
        XCTAssertNil(finishedStep?.reminderState)
    }

    func testRemoteSnapshotPreservesOnlyThisDevicesSavedReminder() async throws {
        let fixture = ReminderFixture(), coordinator = try await make(FaultyJournalIO(), fixture)
        let activity = try await savedStep(coordinator), at = Date().addingTimeInterval(3_600)
        try await coordinator.setReminder(activity.id, at: at, timeZoneIdentifier: "America/New_York")
        while let envelope = try await coordinator.repository.nextEnvelopeToSend(epoch: coordinator.identity.epochID) {
            try await coordinator.repository.resolveAttempt(epoch: coordinator.identity.epochID, operationID: envelope.operationID,
                outcome: .confirmed(revision: (envelope.expectedRevision ?? 0) + 1))
        }
        var remote = activity
        remote.step = remote.step?.accountPayload
        let local = try await coordinator.repository.currentJournal(epoch: coordinator.identity.epochID)
        try await coordinator.repository.applyRemoteSession(epoch: coordinator.identity.epochID,
            remote: .init(session: try XCTUnwrap(local.sessions[activity.sessionID]), activities: [remote], revision: 100))
        let merged = try await coordinator.repository.currentJournal(epoch: coordinator.identity.epochID)
        XCTAssertEqual(merged.activities[activity.id]?.step?.reminderAt, at)
        XCTAssertEqual(merged.activities[activity.id]?.step?.reminderState, .scheduled)
    }

    func testAccountEndCancelsOwnerRequestsEvenWithoutLoadedJournal() async {
        let fixture = ReminderFixture()
        fixture.requests[UUID()] = Date().addingTimeInterval(3_600)
        let coordinator = SupportSessionCoordinator(repository: SupportSessionRepository(identity: .init(ownerID: UUID()), io: FaultyJournalIO()), reminders: fixture)
        await coordinator.invalidate().value
        XCTAssertTrue(fixture.requests.isEmpty)
        XCTAssertEqual(fixture.cancelAllCalls, 1)
    }

    func testReloadWithRevokedPermissionMarksReminderFailedWithoutPrompt() async throws {
        let io = FaultyJournalIO(), fixture = ReminderFixture(), owner = UUID()
        let coordinator = try await make(io, fixture, owner: owner)
        let activity = try await savedStep(coordinator)
        try await coordinator.setReminder(activity.id, at: Date().addingTimeInterval(3_600), timeZoneIdentifier: "America/New_York")
        let copy = FaultyJournalIO()
        copy.seedPrimary(try XCTUnwrap(io.primary(ownerID: owner)), ownerID: owner)
        fixture.authorized = false
        let count = fixture.scheduleCalls
        let again = try await make(copy, fixture, owner: owner)
        XCTAssertEqual(again.journal.activities[activity.id]?.step?.reminderState, .failed)
        XCTAssertTrue(fixture.requests.isEmpty)
        XCTAssertEqual(fixture.scheduleCalls, count)
    }

    func testDeniedSchedulingRetainsStepAndVisibleRetryState() async throws {
        let fixture = ReminderFixture(), coordinator = try await make(FaultyJournalIO(), fixture)
        let activity = try await savedStep(coordinator)
        fixture.fail = true
        do { try await coordinator.setReminder(activity.id, at: Date().addingTimeInterval(3_600), timeZoneIdentifier: "America/New_York"); XCTFail("Permission denied") }
        catch { XCTAssertTrue(error is SupportStepReminderError) }
        XCTAssertEqual(coordinator.journal.activities[activity.id]?.step?.state, .saved)
        XCTAssertEqual(coordinator.journal.activities[activity.id]?.step?.reminderState, .failed)
        XCTAssertTrue(fixture.requests.isEmpty)
        fixture.fail = false
        try await coordinator.setReminder(activity.id, at: Date().addingTimeInterval(3_600), timeZoneIdentifier: "America/New_York")
        XCTAssertEqual(coordinator.journal.activities[activity.id]?.step?.reminderState, .scheduled)
    }

    func testJournalFailurePreventsNotificationAndPermissionWork() async throws {
        let io = FaultyJournalIO(), fixture = ReminderFixture(), coordinator = try await make(io, fixture)
        let activity = try await savedStep(coordinator)
        io.failCommits = true
        do { try await coordinator.setReminder(activity.id, at: Date().addingTimeInterval(3_600), timeZoneIdentifier: "America/New_York"); XCTFail("Write failure") }
        catch {}
        XCTAssertEqual(fixture.scheduleCalls, 0)
        XCTAssertNil(coordinator.journal.activities[activity.id]?.step?.reminderAt)
    }

    func testLateSchedulingAfterCompletionCannotResurrectReminder() async throws {
        let fixture = ReminderFixture(), coordinator = try await make(FaultyJournalIO(), fixture)
        let activity = try await savedStep(coordinator)
        fixture.beforeScheduleReturns = { try await coordinator.chooseStep(activity.id, choice: .didIt, text: nil) }
        do { try await coordinator.setReminder(activity.id, at: Date().addingTimeInterval(3_600), timeZoneIdentifier: "America/New_York"); XCTFail("Completion changed reminder eligibility") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(fixture.requests.isEmpty)
        XCTAssertEqual(coordinator.journal.activities[activity.id]?.status, .completed)
        XCTAssertNil(coordinator.journal.activities[activity.id]?.step?.reminderAt)
    }

    func testLateSchedulingAfterAccountEndCannotPublishOrNotify() async throws {
        let fixture = ReminderFixture(), coordinator = try await make(FaultyJournalIO(), fixture)
        let activity = try await savedStep(coordinator)
        fixture.beforeScheduleReturns = { await coordinator.invalidate().value }
        do { try await coordinator.setReminder(activity.id, at: Date().addingTimeInterval(3_600), timeZoneIdentifier: "America/New_York"); XCTFail("Ended account") }
        catch { XCTAssertEqual(error as? SupportSessionError, .invalidated) }
        XCTAssertTrue(fixture.requests.isEmpty)
        XCTAssertTrue(coordinator.journal.sessions.isEmpty)
    }

    func testCloseAndExplicitCancelRemoveScheduledReminder() async throws {
        let fixture = ReminderFixture(), coordinator = try await make(FaultyJournalIO(), fixture)
        let activity = try await savedStep(coordinator)
        try await coordinator.setReminder(activity.id, at: Date().addingTimeInterval(3_600), timeZoneIdentifier: "America/New_York")
        try await coordinator.cancelReminder(activity.id)
        XCTAssertTrue(fixture.requests.isEmpty)
        XCTAssertEqual(coordinator.journal.activities[activity.id]?.step?.state, .saved)
        XCTAssertNil(coordinator.journal.activities[activity.id]?.step?.reminderAt)
        try await coordinator.setReminder(activity.id, at: Date().addingTimeInterval(3_600), timeZoneIdentifier: "America/New_York")
        try await coordinator.close(activity.sessionID)
        XCTAssertTrue(fixture.requests.isEmpty)
        XCTAssertEqual(coordinator.journal.sessions[activity.sessionID]?.status, .closed)
    }

    func testReloadOnlyReconcilesExistingRequestsAndNeverSchedules() async throws {
        let io = FaultyJournalIO(), fixture = ReminderFixture(), owner = UUID()
        let coordinator = try await make(io, fixture, owner: owner)
        let activity = try await savedStep(coordinator)
        let at = Date().addingTimeInterval(3_600)
        try await coordinator.setReminder(activity.id, at: at, timeZoneIdentifier: "America/New_York")
        let copiedIO = FaultyJournalIO()
        copiedIO.seedPrimary(try XCTUnwrap(io.primary(ownerID: owner)), ownerID: owner)
        let otherDevice = ReminderFixture()
        let reloaded = try await make(copiedIO, otherDevice, owner: owner)
        XCTAssertEqual(otherDevice.scheduleCalls, 0)
        XCTAssertTrue(otherDevice.requests.isEmpty)
        XCTAssertEqual(reloaded.journal.activities[activity.id]?.step?.reminderState, .failed)
        XCTAssertEqual(reloaded.journal.activities[activity.id]?.step?.reminderAt, at)
        XCTAssertEqual(fixture.requests[activity.id], at, "Reconciliation must touch only its own device")
    }
}

@MainActor
private final class ReminderFixture: SupportStepReminding {
    var requests: [UUID: Date] = [:]
    var scheduleCalls = 0
    var fail = false
    var authorized = true
    var cancelAllCalls = 0
    var beforeScheduleReturns: (() async throws -> Void)?
    func schedule(ownerID: UUID, activityID: UUID, at: Date) async throws {
        scheduleCalls += 1
        try await beforeScheduleReturns?()
        if fail { throw SupportStepReminderError.permissionDenied }
        requests[activityID] = at
    }
    func cancel(ownerID: UUID, activityID: UUID) { requests[activityID] = nil }
    func pending(ownerID: UUID) async -> [UUID: Date] { requests }
    func cancelAll(ownerID: UUID) async { cancelAllCalls += 1; requests.removeAll() }
    func authorizationAllowsDelivery() async -> Bool { authorized }
}
