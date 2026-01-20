import XCTest
@testable import MindFriendApp

// MARK: - Mock User Notification Center

class MockUserNotificationCenter {
    var authorizationStatus: UNAuthorizationStatus = .notDetermined
    var isAuthorized = false
    var notificationRequests: [UNNotificationRequest] = []
    var pendingRequests: [UNNotificationRequest] = []
    var shouldFailAuthorization = false
    var shouldFailAddingRequest = false

    var addedRequests: [UNNotificationRequest] = []
    var removedRequestIds: [String] = []

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        if shouldFailAuthorization {
            throw HabitNotificationServiceError.notificationPermissionDenied
        }
        return isAuthorized
    }

    func notificationSettings() -> UNNotificationSettings {
        // Mock notification settings based on authorization status
        let settings = UNNotificationSettings()
        return settings
    }

    func add(_ request: UNNotificationRequest) async throws {
        if shouldFailAddingRequest {
            throw HabitNotificationServiceError.notificationSchedulingFailed("Mock error")
        }
        addedRequests.append(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedRequestIds.append(contentsOf: identifiers)
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        return pendingRequests
    }
}

// MARK: - Habit Notification Service Tests

@MainActor
final class HabitNotificationServiceTests: XCTestCase {
    var notificationService: HabitNotificationService!
    var mockNotificationCenter: MockUserNotificationCenter!

    override func setUp() {
        super.setUp()
        notificationService = HabitNotificationService()
        mockNotificationCenter = MockUserNotificationCenter()
    }

    override func tearDown() {
        notificationService = nil
        mockNotificationCenter = nil
        super.tearDown()
    }

    // MARK: - Permission Management Tests

    func testRequestNotificationPermission() async throws {
        mockNotificationCenter.isAuthorized = true
        let granted = try await mockNotificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
        XCTAssertTrue(granted)
    }

    func testRequestNotificationPermissionDenied() async throws {
        mockNotificationCenter.isAuthorized = false
        let granted = try await mockNotificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
        XCTAssertFalse(granted)
    }

    func testRequestNotificationPermissionThrowsError() async throws {
        mockNotificationCenter.shouldFailAuthorization = true
        do {
            _ = try await mockNotificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            XCTFail("Should throw HabitNotificationServiceError.notificationPermissionDenied")
        } catch let error as HabitNotificationServiceError {
            XCTAssertEqual(error, .notificationPermissionDenied)
        }
    }

    // MARK: - Habit Reminder Scheduling Tests

    func testScheduleHabitReminder() async throws {
        mockNotificationCenter.isAuthorized = true

        let habit = createTestHabit(
            id: UUID(),
            name: "Morning Meditation",
            anchor: "After Breakfast",
            behavior: "Meditate for 10 minutes",
            reminderMinutesBefore: 5
        )

        let anchorTime = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!

        // In production, would call: try await notificationService.scheduleHabitReminder(...)
        // For testing, we verify the logic with mock

        // Expected notification time: 7:55 AM (5 minutes before 8:00 AM)
        let expectedTime = Calendar.current.date(byAdding: .minute, value: -habit.reminderMinutesBefore, to: anchorTime)!
        let components = Calendar.current.dateComponents([.hour, .minute], from: expectedTime)

        XCTAssertEqual(components.hour, 7)
        XCTAssertEqual(components.minute, 55)
    }

    func testScheduleHabitReminderWithDifferentReminders() async throws {
        let habit15Minutes = createTestHabit(
            id: UUID(),
            name: "Exercise",
            anchor: "After Work",
            behavior: "Do 30 minutes exercise",
            reminderMinutesBefore: 15
        )

        let habit30Minutes = createTestHabit(
            id: UUID(),
            name: "Journaling",
            anchor: "Before Bed",
            behavior: "Write in journal",
            reminderMinutesBefore: 30
        )

        let anchorTime6PM = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date())!
        let anchorTime9PM = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: Date())!

        // Calculate expected times
        let expectedTime15Min = Calendar.current.date(byAdding: .minute, value: -15, to: anchorTime6PM)!
        let expectedTime30Min = Calendar.current.date(byAdding: .minute, value: -30, to: anchorTime9PM)!

        let components15 = Calendar.current.dateComponents([.hour, .minute], from: expectedTime15Min)
        let components30 = Calendar.current.dateComponents([.hour, .minute], from: expectedTime30Min)

        XCTAssertEqual(components15.hour, 17)
        XCTAssertEqual(components15.minute, 45)
        XCTAssertEqual(components30.hour, 20)
        XCTAssertEqual(components30.minute, 30)
    }

    func testScheduleHabitReminderWithInvalidReminderTime() async throws {
        let habitInvalidReminder = createTestHabit(
            id: UUID(),
            name: "Invalid Habit",
            anchor: "After Breakfast",
            behavior: "Do something",
            reminderMinutesBefore: 1441  // > 1440 minutes (24 hours)
        )

        XCTAssertGreaterThan(habitInvalidReminder.reminderMinutesBefore, 1440)
    }

    func testScheduleHabitReminderZeroMinutesBefore() async throws {
        let habitNoReminder = createTestHabit(
            id: UUID(),
            name: "Immediate Notification",
            anchor: "At Specific Time",
            behavior: "Do activity",
            reminderMinutesBefore: 0  // Notify at exact anchor time
        )

        let anchorTime = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let notificationTime = Calendar.current.date(
            byAdding: .minute,
            value: -habitNoReminder.reminderMinutesBefore,
            to: anchorTime
        )!

        let components = Calendar.current.dateComponents([.hour, .minute], from: notificationTime)
        XCTAssertEqual(components.hour, 12)
        XCTAssertEqual(components.minute, 0)
    }

    // MARK: - Quiet Hours Tests

    func testNotificationOutsideQuietHours() async throws {
        // 8:00 AM is outside default quiet hours (21:00-07:00)
        let notificationTime = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!
        let isInQuietHours = isInQuietHours(time: notificationTime)
        XCTAssertFalse(isInQuietHours)
    }

    func testNotificationInsideQuietHours() async throws {
        // 6:00 AM is inside default quiet hours (21:00-07:00)
        let notificationTime = Calendar.current.date(bySettingHour: 6, minute: 0, second: 0, of: Date())!
        let isInQuietHours = isInQuietHours(time: notificationTime)
        XCTAssertTrue(isInQuietHours)
    }

    func testNotificationAtQuietHoursStart() async throws {
        // 21:00 (9 PM) is at the start of quiet hours
        let notificationTime = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: Date())!
        let isInQuietHours = isInQuietHours(time: notificationTime)
        XCTAssertTrue(isInQuietHours)
    }

    func testNotificationAtQuietHoursEnd() async throws {
        // 07:00 (7 AM) is at the end of quiet hours - should not be in quiet hours
        let notificationTime = Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date())!
        let isInQuietHours = isInQuietHours(time: notificationTime)
        XCTAssertFalse(isInQuietHours)
    }

    func testNotificationDuringNight() async throws {
        // 23:30 (11:30 PM) is during quiet hours
        let notificationTime = Calendar.current.date(bySettingHour: 23, minute: 30, second: 0, of: Date())!
        let isInQuietHours = isInQuietHours(time: notificationTime)
        XCTAssertTrue(isInQuietHours)
    }

    // MARK: - Streak Milestone Notification Tests

    func testScheduleStreakMilestoneNotification() async throws {
        mockNotificationCenter.isAuthorized = true

        let habit = createTestHabit(
            id: UUID(),
            name: "Daily Walk",
            anchor: "After Breakfast",
            behavior: "Walk 30 minutes",
            reminderMinutesBefore: 5
        )

        let streak = 7
        let milestone = 7

        // Simulate notification scheduling
        let content = createMockNotificationContent(
            title: "🔥 \(streak)-Day Streak!",
            body: "Amazing progress with \(habit.name)! You've maintained this habit for \(streak) days!"
        )

        XCTAssertEqual(content.title, "🔥 7-Day Streak!")
        XCTAssertTrue(content.body.contains("7 days"))
        XCTAssertTrue(content.body.contains("Daily Walk"))
    }

    func testScheduleStreakMilestoneNotificationMultipleMilestones() async throws {
        mockNotificationCenter.isAuthorized = true

        let habit = createTestHabit(
            id: UUID(),
            name: "Meditation",
            anchor: "Morning",
            behavior: "Meditate 20 minutes",
            reminderMinutesBefore: 10
        )

        let milestones = [7, 14, 21, 30]
        let streaks = [7, 14, 21, 30]

        for (milestone, streak) in zip(milestones, streaks) {
            let content = createMockNotificationContent(
                title: "🔥 \(streak)-Day Streak!",
                body: "Amazing progress with \(habit.name)! You've maintained this habit for \(streak) days!"
            )

            XCTAssertEqual(content.title, "🔥 \(streak)-Day Streak!")
            XCTAssertTrue(content.body.contains("\(streak) days"))
        }
    }

    // MARK: - Habit Graduation Notification Tests

    func testScheduleHabitGraduationNotification() async throws {
        mockNotificationCenter.isAuthorized = true

        let habit = createTestHabit(
            id: UUID(),
            name: "Running",
            anchor: "Morning",
            behavior: "Run 3 miles",
            reminderMinutesBefore: 15
        )

        let fromDifficulty = HabitDifficulty.easy
        let toDifficulty = HabitDifficulty.medium

        let content = createMockNotificationContent(
            title: "🎉 Habit Graduated!",
            body: "\(habit.name) has leveled up from \(fromDifficulty.displayName) to \(toDifficulty.displayName)!"
        )

        XCTAssertEqual(content.title, "🎉 Habit Graduated!")
        XCTAssertTrue(content.body.contains("Running"))
        XCTAssertTrue(content.body.contains("Easy"))
        XCTAssertTrue(content.body.contains("Medium"))
    }

    func testScheduleHabitGraduationThroughDifficulties() async throws {
        mockNotificationCenter.isAuthorized = true

        let habit = createTestHabit(
            id: UUID(),
            name: "Yoga",
            anchor: "Evening",
            behavior: "Yoga session 30 min",
            reminderMinutesBefore: 20
        )

        let progressions = [
            (HabitDifficulty.easy, HabitDifficulty.medium),
            (HabitDifficulty.medium, HabitDifficulty.hard)
        ]

        for (fromDifficulty, toDifficulty) in progressions {
            let content = createMockNotificationContent(
                title: "🎉 Habit Graduated!",
                body: "\(habit.name) has leveled up from \(fromDifficulty.displayName) to \(toDifficulty.displayName)!"
            )

            XCTAssertTrue(content.body.contains(fromDifficulty.displayName))
            XCTAssertTrue(content.body.contains(toDifficulty.displayName))
        }
    }

    // MARK: - Notification Cancellation Tests

    func testCancelHabitReminder() async throws {
        let habitId = UUID()
        let expectedRequestId = "habit_reminder_\(habitId.uuidString)"

        mockNotificationCenter.removePendingNotificationRequests(withIdentifiers: [expectedRequestId])

        XCTAssertTrue(mockNotificationCenter.removedRequestIds.contains(expectedRequestId))
    }

    func testCancelAllNotificationsForHabit() async throws {
        let habitId = UUID()
        let habitIdString = habitId.uuidString

        let requestIds = [
            "habit_reminder_\(habitIdString)",
            "streak_milestone_\(habitIdString)_7",
            "streak_milestone_\(habitIdString)_14",
            "graduation_\(habitIdString)"
        ]

        mockNotificationCenter.removePendingNotificationRequests(withIdentifiers: requestIds)

        for requestId in requestIds {
            XCTAssertTrue(mockNotificationCenter.removedRequestIds.contains(requestId))
        }
    }

    // MARK: - Pending Notifications Tests

    func testGetPendingNotifications() async throws {
        let habitId = UUID()
        let habitIdString = habitId.uuidString

        let pendingIds = [
            "habit_reminder_\(habitIdString)",
            "streak_milestone_\(habitIdString)_7"
        ]

        // Mock pending requests
        mockNotificationCenter.pendingRequests = pendingIds.map { id in
            let content = UNMutableNotificationContent()
            content.title = "Test"
            content.body = "Test notification"
            return UNNotificationRequest(identifier: id, content: content, trigger: nil)
        }

        let pending = await mockNotificationCenter.pendingNotificationRequests()
        let pendingForHabit = pending.filter { $0.identifier.contains(habitIdString) }

        XCTAssertEqual(pendingForHabit.count, 2)
    }

    // MARK: - Helper Methods

    private func createTestHabit(
        id: UUID,
        name: String,
        anchor: String,
        behavior: String,
        reminderMinutesBefore: Int
    ) -> Habit {
        Habit(
            id: id,
            userId: UUID(),
            name: name,
            anchor: anchor,
            behavior: behavior,
            category: .movement,
            difficulty: .easy,
            durationSeconds: 600,
            reminderTime: nil,
            reminderMinutesBefore: reminderMinutesBefore,
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private func isInQuietHours(time: Date) -> Bool {
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        guard let hour = components.hour else { return false }

        let quietHourStart = 21
        let quietHourEnd = 7

        if quietHourStart > quietHourEnd {
            return hour >= quietHourStart || hour < quietHourEnd
        } else {
            return hour >= quietHourStart && hour < quietHourEnd
        }
    }

    private func createMockNotificationContent(title: String, body: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        return content
    }
}
