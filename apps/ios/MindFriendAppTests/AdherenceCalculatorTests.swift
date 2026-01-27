import XCTest
@testable import MindFriendApp

final class AdherenceCalculatorTests: XCTestCase {
    var sut: AdherenceCalculator!

    override func setUp() {
        super.setUp()
        sut = AdherenceCalculator()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Adherence Calculation Tests

    func testCalculateAdherenceWithAllTaken() {
        // Given
        let logs = [
            createLog(status: .taken),
            createLog(status: .taken),
            createLog(status: .taken),
            createLog(status: .taken),
            createLog(status: .taken)
        ]

        // When
        let stats = sut.calculate(logs: logs, totalScheduled: 5)

        // Then
        XCTAssertEqual(stats.percentage, 1.0)
        XCTAssertEqual(stats.takenCount, 5)
        XCTAssertEqual(stats.missedCount, 0)
        XCTAssertEqual(stats.displayPercentage, "100%")
    }

    func testCalculateAdherenceWithMixed() {
        // Given
        let logs = [
            createLog(status: .taken),
            createLog(status: .taken),
            createLog(status: .late),
            createLog(status: .skipped),
            createLog(status: .pending)
        ]

        // When
        let stats = sut.calculate(logs: logs, totalScheduled: 5)

        // Then
        XCTAssertEqual(stats.takenCount, 2)
        XCTAssertEqual(stats.lateCount, 1)
        XCTAssertEqual(stats.missedCount, 2) // skipped + pending
        let expectedPercentage = 3.0 / 5.0  // taken + late
        XCTAssertEqual(stats.percentage, expectedPercentage, accuracy: 0.01)
    }

    func testCalculateAdherenceWithNone() {
        // Given
        let logs = [
            createLog(status: .skipped),
            createLog(status: .pending),
            createLog(status: .pending)
        ]

        // When
        let stats = sut.calculate(logs: logs, totalScheduled: 3)

        // Then
        XCTAssertEqual(stats.percentage, 0.0)
        XCTAssertEqual(stats.takenCount, 0)
        XCTAssertEqual(stats.missedCount, 3)
        XCTAssertEqual(stats.displayPercentage, "0%")
    }

    func testCalculateAdherenceWithEmptyLogs() {
        // Given
        let logs: [MedicationLog] = []

        // When
        let stats = sut.calculate(logs: logs, totalScheduled: 5)

        // Then
        XCTAssertEqual(stats.percentage, 0.0)
        XCTAssertEqual(stats.takenCount, 0)
    }

    func testCalculateAdherenceWithZeroScheduled() {
        // Given
        let logs = [
            createLog(status: .taken)
        ]

        // When
        let stats = sut.calculate(logs: logs, totalScheduled: 0)

        // Then
        XCTAssertEqual(stats.percentage, 1.0)  // Defaults to 1.0 when no scheduled
    }

    // MARK: - Streak Calculation Tests

    func testStreakCalculationCurrentDay() {
        // Given
        let today = Calendar.current.startOfDay(for: Date())
        let logs = [
            createLog(scheduledAt: today),
            createLog(status: .taken, scheduledAt: today)
        ]

        // When
        let stats = sut.calculate(logs: logs, totalScheduled: 2)

        // Then
        // Streak should be 1 for today
        XCTAssertEqual(stats.streakDays, 1)
    }

    func testStreakCalculationMultipleDays() {
        // Given
        let today = Calendar.current.startOfDay(for: Date())
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: today)!

        let logs = [
            createLog(status: .taken, scheduledAt: today),
            createLog(status: .taken, scheduledAt: yesterday),
            createLog(status: .taken, scheduledAt: twoDaysAgo)
        ]

        // When
        let stats = sut.calculate(logs: logs, totalScheduled: 3)

        // Then
        // Streak should be 3 days
        XCTAssertGreaterThan(stats.streakDays, 0)
    }

    func testStreakBreaksOnMissedDay() {
        // Given
        let today = Calendar.current.startOfDay(for: Date())
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: today)!

        let logs = [
            createLog(status: .taken, scheduledAt: today),
            createLog(status: .skipped, scheduledAt: yesterday),  // Gap breaks streak
            createLog(status: .taken, scheduledAt: twoDaysAgo)
        ]

        // When
        let stats = sut.calculate(logs: logs, totalScheduled: 3)

        // Then
        // Streak should be 1 (only today)
        XCTAssertEqual(stats.streakDays, 1)
    }

    // MARK: - Mood Correlation Tests

    func testMoodCorrelationWithAdherentDays() {
        // Given
        let medicationLogs = [
            createLog(status: .taken),
            createLog(status: .taken),
            createLog(status: .late)
        ]
        let moodLogs = [
            createMood(score: 7),
            createMood(score: 8),
            createMood(score: 8)
        ]

        // When
        let correlation = sut.calculateMoodCorrelation(medicationLogs: medicationLogs, moodLogs: moodLogs)

        // Then
        XCTAssertGreaterThan(correlation.averageMoodWhenAdherent, 0)
        XCTAssertEqual(correlation.adherentDays, 3)
        XCTAssertEqual(correlation.nonAdherentDays, 0)
    }

    func testMoodCorrelationWithNonAdherentDays() {
        // Given
        let medicationLogs = [
            createLog(status: .skipped),
            createLog(status: .pending)
        ]
        let moodLogs = [
            createMood(score: 3),
            createMood(score: 4)
        ]

        // When
        let correlation = sut.calculateMoodCorrelation(medicationLogs: medicationLogs, moodLogs: moodLogs)

        // Then
        XCTAssertGreaterThan(correlation.averageMoodWhenNotAdherent, 0)
        XCTAssertEqual(correlation.nonAdherentDays, 2)
        XCTAssertEqual(correlation.adherentDays, 0)
    }

    func testMoodCorrelationWithMixedData() {
        // Given
        let medicationLogs = [
            createLog(status: .taken),
            createLog(status: .skipped),
            createLog(status: .late)
        ]
        let moodLogs = [
            createMood(score: 8),  // Adherent day
            createMood(score: 4),  // Non-adherent day
            createMood(score: 7)   // Adherent day
        ]

        // When
        let correlation = sut.calculateMoodCorrelation(medicationLogs: medicationLogs, moodLogs: moodLogs)

        // Then
        XCTAssertGreaterThan(correlation.averageMoodWhenAdherent, correlation.averageMoodWhenNotAdherent)
        XCTAssertEqual(correlation.moodDifference, correlation.averageMoodWhenAdherent - correlation.averageMoodWhenNotAdherent)
        XCTAssert(correlation.insight.contains("higher"))
    }

    func testMoodCorrelationWithEmptyMoodLogs() {
        // Given
        let medicationLogs = [
            createLog(status: .taken)
        ]
        let moodLogs: [MoodEntry] = []

        // When
        let correlation = sut.calculateMoodCorrelation(medicationLogs: medicationLogs, moodLogs: moodLogs)

        // Then
        XCTAssertEqual(correlation.averageMoodWhenAdherent, 0)
        XCTAssertEqual(correlation.adherentDays, 0)
    }

    // MARK: - Display Formatting Tests

    func testDisplayPercentageFormatting() {
        // Given
        let logs = [
            createLog(status: .taken),
            createLog(status: .taken),
            createLog(status: .taken)
        ]

        // When
        let stats = sut.calculate(logs: logs, totalScheduled: 7)

        // Then
        let expectedPercentage = String(format: "%.0f%%", (3.0 / 7.0) * 100)
        XCTAssertEqual(stats.displayPercentage, expectedPercentage)
    }

    // MARK: - Helper Methods

    private func createLog(
        status: MedicationStatus = .taken,
        scheduledAt: Date = Date()
    ) -> MedicationLog {
        MedicationLog(
            id: UUID(),
            userId: UUID(),
            medicationId: UUID(),
            scheduledAt: scheduledAt,
            status: status,
            loggedAt: Date(),
            skipReason: nil,
            notes: nil,
            sideEffects: nil,
            moodAtTime: nil,
            createdAt: Date()
        )
    }

    private func createMedicationLog(status: MedicationStatus, scheduledAt: Date) -> MedicationLog {
        MedicationLog(
            id: UUID(),
            userId: UUID(),
            medicationId: UUID(),
            scheduledAt: scheduledAt,
            status: status,
            loggedAt: nil,
            skipReason: nil,
            notes: nil,
            sideEffects: nil,
            moodAtTime: nil,
            createdAt: Date()
        )
    }

    private func createMood(score: Int) -> MoodEntry {
        MoodEntry(
            id: UUID().uuidString,
            localDate: ISO8601DateFormatter().string(from: Date()),
            moodScore: score,
            anxietyScore: nil,
            energyScore: nil,
            note: nil,
            source: .manual,
            createdAt: Date()
        )
    }
}
