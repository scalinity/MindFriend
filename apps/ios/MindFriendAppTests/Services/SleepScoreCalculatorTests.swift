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
        let wake = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date().addingTimeInterval(-60))!
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
private final class SleepDashboardFixture: SleepTrackingReading {
    var owner: UUID
    var latest: SleepEntry?
    var entries: [SleepEntry] = []
    var fail = false
    var switchAccountAfterRead = false
    var readCount = 0
    init(owner: UUID) { self.owner = owner }
    func currentUserID() async throws -> UUID { owner }
    func fetchLatestEntry() async throws -> SleepEntry? {
        readCount += 1
        if fail { throw URLError(.notConnectedToInternet) }
        return latest
    }
    func fetchEntries(from: Date, to: Date) async throws -> [SleepEntry] {
        readCount += 1
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
        let sessions = SleepHealthKitManager.mainSleepSessions(from: samples,
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
    func testUncoveredGapsRemainSeparateAndMainSessionSelectionIsStable() throws {
        let start = date("2026-10-25T00:00:00-04:00")
        let samples = [sample(start, 360), sample(start.addingTimeInterval(12*3600), 90)]
        XCTAssertEqual(SleepHealthKitManager.sleepSessions(from: samples).count, 2)
        let first = SleepHealthKitManager.mainSleepSessions(from: samples, wakingFrom: start, through: start.addingTimeInterval(24*3600))
        let reversed = SleepHealthKitManager.mainSleepSessions(from: samples.reversed(), wakingFrom: start, through: start.addingTimeInterval(24*3600))
        XCTAssertEqual(first.values.first?.first?.startDate, start)
        XCTAssertEqual(first.values.first?.first?.startDate, reversed.values.first?.first?.startDate)
    }
    func testOverlappingStagesAndAwakeDoNotManufactureMeasuredComponents() {
        let start = Date()
        let data = SleepHealthKitManager.sleepDurations([sample(start, 120), sample(start, 90, .asleepCore),
            sample(start.addingTimeInterval(60*60), 60, .asleepDeep), sample(start, 10, .awake)])
        XCTAssertEqual(data.asleep, 7200)
        XCTAssertFalse(data.hasCompleteStages)
        XCTAssertFalse(data.hasAwakeData)
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
        XCTAssertNil(SleepHealthKitManager.sleepEntry(from: [sample(start, 30)], for: start, owner: owner))
        XCTAssertTrue(SleepHealthKitManager.mainSleepSessions(from: [sample(start, 1441)], wakingFrom: start,
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
        return (200, row)
    }
}
