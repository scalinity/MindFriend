import XCTest
import Foundation
@testable import MindFriendApp

/// Unit tests for FamilyService
@MainActor
final class FamilyServiceTests: XCTestCase {
    var sut: FamilyService!
    var mockSupabase: MockFamilySupabaseClient!

    override func setUp() {
        super.setUp()
        mockSupabase = MockFamilySupabaseClient()
        sut = FamilyService(supabase: mockSupabase)
    }

    override func tearDown() {
        sut = nil
        mockSupabase = nil
        super.tearDown()
    }

    // MARK: - Family Group Tests

    func testFetchFamilyGroup_WithValidUser_ReturnsFamilyGroup() async throws {
        // Arrange
        let expectedFamily = FamilyWellnessGroup(
            id: "family1",
            name: "Test Family",
            adminUserId: "admin1",
            circleId: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        mockSupabase.mockFamilyGroups = [expectedFamily]

        // Act
        let result = try await sut.fetchFamilyGroup()

        // Assert
        XCTAssertEqual(result?.id, expectedFamily.id)
        XCTAssertEqual(result?.name, expectedFamily.name)
    }

    func testFetchFamilyGroup_WithNoUser_ReturnsNil() async throws {
        // Arrange
        mockSupabase.mockCurrentUser = nil

        // Act
        let result = try await sut.fetchFamilyGroup()

        // Assert
        XCTAssertNil(result)
    }

    func testCreateFamily_WithValidData_CreatesAndReturnsFamily() async throws {
        // Arrange
        let familyName = "New Family"
        let defaultAgeFilter = 13
        let maxMembers = 8

        // Act
        let result = try await sut.createFamily(
            name: familyName,
            defaultChildAgeFilter: defaultAgeFilter,
            maxMembers: maxMembers
        )

        // Assert
        XCTAssertEqual(result.name, familyName)
        XCTAssertEqual(result.defaultChildAgeFilter, defaultAgeFilter)
        XCTAssertEqual(result.maxMembers, maxMembers)
        XCTAssertNotNil(result.inviteCode)
        XCTAssertEqual(result.inviteCode?.count, 8)
    }

    // MARK: - Family Member Tests

    func testFetchFamilyMembers_WithActiveMembers_ReturnsMembers() async throws {
        // Arrange
        let members = [
            FamilyWellnessMember(
                id: "member1",
                familyId: "family1",
                userId: "user1",
                role: .admin,
                nickname: "Parent",
                avatarEmoji: "👨",
                birthDate: Date(timeIntervalSince1970: 0),
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
        ]
        mockSupabase.mockMembers = members

        // Act
        let result = try await sut.fetchFamilyMembers()

        // Assert
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].role, .admin)
        XCTAssertEqual(result[0].nickname, "Parent")
    }

    func testUpdateMemberSettings_WithValidData_UpdatesSuccessfully() async throws {
        // Arrange
        let memberId = "member1"
        let newNickname = "Updated Name"

        // Act
        try await sut.updateMemberSettings(
            memberId: memberId,
            nickname: newNickname
        )

        // Assert
        XCTAssertTrue(mockSupabase.updateMemberCalled)
    }

    // MARK: - Challenge Tests

    func testFetchChallenges_ReturnsChallenges() async throws {
        // Arrange
        let challenges = [
            FamilyChallenge(
                id: "challenge1",
                familyId: "family1",
                title: "Daily Meditation",
                description: "Meditate for 10 minutes daily",
                challengeType: .streak,
                targetValue: 7,
                minimumParticipants: 1,
                startDate: Date(),
                endDate: Date().addingTimeInterval(86400 * 7),
                requiresAllMembers: false,
                allowMakeupActivities: true,
                status: .active,
                currentProgress: 3,
                badgeId: nil,
                rewardDescription: nil,
                createdBy: "admin1",
                createdAt: Date(),
                updatedAt: Date()
            )
        ]
        mockSupabase.mockChallenges = challenges

        // Act
        let result = try await sut.fetchChallenges()

        // Assert
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].title, "Daily Meditation")
        XCTAssertEqual(result[0].status, .active)
    }

    func testCreateChallenge_WithValidData_CreatesChallenge() async throws {
        // Arrange
        let title = "New Challenge"
        let targetValue = 10

        // Act
        let result = try await sut.createChallenge(
            title: title,
            challengeType: .cumulative,
            targetValue: targetValue
        )

        // Assert
        XCTAssertEqual(result.title, title)
        XCTAssertEqual(result.targetValue, targetValue)
        XCTAssertEqual(result.status, .active)
    }

    func testUpdateChallengeProgress_WithValidProgress_Updates() async throws {
        // Arrange
        let challengeId = "challenge1"
        let newProgress = 5

        // Act
        try await sut.updateChallengeProgress(
            challengeId: challengeId,
            progress: newProgress
        )

        // Assert
        XCTAssertTrue(mockSupabase.updateChallengeCalled)
    }

    // MARK: - Together Session Tests

    func testFetchTogetherSessions_ReturnsSessions() async throws {
        // Arrange
        let sessions = [
            TogetherSession(
                id: "session1",
                familyId: "family1",
                exerciseId: nil,
                togetherTemplateId: "template1",
                title: "Family Meditation",
                scheduledFor: nil,
                startedAt: Date(),
                endedAt: nil,
                durationSeconds: 600,
                minimumParticipants: 1,
                status: .inProgress,
                syncMode: .realtime,
                asyncWindowHours: nil,
                createdBy: "user1",
                createdAt: Date()
            )
        ]
        mockSupabase.mockSessions = sessions

        // Act
        let result = try await sut.fetchTogetherSessions()

        // Assert
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].title, "Family Meditation")
        XCTAssertEqual(result[0].status, .inProgress)
    }

    func testFetchTogetherTemplates_ReturnsTemplates() async throws {
        // Arrange
        let templates = [
            TogetherTemplate(
                id: "template1",
                title: "Guided Meditation",
                description: "10-minute guided meditation",
                category: .meditation,
                contentType: .guidedAudio,
                durationMinutes: 10,
                audioUrl: nil,
                minimumParticipants: 1,
                maximumParticipants: 10,
                minimumAge: 4,
                configuration: nil,
                isActive: true,
                isPremium: false
            )
        ]
        mockSupabase.mockTemplates = templates

        // Act
        let result = try await sut.fetchTogetherTemplates()

        // Assert
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].category, .meditation)
    }

    // MARK: - Alert Tests

    func testFetchFamilyAlerts_ReturnsAlerts() async throws {
        // Arrange
        let alerts = [
            FamilyAlert(
                id: "alert1",
                familyId: "family1",
                aboutMemberId: "member1",
                forParentId: "parent1",
                alertType: .inactivity,
                severity: .attention,
                title: "Activity Reminder",
                message: "Child has not been active for 3 days",
                actionType: .checkIn,
                actionData: nil,
                conversationStarters: ["How are you feeling?"],
                wasRead: false,
                wasActedUpon: false,
                readAt: nil,
                expiresAt: Date().addingTimeInterval(86400 * 7),
                createdAt: Date()
            )
        ]
        mockSupabase.mockAlerts = alerts

        // Act
        let result = try await sut.fetchFamilyAlerts()

        // Assert
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].alertType, .inactivity)
        XCTAssertFalse(result[0].wasRead)
    }

    func testMarkAlertAsRead_WithValidAlert_MarksAsRead() async throws {
        // Arrange
        let alertId = "alert1"

        // Act
        try await sut.markAlertAsRead(alertId: alertId)

        // Assert
        XCTAssertTrue(mockSupabase.markAlertReadCalled)
    }

    // MARK: - Parental Consent Tests

    func testRequestParentalConsent_WithValidData_CreatesConsent() async throws {
        // Arrange
        let childUserId = "child1"
        let parentEmail = "parent@example.com"

        // Act
        let result = try await sut.requestParentalConsent(
            childUserId: childUserId,
            parentEmail: parentEmail
        )

        // Assert
        XCTAssertEqual(result.childUserId, childUserId)
        XCTAssertEqual(result.parentEmail, parentEmail)
        XCTAssertEqual(result.consentType, .initial)
    }

    // MARK: - Helper Tests

    func testGenerateInviteCode_GeneratesValidCode() {
        // Act
        let code = sut.generateInviteCode()

        // Assert
        XCTAssertEqual(code.count, 8)
        XCTAssertTrue(code.allSatisfy { $0.isLetter || $0.isNumber })
    }
}

// MARK: - Mock Objects

class MockFamilySupabaseClient {
    var mockCurrentUser: Any?
    var mockFamilyGroups: [FamilyWellnessGroup] = []
    var mockMembers: [FamilyWellnessMember] = []
    var mockChallenges: [FamilyChallenge] = []
    var mockSessions: [TogetherSession] = []
    var mockTemplates: [TogetherTemplate] = []
    var mockAlerts: [FamilyAlert] = []

    var updateMemberCalled = false
    var updateChallengeCalled = false
    var markAlertReadCalled = false

    var auth: MockAuthClient { MockAuthClient() }

    func mockQuery<T>(for table: String) -> [T] {
        switch table {
        case "family_groups": return mockFamilyGroups as? [T] ?? []
        case "family_members": return mockMembers as? [T] ?? []
        case "family_challenges": return mockChallenges as? [T] ?? []
        case "together_sessions": return mockSessions as? [T] ?? []
        case "together_templates": return mockTemplates as? [T] ?? []
        case "family_alerts": return mockAlerts as? [T] ?? []
        default: return []
        }
    }
}

class MockAuthClient {
    let currentUser = MockUser()
}

class MockUser {
    let id = UUID().uuidString
}
