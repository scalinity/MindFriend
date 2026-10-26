//
//  SleepScoreCalculatorTests.swift
//  MindFriendAppTests
//
//  Unit tests for sleep score calculation algorithm
//

import XCTest
import SwiftUI
import Supabase
import HealthKit
@testable import MindFriendApp

final class SleepScoreCalculatorTests: XCTestCase {
    private var calculator: SleepScoreCalculator!
    private var goals: SleepGoals!

    override func setUp() {
        super.setUp()
        calculator = SleepScoreCalculator()

        // Default goals: 11 PM bedtime, 7 AM wake, 8 hours sleep
        let calendar = Calendar.current
        let now = Date()
        goals = SleepGoals(
            id: UUID(),
            userId: UUID(),
            targetBedtime: calendar.date(bySettingHour: 23, minute: 0, second: 0, of: now),
            targetWakeTime: calendar.date(bySettingHour: 7, minute: 0, second: 0, of: now),
            targetDurationMinutes: 480, // 8 hours
            windDownDurationMinutes: 30,
            bedtimeReminderEnabled: false,
            bedtimeReminderOffsetMinutes: 60,
            preferredWindDownTypes: [],
            sleepEnvironmentPrefs: SleepEnvironmentPrefs(
                prefersDarkRoom: true,
                prefersCoolRoom: true,
                usesWhiteNoise: false,
                hasBlueLight: false
            ),
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    override func tearDown() {
        calculator = nil
        goals = nil
        super.tearDown()
    }

    // MARK: - Duration Score Tests (0-25 points)

    func testDurationScore_OptimalSleep_Returns25() {
        // 8 hours = 100% of target
        let entry = createEntry(timeAsleepMinutes: 480)
        let breakdown = calculator.calculateScore(entry: entry, goals: goals)

        XCTAssertEqual(breakdown.duration, 25)
    }

    func testDurationScore_SlightlyLow_Returns20() {
        // 7 hours = 87.5% of target (80-90% range)
        let entry = createEntry(timeAsleepMinutes: 420)
        let breakdown = calculator.calculateScore(entry: entry, goals: goals)

        XCTAssertEqual(breakdown.duration, 20)
    }

    func testDurationScore_TooLow_ReturnsLowScore() {
        // 5 hours = 62.5% of target (<70%)
        let entry = createEntry(timeAsleepMinutes: 300)
        let breakdown = calculator.calculateScore(entry: entry, goals: goals)

        XCTAssertLessThanOrEqual(breakdown.duration, 15)
    }

    // MARK: - Efficiency Score Tests (0-25 points)

    func testEfficiencyScore_HighEfficiency_Returns25() {
        // 90% efficiency (≥85%)
        let entry = createEntry(timeInBedMinutes: 480, timeAsleepMinutes: 432)
        let breakdown = calculator.calculateScore(entry: entry, goals: goals)

        XCTAssertEqual(breakdown.efficiency, 25)
    }

    func testEfficiencyScore_MediumEfficiency_Returns20() {
        // 82% efficiency (80-84%)
        let entry = createEntry(timeInBedMinutes: 480, timeAsleepMinutes: 394)
        let breakdown = calculator.calculateScore(entry: entry, goals: goals)

        XCTAssertEqual(breakdown.efficiency, 20)
    }

    func testEfficiencyScore_LowEfficiency_Returns10OrLess() {
        // 60% efficiency (<70%)
        let entry = createEntry(timeInBedMinutes: 480, timeAsleepMinutes: 288)
        let breakdown = calculator.calculateScore(entry: entry, goals: goals)

        XCTAssertLessThanOrEqual(breakdown.efficiency, 10)
    }

    // MARK: - Timing Score Tests (0-20 points)

    func testTimingScore_OnTime_Returns20() {
        // Bedtime exactly at target (11 PM)
        let calendar = Calendar.current
        let targetDate = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: Date())!
        let entry = createEntry(bedtime: targetDate)
        let breakdown = calculator.calculateScore(entry: entry, goals: goals)

        XCTAssertEqual(breakdown.timing, 20)
    }

    func testTimingScore_SlightlyLate_Returns17() {
        // Bedtime 20 minutes late (within 15-30 min)
        let calendar = Calendar.current
        let targetDate = calendar.date(bySettingHour: 23, minute: 20, second: 0, of: Date())!
        let entry = createEntry(bedtime: targetDate)
        let breakdown = calculator.calculateScore(entry: entry, goals: goals)

        XCTAssertGreaterThanOrEqual(breakdown.timing, 14)
        XCTAssertLessThan(breakdown.timing, 20)
    }

    func testTimingScore_VeryLate_ReturnsLowScore() {
        // Bedtime 2 hours late (>90 min)
        let calendar = Calendar.current
        let targetDate = calendar.date(bySettingHour: 1, minute: 0, second: 0, of: Date())!
        let entry = createEntry(bedtime: targetDate)
        let breakdown = calculator.calculateScore(entry: entry, goals: goals)

        XCTAssertLessThanOrEqual(breakdown.timing, 8)
    }

    // MARK: - Stages Score Tests (0-20 points)

    func testStagesScore_OptimalDeepAndREM_Returns20() {
        // 20% deep sleep (15-25% optimal), 22% REM (20-25% optimal)
        let entry = createEntry(
            timeAsleepMinutes: 480,
            deepSleepMinutes: 96,   // 20%
            remSleepMinutes: 106     // 22%
        )
        let breakdown = calculator.calculateScore(entry: entry, goals: goals)

        XCTAssertEqual(breakdown.stages, 20)
    }

    func testStagesScore_NoStageData_Returns0() {
        // No sleep stage data (older device or missing data)
        let entry = createEntry(
            timeAsleepMinutes: 480,
            deepSleepMinutes: nil,
            remSleepMinutes: nil
        )
        let breakdown = calculator.calculateScore(entry: entry, goals: goals)

        XCTAssertEqual(breakdown.stages, 0)
    }

    func testStagesScore_LowDeepSleep_ReturnsReducedScore() {
        // 10% deep sleep (below optimal 15-25%)
        let entry = createEntry(
            timeAsleepMinutes: 480,
            deepSleepMinutes: 48,    // 10%
            remSleepMinutes: 106     // 22%
        )
        let breakdown = calculator.calculateScore(entry: entry, goals: goals)

        // Should have REM points but reduced deep sleep points
        XCTAssertGreaterThan(breakdown.stages, 0)
        XCTAssertLessThan(breakdown.stages, 20)
    }

    // MARK: - Restfulness Score Tests (0-10 points)

    func testRestfulnessScore_MinimalAwakeTime_Returns10() {
        // 2% awake time (<5%)
        let entry = createEntry(
            timeInBedMinutes: 480,
            timeAsleepMinutes: 470,
            awakeMinutes: 10  // 2% of time in bed
        )
        let breakdown = calculator.calculateScore(entry: entry, goals: goals)

        XCTAssertEqual(breakdown.restfulness, 10)
    }

    func testRestfulnessScore_ModerateAwakeTime_Returns8() {
        // 7% awake time (5-10%)
        let entry = createEntry(
            timeInBedMinutes: 480,
            timeAsleepMinutes: 446,
            awakeMinutes: 34  // ~7%
        )
        let breakdown = calculator.calculateScore(entry: entry, goals: goals)

        XCTAssertEqual(breakdown.restfulness, 8)
    }

    func testRestfulnessScore_HighAwakeTime_Returns2() {
        // 25% awake time (>20%)
        let entry = createEntry(
            timeInBedMinutes: 480,
            timeAsleepMinutes: 360,
            awakeMinutes: 120  // 25%
        )
        let breakdown = calculator.calculateScore(entry: entry, goals: goals)

        XCTAssertEqual(breakdown.restfulness, 2)
    }

    // MARK: - Total Score Tests

    func testTotalScore_PerfectSleep_Returns100() {
        // Perfect sleep: 100% duration, 100% efficiency, on time, optimal stages, minimal awake
        let calendar = Calendar.current
        let targetBedtime = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: Date())!

        let entry = SleepEntry(
            id: UUID(),
            userId: UUID(),
            date: Date(),
            source: .healthkit,
            bedtime: targetBedtime,
            wakeTime: calendar.date(byAdding: .hour, value: 8, to: targetBedtime)!,
            timeInBedMinutes: 480,
            timeAsleepMinutes: 475,  // High efficiency
            deepSleepMinutes: 96,     // 20% optimal
            remSleepMinutes: 106,     // 22% optimal
            lightSleepMinutes: 273,
            awakeMinutes: 5,          // <1% minimal
            sleepEfficiency: 0.99,
            heartRateAvg: nil,
            heartRateMin: nil,
            hrvAvg: nil,
            respiratoryRate: nil,
            userRating: nil,
            dreamNotes: nil,
            notes: nil,
            sleepScore: nil,
            scoreBreakdown: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        let breakdown = calculator.calculateScore(entry: entry, goals: goals)

        XCTAssertEqual(breakdown.total, 100)
    }

    func testTotalScore_PoorSleep_ReturnsLowScore() {
        // Poor sleep: low duration, low efficiency, late, no stage data, high awake
        let calendar = Calendar.current
        let lateBedtime = calendar.date(bySettingHour: 2, minute: 0, second: 0, of: Date())!

        let entry = SleepEntry(
            id: UUID(),
            userId: UUID(),
            date: Date(),
            source: .manual,
            bedtime: lateBedtime,
            wakeTime: calendar.date(byAdding: .hour, value: 5, to: lateBedtime)!,
            timeInBedMinutes: 300,
            timeAsleepMinutes: 210,  // 70% efficiency
            deepSleepMinutes: nil,
            remSleepMinutes: nil,
            lightSleepMinutes: nil,
            awakeMinutes: 90,        // 30% awake
            sleepEfficiency: 0.70,
            heartRateAvg: nil,
            heartRateMin: nil,
            hrvAvg: nil,
            respiratoryRate: nil,
            userRating: nil,
            dreamNotes: nil,
            notes: nil,
            sleepScore: nil,
            scoreBreakdown: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        let breakdown = calculator.calculateScore(entry: entry, goals: goals)

        // Total should be significantly below 50
        XCTAssertLessThan(breakdown.total, 50)
    }

    // MARK: - Helper Methods

    private func createEntry(
        bedtime: Date? = nil,
        timeInBedMinutes: Int = 480,
        timeAsleepMinutes: Int = 450,
        deepSleepMinutes: Int? = nil,
        remSleepMinutes: Int? = nil,
        awakeMinutes: Int? = nil
    ) -> SleepEntry {
        let calendar = Calendar.current
        let actualBedtime = bedtime ?? calendar.date(bySettingHour: 23, minute: 0, second: 0, of: Date())!
        let wakeTime = calendar.date(byAdding: .minute, value: timeInBedMinutes, to: actualBedtime)!

        return SleepEntry(
            id: UUID(),
            userId: UUID(),
            date: Date(),
            source: .healthkit,
            bedtime: actualBedtime,
            wakeTime: wakeTime,
            timeInBedMinutes: timeInBedMinutes,
            timeAsleepMinutes: timeAsleepMinutes,
            deepSleepMinutes: deepSleepMinutes,
            remSleepMinutes: remSleepMinutes,
            lightSleepMinutes: nil,
            awakeMinutes: awakeMinutes,
            sleepEfficiency: awakeMinutes != nil ? Double(timeAsleepMinutes) / Double(timeInBedMinutes) : nil,
            heartRateAvg: nil,
            heartRateMin: nil,
            hrvAvg: nil,
            respiratoryRate: nil,
            userRating: nil,
            dreamNotes: nil,
            notes: nil,
            sleepScore: nil,
            scoreBreakdown: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}


@MainActor
final class SleepDashboardRegressionTests: XCTestCase {
    private let owner = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!

    func testCancelledPullStillCompletesTheScreenOwnedRefresh() async {
        let reader = SleepDashboardFixture(owner: owner)
        reader.entries = [entry(owner: owner)]
        let model = SleepDashboardViewModel()
        let gate = SleepRefreshGate()
        let pull = Task { await model.refresh(trackingService: reader) {
            await gate.wait()
            try Task.checkCancellation()
        } }
        await gate.waitUntilStarted()
        pull.cancel()
        gate.open()
        await pull.value
        XCTAssertEqual(model.lastSleepEntry?.id, reader.entries.first?.id)
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.syncErrorMessage)
        XCTAssertEqual(reader.readCount, 1)
    }

    func testOverlappingPullsUseOneSyncAndOneReload() async {
        let reader = SleepDashboardFixture(owner: owner)
        reader.entries = [entry(owner: owner)]
        let model = SleepDashboardViewModel()
        let gate = SleepRefreshGate()
        var syncCount = 0
        let first = Task { await model.refresh(trackingService: reader) {
            syncCount += 1
            await gate.wait()
        } }
        await gate.waitUntilStarted()
        let joinedStarted = SleepRefreshGate()
        let joined = Task {
            joinedStarted.signalStart()
            await model.refresh(trackingService: reader) { syncCount += 1 }
        }
        await joinedStarted.waitUntilStarted()
        first.cancel()
        gate.open()
        await first.value
        await joined.value
        XCTAssertEqual(syncCount, 1)
        XCTAssertEqual(reader.readCount, 1)
        XCTAssertEqual(model.lastSleepEntry?.id, reader.entries.first?.id)
    }

    func testLeavingScreenCancelsRefreshAndAllowsANewAttempt() async {
        let reader = SleepDashboardFixture(owner: owner)
        reader.entries = [entry(owner: owner)]
        let model = SleepDashboardViewModel()
        let gate = SleepRefreshGate()
        let first = Task { await model.refresh(trackingService: reader) { await gate.wait() } }
        await gate.waitUntilStarted()
        model.cancelRefresh()
        await model.refresh(trackingService: reader) { }
        let currentID = model.lastSleepEntry?.id
        gate.open()
        await first.value
        XCTAssertEqual(currentID, reader.entries.first?.id)
        XCTAssertEqual(model.lastSleepEntry?.id, currentID)
        XCTAssertEqual(reader.readCount, 1, "The cancelled operation must not reload after returning")
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.syncErrorMessage)
    }

    func testCancelledOldCompletionDoesNotClearTheNewRefresh() async {
        let reader = SleepDashboardFixture(owner: owner)
        reader.entries = [entry(owner: owner)]
        let model = SleepDashboardViewModel()
        let oldGate = SleepRefreshGate(), newGate = SleepRefreshGate(), joinedStarted = SleepRefreshGate()
        var syncCount = 0
        let old = Task { await model.refresh(trackingService: reader) {
            syncCount += 1
            await oldGate.wait()
        } }
        await oldGate.waitUntilStarted()
        model.cancelRefresh()
        let current = Task { await model.refresh(trackingService: reader) {
            syncCount += 1
            await newGate.wait()
        } }
        await newGate.waitUntilStarted()
        oldGate.open()
        await old.value
        let joined = Task {
            joinedStarted.signalStart()
            await model.refresh(trackingService: reader) { syncCount += 1 }
        }
        await joinedStarted.waitUntilStarted()
        newGate.open()
        await current.value
        await joined.value
        XCTAssertEqual(syncCount, 2, "The third pull must join the active replacement")
        XCTAssertEqual(reader.readCount, 1)
        XCTAssertEqual(model.lastSleepEntry?.id, reader.entries.first?.id)
    }

    func testCancellationDuringOwnerRecheckCannotOverwriteANewerLoad() async {
        let reader = SleepDashboardFixture(owner: owner)
        let gate = SleepRefreshGate()
        reader.beforeOwnerRead = { count in if count == 2 { await gate.wait() } }
        let model = SleepDashboardViewModel()
        let pull = Task { await model.refresh(trackingService: reader) { } }
        await gate.waitUntilStarted()
        model.cancelRefresh()
        let current = entry(owner: owner)
        reader.entries = [current]
        await model.loadData(trackingService: reader)
        reader.entries = []
        gate.open()
        await pull.value
        XCTAssertEqual(model.lastSleepEntry?.id, current.id)
        XCTAssertEqual(reader.readCount, 1)
        XCTAssertNil(model.errorMessage)
    }

    func testOwnerLookupFailureStillShowsActionableLoadFailure() async {
        let reader = SleepDashboardFixture(owner: owner)
        reader.beforeOwnerRead = { _ in throw URLError(.userAuthenticationRequired) }
        let model = SleepDashboardViewModel()
        var didSync = false
        await model.refresh(trackingService: reader) { didSync = true }
        XCTAssertFalse(didSync)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertNil(model.lastSleepEntry)
    }

    func testCancellationDuringReloadCannotPublishOverANewerLoad() async {
        let reader = SleepDashboardFixture(owner: owner)
        let gate = SleepRefreshGate()
        reader.beforeEntriesRead = { await gate.wait(); try Task.checkCancellation() }
        let model = SleepDashboardViewModel()
        let pull = Task { await model.refresh(trackingService: reader) { } }
        await gate.waitUntilStarted()
        model.cancelRefresh()
        let currentReader = SleepDashboardFixture(owner: owner)
        let current = entry(owner: owner)
        currentReader.entries = [current]
        await model.loadData(trackingService: currentReader)
        gate.open()
        await pull.value
        XCTAssertEqual(model.lastSleepEntry?.id, current.id)
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(model.syncErrorMessage)
    }

    func testAccountChangeDuringSyncDiscardsTheRefresh() async {
        let reader = SleepDashboardFixture(owner: owner)
        reader.entries = [entry(owner: owner)]
        let model = SleepDashboardViewModel()
        let gate = SleepRefreshGate()
        let pull = Task { await model.refresh(trackingService: reader) { await gate.wait() } }
        await gate.waitUntilStarted()
        reader.owner = UUID()
        gate.open()
        await pull.value
        XCTAssertEqual(reader.readCount, 0)
        XCTAssertNil(model.lastSleepEntry)
        XCTAssertNil(model.errorMessage)
    }

    func testSkipSurvivesRefreshAndModelRecreationForOnlyThatOwnerAndEntry() async {
        let suite = "sleep-skip-test-" + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let reader = SleepDashboardFixture(owner: owner)
        let record = entry(owner: owner)
        reader.entries = [record]
        let model = SleepDashboardViewModel(preferences: preferences)
        await model.loadData(trackingService: reader)
        XCTAssertTrue(model.showMorningCheckIn)
        model.skipMorningCheckIn(for: record)
        await model.refresh(trackingService: reader) { }
        XCTAssertFalse(model.showMorningCheckIn)
        let reopened = SleepDashboardViewModel(preferences: preferences)
        await reopened.loadData(trackingService: reader)
        XCTAssertFalse(reopened.showMorningCheckIn)
        reader.entries = [entry(owner: owner)]
        await reopened.loadData(trackingService: reader)
        XCTAssertTrue(reopened.showMorningCheckIn, "A different sleep entry remains eligible")
        let otherOwner = UUID()
        let otherReader = SleepDashboardFixture(owner: otherOwner)
        otherReader.entries = [entry(owner: otherOwner)]
        await reopened.loadData(trackingService: otherReader)
        XCTAssertTrue(reopened.showMorningCheckIn, "Skip does not carry between owners")
    }

    func testRecentRefreshReturnsWhileHistoryRunsAndFailureAllowsRetry() async {
        let reader = SleepDashboardFixture(owner: owner)
        reader.entries = [entry(owner: owner)]
        let model = SleepDashboardViewModel()
        let gate = SleepRefreshGate()
        let returned = expectation(description: "Recent refresh returns before old history finishes")
        let pull = Task {
            await model.refresh(trackingService: reader, sync: { }, history: { started in
                started()
                await gate.wait()
                throw URLError(.notConnectedToInternet)
            })
            returned.fulfill()
        }
        await gate.waitUntilStarted()
        await fulfillment(of: [returned], timeout: 2)
        XCTAssertEqual(model.lastSleepEntry?.id, reader.entries.first?.id)
        XCTAssertTrue(model.isImportingHistory)
        // Another foreground must still refresh recent records during a long history import.
        var recentSyncs = 0
        await model.refresh(trackingService: reader, sync: { recentSyncs += 1 }, history: { _ in
            XCTFail("History must remain coalesced")
        })
        XCTAssertEqual(recentSyncs, 1)
        gate.open()
        await pull.value
        for _ in 0..<1000 { if model.syncErrorMessage != nil { break }; await Task.yield() }
        XCTAssertNotNil(model.syncErrorMessage)
        XCTAssertFalse(model.isImportingHistory)
        XCTAssertEqual(model.lastSleepEntry?.id, reader.entries.first?.id)
        await model.refresh(trackingService: reader, sync: { }, history: { _ in })
        XCTAssertNil(model.syncErrorMessage)
        XCTAssertFalse(model.isImportingHistory, "No batches means no importing row")
        model.cancelRefresh()
    }

    func testLeavingDuringHistoryStopsItsPublicationAndClearsProgress() async {
        let reader = SleepDashboardFixture(owner: owner)
        let model = SleepDashboardViewModel()
        let gate = SleepRefreshGate()
        await model.refresh(trackingService: reader, sync: { }, history: { started in
            started()
            await gate.wait()
            try Task.checkCancellation()
        })
        await gate.waitUntilStarted()
        model.cancelRefresh()
        gate.open()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(model.isImportingHistory)
        XCTAssertNil(model.syncErrorMessage)
        XCTAssertTrue(model.isLoading, "Returning without records must start with loading rather than an empty flash")
    }

    func testAccountResetClearsResultsBeforeAutomaticSyncCanSuspend() async {
        let reader = SleepDashboardFixture(owner: owner)
        reader.entries = [entry(owner: owner)]
        let model = SleepDashboardViewModel()
        await model.loadData(trackingService: reader)
        XCTAssertNotNil(model.lastSleepEntry)
        XCTAssertTrue(model.showMorningCheckIn)
        model.prepareForOwner(UUID())
        XCTAssertNil(model.lastSleepEntry)
        XCTAssertTrue(model.weekEntries.isEmpty)
        XCTAssertTrue(model.insights.isEmpty)
        XCTAssertFalse(model.showMorningCheckIn)
        XCTAssertTrue(model.isLoading)
        let gate = SleepRefreshGate()
        let refresh = Task { await model.refresh(trackingService: reader, sync: { await gate.wait() }) }
        await gate.waitUntilStarted()
        XCTAssertNil(model.lastSleepEntry, "Previous results must not remain during the new owner's Health query")
        model.cancelRefresh()
        gate.open()
        await refresh.value
    }

    func testSameOwnerReentryRetainsContentAndAFormOpenedDuringReadKeepsItsDraft() async {
        let reader = SleepDashboardFixture(owner: owner)
        let original = entry(owner: owner)
        reader.entries = [original]
        let model = SleepDashboardViewModel()
        await model.loadData(trackingService: reader)
        model.skipMorningCheckIn(for: original)
        model.prepareForOwner(owner)
        XCTAssertEqual(model.lastSleepEntry?.id, original.id)
        XCTAssertEqual(model.weekEntries.count, 1)
        let gate = SleepRefreshGate()
        reader.beforeEntriesRead = { await gate.wait() }
        let refresh = Task { await model.refresh(trackingService: reader, sync: { }) }
        await gate.waitUntilStarted()
        XCTAssertEqual(model.lastSleepEntry?.id, original.id, "Re-entry must not blank the known current-owner record")
        model.showMorningCheckIn = true
        gate.open()
        await refresh.value
        XCTAssertTrue(model.showMorningCheckIn, "A form opened during the read must not be force-dismissed")
        XCTAssertEqual(model.lastSleepEntry?.id, original.id)
        reader.beforeEntriesRead = nil
        reader.fail = true
        await model.refresh(trackingService: reader, sync: { })
        XCTAssertTrue(model.showMorningCheckIn, "A failed read must not discard the open draft either")
        XCTAssertEqual(model.lastSleepEntry?.id, original.id)
        XCTAssertNotNil(model.errorMessage)
        model.cancelRefresh()
    }

    func testRecentDateConflictStillAllowsOlderHistoryAndShowsSpecificFeedback() async {
        let reader = SleepDashboardFixture(owner: owner)
        let model = SleepDashboardViewModel()
        let imported = expectation(description: "Older history remains reachable")
        await model.refresh(trackingService: reader, sync: { throw SleepTrackingError.importDateConflict },
            history: { _ in imported.fulfill() })
        await fulfillment(of: [imported], timeout: 2)
        XCTAssertEqual(model.syncErrorMessage, SleepTrackingError.importDateConflict.localizedDescription)
        model.cancelRefresh()
    }

    func testEmptyDeletedAndFailedReloadNeverKeepPersonalResults() async {
        let reader = SleepDashboardFixture(owner: owner)
        let model = SleepDashboardViewModel()
        reader.latest = entry(owner: owner)
        reader.entries = [reader.latest!]
        await model.loadData(trackingService: reader)
        XCTAssertNotNil(model.lastSleepEntry)
        reader.latest = nil
        reader.entries = []
        await model.loadData(trackingService: reader)
        XCTAssertNil(model.lastSleepEntry)
        XCTAssertTrue(model.weekEntries.isEmpty)
        reader.fail = true
        await model.loadData(trackingService: reader)
        XCTAssertNil(model.lastSleepEntry)
        XCTAssertNotNil(model.errorMessage)
    }

    func testStaleFutureAndOtherOwnerRecordsAreNotLastNight() async {
        let reader = SleepDashboardFixture(owner: owner)
        let model = SleepDashboardViewModel()
        for invalid in [entry(owner: UUID()), entry(owner: owner, daysAgo: 30), entry(owner: owner, daysAgo: -1)] {
            reader.latest = invalid
            reader.entries = [invalid]
            await model.loadData(trackingService: reader)
            XCTAssertNil(model.lastSleepEntry)
            XCTAssertTrue(model.weekEntries.isEmpty)
        }
    }

    func testAccountSwitchDuringRequestDiscardsResponse() async {
        let reader = SleepDashboardFixture(owner: owner)
        reader.latest = entry(owner: owner)
        reader.entries = [reader.latest!]
        reader.switchAccountAfterRead = true
        let model = SleepDashboardViewModel()
        await model.loadData(trackingService: reader)
        XCTAssertNil(model.lastSleepEntry)
        XCTAssertTrue(model.weekEntries.isEmpty)
    }

    func testIncompleteMeasurementsNeverBecomeAZeroOrDefaultScore() {
        let record = entry(owner: owner)
        XCTAssertFalse(record.hasCompleteScoreData)
        XCTAssertNil(record.displayableScore)
    }

    func testDeletedLatestRecordCannotOutliveTheSourceBatch() async {
        let reader = SleepDashboardFixture(owner: owner)
        reader.latest = entry(owner: owner)
        reader.entries = []
        let model = SleepDashboardViewModel()
        await model.loadData(trackingService: reader)
        XCTAssertNil(model.lastSleepEntry)
        XCTAssertTrue(model.weekEntries.isEmpty)
    }

    func testRenderNoData() async throws {
        let reader = SleepDashboardFixture(owner: owner)
        let host = UIHostingController(rootView: SleepDashboardView(trackingReader: reader)
            .environmentObject(DependencyContainer.preview)
            .environmentObject(AppState())
            .preferredColorScheme(.dark))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        // Wait for the real SwiftUI task and layout on the simulator, without network access.
        try await Task.sleep(for: .milliseconds(500))
        host.view.layoutIfNeeded()
        let renderer = UIGraphicsImageRenderer(bounds: host.view.bounds)
        let attachment = XCTAttachment(image: renderer.image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) })
        attachment.name = "Issue19-no-data-dark"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(reader.readCount > 0)
    }

    func testRenderPartialMeasurementsWithLargeText() async throws {
        let reader = SleepDashboardFixture(owner: owner)
        reader.latest = entry(owner: owner)
        reader.entries = [reader.latest!]
        let host = UIHostingController(rootView: SleepDashboardView(trackingReader: reader)
            .environmentObject(DependencyContainer.preview)
            .environmentObject(AppState())
            .environment(\.dynamicTypeSize, .accessibility1)
            .preferredColorScheme(.dark))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(500))
        host.view.layoutIfNeeded()
        let renderer = UIGraphicsImageRenderer(bounds: host.view.bounds)
        let attachment = XCTAttachment(image: renderer.image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) })
        attachment.name = "Issue19-partial-measurements-large-text"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertNil(reader.latest?.displayableScore)
    }

    private func entry(owner: UUID, daysAgo: Int = 0) -> SleepEntry {
        let wake = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return SleepEntry(id: UUID(), userId: owner, date: wake, source: .healthkit,
            bedtime: wake.addingTimeInterval(-8 * 3600), wakeTime: wake,
            timeInBedMinutes: 480, timeAsleepMinutes: 450, deepSleepMinutes: nil,
            remSleepMinutes: nil, lightSleepMinutes: nil, awakeMinutes: nil,
            sleepEfficiency: nil, heartRateAvg: nil, heartRateMin: nil, hrvAvg: nil,
            respiratoryRate: nil, userRating: nil, dreamNotes: nil, notes: nil,
            sleepScore: 55, scoreBreakdown: SleepScoreBreakdown(duration: 20, efficiency: 25, timing: 5, stages: 0, restfulness: 5),
            createdAt: wake, updatedAt: wake)
    }
}

@MainActor
private final class SleepRefreshGate {
    private var started = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var continuation: CheckedContinuation<Void, Never>?
    func signalStart() {
        started = true
        startWaiter?.resume()
        startWaiter = nil
    }
    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            signalStart()
        }
    }
    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }
    func open() { continuation?.resume(); continuation = nil }
}

@MainActor
private final class SleepDashboardFixture: SleepTrackingReading {
    var owner: UUID
    var latest: SleepEntry?
    var entries: [SleepEntry] = []
    var fail = false
    var switchAccountAfterRead = false
    var readCount = 0
    private var ownerReadCount = 0
    var beforeOwnerRead: ((Int) async throws -> Void)?
    var beforeEntriesRead: (() async throws -> Void)?
    init(owner: UUID) { self.owner = owner }
    func currentUserID() async throws -> UUID {
        ownerReadCount += 1
        try await beforeOwnerRead?(ownerReadCount)
        return owner
    }
    func fetchLatestEntry() async throws -> SleepEntry? {
        readCount += 1
        if fail { throw URLError(.notConnectedToInternet) }
        return latest
    }
    func fetchEntries(from: Date, to: Date) async throws -> [SleepEntry] {
        readCount += 1
        try await beforeEntriesRead?()
        if fail { throw URLError(.notConnectedToInternet) }
        return entries
    }
    func fetchInsights() async throws -> [SleepInsight] {
        if switchAccountAfterRead { owner = UUID() }
        return []
    }
}

@MainActor
final class SleepEntryDecodingRegressionTests: XCTestCase {
    private let owner = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private func decode(asleep: Int? = 450, deep: Int = 90, awake: Int = 30) throws -> SleepEntry {
        let wake = Date()
        var record: [String: Any] = ["id": UUID().uuidString, "user_id": owner.uuidString,
            "date": String(wake.ISO8601Format().prefix(10)), "source": "healthkit",
            "bedtime": wake.addingTimeInterval(-8 * 3600).ISO8601Format(), "wake_time": wake.ISO8601Format(),
            "time_in_bed_minutes": 480, "deep_sleep_minutes": deep, "rem_sleep_minutes": 100,
            "light_sleep_minutes": 260, "awake_minutes": awake,
            "created_at": wake.ISO8601Format(), "updated_at": wake.ISO8601Format()]
        record["time_asleep_minutes"] = asleep
        return try PostgrestClient.Configuration.jsonDecoder.decode(SleepEntry.self, from: JSONSerialization.data(withJSONObject: record))
    }
    func testHealthKitNightWithAwakeTimeDecodesAndLoads() async throws {
        let entry = try decode()
        XCTAssertEqual(entry.timeAsleepMinutes, 450)
        XCTAssertEqual(entry.awakeMinutes, 30)
        XCTAssertNil(entry.displayableScore, "Missing stored score must stay unavailable")
        let reader = SleepDashboardFixture(owner: owner)
        reader.entries = [entry]
        let model = SleepDashboardViewModel()
        await model.loadData(trackingService: reader)
        XCTAssertEqual(model.weekEntries.first?.id, entry.id)
        XCTAssertNil(model.errorMessage)
    }
    func testAsleepStagesCannotExceedTimeAsleep() async {
        await XCTAssertThrowsError(try decode(deep: 91))
    }
    func testSleepAndAwakeCannotExceedTimeInBed() async {
        await XCTAssertThrowsError(try decode(awake: 31))
    }
    func testPartialSleepTotalsStillValidateAgainstTimeInBed() async throws {
        let entry = try decode(asleep: nil)
        XCTAssertNil(entry.timeAsleepMinutes)
        XCTAssertNil(entry.displayableScore)
        await XCTAssertThrowsError(try decode(asleep: nil, awake: 31))
    }
}


@MainActor
final class SleepHealthImportRegressionTests: XCTestCase {
    private let owner = UUID(uuidString: "aabbccdd-1140-4111-8111-aabbccddeeff")!
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func sample(_ start: Date, _ minutes: Double, _ value: HKCategoryValueSleepAnalysis = .asleepUnspecified) -> HKCategorySample {
        HKCategorySample(type: HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!, value: value.rawValue,
                         start: start, end: start.addingTimeInterval(minutes * 60))
    }
    private func entry(_ start: Date, _ minutes: Double = 1080) -> SleepEntry {
        SleepHealthKitManager.sleepEntry(from: [sample(start, minutes)], for: start, owner: owner)!
    }
    func testLongCrossMidnightSessionUsesFullIntervalsAndLocalWakeDay() throws {
        let start = date("2026-10-24T10:00:00-04:00")
        // Duplicate unspecified data overlays detailed Health stages.
        let samples = [sample(start, 1080), sample(start, 400, .asleepCore),
            sample(start.addingTimeInterval(400*60), 250, .asleepDeep),
            sample(start.addingTimeInterval(650*60), 430, .asleepREM)]
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let sessions = SleepHealthKitManager.dailySleepSamples(from: samples,
            wakingFrom: date("2026-10-25T00:00:00-04:00"), through: date("2026-10-25T20:00:00-04:00"), calendar: calendar)
        XCTAssertEqual(sessions.count, 1)
        let day = try XCTUnwrap(sessions.keys.first)
        XCTAssertEqual(day, date("2026-10-25T00:00:00-04:00"))
        let imported = try XCTUnwrap(SleepHealthKitManager.sleepEntry(from: sessions[day]!, for: day, owner: owner))
        XCTAssertEqual(imported.timeAsleepMinutes, 1080)
        XCTAssertEqual(imported.durationFormatted, "18h 0m")
        XCTAssertEqual(imported.bedtime, start)
        XCTAssertNil(imported.displayableScore, "No measured awake intervals means no complete MindFriend score")
    }
    func testNestedInBedIntervalKeepsTheWholeConnectedSession() {
        let start = date("2026-10-24T10:00:00-04:00")
        let samples = [sample(start, 1140, .inBed), sample(start, 60), sample(start.addingTimeInterval(120*60), 900)]
        XCTAssertEqual(SleepHealthKitManager.sleepSessions(from: samples).count, 1)
        XCTAssertEqual(SleepHealthKitManager.sleepDurations(samples).asleep, 960*60)
    }
    func testDailyLogRetainsBothPeriodsWithoutCountingTheGap() throws {
        let start = date("2026-10-25T00:00:00-04:00")
        let samples = [sample(start, 360), sample(start.addingTimeInterval(12*3600), 90)]
        XCTAssertEqual(SleepHealthKitManager.sleepSessions(from: samples).count, 2)
        let first = SleepHealthKitManager.dailySleepSamples(from: samples, wakingFrom: start, through: start.addingTimeInterval(24*3600))
        let reversed = SleepHealthKitManager.dailySleepSamples(from: samples.reversed(), wakingFrom: start, through: start.addingTimeInterval(24*3600))
        XCTAssertEqual(first.values.first?.first?.startDate, start)
        XCTAssertEqual(first.values.first?.first?.startDate, reversed.values.first?.first?.startDate)
        let day = try XCTUnwrap(first.keys.first)
        let daily = try XCTUnwrap(SleepHealthKitManager.sleepEntry(from: first[day]!, for: day, owner: owner))
        XCTAssertEqual(daily.timeAsleepMinutes, 450, "Retain the 90-minute second period")
        XCTAssertEqual(daily.timeInBedMinutes, 450, "The six-hour gap is not time in bed")
        XCTAssertEqual(daily.sleepEfficiency, 100)
        let reversedDaily = try XCTUnwrap(SleepHealthKitManager.sleepEntry(from: reversed[day]!, for: day, owner: owner))
        XCTAssertEqual(reversedDaily.timeAsleepMinutes, daily.timeAsleepMinutes)
        XCTAssertEqual(reversedDaily.timeInBedMinutes, daily.timeInBedMinutes)
    }
    func testOverlappingStagesAndAwakeDoNotManufactureMeasuredComponents() {
        let start = Date()
        let data = SleepHealthKitManager.sleepDurations([sample(start, 120), sample(start, 90, .asleepCore),
            sample(start.addingTimeInterval(60*60), 60, .asleepDeep), sample(start, 10, .awake)])
        XCTAssertEqual(data.asleep, 7200)
        XCTAssertFalse(data.hasCompleteStages)
        XCTAssertFalse(data.hasAwakeData)
    }
    func testLaterSleepRetainsTheEarlierNapAndItsSavedIdentity() throws {
        let start = date("2026-10-25T22:00:00-04:00")
        let nap = sample(start, 120)
        let night = sample(date("2026-10-26T04:00:00-04:00"), 420)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let day = calendar.startOfDay(for: night.endDate)
        let samples = SleepHealthKitManager.dailySleepSamples(from: [night, nap], wakingFrom: day,
            through: day.addingTimeInterval(86400), calendar: calendar)
        let combined = try XCTUnwrap(SleepHealthKitManager.sleepEntry(from: samples[day]!, for: day, owner: owner))
        var savedNap = try XCTUnwrap(SleepHealthKitManager.sleepEntry(from: [nap], for: day, owner: owner))
        savedNap.notes = "Synthetic nap feedback"
        XCTAssertEqual(combined.timeAsleepMinutes, 540)
        XCTAssertEqual(combined.timeInBedMinutes, 540)
        XCTAssertEqual(try SleepHealthKitManager.matchingImport(for: combined, occupying: [savedNap])?.id, savedNap.id)
        XCTAssertEqual(savedNap.notes, "Synthetic nap feedback")
        let decoded = try JSONDecoder().decode(SleepEntry.self, from: JSONEncoder().encode(combined))
        XCTAssertEqual(decoded.timeAsleepMinutes, 540)
        XCTAssertEqual(decoded.timeInBedMinutes, 540)
    }
    func testMeasuredInBedStillCoversAnAwakeGap() throws {
        let start = date("2026-10-25T00:00:00-04:00")
        let samples = [sample(start, 300, .inBed), sample(start, 120),
            sample(start.addingTimeInterval(180 * 60), 120)]
        let entry = try XCTUnwrap(SleepHealthKitManager.sleepEntry(from: samples, for: start, owner: owner))
        XCTAssertEqual(entry.timeAsleepMinutes, 240)
        XCTAssertEqual(entry.timeInBedMinutes, 300)
        XCTAssertEqual(entry.sleepEfficiency, 80)
    }
    func testOvernightSleepAndLateNapCanHaveAnEnvelopeOver24Hours() throws {
        let first = sample(date("2026-10-25T22:00:00-04:00"), 540)
        let second = sample(date("2026-10-26T23:00:00-04:00"), 30)
        let day = date("2026-10-26T00:00:00-04:00")
        let daily = try XCTUnwrap(SleepHealthKitManager.sleepEntry(from: [first, second], for: day, owner: owner))
        XCTAssertEqual(daily.timeAsleepMinutes, 570)
        XCTAssertEqual(daily.timeInBedMinutes, 570)
        XCTAssertEqual(daily.validatedRecordedPeriods?.count, 2)
        XCTAssertTrue(SleepScoreCalculator().isValidForScoring(entry: daily))
        var fragment = try XCTUnwrap(SleepHealthKitManager.sleepEntry(from: [first], for: day, owner: owner))
        fragment.notes = "Synthetic saved night feedback"
        let rows = SleepEntry.withoutContainedHealthImports([fragment, daily])
        XCTAssertEqual(rows.map(\.id), [daily.id])
        XCTAssertEqual(rows.first?.previousImportFeedback.first?.notes, fragment.notes)
        let gap = entry(date("2026-10-26T12:00:00-04:00"), 90)
        XCTAssertEqual(SleepEntry.withoutContainedHealthImports([gap, daily]).count, 2,
            "An unmeasured gap cannot establish that another record was superseded")
        do {
            _ = try SleepHealthKitManager.matchingImport(for: daily, occupying: [gap])
            XCTFail("An unmeasured gap cannot repurpose another record's ID or feedback")
        } catch SleepTrackingError.importDateConflict { }
    }
    func testShortNapImportsAndInBedOnlyDaysDoNotEnterTheDailyBatch() throws {
        let start = date("2026-10-25T01:00:00-04:00")
        let nap = sample(start, 30)
        let imported = try XCTUnwrap(SleepHealthKitManager.sleepEntry(from: [nap], for: start, owner: owner))
        XCTAssertEqual(imported.timeAsleepMinutes, 30)
        XCTAssertTrue(SleepScoreCalculator().isValidForScoring(entry: imported))
        let groups = SleepHealthKitManager.dailySleepSamples(from: [sample(start, 60, .inBed),
            sample(start.addingTimeInterval(-86400), 480)], wakingFrom: start.addingTimeInterval(-86400),
            through: start.addingTimeInterval(86400))
        XCTAssertEqual(groups.count, 1, "A newer day without measured sleep must not block the older night")
    }
    func testLegacyWholeSecondFragmentMatchesFractionalMeasuredCoverage() throws {
        let start = date("2026-10-25T22:00:00-04:00").addingTimeInterval(0.123)
        let first = sample(start, 540)
        let last = sample(date("2026-10-26T23:00:00-04:00").addingTimeInterval(0.123), 30)
        let day = date("2026-10-26T00:00:00-04:00")
        let aggregate = try XCTUnwrap(SleepHealthKitManager.sleepEntry(from: [first, last], for: day, owner: owner))
        let original = try XCTUnwrap(SleepHealthKitManager.sleepEntry(from: [first], for: day, owner: owner))
        var json = try JSONSerialization.jsonObject(with: PostgrestClient.Configuration.jsonEncoder.encode(original)) as! [String: Any]
        json["bedtime"] = original.bedtime.ISO8601Format()
        json["wake_time"] = original.wakeTime.ISO8601Format()
        json["recorded_periods"] = NSNull()
        json["notes"] = "Synthetic legacy feedback"
        let legacy = try PostgrestClient.Configuration.jsonDecoder.decode(SleepEntry.self, from: JSONSerialization.data(withJSONObject: json))
        let rows = SleepEntry.withoutContainedHealthImports([legacy, aggregate])
        XCTAssertEqual(rows.map(\.id), [aggregate.id])
        XCTAssertEqual(rows.first?.previousImportFeedback.first?.notes, "Synthetic legacy feedback")
        let gap = entry(date("2026-10-26T12:00:00-04:00"), 60)
        XCTAssertEqual(SleepEntry.withoutContainedHealthImports([gap, aggregate]).count, 2)
    }
    func testNearbyLegacyRowsNeverRemoveEachOtherAndMeasuredCoverageWinsMutualContainment() throws {
        let start = date("2026-10-25T22:00:00-04:00")
        var a = entry(start, 480); a.recordedPeriods = nil
        var b = entry(start.addingTimeInterval(1), 480); b.recordedPeriods = nil
        XCTAssertEqual(SleepEntry.withoutContainedHealthImports([a, b]).count, 2)
        XCTAssertEqual(SleepEntry.withoutContainedHealthImports([b, a]).count, 2)
        let measured = entry(start.addingTimeInterval(0.123), 480)
        var json = try JSONSerialization.jsonObject(with: PostgrestClient.Configuration.jsonEncoder.encode(a)) as! [String: Any]
        json["wake_time"] = a.wakeTime.ISO8601Format()
        json["updated_at"] = a.updatedAt.addingTimeInterval(3600).ISO8601Format()
        json["notes"] = "Synthetic precision feedback"
        let legacy = try PostgrestClient.Configuration.jsonDecoder.decode(SleepEntry.self, from: JSONSerialization.data(withJSONObject: json))
        for rows in [[legacy, measured], [measured, legacy]] {
            let result = SleepEntry.withoutContainedHealthImports(rows)
            XCTAssertEqual(result.map(\.id), [measured.id])
            XCTAssertEqual(result.first?.previousImportFeedback.first?.notes, "Synthetic precision feedback")
        }
    }
    func testMixedFourRowCoverageCannotFormADominanceCycle() throws {
        let start = date("2026-10-26T01:00:00-04:00")
        func row(_ offset: Double, _ seconds: Double, legacy: Bool) throws -> SleepEntry {
            var result = try XCTUnwrap(SleepHealthKitManager.sleepEntry(from:
                [sample(start.addingTimeInterval(offset), seconds / 60)], for: start, owner: owner))
            if legacy { result.recordedPeriods = nil }
            return result
        }
        let a = try row(0, 100, legacy: false), b = try row(-1, 102, legacy: true)
        let c = try row(-1, 100, legacy: false), d = try row(-2, 102, legacy: true)
        for input in [[a,b,c,d], [d,c,b,a], [b,d,a,c], [c,a,d,b]] {
            let result = SleepEntry.withoutContainedHealthImports(input)
            XCTAssertEqual(Set(result.map(\.id)), Set([b.id, d.id]))
        }
    }
    func testOldClientMeasurementUpdatesInvalidateStalePeriodMetadata() throws {
        var imported = try XCTUnwrap(SleepHealthKitManager.sleepEntry(from:
            [sample(date("2026-10-26T01:00:00-04:00"), 90)], for: date("2026-10-26T00:00:00-04:00"), owner: owner))
        let period = try XCTUnwrap(imported.recordedPeriods?.first)
        imported.recordedPeriods = [SleepRecordedPeriod(start: period.start, end: period.end,
            inBedSeconds: period.inBedSeconds, asleepSeconds: 1)]
        XCTAssertNil(imported.validatedRecordedPeriods)
        let decoded = try JSONDecoder().decode(SleepEntry.self, from: JSONEncoder().encode(imported))
        XCTAssertNil(decoded.recordedPeriods)
        XCTAssertEqual(decoded.timeAsleepMinutes, 90)
        let fragment = entry(period.start.addingTimeInterval(60), 60)
        XCTAssertEqual(SleepEntry.withoutContainedHealthImports([fragment, imported]).count, 2,
            "Stale metadata must not be treated as a legacy continuous coverage range")
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(imported)) as! [String: Any]
        json["recorded_periods"] = [NSNull()]
        let malformed = try JSONDecoder().decode(SleepEntry.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(malformed.validatedRecordedPeriods)
        XCTAssertEqual(SleepEntry.withoutContainedHealthImports([fragment, malformed]).count, 2)
    }
    func testMetricQueryExcludesTheGapAndSamplesOutsideMeasuredPeriods() throws {
        let start = date("2026-10-25T00:00:00-04:00")
        let periods = [DateInterval(start: start, duration: 120 * 60),
            DateInterval(start: start.addingTimeInterval(6 * 3600), duration: 120 * 60)]
        let predicate = SleepHealthKitManager.metricsPredicate(during: periods)
        let type = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        func metric(at minutes: Double, duration: Double = 1) -> HKQuantitySample {
            let date = start.addingTimeInterval(minutes * 60)
            return HKQuantitySample(type: type, quantity: HKQuantity(unit: .count().unitDivided(by: .minute()), doubleValue: 60),
                start: date, end: date.addingTimeInterval(duration * 60))
        }
        XCTAssertTrue(predicate.evaluate(with: metric(at: 30)))
        XCTAssertTrue(predicate.evaluate(with: metric(at: 390)))
        XCTAssertFalse(predicate.evaluate(with: metric(at: 240)))
        XCTAssertFalse(predicate.evaluate(with: metric(at: -1)))
        XCTAssertFalse(predicate.evaluate(with: metric(at: 119, duration: 2)))
    }
    func testMeasuredZeroStagesRemainDistinctFromMissingStages() throws {
        let start = Date()
        let imported = try XCTUnwrap(SleepHealthKitManager.sleepEntry(from:
            [sample(start, 120, .asleepCore), sample(start.addingTimeInterval(120*60), 10, .awake)], for: start, owner: owner))
        XCTAssertEqual(imported.deepSleepMinutes, 0)
        XCTAssertEqual(imported.remSleepMinutes, 0)
        XCTAssertEqual(imported.awakeMinutes, 10)
        XCTAssertTrue(imported.hasCompleteScoreData)
    }
    func testSubmillisecondStageHandoffsKeepOneSessionWithoutAddingSleepTime() throws {
        let start = date("2026-01-04T20:00:00Z")
        let first = sample(start, 90, .asleepCore)
        for gap in [0.00000025, 0.0005] {
            let second = sample(first.endDate.addingTimeInterval(gap), 180, .asleepREM)
            let samples = [first, second]
            XCTAssertEqual(SleepHealthKitManager.sleepSessions(from: samples).count, 1)
            XCTAssertEqual(SleepHealthKitManager.sleepDurations(samples).asleep, 270 * 60)
            XCTAssertEqual(try XCTUnwrap(SleepHealthKitManager.sleepEntry(from: samples, for: start, owner: owner)).timeAsleepMinutes, 270)
        }
    }
    func testActualRecordingGapsRemainSeparate() {
        let start = date("2026-01-04T20:00:00Z")
        let first = sample(start, 90)
        for gap in [0.002, 1.0] {
            let second = sample(first.endDate.addingTimeInterval(gap), 180)
            XCTAssertEqual(SleepHealthKitManager.sleepSessions(from: [first, second]).count, 2)
            XCTAssertEqual(SleepHealthKitManager.sleepDurations([first, second]).asleep, 270 * 60)
        }
    }
    func testSubminuteIntervalsAreUnionedBeforeRounding() {
        let start = Date()
        let samples = (0..<200).map { sample(start.addingTimeInterval(Double($0)*30), 0.5) }
        XCTAssertEqual(SleepHealthKitManager.sleepDurations(samples + samples).asleep, 6000)
        XCTAssertEqual(SleepHealthKitManager.sleepEntry(from: samples, for: start, owner: owner)?.timeAsleepMinutes, 100)
    }
    func testDaylightSavingUsesActualElapsedTime() {
        let start = date("2026-11-01T00:00:00-04:00")
        let end = date("2026-11-01T08:00:00-05:00")
        XCTAssertEqual(entry(start, end.timeIntervalSince(start)/60).timeAsleepMinutes, 540)
    }
    func testUnsupportedOversizeAndEmptySessionsDoNotConstructAnEntry() {
        let start = Date()
        XCTAssertNil(SleepHealthKitManager.sleepEntry(from: [sample(start, 1441)], for: start, owner: owner))
        XCTAssertNil(SleepHealthKitManager.sleepEntry(from: [], for: start, owner: owner))
        XCTAssertEqual(SleepHealthKitManager.sleepEntry(from: [sample(start, 30)], for: start, owner: owner)?.timeAsleepMinutes, 30)
        XCTAssertTrue(SleepHealthKitManager.dailySleepSamples(from: [sample(start, 1441)], wakingFrom: start,
            through: start.addingTimeInterval(2*86400)).isEmpty)
    }
    func testContainedImportsAreExcludedWhileFeedbackIsStillVisible() {
        let start = Date().addingTimeInterval(-20*3600)
        let full = entry(start)
        var fragment = entry(start.addingTimeInterval(14*3600), 180)
        fragment.notes = "Synthetic saved note"; fragment.userRating = 4
        let result = SleepEntry.withoutContainedHealthImports([fragment, full])
        XCTAssertEqual(result.map(\.id), [full.id])
        XCTAssertEqual(result[0].previousImportFeedback.first?.notes, "Synthetic saved note")
        XCTAssertEqual(result[0].previousImportFeedback.first?.userRating, 4)
    }
    func testSameBoundsChooseOneStableImportWithoutDroppingManualOrOtherOwner() throws {
        let original = entry(Date())
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        json["id"] = UUID().uuidString
        let duplicate = try JSONDecoder().decode(SleepEntry.self, from: JSONSerialization.data(withJSONObject: json))
        json["id"] = UUID().uuidString; json["source"] = "manual"
        let manual = try JSONDecoder().decode(SleepEntry.self, from: JSONSerialization.data(withJSONObject: json))
        json["id"] = UUID().uuidString; json["source"] = "healthkit"; json["user_id"] = UUID().uuidString
        let other = try JSONDecoder().decode(SleepEntry.self, from: JSONSerialization.data(withJSONObject: json))
        let result = SleepEntry.withoutContainedHealthImports([original, duplicate, manual, other])
        XCTAssertEqual(result.count, 3); XCTAssertTrue(result.contains { $0.id == manual.id }); XCTAssertTrue(result.contains { $0.id == other.id })
    }
    func testLegacyStartDateFragmentCannotTransferFeedbackToThePrecedingNight() throws {
        let prior = entry(date("2026-10-23T23:00:00-04:00"), 480)
        var fragment = entry(date("2026-10-24T22:00:00-04:00"), 120)
        fragment.notes = "Feedback for the following night"
        do {
            _ = try SleepHealthKitManager.matchingImport(for: prior, occupying: [fragment])
            XCTFail("An unrelated legacy fragment must not be replaced")
        } catch SleepTrackingError.importDateConflict { }
        let following = entry(date("2026-10-24T10:00:00-04:00"))
        XCTAssertEqual(try SleepHealthKitManager.matchingImport(for: following, occupying: [fragment])?.id, fragment.id)
        XCTAssertEqual(fragment.notes, "Feedback for the following night")
    }
    func testResyncPatchExplicitlyClearsMissingMeasurementsWithoutWritingFeedbackOrOwnership() throws {
        let dto = CreateSleepEntryDTO(userId: owner, date: "2026-10-25", source: "healthkit", bedtime: "bed", wakeTime: "wake",
            timeInBedMinutes: 1140, timeAsleepMinutes: 1080, deepSleepMinutes: nil, remSleepMinutes: nil,
            lightSleepMinutes: nil, awakeMinutes: nil, sleepEfficiency: nil, heartRateAvg: nil, heartRateMin: nil,
            hrvAvg: nil, respiratoryRate: nil, userRating: nil, dreamNotes: nil, notes: nil, sleepScore: nil, scoreBreakdown: nil)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ImportedSleepUpdateDTO(measurements: dto))) as! [String: Any]
        for key in ["deep_sleep_minutes", "rem_sleep_minutes", "awake_minutes", "sleep_score", "score_breakdown"] {
            XCTAssertTrue(json[key] is NSNull, key)
        }
        for key in ["id", "user_id", "created_at", "user_rating", "dream_notes", "notes"] { XCTAssertNil(json[key], key) }
    }
    func testFailedSyncShowsRecoveryWhilePreservingSavedRecordAndRetryClearsFailure() async {
        let reader = SleepDashboardFixture(owner: owner)
        reader.entries = [entry(Date().addingTimeInterval(-18*3600))]
        let model = SleepDashboardViewModel()
        await model.refresh(trackingService: reader) { throw URLError(.notConnectedToInternet) }
        XCTAssertNotNil(model.syncErrorMessage); XCTAssertEqual(model.weekEntries.count, 1)
        await model.refresh(trackingService: reader) { }
        XCTAssertNil(model.syncErrorMessage); XCTAssertEqual(model.weekEntries.count, 1)
    }
}

@MainActor
final class SleepImportPersistenceRegressionTests: XCTestCase {
    private var client: SupabaseClient!
    private var service: SleepTrackingService!
    private var record: SleepEntry!
    override func setUp() async throws {
        try await super.setUp()
        let owner = UUID(uuidString: SleepImportHTTP.owner)!
        let now = Date()
        let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        record = SleepHealthKitManager.sleepEntry(from: [HKCategorySample(type: type,
            value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            start: now.addingTimeInterval(-1080*60), end: now)], for: now, owner: owner)!
        record.notes = "Synthetic retained note"; record.userRating = 4
        SleepImportURLProtocol.fixture.reset(record: record)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SleepImportURLProtocol.self]
        client = SupabaseClient(supabaseURL: URL(string: "https://sleep-import-fixture.invalid")!, supabaseKey: "synthetic-anon",
            options: .init(auth: .init(storage: SleepImportAuthStorage(), autoRefreshToken: false),
                           global: .init(session: URLSession(configuration: configuration))))
        _ = try await client.auth.signIn(email: "qa@example.invalid", password: "offline-synthetic")
        service = SleepTrackingService(supabase: client)
    }
    private var goals: SleepGoals { SleepGoals(id: UUID(), userId: record.userId, targetBedtime: nil, targetWakeTime: nil,
        targetDurationMinutes: 480, windDownDurationMinutes: 30, bedtimeReminderEnabled: false,
        bedtimeReminderOffsetMinutes: 60, preferredWindDownTypes: [], sleepEnvironmentPrefs: SleepEnvironmentPrefs(),
        createdAt: Date(), updatedAt: Date()) }
    func testRepeatedHealthResyncPreservesIDAndFeedbackAndClearsStaleScoreOnRealSDKWire() async throws {
        let first = try await service.createEntry(record, goals: goals, replacing: record)
        let second = try await service.createEntry(record, goals: goals, replacing: first)
        XCTAssertEqual(first.id, second.id); XCTAssertEqual(second.notes, "Synthetic retained note"); XCTAssertEqual(second.userRating, 4)
        let writes = SleepImportURLProtocol.fixture.requests.filter { $0.httpMethod == "PATCH" }
        XCTAssertEqual(writes.count, 2)
        for request in writes {
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertTrue(query.contains { $0.name == "id" && $0.value?.lowercased() == "eq.\(record.id.uuidString.lowercased())" })
            XCTAssertTrue(query.contains { $0.name == "user_id" && $0.value?.lowercased() == "eq.\(SleepImportHTTP.owner)" })
            XCTAssertTrue(query.contains { $0.name == "source" && $0.value == "neq.manual" })
            let body = try JSONSerialization.jsonObject(with: SleepImportHTTP.body(request)) as! [String: Any]
            XCTAssertTrue(body["sleep_score"] is NSNull); XCTAssertTrue(body["deep_sleep_minutes"] is NSNull)
            for key in ["user_id", "id", "notes", "dream_notes", "user_rating", "created_at"] { XCTAssertNil(body[key], key) }
        }
    }
    func testConcurrentInsertCollisionRefetchesOwnedDateAndRetriesOnlyOnePatch() async throws {
        SleepImportURLProtocol.fixture.failInsertOnce = true
        let saved = try await service.createEntry(record, goals: goals)
        XCTAssertEqual(saved.id, record.id)
        XCTAssertEqual(SleepImportURLProtocol.fixture.requests.map(\.httpMethod), ["POST", "GET", "PATCH"])
    }
    func testImportedPeriodsPersistAndReloadThroughRealSDK() async throws {
        let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let wake = Date()
        let samples = [HKCategorySample(type: type, value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            start: wake.addingTimeInterval(-25.5 * 3600), end: wake.addingTimeInterval(-16.5 * 3600)),
            HKCategorySample(type: type, value: HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            start: wake.addingTimeInterval(-1800), end: wake)]
        record = try XCTUnwrap(SleepHealthKitManager.sleepEntry(from: samples, for: wake, owner: record.userId))
        SleepImportURLProtocol.fixture.reset(record: record)
        let saved = try await service.createEntry(record, goals: goals, replacing: record)
        let reloaded = try await service.fetchEntries(from: record.date, to: record.date)
        XCTAssertEqual(saved.validatedRecordedPeriods?.count, 2)
        XCTAssertEqual(reloaded.first?.validatedRecordedPeriods, saved.validatedRecordedPeriods)
        let patch = try XCTUnwrap(SleepImportURLProtocol.fixture.requests.first { $0.httpMethod == "PATCH" })
        let body = try JSONSerialization.jsonObject(with: SleepImportHTTP.body(patch)) as! [String: Any]
        let periods = try XCTUnwrap(body["recorded_periods"] as? [[String: Any]])
        XCTAssertEqual(periods.count, 2)
        XCTAssertTrue(periods.allSatisfy { $0["start"] is String && $0["end"] is String })
        XCTAssertEqual(periods.reduce(0) { $0 + ($1["asleep_seconds"] as! Double) }, 570 * 60)
    }
    func testManualAndCrossOwnerReplacementAreRejectedBeforeAnyWrite() async throws {
        var json = try JSONSerialization.jsonObject(with: PostgrestClient.Configuration.jsonEncoder.encode(record)) as! [String: Any]
        json["source"] = "manual"
        let manual = try PostgrestClient.Configuration.jsonDecoder.decode(SleepEntry.self, from: JSONSerialization.data(withJSONObject: json))
        do { _ = try await service.createEntry(record, goals: goals, replacing: manual); XCTFail("Manual replacement must fail") } catch { }
        json["source"] = "healthkit"; json["user_id"] = UUID().uuidString
        let other = try PostgrestClient.Configuration.jsonDecoder.decode(SleepEntry.self, from: JSONSerialization.data(withJSONObject: json))
        do { _ = try await service.createEntry(other, goals: goals); XCTFail("Cross-owner import must fail") } catch { }
        XCTAssertTrue(SleepImportURLProtocol.fixture.requests.isEmpty)
    }
}
private final class SleepImportAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock(); private var values: [String: Data] = [:]
    func store(key: String, value: Data) throws { lock.lock(); defer { lock.unlock() }; values[key] = value }
    func retrieve(key: String) throws -> Data? { lock.lock(); defer { lock.unlock() }; return values[key] }
    func remove(key: String) throws { lock.lock(); defer { lock.unlock() }; values[key] = nil }
}
private final class SleepImportURLProtocol: URLProtocol {
    static let fixture = SleepImportHTTP()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "sleep-import-fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, body) = Self.fixture.respond(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
private final class SleepImportHTTP: @unchecked Sendable {
    static let owner = "aabbccdd-1140-4111-8111-aabbccddeeff"
    private let lock = NSLock(); private var recorded: [URLRequest] = []; private var row = Data()
    var failInsertOnce = false
    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return recorded }
    func reset(record: SleepEntry) { lock.lock(); defer { lock.unlock() }; recorded = []; failInsertOnce = false
        row = try! PostgrestClient.Configuration.jsonEncoder.encode(record) }
    static func body(_ request: URLRequest) -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }; var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable && data.count < 65536 {
            let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
    func respond(_ request: URLRequest) -> (Int, Data) {
        lock.lock(); defer { lock.unlock() }
        if request.url?.path == "/auth/v1/token" {
            let body: [String: Any] = ["access_token": "synthetic-access", "refresh_token": "synthetic-refresh", "token_type": "bearer",
                "expires_in": 3600, "expires_at": Int(Date().timeIntervalSince1970)+3600,
                "user": ["id": Self.owner, "aud": "authenticated", "role": "authenticated", "app_metadata": [:], "user_metadata": [:],
                         "created_at": "2026-10-25T00:00:00Z", "updated_at": "2026-10-25T00:00:00Z"]]
            return (200, try! JSONSerialization.data(withJSONObject: body))
        }
        guard request.url?.path == "/rest/v1/sleep_entries" else { return (404, Data("{}".utf8)) }
        var copy = request; copy.httpBody = Self.body(request); recorded.append(copy)
        if request.httpMethod == "POST" && failInsertOnce {
            failInsertOnce = false; return (409, Data(#"{"code":"23505","message":"synthetic unique date collision"}"#.utf8))
        }
        if request.httpMethod == "GET" { return (200, Data("[".utf8) + row + Data("]".utf8)) }
        if request.httpMethod == "PATCH" || request.httpMethod == "POST",
           var stored = try? JSONSerialization.jsonObject(with: row) as? [String: Any],
           let fields = try? JSONSerialization.jsonObject(with: copy.httpBody ?? Data()) as? [String: Any] {
            for (key, value) in fields { stored[key] = value }
            row = try! JSONSerialization.data(withJSONObject: stored)
        }
        return (200, row)
    }
}

@MainActor
final class SleepHistoryImportRegressionTests: XCTestCase {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: "America/New_York")!
        return result
    }
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
    func testAllAvailableHistoryUsesContiguousBoundedCalendarBatchesAcrossDST() async throws {
        let earliest = date(2020, 1, 1), recent = date(2026, 11, 5)
        var batches: [(Date, Date)] = []
        var checkpoints: [Date] = []
        try await SleepHealthKitManager.importHistory(from: earliest, before: recent, checkpoint: nil,
            calendar: calendar, importBatch: { batches.append(($0, $1)) }, saveCheckpoint: { checkpoints.append($0) })
        XCTAssertGreaterThan(batches.count, 80)
        XCTAssertEqual(batches.first?.1.timeIntervalSinceReferenceDate.nextUp, recent.timeIntervalSinceReferenceDate)
        XCTAssertEqual(batches.last?.0, earliest)
        XCTAssertEqual(checkpoints, batches.map(\.0))
        for (index, batch) in batches.enumerated() {
            let end = Date(timeIntervalSinceReferenceDate: batch.1.timeIntervalSinceReferenceDate.nextUp)
            XCTAssertGreaterThan(end, batch.0)
            XCTAssertLessThanOrEqual(calendar.dateComponents([.day], from: batch.0, to: end).day!, 30)
            XCTAssertEqual(calendar.startOfDay(for: batch.0), batch.0)
            if index > 0 { XCTAssertEqual(end, batches[index - 1].0) }
        }
    }
    func testFailedBatchDoesNotAdvanceCheckpointAndRetryResumesThere() async throws {
        let earliest = date(2026, 1, 1), recent = date(2026, 10, 1)
        var checkpoint: Date?
        var calls = 0
        do {
            try await SleepHealthKitManager.importHistory(from: earliest, before: recent, checkpoint: nil,
                calendar: calendar, importBatch: { _, _ in
                    calls += 1
                    if calls == 3 { throw URLError(.notConnectedToInternet) }
                }, saveCheckpoint: { checkpoint = $0 })
            XCTFail("Expected batch failure")
        } catch { XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet) }
        XCTAssertEqual(calls, 3)
        let saved = try XCTUnwrap(checkpoint)
        XCTAssertEqual(saved, calendar.date(byAdding: .day, value: -60, to: recent))
        var firstRetryEnd: Date?
        try await SleepHealthKitManager.importHistory(from: earliest, before: recent, checkpoint: checkpoint,
            calendar: calendar, importBatch: { _, end in if firstRetryEnd == nil { firstRetryEnd = end } },
            saveCheckpoint: { checkpoint = $0 })
        XCTAssertEqual(firstRetryEnd?.timeIntervalSinceReferenceDate.nextUp, saved.timeIntervalSinceReferenceDate)
        XCTAssertEqual(checkpoint, earliest)
    }
    func testCancellationDoesNotCheckpointTheIncompleteBatch() async {
        let gate = SleepRefreshGate()
        var checkpoint: Date?
        let task = Task {
            try await SleepHealthKitManager.importHistory(from: date(2025, 1, 1), before: date(2026, 1, 1),
                checkpoint: nil, calendar: calendar, importBatch: { _, _ in await gate.wait() },
                saveCheckpoint: { checkpoint = $0 })
        }
        await gate.waitUntilStarted()
        task.cancel()
        gate.open()
        do { try await task.value; XCTFail("Expected cancellation") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(checkpoint)
    }
    func testConflictingBatchIsRecordedBeforeCheckpointAndDoesNotBlockOlderHistory() async throws {
        let earliest = date(2026, 1, 1), recent = date(2026, 4, 1)
        var events: [String] = []
        var batches = 0
        var checkpoint: Date?
        var failed: [(Date, Date)] = []
        do {
            try await SleepHealthKitManager.importHistory(from: earliest, before: recent, checkpoint: nil,
                calendar: calendar, importBatch: { _, _ in
                    batches += 1
                    if batches == 1 { throw SleepTrackingError.importDateConflict }
                }, saveCheckpoint: { checkpoint = $0; events.append("checkpoint") }, saveConflict: {
                    failed.append(($0, $1)); events.append("conflict")
                })
            XCTFail("The incomplete range must still be reported")
        } catch { XCTAssertTrue(error is SleepTrackingError) }
        XCTAssertEqual(batches, 3, "A conflicting night cannot strand older batches")
        XCTAssertEqual(failed.count, 1)
        XCTAssertEqual(events.first, "conflict", "Persist the retry range before advancing")
        XCTAssertEqual(checkpoint, earliest)
        XCTAssertEqual(failed.first?.1.timeIntervalSinceReferenceDate.nextUp, recent.timeIntervalSinceReferenceDate)
    }
    func testConflictCannotAdvanceWithoutADurableRetryRecorder() async {
        var checkpoint: Date?
        do {
            try await SleepHealthKitManager.importHistory(from: date(2026, 1, 1), before: date(2026, 4, 1),
                checkpoint: nil, calendar: calendar, importBatch: { _, _ in throw SleepTrackingError.importDateConflict },
                saveCheckpoint: { checkpoint = $0 })
            XCTFail("Expected conflict")
        } catch { XCTAssertTrue(error is SleepTrackingError) }
        XCTAssertNil(checkpoint)
    }
    func testReturningAfterSeveralWeeksImportsTheGapWithoutReplayingOlderHistory() async throws {
        let earliest = date(2020, 1, 1), previousRecent = date(2026, 8, 1), recent = date(2026, 10, 1)
        var batches: [(Date, Date)] = []
        var covered = previousRecent
        try await SleepHealthKitManager.importHistory(from: earliest, before: recent, checkpoint: earliest,
            coveredUntil: covered, calendar: calendar, importBatch: { batches.append(($0, $1)) },
            saveCheckpoint: { _ in XCTFail("Older history was already complete") }, saveCoveredUntil: { covered = $0 })
        XCTAssertEqual(batches.count, 3)
        XCTAssertEqual(batches.last?.0, previousRecent)
        XCTAssertEqual(batches.first?.1.timeIntervalSinceReferenceDate.nextUp, recent.timeIntervalSinceReferenceDate)
        XCTAssertEqual(covered, recent)
    }
    func testFailedCatchUpKeepsBothCoverageAndOlderCheckpointForRetry() async throws {
        let earliest = date(2020, 1, 1), previousRecent = date(2026, 8, 1), recent = date(2026, 10, 1)
        var covered = previousRecent
        var checkpoint = date(2025, 1, 1)
        do {
            try await SleepHealthKitManager.importHistory(from: earliest, before: recent, checkpoint: checkpoint,
                coveredUntil: covered, calendar: calendar, importBatch: { _, _ in throw URLError(.notConnectedToInternet) },
                saveCheckpoint: { checkpoint = $0 }, saveCoveredUntil: { covered = $0 })
            XCTFail("Expected catch-up failure")
        } catch { XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet) }
        XCTAssertEqual(covered, previousRecent)
        XCTAssertEqual(checkpoint, date(2025, 1, 1))
    }
    func testBatchBoundaryReadsTheCompleteSessionBeforeSelectingItsWakeDay() throws {
        let midnight = date(2026, 10, 1)
        let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let samples = [(-2.0, -1.0), (-1.0, -0.00000005), (0.00000005, 4.0), (4.0, 7.0)].map { start, end in
            HKCategorySample(type: type, value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                start: midnight.addingTimeInterval(start * 3600), end: midnight.addingTimeInterval(end * 3600))
        }
        let end = Date(timeIntervalSinceReferenceDate: midnight.timeIntervalSinceReferenceDate.nextDown)
        let window = SleepHealthKitManager.sampleQueryWindow(wakingFrom: date(2026, 9, 1), through: end,
            now: date(2026, 10, 3))
        let queried = samples.filter { $0.startDate < window.end && $0.endDate > window.start }
        XCTAssertEqual(queried.count, samples.count)
        XCTAssertTrue(SleepHealthKitManager.dailySleepSamples(from: queried, wakingFrom: date(2026, 9, 1),
            through: end, calendar: calendar).isEmpty, "A batch must not save a clipped start-date fragment")
        let following = SleepHealthKitManager.dailySleepSamples(from: queried, wakingFrom: midnight,
            through: date(2026, 10, 2), calendar: calendar)
        XCTAssertEqual(following.count, 1)
        XCTAssertEqual(SleepHealthKitManager.sleepDurations(try XCTUnwrap(following.values.first)).asleep, 9 * 3600 - 0.00036, accuracy: 0.00001)
    }
    func testCompletedHistoryDoesNotReprocessAndNewlyAvailableOlderHistoryCanImport() async throws {
        let earliest = date(2025, 1, 1), recent = date(2026, 1, 1)
        var calls = 0
        try await SleepHealthKitManager.importHistory(from: earliest, before: recent, checkpoint: earliest,
            calendar: calendar, importBatch: { _, _ in calls += 1 }, saveCheckpoint: { _ in XCTFail("Already complete") })
        XCTAssertEqual(calls, 0)
        var finalCheckpoint: Date?
        let older = date(2024, 12, 1)
        try await SleepHealthKitManager.importHistory(from: older, before: recent, checkpoint: earliest,
            calendar: calendar, importBatch: { _, _ in calls += 1 }, saveCheckpoint: { finalCheckpoint = $0 })
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(finalCheckpoint, older)
    }
}
