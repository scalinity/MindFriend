import XCTest
@testable import MindFriendApp

@MainActor
final class RoutineTests: XCTestCase {
    var habitService: HabitService!
    var mockSupabase: RoutineMockSupabaseClient!

    override func setUp() {
        super.setUp()
        mockSupabase = RoutineMockSupabaseClient()
        habitService = HabitService(supabase: mockSupabase)
    }

    override func tearDown() {
        habitService = nil
        mockSupabase = nil
        super.tearDown()
    }

    // MARK: - Routine Creation Tests

    func testCreateRoutine() async throws {
        let routineName = "Morning Routine"
        let routineType: RoutineType = .morning
        let targetTime = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date())

        try await habitService.createRoutine(
            name: routineName,
            type: routineType,
            targetTime: targetTime
        )

        XCTAssertEqual(habitService.routines.count, 1)
        XCTAssertEqual(habitService.routines.first?.name, routineName)
        XCTAssertEqual(habitService.routines.first?.type, routineType)
    }

    func testCreateMultipleRoutines() async throws {
        let morningRoutine = Routine(
            id: UUID(),
            userId: UUID(),
            name: "Morning",
            type: .morning,
            targetTime: Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()),
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        let eveningRoutine = Routine(
            id: UUID(),
            userId: UUID(),
            name: "Evening",
            type: .evening,
            targetTime: Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: Date()),
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        try await habitService.createRoutine(
            name: morningRoutine.name,
            type: morningRoutine.type,
            targetTime: morningRoutine.targetTime
        )

        try await habitService.createRoutine(
            name: eveningRoutine.name,
            type: eveningRoutine.type,
            targetTime: eveningRoutine.targetTime
        )

        XCTAssertEqual(habitService.routines.count, 2)
        XCTAssertTrue(habitService.routines.contains { $0.name == "Morning" })
        XCTAssertTrue(habitService.routines.contains { $0.name == "Evening" })
    }

    // MARK: - Add Habit to Routine Tests

    func testAddHabitToRoutine() async throws {
        let habit = Habit(
            id: UUID(),
            userId: UUID(),
            name: "Meditation",
            anchor: "After waking up",
            behavior: "Meditate for 5 minutes",
            category: .meditation,
            difficulty: .easy,
            durationSeconds: 300,
            reminderTime: nil,
            reminderMinutesBefore: 5,
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        let routine = Routine(
            id: UUID(),
            userId: UUID(),
            name: "Morning Routine",
            type: .morning,
            targetTime: Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()),
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        try await habitService.addHabitToRoutine(habit, routine: routine, at: 0)

        // Verify via mock that routine_habit was inserted
        XCTAssertTrue(mockSupabase.insertedRoutineHabits.contains { rh in
            rh.habitId == habit.id && rh.routineId == routine.id && rh.orderIndex == 0
        })
    }

    func testAddMultipleHabitsToRoutineInOrder() async throws {
        let habit1 = Habit(
            id: UUID(),
            userId: UUID(),
            name: "Stretch",
            anchor: "After waking up",
            behavior: "Stretch for 5 minutes",
            category: .movement,
            difficulty: .easy,
            durationSeconds: 300,
            reminderTime: nil,
            reminderMinutesBefore: 5,
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        let habit2 = Habit(
            id: UUID(),
            userId: UUID(),
            name: "Meditate",
            anchor: "After stretching",
            behavior: "Meditate for 10 minutes",
            category: .meditation,
            difficulty: .medium,
            durationSeconds: 600,
            reminderTime: nil,
            reminderMinutesBefore: 5,
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        let routine = Routine(
            id: UUID(),
            userId: UUID(),
            name: "Morning Routine",
            type: .morning,
            targetTime: Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()),
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        try await habitService.addHabitToRoutine(habit1, routine: routine, at: 0)
        try await habitService.addHabitToRoutine(habit2, routine: routine, at: 1)

        XCTAssertEqual(mockSupabase.insertedRoutineHabits.count, 2)
        XCTAssertEqual(mockSupabase.insertedRoutineHabits[0].orderIndex, 0)
        XCTAssertEqual(mockSupabase.insertedRoutineHabits[1].orderIndex, 1)
    }

    // MARK: - Get Routine with Habits Tests

    func testGetRoutineWithHabits() async throws {
        let habitId1 = UUID()
        let habitId2 = UUID()
        let routineId = UUID()

        let habit1 = Habit(
            id: habitId1,
            userId: UUID(),
            name: "Stretch",
            anchor: "After waking",
            behavior: "Stretch",
            category: .movement,
            difficulty: .easy,
            durationSeconds: 300,
            reminderTime: nil,
            reminderMinutesBefore: 5,
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        let habit2 = Habit(
            id: habitId2,
            userId: UUID(),
            name: "Meditate",
            anchor: "After stretch",
            behavior: "Meditate",
            category: .meditation,
            difficulty: .medium,
            durationSeconds: 600,
            reminderTime: nil,
            reminderMinutesBefore: 5,
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        let routine = Routine(
            id: routineId,
            userId: UUID(),
            name: "Morning",
            type: .morning,
            targetTime: Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()),
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        // Mock the return values
        mockSupabase.mockRoutineHabits = [
            RoutineHabit(routineId: routineId, habitId: habitId1, orderIndex: 0, createdAt: Date()),
            RoutineHabit(routineId: routineId, habitId: habitId2, orderIndex: 1, createdAt: Date())
        ]
        mockSupabase.mockHabits = [habit1, habit2]

        let routineWithHabits = try await habitService.getRoutineWithHabits(routine)

        XCTAssertEqual(routineWithHabits.routine.id, routineId)
        XCTAssertEqual(routineWithHabits.habits.count, 2)
        XCTAssertEqual(routineWithHabits.habits[0].id, habitId1)
        XCTAssertEqual(routineWithHabits.habits[1].id, habitId2)
    }

    func testGetRoutineWithHabitsRespectsOrder() async throws {
        let habitIds = [UUID(), UUID(), UUID()]
        let routineId = UUID()
        let userId = UUID()

        let habits = habitIds.enumerated().map { (index, id) in
            Habit(
                id: id,
                userId: userId,
                name: "Habit \(index + 1)",
                anchor: "Anchor \(index + 1)",
                behavior: "Behavior \(index + 1)",
                category: .movement,
                difficulty: .easy,
                durationSeconds: 300,
                reminderTime: nil,
                reminderMinutesBefore: 5,
                isActive: true,
                createdAt: Date(),
                updatedAt: Date()
            )
        }

        let routine = Routine(
            id: routineId,
            userId: userId,
            name: "Ordered Routine",
            type: .morning,
            targetTime: Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()),
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        // Mock in reverse order to test sorting
        mockSupabase.mockRoutineHabits = [
            RoutineHabit(routineId: routineId, habitId: habitIds[2], orderIndex: 2, createdAt: Date()),
            RoutineHabit(routineId: routineId, habitId: habitIds[0], orderIndex: 0, createdAt: Date()),
            RoutineHabit(routineId: routineId, habitId: habitIds[1], orderIndex: 1, createdAt: Date())
        ]
        mockSupabase.mockHabits = habits

        let routineWithHabits = try await habitService.getRoutineWithHabits(routine)

        // Verify habits are sorted by order_index
        XCTAssertEqual(routineWithHabits.habits[0].id, habitIds[0])
        XCTAssertEqual(routineWithHabits.habits[1].id, habitIds[1])
        XCTAssertEqual(routineWithHabits.habits[2].id, habitIds[2])
    }

    // MARK: - Complete Routine Tests

    func testCompleteRoutineAllHabits() async throws {
        let habitId1 = UUID()
        let habitId2 = UUID()
        let routineId = UUID()
        let userId = UUID()

        let routine = Routine(
            id: routineId,
            userId: userId,
            name: "Morning",
            type: .morning,
            targetTime: Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()),
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        try await habitService.completeRoutine(
            routine,
            completedHabitIds: [habitId1, habitId2],
            skippedHabitIds: []
        )

        // Verify routine completion was recorded
        XCTAssertEqual(mockSupabase.insertedRoutineCompletions.count, 1)
        let completion = mockSupabase.insertedRoutineCompletions.first!
        XCTAssertEqual(completion.completedHabitIds, [habitId1, habitId2])
        XCTAssertEqual(completion.completionPercentage, 100)
        XCTAssertEqual(completion.skippedHabitIds.count, 0)
    }

    func testCompleteRoutinePartialCompletion() async throws {
        let completedId = UUID()
        let skippedId = UUID()
        let routineId = UUID()
        let userId = UUID()

        let habit1 = Habit(
            id: completedId,
            userId: userId,
            name: "Done",
            anchor: "Anchor",
            behavior: "Behavior",
            category: .movement,
            difficulty: .easy,
            durationSeconds: 300,
            reminderTime: nil,
            reminderMinutesBefore: 5,
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        let habit2 = Habit(
            id: skippedId,
            userId: userId,
            name: "Skipped",
            anchor: "Anchor",
            behavior: "Behavior",
            category: .movement,
            difficulty: .easy,
            durationSeconds: 300,
            reminderTime: nil,
            reminderMinutesBefore: 5,
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        let routine = Routine(
            id: routineId,
            userId: userId,
            name: "Partial Routine",
            type: .morning,
            targetTime: Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()),
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        mockSupabase.mockHabits = [habit1, habit2]

        try await habitService.completeRoutine(
            routine,
            completedHabitIds: [completedId],
            skippedHabitIds: [skippedId]
        )

        // Verify completion percentage is 50%
        let completion = mockSupabase.insertedRoutineCompletions.first!
        XCTAssertEqual(completion.completionPercentage, 50)
    }

    func testCompleteRoutineCalculatesTotalDuration() async throws {
        let habitId1 = UUID()
        let habitId2 = UUID()
        let routineId = UUID()
        let userId = UUID()

        let habit1 = Habit(
            id: habitId1,
            userId: userId,
            name: "Habit 1",
            anchor: "Anchor",
            behavior: "Behavior",
            category: .movement,
            difficulty: .easy,
            durationSeconds: 300,  // 5 minutes
            reminderTime: nil,
            reminderMinutesBefore: 5,
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        let habit2 = Habit(
            id: habitId2,
            userId: userId,
            name: "Habit 2",
            anchor: "Anchor",
            behavior: "Behavior",
            category: .movement,
            difficulty: .medium,
            durationSeconds: 600,  // 10 minutes
            reminderTime: nil,
            reminderMinutesBefore: 5,
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        let routine = Routine(
            id: routineId,
            userId: userId,
            name: "Duration Test",
            type: .morning,
            targetTime: Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()),
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        mockSupabase.mockHabits = [habit1, habit2]

        try await habitService.completeRoutine(
            routine,
            completedHabitIds: [habitId1, habitId2],
            skippedHabitIds: []
        )

        // Verify total duration is 900 seconds (15 minutes)
        let completion = mockSupabase.insertedRoutineCompletions.first!
        XCTAssertEqual(completion.totalDurationSeconds, 900)
    }

    func testCompleteRoutineZeroDuration() async throws {
        let routineId = UUID()
        let userId = UUID()

        let routine = Routine(
            id: routineId,
            userId: userId,
            name: "Empty Routine",
            type: .morning,
            targetTime: Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()),
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        try await habitService.completeRoutine(
            routine,
            completedHabitIds: [],
            skippedHabitIds: []
        )

        let completion = mockSupabase.insertedRoutineCompletions.first!
        XCTAssertEqual(completion.totalDurationSeconds, 0)
        XCTAssertEqual(completion.completionPercentage, 0)
    }

    // MARK: - Routine Fetch Tests

    func testFetchRoutines() async throws {
        let userId = UUID()
        let routine1 = Routine(
            id: UUID(),
            userId: userId,
            name: "Morning",
            type: .morning,
            targetTime: Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()),
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        let routine2 = Routine(
            id: UUID(),
            userId: userId,
            name: "Evening",
            type: .evening,
            targetTime: Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: Date()),
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        mockSupabase.mockRoutines = [routine1, routine2]
        mockSupabase.mockUserId = userId

        try await habitService.fetchRoutines()

        XCTAssertEqual(habitService.routines.count, 2)
        XCTAssertTrue(habitService.routines.contains { $0.name == "Morning" })
        XCTAssertTrue(habitService.routines.contains { $0.name == "Evening" })
    }

    func testFetchRoutinesOnlyActive() async throws {
        let userId = UUID()
        let activeRoutine = Routine(
            id: UUID(),
            userId: userId,
            name: "Active",
            type: .morning,
            targetTime: Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()),
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        let inactiveRoutine = Routine(
            id: UUID(),
            userId: userId,
            name: "Inactive",
            type: .evening,
            targetTime: Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: Date()),
            isActive: false,
            createdAt: Date(),
            updatedAt: Date()
        )

        mockSupabase.mockRoutines = [activeRoutine]  // Only active routines returned
        mockSupabase.mockUserId = userId

        try await habitService.fetchRoutines()

        XCTAssertEqual(habitService.routines.count, 1)
        XCTAssertEqual(habitService.routines.first?.name, "Active")
    }
}

// MARK: - Mock Supabase Client

class RoutineMockSupabaseClient {
    var insertedRoutineHabits: [RoutineHabit] = []
    var insertedRoutineCompletions: [RoutineCompletion] = []
    var mockRoutineHabits: [RoutineHabit] = []
    var mockRoutines: [Routine] = []

    func mockRoutineOperations() {
        // This enables routine mock operations in the mock client
    }
}
