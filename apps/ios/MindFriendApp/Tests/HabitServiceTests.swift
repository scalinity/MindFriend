import XCTest
@testable import MindFriendApp

@MainActor
final class HabitServiceTests: XCTestCase {
    var sut: HabitService!

    override func setUp() {
        super.setUp()
        // Use the real Supabase client for now (or mock it)
        sut = HabitService(supabase: supabase)
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Basic Initialization Tests

    func test_habitServiceInitializes() {
        XCTAssertNotNil(sut)
        XCTAssertTrue(sut.habits.isEmpty)
        XCTAssertTrue(sut.routines.isEmpty)
        XCTAssertTrue(sut.habitTemplates.isEmpty)
    }

    // MARK: - Habit Creation Tests

    func test_createHabit_withValidInput_createsHabitStructure() {
        let habit = Habit(
            id: UUID(),
            userId: UUID(),
            name: "Morning Breathing",
            anchor: "I wake up",
            behavior: "I take 5 deep breaths",
            category: .breathing,
            difficulty: .easy,
            durationSeconds: 120,
            reminderTime: nil,
            reminderMinutesBefore: nil,
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        XCTAssertEqual(habit.name, "Morning Breathing")
        XCTAssertEqual(habit.anchor, "I wake up")
        XCTAssertEqual(habit.behavior, "I take 5 deep breaths")
        XCTAssertEqual(habit.category, .breathing)
        XCTAssertEqual(habit.difficulty, .easy)
        XCTAssertEqual(habit.durationSeconds, 120)
    }

    // MARK: - Habit Stacking Tests

    func test_habitStackingStatement_formatsCorrectly() {
        let habit = Habit(
            id: UUID(),
            userId: UUID(),
            name: "Breathing",
            anchor: "I wake up",
            behavior: "I take 5 deep breaths",
            category: .breathing,
            difficulty: .easy,
            durationSeconds: 120,
            reminderTime: nil,
            reminderMinutesBefore: nil,
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        let expectedStatement = "After I I wake up, I will I take 5 deep breaths"
        XCTAssertEqual(habit.fullHabitStatement, expectedStatement)
    }

    // MARK: - Habit Difficulty Tests

    func test_habitDifficulty_easyHas120SecondDefault() {
        XCTAssertEqual(HabitDifficulty.easy.defaultDuration, 120)
    }

    func test_habitDifficulty_mediumHas300SecondDefault() {
        XCTAssertEqual(HabitDifficulty.medium.defaultDuration, 300)
    }

    func test_habitDifficulty_hardHas600SecondDefault() {
        XCTAssertEqual(HabitDifficulty.hard.defaultDuration, 600)
    }

    func test_habitDifficulty_maxDurationIs600Seconds() {
        XCTAssertEqual(HabitDifficulty.maxDuration, 600)
    }

    // MARK: - Habit Completion Tests

    func test_habitCompletion_storesCompletionDate() {
        let habitId = UUID()
        let userId = UUID()
        let today = Calendar.current.startOfDay(for: Date())

        let completion = HabitCompletion(
            id: UUID(),
            habitId: habitId,
            userId: userId,
            completedDate: today,
            currentStreak: 1,
            skipped: false,
            skipReason: nil,
            createdAt: Date()
        )

        XCTAssertEqual(completion.habitId, habitId)
        XCTAssertEqual(completion.completedDate, today)
        XCTAssertEqual(completion.currentStreak, 1)
        XCTAssertFalse(completion.skipped)
    }

    func test_habitCompletion_withSkipRecordsReason() {
        let completion = HabitCompletion(
            id: UUID(),
            habitId: UUID(),
            userId: UUID(),
            completedDate: Date(),
            currentStreak: 0,
            skipped: true,
            skipReason: "Too busy",
            createdAt: Date()
        )

        XCTAssertTrue(completion.skipped)
        XCTAssertEqual(completion.skipReason, "Too busy")
    }

    // MARK: - Streak Info Tests

    func test_streakInfo_tracksCurrentAndLongestStreaks() {
        let streak = StreakInfo(
            currentStreak: 5,
            longestStreak: 12,
            lastCompletionDate: Date(),
            isCompletedToday: true,
            willResetNextDay: false
        )

        XCTAssertEqual(streak.currentStreak, 5)
        XCTAssertEqual(streak.longestStreak, 12)
        XCTAssertTrue(streak.isCompletedToday)
        XCTAssertFalse(streak.willResetNextDay)
    }

    // MARK: - Habit Template Tests

    func test_habitTemplate_storesDefaultDuration() {
        let template = HabitTemplate(
            id: UUID(),
            name: "Box Breathing",
            description: "4-4-4-4 breathing",
            category: .breathing,
            difficulty: .easy,
            defaultDurationSeconds: 120,
            instructions: "Breathe in...",
            createdAt: Date()
        )

        XCTAssertEqual(template.name, "Box Breathing")
        XCTAssertEqual(template.defaultDurationSeconds, 120)
        XCTAssertEqual(template.category, .breathing)
    }

    // MARK: - Routine Tests

    func test_routine_storesNameAndType() {
        let routine = Routine(
            id: UUID(),
            userId: UUID(),
            name: "Morning Calm",
            type: .morning,
            targetTime: Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()),
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        XCTAssertEqual(routine.name, "Morning Calm")
        XCTAssertEqual(routine.type, .morning)
        XCTAssertTrue(routine.isActive)
    }

    func test_routineWithHabits_calculatesTotalDuration() {
        let routine = Routine(
            id: UUID(),
            userId: UUID(),
            name: "Test",
            type: .morning,
            targetTime: nil,
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        let habit1 = Habit(
            id: UUID(),
            userId: UUID(),
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
        )

        let habit2 = Habit(
            id: UUID(),
            userId: UUID(),
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

        let routineWithHabits = RoutineWithHabits(
            routine: routine,
            habits: [habit1, habit2]
        )

        XCTAssertEqual(routineWithHabits.totalDuration, 420)  // 120 + 300
    }

    // MARK: - Routine Completion Tests

    func test_routineCompletion_calculatesCompletionPercentage() {
        let completion = RoutineCompletion(
            id: UUID(),
            routineId: UUID(),
            userId: UUID(),
            completedDate: Date(),
            completedHabitIds: [UUID(), UUID()],  // 2 completed
            skippedHabitIds: [UUID()],  // 1 skipped
            completionPercentage: 67,  // 2 out of 3
            totalDurationSeconds: 420,
            createdAt: Date(),
            updatedAt: Date()
        )

        XCTAssertEqual(completion.completionPercentage, 67)
        XCTAssertEqual(completion.completedHabitIds.count, 2)
        XCTAssertEqual(completion.skippedHabitIds.count, 1)
    }

    // MARK: - Habit Categories Tests

    func test_habitCategories_allCasesAvailable() {
        let categories: [HabitCategory] = [.breathing, .meditation, .journaling, .movement, .custom]

        XCTAssertEqual(HabitCategory.allCases.count, 5)
        for category in categories {
            XCTAssertTrue(HabitCategory.allCases.contains(category))
        }
    }

    // MARK: - Routine Types Tests

    func test_routineTypes_allCasesAvailable() {
        let types: [RoutineType] = [.morning, .evening, .custom]

        XCTAssertEqual(RoutineType.allCases.count, 3)
        for type in types {
            XCTAssertTrue(RoutineType.allCases.contains(type))
        }
    }
}
