import XCTest
import Supabase
@testable import MindFriendApp

final class HabitDateTests: XCTestCase {
    func testCompletionRoundTripUsesLocalDateLabels() throws {
        for zone in ["America/New_York", "Asia/Tokyo"] {
            try withTimeZone(zone) { calendar in
                for label in ["2026-03-08", "2026-03-09", "2026-11-01", "2026-11-02"] {
                    let day = try XCTUnwrap(HabitDateFormatter.dayOnly.date(from: label))
                    let completion = makeCompletion(date: day)
                    let encoded = try JSONEncoder().encode(completion)
                    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
                    XCTAssertEqual(json["completed_date"] as? String, label, zone)
                    let reloaded = try JSONDecoder().decode(HabitCompletion.self, from: encoded)
                    XCTAssertEqual(reloaded.completedDate, calendar.startOfDay(for: day), zone)
                    // The duplicate query and persisted DATE must address the same day.
                    XCTAssertEqual(HabitDateFormatter.dayOnly.string(from: reloaded.completedDate), label)
                    let info = HabitService.streakInfo(completions: [reloaded], today: day, calendar: calendar)
                    XCTAssertTrue(info.isCompletedToday, zone)
                    XCTAssertEqual(info.currentStreak, 4)
                    XCTAssertFalse(info.willResetNextDay)
                }
            }
        }
    }

    func testStreakAndWeeklyStatsAcrossDaylightSavingTransitions() throws {
        for zone in ["America/New_York", "Asia/Tokyo"] {
            try withTimeZone(zone) { calendar in
                for label in ["2026-03-09", "2026-11-02"] {
                    let today = try XCTUnwrap(HabitDateFormatter.dayOnly.date(from: label))
                    let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
                    let firstDay = try XCTUnwrap(calendar.date(byAdding: .day, value: -6, to: today))
                    let completions = try [makeCompletion(date: today), makeCompletion(date: yesterday),
                                           makeCompletion(date: firstDay)].map {
                        try JSONDecoder().decode(HabitCompletion.self, from: JSONEncoder().encode($0))
                    }
                    XCTAssertEqual(HabitService.nextStreak(after: completions[1], today: today, calendar: calendar), 5)
                    XCTAssertEqual(HabitService.weeklyStats(completions: completions, today: today, calendar: calendar),
                                   [1, 0, 0, 0, 0, 1, 1])
                    let skipped = makeCompletion(date: today, skipped: true)
                    XCTAssertFalse(HabitService.streakInfo(completions: [skipped], today: today, calendar: calendar).isCompletedToday)
                    XCTAssertEqual(HabitService.weeklyStats(completions: [skipped], today: today, calendar: calendar),
                                   [0, 0, 0, 0, 0, 0, 0])
                }
            }
        }
    }

    private func withTimeZone(_ identifier: String, body: (Calendar) throws -> Void) rethrows {
        let previous = NSTimeZone.default
        let zone = TimeZone(identifier: identifier)!
        NSTimeZone.default = zone
        defer { NSTimeZone.default = previous }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        try body(calendar)
    }

    private func makeCompletion(date: Date, skipped: Bool = false) -> HabitCompletion {
        HabitCompletion(id: UUID(), habitId: UUID(), userId: UUID(), completedDate: date,
                        currentStreak: 4, skipped: skipped, skipReason: nil, createdAt: date)
    }
}

/// A habit with a reminder, created on a phone in America/New_York, saved, reloaded, and
/// scheduled. The wire format is the Supabase client's own; the server body is what
/// PostgREST returns for habits.reminder_time once the column is timestamptz.
final class HabitReminderWireTests: XCTestCase {
    func testReminderSavesReloadsAndFiresAtThePickedLocalTime() throws {
        let newYork = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = newYork
        // 8:30 AM picked on 13 November 2026.
        let picked = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 8, minute: 30)))
        let habit = Habit(id: UUID(), userId: UUID(), name: "Morning breath", anchor: "pour my coffee",
                          behavior: "take three breaths", category: .breathing, difficulty: .easy,
                          durationSeconds: 30, reminderTime: picked, reminderMinutesBefore: 5,
                          isActive: true, createdAt: picked, updatedAt: picked)

        // Save: the exact text the insert carries, which supabase/tests/habit_reminders.sql casts.
        let body = try PostgrestClient.Configuration.jsonEncoder.encode(habit)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["reminder_time"] as? String, "2026-11-13T13:30:00.000")

        // Reload: a timetz body could not be decoded; the timestamptz body is the same instant.
        var row = json
        row["reminder_time"] = "13:30:00+00"
        XCTAssertThrowsError(try PostgrestClient.Configuration.jsonDecoder.decode(
            Habit.self, from: JSONSerialization.data(withJSONObject: row)))
        row["reminder_time"] = "2026-11-13T13:30:00+00:00"
        let reloaded = try PostgrestClient.Configuration.jsonDecoder.decode(
            Habit.self, from: JSONSerialization.data(withJSONObject: row))
        let reminder = try XCTUnwrap(reloaded.reminderTime)
        XCTAssertEqual(reminder, picked)

        // Fire: every day at 8:25 AM New York time, five minutes ahead, also after the DST change.
        let trigger = HabitNotificationService.dailyTrigger(
            anchorTime: reminder, minutesBefore: try XCTUnwrap(reloaded.reminderMinutesBefore), timeZone: newYork)
        XCTAssertEqual(trigger.hour, 8)
        XCTAssertEqual(trigger.minute, 25)
        XCTAssertEqual(trigger.timeZone, newYork)
        let july = try XCTUnwrap(calendar.date(from: DateComponents(year: 2027, month: 7, day: 1)))
        let next = try XCTUnwrap(calendar.nextDate(after: july, matching: trigger, matchingPolicy: .nextTime))
        XCTAssertEqual(calendar.dateComponents([.hour, .minute], from: next), DateComponents(hour: 8, minute: 25))
    }
}

// FIXME: Tests disabled - HabitMockSupabaseDataService cannot inherit from final SupabaseDataService
/*
@MainActor
final class HabitServiceTests: XCTestCase {
    var sut: HabitService!
    var mockSupabase: HabitMockSupabaseDataService!

    override func setUp() {
        super.setUp()
        mockSupabase = HabitMockSupabaseDataService()
        sut = HabitService(supabaseDataService: mockSupabase)
    }

    override func tearDown() {
        sut = nil
        mockSupabase = nil
        super.tearDown()
    }

    // MARK: - Habit Creation Tests

    func test_createHabit_withValidInput_createsHabit() async throws {
        let testUserId = UUID()
        let habitName = "Morning Breathing"
        let anchor = "I wake up"
        let behavior = "I take 5 deep breaths"
        let category = HabitCategory.breathing
        let difficulty = HabitDifficulty.easy

        mockSupabase.mockCreateHabitResult = Habit(
            id: UUID(),
            userId: testUserId,
            name: habitName,
            anchor: anchor,
            behavior: behavior,
            category: category,
            difficulty: difficulty,
            durationSeconds: 120,
            reminderTime: nil,
            reminderMinutesBefore: nil,
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        let result = try await sut.createHabit(
            name: habitName,
            anchor: anchor,
            behavior: behavior,
            category: category,
            difficulty: difficulty,
            reminderTime: nil,
            reminderMinutesBefore: nil
        )

        XCTAssertEqual(result.name, habitName)
        XCTAssertEqual(result.anchor, anchor)
        XCTAssertEqual(result.behavior, behavior)
        XCTAssertEqual(result.category, category)
        XCTAssertEqual(result.durationSeconds, 120)
    }

    func test_createHabit_withCustomReminder_createsHabitWithReminder() async throws {
        let reminderTime = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date())!

        mockSupabase.mockCreateHabitResult = Habit(
            id: UUID(),
            userId: UUID(),
            name: "Test",
            anchor: "anchor",
            behavior: "behavior",
            category: .meditation,
            difficulty: .medium,
            durationSeconds: 300,
            reminderTime: reminderTime,
            reminderMinutesBefore: 15,
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        let result = try await sut.createHabit(
            name: "Test",
            anchor: "anchor",
            behavior: "behavior",
            category: .meditation,
            difficulty: .medium,
            reminderTime: reminderTime,
            reminderMinutesBefore: 15
        )

        XCTAssertEqual(result.reminderTime, reminderTime)
        XCTAssertEqual(result.reminderMinutesBefore, 15)
    }

    func test_createHabitFromTemplate_createsHabitWithTemplateDefaults() async throws {
        let template = HabitTemplate(
            id: UUID(),
            name: "Box Breathing",
            category: .breathing,
            difficulty: .easy,
            defaultDurationSeconds: 120,
            behaviorTemplate: "Breathe in for 4, hold for 4...",
            description: "4-4-4-4 breathing pattern",
            anchorExample: "After I wake up",
            createdAt: Date()
        )

        mockSupabase.mockCreateHabitResult = Habit(
            id: UUID(),
            userId: UUID(),
            name: template.name,
            anchor: "After I wake up",
            behavior: "I do box breathing",
            category: template.category,
            difficulty: template.difficulty,
            durationSeconds: template.defaultDurationSeconds,
            reminderTime: nil,
            reminderMinutesBefore: nil,
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        let result = try await sut.createHabitFromTemplate(template: template, anchor: "After I wake up")

        XCTAssertEqual(result.name, template.name)
        XCTAssertEqual(result.category, template.category)
        XCTAssertEqual(result.durationSeconds, template.defaultDurationSeconds)
    }

    // MARK: - Streak Calculation Tests

    func test_calculateStreak_firstCompletion_returnsStreakOne() async throws {
        let habit = Habit(
            id: UUID(),
            userId: UUID(),
            name: "Test",
            anchor: "anchor",
            behavior: "behavior",
            category: .breathing,
            difficulty: .easy,
            durationSeconds: 120,
            reminderTime: nil,
            reminderMinutesBefore: nil,
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        let today = Calendar.current.startOfDay(for: Date())
        mockSupabase.mockFetchCompletionsResult = []

        let streak = try await sut.getCurrentStreak(for: habit.id)

        XCTAssertEqual(streak.currentStreak, 0)
        XCTAssertFalse(streak.isCompletedToday)
    }

    func test_calculateStreak_completedToday_returnsStreakOne() async throws {
        let habitId = UUID()
        let today = Calendar.current.startOfDay(for: Date())

        mockSupabase.mockFetchCompletionsResult = [
            HabitCompletion(
                id: UUID(),
                habitId: habitId,
                userId: UUID(),
                completedDate: today,
                currentStreak: 1,
                skipped: false,
                skipReason: nil,
                createdAt: Date()
            )
        ]

        let streak = try await sut.getCurrentStreak(for: habitId)

        XCTAssertEqual(streak.currentStreak, 1)
        XCTAssertTrue(streak.isCompletedToday)
    }

    func test_calculateStreak_consecutiveDays_incrementsStreak() async throws {
        let habitId = UUID()
        let today = Calendar.current.startOfDay(for: Date())
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!

        mockSupabase.mockFetchCompletionsResult = [
            HabitCompletion(
                id: UUID(),
                habitId: habitId,
                userId: UUID(),
                completedDate: yesterday,
                currentStreak: 1,
                skipped: false,
                skipReason: nil,
                createdAt: Date()
            ),
            HabitCompletion(
                id: UUID(),
                habitId: habitId,
                userId: UUID(),
                completedDate: today,
                currentStreak: 2,
                skipped: false,
                skipReason: nil,
                createdAt: Date()
            )
        ]

        let streak = try await sut.getCurrentStreak(for: habitId)

        XCTAssertEqual(streak.currentStreak, 2)
        XCTAssertTrue(streak.isCompletedToday)
    }

    func test_calculateStreak_skipResetsStreak() async throws {
        let habitId = UUID()
        let today = Calendar.current.startOfDay(for: Date())
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!

        mockSupabase.mockFetchCompletionsResult = [
            HabitCompletion(
                id: UUID(),
                habitId: habitId,
                userId: UUID(),
                completedDate: yesterday,
                currentStreak: 5,
                skipped: false,
                skipReason: nil,
                createdAt: Date()
            ),
            HabitCompletion(
                id: UUID(),
                habitId: habitId,
                userId: UUID(),
                completedDate: today,
                currentStreak: 0,
                skipped: true,
                skipReason: "Busy day",
                createdAt: Date()
            )
        ]

        let streak = try await sut.getCurrentStreak(for: habitId)

        XCTAssertEqual(streak.currentStreak, 0)
        XCTAssertTrue(streak.isCompletedToday)
    }

    func test_calculateStreak_gapGreaterThan3Days_resetsStreak() async throws {
        let habitId = UUID()
        let today = Calendar.current.startOfDay(for: Date())
        let fourDaysAgo = Calendar.current.date(byAdding: .day, value: -4, to: today)!

        mockSupabase.mockFetchCompletionsResult = [
            HabitCompletion(
                id: UUID(),
                habitId: habitId,
                userId: UUID(),
                completedDate: fourDaysAgo,
                currentStreak: 3,
                skipped: false,
                skipReason: nil,
                createdAt: Date()
            )
        ]

        let streak = try await sut.getCurrentStreak(for: habitId)

        XCTAssertEqual(streak.currentStreak, 0)
        XCTAssertFalse(streak.isCompletedToday)
    }

    func test_calculateStreak_maxStreakTracked() async throws {
        let habitId = UUID()
        let today = Calendar.current.startOfDay(for: Date())

        var completions: [HabitCompletion] = []
        for i in 0..<10 {
            let date = Calendar.current.date(byAdding: .day, value: -i, to: today)!
            completions.append(
                HabitCompletion(
                    id: UUID(),
                    habitId: habitId,
                    userId: UUID(),
                    completedDate: date,
                    currentStreak: 10 - i,
                    skipped: false,
                    skipReason: nil,
                    createdAt: Date()
                )
            )
        }

        mockSupabase.mockFetchCompletionsResult = completions

        let streak = try await sut.getCurrentStreak(for: habitId)

        XCTAssertEqual(streak.currentStreak, 10)
        XCTAssertEqual(streak.longestStreak, 10)
    }

    // MARK: - Habit Completion Tests

    func test_completeHabit_succeeds() async throws {
        let habitId = UUID()
        let userId = UUID()
        let today = Calendar.current.startOfDay(for: Date())

        mockSupabase.mockCompleteHabitSuccess = true
        mockSupabase.mockFetchCompletionsResult = []

        try await sut.completeHabit(habitId: habitId, userId: userId)

        XCTAssertTrue(mockSupabase.mockCompleteHabitSuccess)
    }

    func test_completeHabit_duplicateCompletion_throwsError() async throws {
        let habitId = UUID()
        let userId = UUID()
        let today = Calendar.current.startOfDay(for: Date())

        mockSupabase.mockCompleteHabitSuccess = false
        mockSupabase.mockCompleteHabitError = HabitServiceError.duplicateCompletion

        do {
            try await sut.completeHabit(habitId: habitId, userId: userId)
            XCTFail("Should throw duplicateCompletion error")
        } catch HabitServiceError.duplicateCompletion {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Skip Habit Tests

    func test_skipHabit_recordsSkipWithReason() async throws {
        let habitId = UUID()
        let userId = UUID()
        let skipReason = "Too busy today"

        mockSupabase.mockSkipHabitSuccess = true

        try await sut.skipHabit(habitId: habitId, userId: userId, reason: skipReason)

        XCTAssertTrue(mockSupabase.mockSkipHabitSuccess)
    }

    // MARK: - Habit Deletion Tests

    func test_deleteHabit_softDeletesHabit() async throws {
        let habitId = UUID()

        mockSupabase.mockDeleteHabitSuccess = true

        try await sut.deleteHabit(habitId: habitId)

        XCTAssertTrue(mockSupabase.mockDeleteHabitSuccess)
    }

    // MARK: - Habit Fetching Tests

    func test_fetchHabits_returnsAllActiveHabits() async throws {
        let userId = UUID()
        let habits = [
            Habit(
                id: UUID(),
                userId: userId,
                name: "Habit 1",
                anchor: "anchor",
                behavior: "behavior",
                category: .breathing,
                difficulty: .easy,
                durationSeconds: 120,
                reminderTime: nil,
                reminderMinutesBefore: nil,
                isActive: true,
                createdAt: Date(),
                updatedAt: Date()
            ),
            Habit(
                id: UUID(),
                userId: userId,
                name: "Habit 2",
                anchor: "anchor",
                behavior: "behavior",
                category: .meditation,
                difficulty: .medium,
                durationSeconds: 300,
                reminderTime: nil,
                reminderMinutesBefore: nil,
                isActive: true,
                createdAt: Date(),
                updatedAt: Date()
            )
        ]

        mockSupabase.mockFetchHabitsResult = habits

        let result = try await sut.fetchHabits()

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].name, "Habit 1")
        XCTAssertEqual(result[1].name, "Habit 2")
    }

    // MARK: - Habit Template Tests

    func test_fetchHabitTemplates_returnsAllTemplates() async throws {
        let templates = [
            HabitTemplate(
                id: UUID(),
                name: "Box Breathing",
                description: "4-4-4-4 breathing",
                category: .breathing,
                difficulty: .easy,
                defaultDurationSeconds: 120,
                instructions: "Breathe in...",
                createdAt: Date()
            ),
            HabitTemplate(
                id: UUID(),
                name: "Mindfulness",
                description: "Mindful meditation",
                category: .meditation,
                difficulty: .medium,
                defaultDurationSeconds: 300,
                instructions: "Sit quietly...",
                createdAt: Date()
            )
        ]

        mockSupabase.mockFetchHabitTemplatesResult = templates

        let result = try await sut.fetchHabitTemplates()

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].name, "Box Breathing")
        XCTAssertEqual(result[1].name, "Mindfulness")
    }

    // MARK: - Weekly Stats Tests

    func test_getWeeklyStats_returns7DayArray() async throws {
        let habitId = UUID()
        let today = Calendar.current.startOfDay(for: Date())

        var completions: [HabitCompletion] = []
        for i in [0, 2, 4, 6] {  // Completed on days 0, 2, 4, 6
            let date = Calendar.current.date(byAdding: .day, value: -i, to: today)!
            completions.append(
                HabitCompletion(
                    id: UUID(),
                    habitId: habitId,
                    userId: UUID(),
                    completedDate: date,
                    currentStreak: 1,
                    skipped: false,
                    skipReason: nil,
                    createdAt: Date()
                )
            )
        }

        mockSupabase.mockFetchCompletionsResult = completions

        let stats = try await sut.getWeeklyStats(for: habitId)

        XCTAssertEqual(stats.count, 7)
        // stats[0] = today (completed)
        XCTAssertEqual(stats[0], 1)
        // stats[1] = yesterday (not completed)
        XCTAssertEqual(stats[1], 0)
        // stats[2] = 2 days ago (completed)
        XCTAssertEqual(stats[2], 1)
    }

    // MARK: - Habit Graduation Tests

    func test_checkForGraduation_after7DayStreak_graduatesHabit() async throws {
        let habit = Habit(
            id: UUID(),
            userId: UUID(),
            name: "Test",
            anchor: "anchor",
            behavior: "behavior",
            category: .breathing,
            difficulty: .easy,
            durationSeconds: 120,
            reminderTime: nil,
            reminderMinutesBefore: nil,
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        let today = Calendar.current.startOfDay(for: Date())
        var completions: [HabitCompletion] = []
        
        for i in 0..<7 {
            let date = Calendar.current.date(byAdding: .day, value: -i, to: today)!
            completions.append(
                HabitCompletion(
                    id: UUID(),
                    habitId: habit.id,
                    userId: habit.userId,
                    completedDate: date,
                    currentStreak: 7 - i,
                    skipped: false,
                    skipReason: nil,
                    createdAt: Date()
                )
            )
        }

        mockSupabase.mockFetchCompletionsResult = completions
        mockSupabase.mockGraduateHabitSuccess = true

        let streak = try await sut.getCurrentStreak(for: habit.id)
        XCTAssertEqual(streak.currentStreak, 7)
    }

    // MARK: - Error Handling Tests

    func test_fetchHabits_networkError_throwsError() async throws {
        mockSupabase.mockFetchHabitsError = HabitServiceError.networkError

        do {
            _ = try await sut.fetchHabits()
            XCTFail("Should throw networkError")
        } catch HabitServiceError.networkError {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_createHabit_invalidInput_throwsValidationError() async throws {
        mockSupabase.mockCreateHabitError = HabitServiceError.invalidInput

        do {
            _ = try await sut.createHabit(
                name: "",
                anchor: "",
                behavior: "",
                category: .breathing,
                difficulty: .easy,
                reminderTime: nil,
                reminderMinutesBefore: nil
            )
            XCTFail("Should throw invalidInput error")
        } catch HabitServiceError.invalidInput {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
*/

// MARK: - Mock Supabase Data Service
// FIXME: SupabaseDataService is a final class - cannot be subclassed for mocking
// Need to use protocol-based dependency injection instead
/*
final class HabitMockSupabaseDataService: SupabaseDataService {
    init() { super.init(authService: SupabaseAuthService(client: SupabaseClient(supabaseURL: URL(string: "https://test.com")!, supabaseKey: "test"))) }
    var mockFetchHabitsResult: [Habit] = []
    var mockFetchHabitsError: HabitServiceError?
    var mockCreateHabitResult: Habit?
    var mockCreateHabitError: HabitServiceError?
    var mockDeleteHabitSuccess = false
    var mockCompleteHabitSuccess = false
    var mockCompleteHabitError: HabitServiceError?
    var mockSkipHabitSuccess = false
    var mockFetchCompletionsResult: [HabitCompletion] = []
    var mockFetchHabitTemplatesResult: [HabitTemplate] = []
    var mockGraduateHabitSuccess = false

    override func fetchHabits() async throws -> [Habit] {
        if let error = mockFetchHabitsError { throw error }
        return mockFetchHabitsResult
    }

    override func createHabit(_ habit: Habit) async throws -> Habit {
        if let error = mockCreateHabitError { throw error }
        guard let result = mockCreateHabitResult else { throw HabitServiceError.networkError }
        return result
    }

    override func deleteHabit(habitId: UUID) async throws {
        guard mockDeleteHabitSuccess else { throw HabitServiceError.networkError }
    }

    override func completeHabit(habitId: UUID, userId: UUID) async throws {
        if let error = mockCompleteHabitError { throw error }
        guard mockCompleteHabitSuccess else { throw HabitServiceError.networkError }
    }

    override func skipHabit(habitId: UUID, userId: UUID, reason: String?) async throws {
        guard mockSkipHabitSuccess else { throw HabitServiceError.networkError }
    }

    override func fetchHabitCompletions(habitId: UUID) async throws -> [HabitCompletion] {
        return mockFetchCompletionsResult
    }

    override func fetchHabitTemplates() async throws -> [HabitTemplate] {
        return mockFetchHabitTemplatesResult
    }

    override func graduateHabit(habitId: UUID, newDifficulty: HabitDifficulty) async throws {
        guard mockGraduateHabitSuccess else { throw HabitServiceError.networkError }
    }
}
*/
