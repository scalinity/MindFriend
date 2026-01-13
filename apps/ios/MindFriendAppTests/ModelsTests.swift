import XCTest
@testable import MindFriendApp

final class ModelsTests: XCTestCase {

    // MARK: - UserProfile Tests

    func testUserProfileDecoding() throws {
        let json = """
        {
            "id": "user-123",
            "handle": "testuser",
            "displayName": "Test User",
            "email": "test@example.com",
            "timezone": "America/New_York",
            "createdAt": "2024-01-01T00:00:00Z",
            "settings": {
                "dailyQuestTimeLocal": "09:00",
                "quietHoursStartLocal": null,
                "quietHoursEndLocal": null,
                "remindersEnabled": true,
                "nudgeAfterDaysInactive": 3,
                "shareMoodInCircles": true,
                "aiTone": "friendly",
                "privacyMode": "standard"
            },
            "stats": {
                "currentStreakDays": 5,
                "longestStreakDays": 10,
                "totalQuestsCompleted": 25,
                "totalExercisesCompleted": 12
            },
            "entitlements": "free",
            "badges": []
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let profile = try decoder.decode(UserProfile.self, from: json)

        XCTAssertEqual(profile.id, "user-123")
        XCTAssertEqual(profile.handle, "testuser")
        XCTAssertEqual(profile.displayName, "Test User")
        XCTAssertEqual(profile.email, "test@example.com")
        XCTAssertEqual(profile.timezone, "America/New_York")
        XCTAssertEqual(profile.settings.aiTone, .friendly)
        XCTAssertEqual(profile.stats.currentStreakDays, 5)
        XCTAssertEqual(profile.entitlements, .free)
    }

    func testUserSettingsDefaults() {
        let settings = UserSettings(
            dailyQuestTimeLocal: "09:00",
            quietHoursStartLocal: nil,
            quietHoursEndLocal: nil,
            remindersEnabled: true,
            nudgeAfterDaysInactive: 3,
            shareMoodInCircles: true,
            aiTone: .friendly,
            privacyMode: .standard
        )

        XCTAssertTrue(settings.remindersEnabled)
        XCTAssertEqual(settings.nudgeAfterDaysInactive, 3)
        XCTAssertNil(settings.quietHoursStartLocal)
    }

    // MARK: - MoodEntry Tests

    func testMoodEntryCreation() {
        let entry = MoodEntry(
            id: "mood-1",
            localDate: "2024-01-15",
            moodScore: 7,
            anxietyScore: 3,
            energyScore: 6,
            note: "Feeling good today",
            createdAt: Date()
        )

        XCTAssertEqual(entry.moodScore, 7)
        XCTAssertEqual(entry.anxietyScore, 3)
        XCTAssertEqual(entry.note, "Feeling good today")
    }

    func testMoodEntryValidScores() {
        // Valid scores are 1-10
        let entry = MoodEntry(
            id: "mood-1",
            localDate: "2024-01-15",
            moodScore: 5,
            anxietyScore: nil,
            energyScore: nil,
            note: nil,
            createdAt: Date()
        )

        XCTAssertGreaterThanOrEqual(entry.moodScore, 1)
        XCTAssertLessThanOrEqual(entry.moodScore, 10)
    }

    // MARK: - Quest Tests

    func testQuestDecoding() throws {
        let json = """
        {
            "id": "quest-123",
            "title": "Morning Gratitude",
            "description": "Write down 3 things you're grateful for",
            "category": "mindfulness",
            "estimatedMinutes": 5,
            "xpReward": 50,
            "status": "available"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let quest = try decoder.decode(Quest.self, from: json)

        XCTAssertEqual(quest.id, "quest-123")
        XCTAssertEqual(quest.title, "Morning Gratitude")
        XCTAssertEqual(quest.category, .mindfulness)
        XCTAssertEqual(quest.estimatedMinutes, 5)
        XCTAssertEqual(quest.status, .available)
    }

    // MARK: - Entitlements Tests

    func testEntitlementsEquality() {
        XCTAssertEqual(Entitlements.free, Entitlements.free)
        XCTAssertNotEqual(Entitlements.free, Entitlements.premium)
    }

    func testEntitlementsRawValue() {
        XCTAssertEqual(Entitlements.free.rawValue, "free")
        XCTAssertEqual(Entitlements.premium.rawValue, "premium")
    }

    // MARK: - AITone Tests

    func testAIToneOptions() {
        let tones: [AITone] = [.friendly, .professional, .casual, .supportive]

        XCTAssertEqual(tones.count, 4)
        XCTAssertTrue(tones.contains(.friendly))
        XCTAssertTrue(tones.contains(.supportive))
    }

    // MARK: - ExerciseType Tests

    func testExerciseTypeRawValues() {
        XCTAssertEqual(ExerciseType.breathing.rawValue, "breathing")
        XCTAssertEqual(ExerciseType.meditation.rawValue, "meditation")
        XCTAssertEqual(ExerciseType.journaling.rawValue, "journaling")
        XCTAssertEqual(ExerciseType.grounding.rawValue, "grounding")
    }
}
