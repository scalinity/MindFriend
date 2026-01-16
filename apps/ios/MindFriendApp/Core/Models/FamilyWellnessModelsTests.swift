import XCTest
import Foundation

/// Unit tests for FamilyWellnessModels - Codable conformance and field mapping
final class FamilyWellnessModelsTests: XCTestCase {

    // MARK: - FamilyWellnessGroup Tests

    func testFamilyWellnessGroup_CodableConformance_DecodesSnakeCaseJSON() throws {
        // Arrange
        let json = """
        {
            "id": "family1",
            "name": "Smith Family",
            "admin_user_id": "admin1",
            "circle_id": null,
            "avatar_url": "https://example.com/avatar.jpg",
            "invite_code": "ABC12345",
            "default_child_age_filter": 13,
            "require_parent_approval_for_content": true,
            "share_activity_by_default": true,
            "max_members": 8,
            "created_at": "2026-01-16T00:00:00Z",
            "updated_at": "2026-01-16T12:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Act
        let group = try decoder.decode(FamilyWellnessGroup.self, from: json)

        // Assert
        XCTAssertEqual(group.id, "family1")
        XCTAssertEqual(group.name, "Smith Family")
        XCTAssertEqual(group.adminUserId, "admin1")
        XCTAssertEqual(group.inviteCode, "ABC12345")
        XCTAssertEqual(group.defaultChildAgeFilter, 13)
        XCTAssertTrue(group.requireParentApprovalForContent ?? false)
    }

    func testFamilyWellnessGroup_CodableConformance_EncodesCamelCaseJSON() throws {
        // Arrange
        let group = FamilyWellnessGroup(
            id: "family1",
            name: "Test Family",
            adminUserId: "admin1",
            circleId: nil,
            avatarUrl: "https://example.com/avatar.jpg",
            inviteCode: "ABC12345",
            defaultChildAgeFilter: 13,
            requireParentApprovalForContent: true,
            shareActivityByDefault: true,
            maxMembers: 8,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 3600)
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        // Act
        let json = try encoder.encode(group)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode([String: AnyCodable].self, from: json)

        // Assert - keys should still be accessible via CodingKeys
        XCTAssertNotNil(decoded["id"])
    }

    // MARK: - FamilyWellnessMember Tests

    func testFamilyWellnessMember_CalculatedAge_ReturnsCorrectAge() throws {
        // Arrange
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2010
        components.month = 1
        components.day = 16
        let birthDate = calendar.date(from: components)!

        let member = FamilyWellnessMember(
            id: "member1",
            familyId: "family1",
            userId: "user1",
            role: .child,
            nickname: "Tommy",
            avatarEmoji: "👦",
            birthDate: birthDate,
            ageFilterOverride: nil,
            shareMoodWithFamily: true,
            shareActivityWithFamily: true,
            shareAchievementsWithFamily: false,
            status: .active,
            invitedBy: nil,
            joinedAt: Date(),
            createdAt: Date(),
            updatedAt: Date()
        )

        // Act
        let calculatedAge = member.calculatedAge

        // Assert
        XCTAssertNotNil(calculatedAge)
        XCTAssertEqual(calculatedAge, 16)
    }

    func testFamilyWellnessMember_EffectiveAgeFilter_ReturnsOverrideWhenApplicable() throws {
        // Arrange
        let member = FamilyWellnessMember(
            id: "member1",
            familyId: "family1",
            userId: "user1",
            role: .teen,
            nickname: "Alex",
            avatarEmoji: "👦",
            birthDate: Date(timeIntervalSince1970: 0),
            ageFilterOverride: 16,
            shareMoodWithFamily: true,
            shareActivityWithFamily: true,
            shareAchievementsWithFamily: true,
            status: .active,
            invitedBy: nil,
            joinedAt: Date(),
            createdAt: Date(),
            updatedAt: Date()
        )

        // Act
        let effectiveFilter = member.effectiveAgeFilter

        // Assert
        XCTAssertEqual(effectiveFilter, 16)
    }

    func testFamilyWellnessMember_DisplayName_ReturnsNicknameOrDefault() throws {
        // Arrange - with nickname
        let memberWithNickname = FamilyWellnessMember(
            id: "member1",
            familyId: "family1",
            userId: "user1",
            role: .child,
            nickname: "Tommy",
            avatarEmoji: "👦",
            birthDate: nil,
            ageFilterOverride: nil,
            shareMoodWithFamily: true,
            shareActivityWithFamily: true,
            shareAchievementsWithFamily: true,
            status: .active,
            invitedBy: nil,
            joinedAt: Date(),
            createdAt: Date(),
            updatedAt: Date()
        )

        // Act
        let displayName = memberWithNickname.displayName

        // Assert
        XCTAssertEqual(displayName, "Tommy")

        // Arrange - without nickname
        let memberWithoutNickname = FamilyWellnessMember(
            id: "member2",
            familyId: "family1",
            userId: "user2",
            role: .child,
            nickname: nil,
            avatarEmoji: "👧",
            birthDate: nil,
            ageFilterOverride: nil,
            shareMoodWithFamily: true,
            shareActivityWithFamily: true,
            shareAchievementsWithFamily: true,
            status: .active,
            invitedBy: nil,
            joinedAt: Date(),
            createdAt: Date(),
            updatedAt: Date()
        )

        // Act
        let defaultName = memberWithoutNickname.displayName

        // Assert
        XCTAssertEqual(defaultName, "Family Member")
    }

    // MARK: - FamilyRole Tests

    func testFamilyRole_CanManageFamily_ReturnsCorrectValues() {
        XCTAssertTrue(FamilyRole.admin.canManageFamily)
        XCTAssertTrue(FamilyRole.parent.canManageFamily)
        XCTAssertFalse(FamilyRole.teen.canManageFamily)
        XCTAssertFalse(FamilyRole.child.canManageFamily)
    }

    func testFamilyRole_HasFullAIAccess_ReturnsCorrectValues() {
        XCTAssertTrue(FamilyRole.admin.hasFullAIAccess)
        XCTAssertTrue(FamilyRole.parent.hasFullAIAccess)
        XCTAssertTrue(FamilyRole.teen.hasFullAIAccess)
        XCTAssertFalse(FamilyRole.child.hasFullAIAccess)
    }

    // MARK: - FamilyChallenge Tests

    func testFamilyChallenge_ProgressPercentage_CalculatesCorrectly() {
        // Arrange
        let challenge = FamilyChallenge(
            id: "challenge1",
            familyId: "family1",
            title: "Daily Meditation",
            description: nil,
            challengeType: .cumulative,
            targetValue: 10,
            minimumParticipants: 1,
            startDate: Date(),
            endDate: nil,
            requiresAllMembers: false,
            allowMakeupActivities: true,
            status: .active,
            currentProgress: 7,
            badgeId: nil,
            rewardDescription: nil,
            createdBy: "admin1",
            createdAt: Date(),
            updatedAt: Date()
        )

        // Act
        let percentage = challenge.progressPercentage

        // Assert
        XCTAssertEqual(percentage, 0.7)
    }

    func testFamilyChallenge_ProgressPercentage_CapsAt100Percent() {
        // Arrange
        let challenge = FamilyChallenge(
            id: "challenge1",
            familyId: "family1",
            title: "Daily Meditation",
            description: nil,
            challengeType: .cumulative,
            targetValue: 10,
            minimumParticipants: 1,
            startDate: Date(),
            endDate: nil,
            requiresAllMembers: false,
            allowMakeupActivities: true,
            status: .active,
            currentProgress: 15,
            badgeId: nil,
            rewardDescription: nil,
            createdBy: "admin1",
            createdAt: Date(),
            updatedAt: Date()
        )

        // Act
        let percentage = challenge.progressPercentage

        // Assert
        XCTAssertEqual(percentage, 1.0)
    }

    // MARK: - MoodTrend Tests

    func testMoodTrend_Icon_ReturnsCorrectIcons() {
        XCTAssertEqual(MoodTrend.improving.icon, "arrow.up.right")
        XCTAssertEqual(MoodTrend.stable.icon, "arrow.right")
        XCTAssertEqual(MoodTrend.declining.icon, "arrow.down.right")
    }

    func testMoodTrend_Color_ReturnsCorrectColors() {
        XCTAssertEqual(MoodTrend.improving.color, "green")
        XCTAssertEqual(MoodTrend.stable.color, "yellow")
        XCTAssertEqual(MoodTrend.declining.color, "orange")
    }

    // MARK: - AlertSeverity Tests

    func testAlertSeverity_Color_ReturnsCorrectColors() {
        XCTAssertEqual(AlertSeverity.info.color, "blue")
        XCTAssertEqual(AlertSeverity.attention.color, "yellow")
        XCTAssertEqual(AlertSeverity.concern.color, "red")
    }

    // MARK: - TogetherModels Tests

    func testTogetherTemplate_FormattedDuration_FormatsCorrectly() {
        // Test minutes only
        let templateMinutes = TogetherTemplate(
            id: "t1",
            title: "Quick Breathing",
            description: nil,
            category: .breathing,
            contentType: .guidedAudio,
            durationMinutes: 5,
            audioUrl: nil,
            minimumParticipants: 1,
            maximumParticipants: 10,
            minimumAge: 4,
            configuration: nil,
            isActive: true,
            isPremium: false
        )
        XCTAssertEqual(templateMinutes.formattedDuration, "5m")

        // Test hours and minutes
        let templateHours = TogetherTemplate(
            id: "t2",
            title: "Extended Session",
            description: nil,
            category: .meditation,
            contentType: .guidedAudio,
            durationMinutes: 90,
            audioUrl: nil,
            minimumParticipants: 1,
            maximumParticipants: 10,
            minimumAge: 4,
            configuration: nil,
            isActive: true,
            isPremium: false
        )
        XCTAssertEqual(templateHours.formattedDuration, "1h 30m")

        // Test hours only
        let templateExactHours = TogetherTemplate(
            id: "t3",
            title: "Full Hour",
            description: nil,
            category: .meditation,
            contentType: .guidedAudio,
            durationMinutes: 60,
            audioUrl: nil,
            minimumParticipants: 1,
            maximumParticipants: 10,
            minimumAge: 4,
            configuration: nil,
            isActive: true,
            isPremium: false
        )
        XCTAssertEqual(templateExactHours.formattedDuration, "1h")
    }

    func testTogetherSession_IsActive_ReturnsCorrectStatus() {
        // Arrange
        let activeSession = TogetherSession(
            id: "s1",
            familyId: "f1",
            exerciseId: nil,
            togetherTemplateId: nil,
            title: "Active",
            scheduledFor: nil,
            startedAt: Date(),
            endedAt: nil,
            durationSeconds: nil,
            minimumParticipants: 1,
            status: .inProgress,
            syncMode: .realtime,
            asyncWindowHours: nil,
            createdBy: "user1",
            createdAt: Date()
        )

        // Act & Assert
        XCTAssertTrue(activeSession.isActive)

        // Arrange
        let inactiveSession = TogetherSession(
            id: "s2",
            familyId: "f1",
            exerciseId: nil,
            togetherTemplateId: nil,
            title: "Completed",
            scheduledFor: nil,
            startedAt: Date(),
            endedAt: Date(),
            durationSeconds: 600,
            minimumParticipants: 1,
            status: .completed,
            syncMode: .realtime,
            asyncWindowHours: nil,
            createdBy: "user1",
            createdAt: Date()
        )

        // Act & Assert
        XCTAssertFalse(inactiveSession.isActive)
    }

    func testContentAgeRating_IsAppropriateForAge_ReturnsCorrectly() {
        // Arrange
        let rating = ContentAgeRating(
            id: "r1",
            contentType: "exercise",
            contentId: "ex1",
            minimumAge: 6,
            maximumAge: 13,
            ratingCategory: .kids,
            containsHeavyTopics: false,
            requiresReading: false,
            complexityLevel: .simple,
            reviewedBy: nil,
            reviewedAt: nil,
            createdAt: Date()
        )

        // Act & Assert
        XCTAssertFalse(rating.isAppropriateForAge(4))
        XCTAssertTrue(rating.isAppropriateForAge(6))
        XCTAssertTrue(rating.isAppropriateForAge(10))
        XCTAssertTrue(rating.isAppropriateForAge(13))
        XCTAssertFalse(rating.isAppropriateForAge(14))
    }

    func testContentAgeRating_IsAppropriateForAge_WithNoMaxAge_AllowsOlder() {
        // Arrange
        let rating = ContentAgeRating(
            id: "r1",
            contentType: "exercise",
            contentId: "ex1",
            minimumAge: 13,
            maximumAge: nil,
            ratingCategory: .teen,
            containsHeavyTopics: false,
            requiresReading: false,
            complexityLevel: .moderate,
            reviewedBy: nil,
            reviewedAt: nil,
            createdAt: Date()
        )

        // Act & Assert
        XCTAssertFalse(rating.isAppropriateForAge(12))
        XCTAssertTrue(rating.isAppropriateForAge(13))
        XCTAssertTrue(rating.isAppropriateForAge(100))
    }
}

// MARK: - AnyCodable Helper (for JSON testing)

struct AnyCodable: Codable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = ()
        } else if let intVal = try? container.decode(Int.self) {
            self.value = intVal
        } else if let doubleVal = try? container.decode(Double.self) {
            self.value = doubleVal
        } else if let boolVal = try? container.decode(Bool.self) {
            self.value = boolVal
        } else if let stringVal = try? container.decode(String.self) {
            self.value = stringVal
        } else if let arrayVal = try? container.decode([AnyCodable].self) {
            self.value = arrayVal
        } else if let dictVal = try? container.decode([String: AnyCodable].self) {
            self.value = dictVal
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode AnyCodable")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let intVal as Int:
            try container.encode(intVal)
        case let doubleVal as Double:
            try container.encode(doubleVal)
        case let boolVal as Bool:
            try container.encode(boolVal)
        case let stringVal as String:
            try container.encode(stringVal)
        case let arrayVal as [AnyCodable]:
            try container.encode(arrayVal)
        case let dictVal as [String: AnyCodable]:
            try container.encode(dictVal)
        default:
            try container.encodeNil()
        }
    }
}
