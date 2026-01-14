import XCTest
@testable import MindFriendApp

final class NotificationTests: XCTestCase {

    // MARK: - Deep Link URL Parsing Tests

    @MainActor
    func testParseDeepLinkUrl_CircleWithId() {
        let manager = NotificationManager()
        let result = manager.parseDeepLinkUrl("mindfriend://circle/abc-123")

        if case .circle(let id) = result {
            XCTAssertEqual(id, "abc-123")
        } else {
            XCTFail("Expected .circle deep link, got \(result)")
        }
    }

    @MainActor
    func testParseDeepLinkUrl_QuestWithId() {
        let manager = NotificationManager()
        let result = manager.parseDeepLinkUrl("mindfriend://quest/quest-456")

        if case .quest(let id) = result {
            XCTAssertEqual(id, "quest-456")
        } else {
            XCTFail("Expected .quest deep link, got \(result)")
        }
    }

    @MainActor
    func testParseDeepLinkUrl_QuestWithoutId() {
        let manager = NotificationManager()
        let result = manager.parseDeepLinkUrl("mindfriend://quest")

        if case .quest(let id) = result {
            XCTAssertNil(id)
        } else {
            XCTFail("Expected .quest deep link, got \(result)")
        }
    }

    @MainActor
    func testParseDeepLinkUrl_ChatWithConversationId() {
        let manager = NotificationManager()
        let result = manager.parseDeepLinkUrl("mindfriend://chat/conv-789")

        if case .chat(let conversationId) = result {
            XCTAssertEqual(conversationId, "conv-789")
        } else {
            XCTFail("Expected .chat deep link, got \(result)")
        }
    }

    @MainActor
    func testParseDeepLinkUrl_Insights() {
        let manager = NotificationManager()
        let result = manager.parseDeepLinkUrl("mindfriend://insights")

        if case .insights = result {
            // Success
        } else {
            XCTFail("Expected .insights deep link, got \(result)")
        }
    }

    @MainActor
    func testParseDeepLinkUrl_Mood() {
        let manager = NotificationManager()
        let result = manager.parseDeepLinkUrl("mindfriend://mood")

        if case .mood = result {
            // Success
        } else {
            XCTFail("Expected .mood deep link, got \(result)")
        }
    }

    @MainActor
    func testParseDeepLinkUrl_Settings() {
        let manager = NotificationManager()
        let result = manager.parseDeepLinkUrl("mindfriend://settings")

        if case .settings = result {
            // Success
        } else {
            XCTFail("Expected .settings deep link, got \(result)")
        }
    }

    @MainActor
    func testParseDeepLinkUrl_InvalidScheme() {
        let manager = NotificationManager()
        let result = manager.parseDeepLinkUrl("https://example.com/circle/123")

        if case .none = result {
            // Success - invalid scheme should return .none
        } else {
            XCTFail("Expected .none for invalid scheme, got \(result)")
        }
    }

    @MainActor
    func testParseDeepLinkUrl_EmptyUrl() {
        let manager = NotificationManager()
        let result = manager.parseDeepLinkUrl("")

        if case .none = result {
            // Success
        } else {
            XCTFail("Expected .none for empty URL, got \(result)")
        }
    }

    @MainActor
    func testParseDeepLinkUrl_MalformedUrl() {
        let manager = NotificationManager()
        let result = manager.parseDeepLinkUrl("not a valid url")

        if case .none = result {
            // Success
        } else {
            XCTFail("Expected .none for malformed URL, got \(result)")
        }
    }

    @MainActor
    func testParseDeepLinkUrl_UnknownPath() {
        let manager = NotificationManager()
        let result = manager.parseDeepLinkUrl("mindfriend://unknown/path")

        if case .none = result {
            // Success - unknown paths should return .none
        } else {
            XCTFail("Expected .none for unknown path, got \(result)")
        }
    }

    @MainActor
    func testParseDeepLinkUrl_BaseUrl() {
        let manager = NotificationManager()
        let result = manager.parseDeepLinkUrl("mindfriend://")

        if case .none = result {
            // Success - base URL with no path should return .none
        } else {
            XCTFail("Expected .none for base URL, got \(result)")
        }
    }

    // MARK: - NotificationType Tests

    func testNotificationTypeRawValues() {
        XCTAssertEqual(NotificationType.dailyQuest.rawValue, "daily_quest")
        XCTAssertEqual(NotificationType.questReminder.rawValue, "quest_reminder")
        XCTAssertEqual(NotificationType.streakReminder.rawValue, "streak_reminder")
        XCTAssertEqual(NotificationType.circleActivity.rawValue, "circle_activity")
        XCTAssertEqual(NotificationType.chatMessage.rawValue, "chat_message")
        XCTAssertEqual(NotificationType.systemMessage.rawValue, "system_message")
        // Smart notification types
        XCTAssertEqual(NotificationType.hug.rawValue, "hug")
        XCTAssertEqual(NotificationType.streakRisk.rawValue, "streak_risk")
        XCTAssertEqual(NotificationType.weeklySummary.rawValue, "weekly_summary")
        XCTAssertEqual(NotificationType.challenge.rawValue, "challenge")
    }

    func testNotificationTypeFromRawValue() {
        XCTAssertEqual(NotificationType(rawValue: "hug"), .hug)
        XCTAssertEqual(NotificationType(rawValue: "weekly_summary"), .weeklySummary)
        XCTAssertEqual(NotificationType(rawValue: "streak_risk"), .streakRisk)
        XCTAssertEqual(NotificationType(rawValue: "challenge"), .challenge)
        XCTAssertNil(NotificationType(rawValue: "invalid_type"))
    }

    // MARK: - NotificationDeepLink Tests

    func testNotificationDeepLinkEquality() {
        // Test circle
        let circle1 = NotificationDeepLink.circle(id: "123")
        let circle2 = NotificationDeepLink.circle(id: "123")
        let circle3 = NotificationDeepLink.circle(id: "456")

        XCTAssertEqual(circle1.description, circle2.description)
        XCTAssertNotEqual(circle1.description, circle3.description)

        // Test quest
        let quest1 = NotificationDeepLink.quest(id: "q1")
        let quest2 = NotificationDeepLink.quest(id: nil)

        XCTAssertNotEqual(quest1.description, quest2.description)

        // Test other types
        let insights = NotificationDeepLink.insights
        let mood = NotificationDeepLink.mood

        XCTAssertNotEqual(insights.description, mood.description)
    }

    // MARK: - Week Start Calculation Tests

    func testWeekStartCalculation_Monday() {
        // Test that we correctly calculate Monday as week start
        let calendar = Calendar.current

        // Create a known Wednesday (Jan 15, 2025 is a Wednesday)
        var components = DateComponents()
        components.year = 2025
        components.month = 1
        components.day = 15
        components.hour = 12
        let wednesday = calendar.date(from: components)!

        // Calculate week start (should be Monday Jan 13)
        let weekday = calendar.component(.weekday, from: wednesday)
        // weekday 1 = Sunday, 2 = Monday, 3 = Tuesday, 4 = Wednesday, etc.
        let daysFromMonday = (weekday == 1) ? 6 : weekday - 2

        XCTAssertEqual(daysFromMonday, 2) // Wednesday is 2 days after Monday

        let weekStart = calendar.date(byAdding: .day, value: -daysFromMonday, to: wednesday)!
        let weekStartDay = calendar.component(.day, from: weekStart)
        let weekStartWeekday = calendar.component(.weekday, from: weekStart)

        XCTAssertEqual(weekStartDay, 13)     // Jan 13
        XCTAssertEqual(weekStartWeekday, 2)   // Monday
    }

    func testWeekStartCalculation_Sunday() {
        // Test Sunday edge case (should go back to previous Monday)
        let calendar = Calendar.current

        // Create a known Sunday (Jan 19, 2025 is a Sunday)
        var components = DateComponents()
        components.year = 2025
        components.month = 1
        components.day = 19
        components.hour = 12
        let sunday = calendar.date(from: components)!

        // Calculate week start
        let weekday = calendar.component(.weekday, from: sunday)
        XCTAssertEqual(weekday, 1) // Verify it's Sunday

        let daysFromMonday = (weekday == 1) ? 6 : weekday - 2
        XCTAssertEqual(daysFromMonday, 6) // Sunday is 6 days after Monday

        let weekStart = calendar.date(byAdding: .day, value: -daysFromMonday, to: sunday)!
        let weekStartDay = calendar.component(.day, from: weekStart)
        let weekStartWeekday = calendar.component(.weekday, from: weekStart)

        XCTAssertEqual(weekStartDay, 13)     // Jan 13
        XCTAssertEqual(weekStartWeekday, 2)   // Monday
    }

    func testWeekStartCalculation_Monday_NoChange() {
        // Test Monday should stay on same day
        let calendar = Calendar.current

        // Create a known Monday (Jan 13, 2025 is a Monday)
        var components = DateComponents()
        components.year = 2025
        components.month = 1
        components.day = 13
        components.hour = 12
        let monday = calendar.date(from: components)!

        let weekday = calendar.component(.weekday, from: monday)
        XCTAssertEqual(weekday, 2) // Verify it's Monday

        let daysFromMonday = (weekday == 1) ? 6 : weekday - 2
        XCTAssertEqual(daysFromMonday, 0) // Monday is 0 days from Monday

        let weekStart = calendar.date(byAdding: .day, value: -daysFromMonday, to: monday)!
        let weekStartDay = calendar.component(.day, from: weekStart)

        XCTAssertEqual(weekStartDay, 13) // Should stay on Jan 13
    }

    // MARK: - WeeklySummary Model Tests

    func testWeeklySummaryDecoding() throws {
        let json = """
        {
            "id": "summary-123",
            "userId": "user-456",
            "weekStart": "2025-01-13",
            "checkinCount": 5,
            "questCount": 7,
            "exerciseCount": 3,
            "avgMood": 7.5,
            "moodTrend": "improving",
            "generatedAt": "2025-01-19T18:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let summary = try decoder.decode(WeeklySummary.self, from: json)

        XCTAssertEqual(summary.id, "summary-123")
        XCTAssertEqual(summary.userId, "user-456")
        XCTAssertEqual(summary.weekStart, "2025-01-13")
        XCTAssertEqual(summary.checkinCount, 5)
        XCTAssertEqual(summary.questCount, 7)
        XCTAssertEqual(summary.exerciseCount, 3)
        XCTAssertEqual(summary.avgMood, 7.5)
        XCTAssertEqual(summary.moodTrend, .improving)
    }

    func testWeeklySummaryWithNilValues() throws {
        let json = """
        {
            "id": "summary-123",
            "userId": "user-456",
            "weekStart": "2025-01-13",
            "checkinCount": 0,
            "questCount": 0,
            "exerciseCount": 0,
            "avgMood": null,
            "moodTrend": null,
            "generatedAt": "2025-01-19T18:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let summary = try decoder.decode(WeeklySummary.self, from: json)

        XCTAssertEqual(summary.checkinCount, 0)
        XCTAssertNil(summary.avgMood)
        XCTAssertNil(summary.moodTrend)
    }

    // MARK: - MoodTrend Tests

    func testMoodTrendRawValues() {
        XCTAssertEqual(MoodTrend.improving.rawValue, "improving")
        XCTAssertEqual(MoodTrend.stable.rawValue, "stable")
        XCTAssertEqual(MoodTrend.declining.rawValue, "declining")
    }

    func testMoodTrendFromRawValue() {
        XCTAssertEqual(MoodTrend(rawValue: "improving"), .improving)
        XCTAssertEqual(MoodTrend(rawValue: "stable"), .stable)
        XCTAssertEqual(MoodTrend(rawValue: "declining"), .declining)
        XCTAssertNil(MoodTrend(rawValue: "unknown"))
    }

    // MARK: - UUID Validation Tests (markNotificationOpened)

    func testUUIDValidation() {
        // Valid UUID
        let validUUID = "550e8400-e29b-41d4-a716-446655440000"
        XCTAssertNotNil(UUID(uuidString: validUUID))

        // Invalid UUIDs
        XCTAssertNil(UUID(uuidString: "not-a-uuid"))
        XCTAssertNil(UUID(uuidString: ""))
        XCTAssertNil(UUID(uuidString: "123"))
        XCTAssertNil(UUID(uuidString: "550e8400-e29b-41d4-a716")) // Too short

        // UUID without hyphens is NOT valid in Swift's UUID initializer
        let noHyphens = "550e8400e29b41d4a716446655440000"
        XCTAssertNil(UUID(uuidString: noHyphens)) // Swift UUID requires hyphens
    }
}

// MARK: - NotificationDeepLink Description Extension (for testing)

extension NotificationDeepLink: CustomStringConvertible {
    public var description: String {
        switch self {
        case .quest(let id):
            return "quest(\(id ?? "nil"))"
        case .chat(let conversationId):
            return "chat(\(conversationId))"
        case .circle(let id):
            return "circle(\(id))"
        case .mood:
            return "mood"
        case .settings:
            return "settings"
        case .insights:
            return "insights"
        case .none:
            return "none"
        }
    }
}
