//
//  SleepScoreCalculatorTests.swift
//  MindFriendAppTests
//
//  Unit tests for sleep score calculation algorithm
//

import XCTest
import SwiftUI
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
