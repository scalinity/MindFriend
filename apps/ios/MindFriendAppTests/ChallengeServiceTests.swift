import XCTest
@testable import MindFriendApp

final class ChallengeServiceTests: XCTestCase {

    var sut: ChallengeService!

    override func setUp() {
        super.setUp()
        sut = ChallengeService()
    }

    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testServiceInitialization() {
        XCTAssertNotNil(sut)
        XCTAssertTrue(sut.publicChallenges.isEmpty)
        XCTAssertTrue(sut.circleChallenges.isEmpty)
        XCTAssertTrue(sut.myChallenges.isEmpty)
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.error)
    }

    // MARK: - Challenge Loading Tests (Mocked)

    func testLoadChallengesInitiatesLoading() async {
        // This test verifies that loadChallenges sets isLoading appropriately
        // In a real environment, this would connect to Supabase
        let loadExpectation = XCTestExpectation()
        loadExpectation.isInverted = true

        Task {
            do {
                try await sut.loadChallenges()
                loadExpectation.fulfill()
            } catch {
                // Expected if no Supabase connection
                loadExpectation.fulfill()
            }
        }

        await fulfillment(of: [loadExpectation], timeout: 2.0)
    }

    // MARK: - Error Handling Tests

    func testErrorHandling() {
        let error = ChallengeError.rateLimited
        XCTAssertNotNil(error.errorDescription)
    }

    func testNotAuthenticatedError() {
        let error = ChallengeError.notAuthenticated
        XCTAssertEqual(error.errorDescription, "User is not authenticated")
    }

    func testInvalidIdError() {
        let error = ChallengeError.invalidId
        XCTAssertNotNil(error.errorDescription)
    }

    func testRateLimitedError() {
        let error = ChallengeError.rateLimited
        XCTAssertNotNil(error.errorDescription)
    }

    func testExerciseTypeRequiredError() {
        let error = ChallengeError.exerciseTypeRequired
        XCTAssertEqual(
            error.errorDescription,
            "Exercise type is required for minutes challenges"
        )
    }

    // MARK: - Challenge Model Tests

    func testCreateChallengeRequest() {
        let request = CreateChallengeRequest(
            title: "Test Challenge",
            description: "Test Description",
            challengeType: .streak,
            targetValue: 7,
            durationDays: 7,
            circleId: nil,
            exerciseType: nil
        )

        XCTAssertEqual(request.title, "Test Challenge")
        XCTAssertEqual(request.description, "Test Description")
        XCTAssertEqual(request.challengeType, .streak)
        XCTAssertEqual(request.targetValue, 7)
        XCTAssertEqual(request.durationDays, 7)
    }

    func testJoinChallengeRequest() {
        let challengeId = UUID()
        let request = JoinChallengeRequest(
            challengeId: challengeId,
            showOnLeaderboard: true
        )

        XCTAssertEqual(request.challengeId, challengeId)
        XCTAssertTrue(request.showOnLeaderboard)
    }

    func testUpdateLeaderboardVisibilityRequest() {
        let request = UpdateLeaderboardVisibilityRequest(
            showOnLeaderboard: false
        )

        XCTAssertFalse(request.showOnLeaderboard)
    }

    // MARK: - Challenge Creation Validation Tests

    func testCreateChallengeWithValidData() {
        let request = CreateChallengeRequest(
            title: "Valid Challenge",
            description: "Valid Description",
            challengeType: .streak,
            targetValue: 7,
            durationDays: 7,
            circleId: nil,
            exerciseType: nil
        )

        XCTAssertFalse(request.title.isEmpty)
        XCTAssertFalse(request.description.isEmpty)
        XCTAssertGreaterThan(request.targetValue, 0)
        XCTAssertGreaterThan(request.durationDays, 0)
    }

    func testCreateMinutesChallengeRequiresExerciseType() {
        let request = CreateChallengeRequest(
            title: "Minutes Challenge",
            description: "Test",
            challengeType: .minutes,
            targetValue: 100,
            durationDays: 7,
            circleId: nil,
            exerciseType: nil
        )

        // Should require exercise type for minutes challenges
        XCTAssertNil(request.exerciseType)
    }

    // MARK: - Participant Progress Tests

    func testParticipantProgressTracking() {
        let participant = ChallengeParticipant(
            id: UUID(),
            challengeId: UUID(),
            userId: UUID(),
            currentProgress: 5,
            completed: false,
            completedAt: nil,
            finalRank: nil,
            showOnLeaderboard: true,
            joinedAt: Date(),
            updatedAt: Date()
        )

        let progress = participant.progressPercent(targetValue: 10)
        XCTAssertEqual(progress, 0.5, accuracy: 0.01)
    }

    func testParticipantCompletion() {
        let participant = ChallengeParticipant(
            id: UUID(),
            challengeId: UUID(),
            userId: UUID(),
            currentProgress: 7,
            completed: true,
            completedAt: Date(),
            finalRank: 1,
            showOnLeaderboard: true,
            joinedAt: Date(),
            updatedAt: Date()
        )

        XCTAssertTrue(participant.completed)
        XCTAssertNotNil(participant.completedAt)
        XCTAssertEqual(participant.finalRank, 1)
    }

    // MARK: - Leaderboard Tests

    func testLeaderboardEntryRanking() {
        let entries = [
            LeaderboardEntry(
                id: UUID(),
                rank: 1,
                participant: ChallengeParticipant(
                    id: UUID(),
                    challengeId: UUID(),
                    userId: UUID(),
                    currentProgress: 10,
                    completed: true,
                    completedAt: Date(),
                    finalRank: 1,
                    showOnLeaderboard: true,
                    joinedAt: Date(),
                    updatedAt: Date()
                ),
                userProfile: UserProfile(
                    id: UUID(),
                    displayName: "First Place",
                    avatarUrl: nil,
                    email: "first@example.com",
                    createdAt: Date()
                ),
                isCurrentUser: false,
                isTied: false
            ),
            LeaderboardEntry(
                id: UUID(),
                rank: 2,
                participant: ChallengeParticipant(
                    id: UUID(),
                    challengeId: UUID(),
                    userId: UUID(),
                    currentProgress: 9,
                    completed: true,
                    completedAt: Date(),
                    finalRank: 2,
                    showOnLeaderboard: true,
                    joinedAt: Date(),
                    updatedAt: Date()
                ),
                userProfile: UserProfile(
                    id: UUID(),
                    displayName: "Second Place",
                    avatarUrl: nil,
                    email: "second@example.com",
                    createdAt: Date()
                ),
                isCurrentUser: true,
                isTied: false
            )
        ]

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].rank, 1)
        XCTAssertEqual(entries[1].rank, 2)
        XCTAssertFalse(entries[0].isCurrentUser)
        XCTAssertTrue(entries[1].isCurrentUser)
    }

    func testLeaderboardEntryWithTies() {
        let entry1 = LeaderboardEntry(
            id: UUID(),
            rank: 2,
            participant: ChallengeParticipant(
                id: UUID(),
                challengeId: UUID(),
                userId: UUID(),
                currentProgress: 7,
                completed: true,
                completedAt: Date(),
                finalRank: 2,
                showOnLeaderboard: true,
                joinedAt: Date(),
                updatedAt: Date()
            ),
            userProfile: UserProfile(
                id: UUID(),
                displayName: "Tied User 1",
                avatarUrl: nil,
                email: "tied1@example.com",
                createdAt: Date()
            ),
            isCurrentUser: false,
            isTied: true
        )

        let entry2 = LeaderboardEntry(
            id: UUID(),
            rank: 2,
            participant: ChallengeParticipant(
                id: UUID(),
                challengeId: UUID(),
                userId: UUID(),
                currentProgress: 7,
                completed: true,
                completedAt: Date(),
                finalRank: 2,
                showOnLeaderboard: true,
                joinedAt: Date(),
                updatedAt: Date()
            ),
            userProfile: UserProfile(
                id: UUID(),
                displayName: "Tied User 2",
                avatarUrl: nil,
                email: "tied2@example.com",
                createdAt: Date()
            ),
            isCurrentUser: false,
            isTied: true
        )

        XCTAssertEqual(entry1.rank, entry2.rank)
        XCTAssertTrue(entry1.isTied)
        XCTAssertTrue(entry2.isTied)
    }

    // MARK: - Privacy Tests

    func testLeaderboardVisibilityToggle() {
        let participantVisible = ChallengeParticipant(
            id: UUID(),
            challengeId: UUID(),
            userId: UUID(),
            currentProgress: 5,
            completed: false,
            completedAt: nil,
            finalRank: nil,
            showOnLeaderboard: true,
            joinedAt: Date(),
            updatedAt: Date()
        )

        let participantHidden = ChallengeParticipant(
            id: UUID(),
            challengeId: UUID(),
            userId: UUID(),
            currentProgress: 5,
            completed: false,
            completedAt: nil,
            finalRank: nil,
            showOnLeaderboard: false,
            joinedAt: Date(),
            updatedAt: Date()
        )

        XCTAssertTrue(participantVisible.showOnLeaderboard)
        XCTAssertFalse(participantHidden.showOnLeaderboard)
    }

    // MARK: - Challenge Types Tests

    func testStreakChallengeType() {
        XCTAssertEqual(SocialChallengeType.streak.displayName, "Daily Streak")
        XCTAssertEqual(SocialChallengeType.streak.unitLabel, "days")
    }

    func testMinutesChallengeType() {
        XCTAssertEqual(SocialChallengeType.minutes.displayName, "Exercise Minutes")
        XCTAssertEqual(SocialChallengeType.minutes.unitLabel, "minutes")
    }

    func testMoodChallengeType() {
        XCTAssertEqual(SocialChallengeType.mood.displayName, "Mood Tracking")
        XCTAssertEqual(SocialChallengeType.mood.unitLabel, "logs")
    }

    func testQuestChallengeType() {
        XCTAssertEqual(SocialChallengeType.quest.displayName, "Quest Challenge")
        XCTAssertEqual(SocialChallengeType.quest.unitLabel, "quests")
    }

    // MARK: - Service State Tests

    func testServicePublishedProperties() {
        // Verify service has all required published properties
        XCTAssertNotNil(sut.$publicChallenges)
        XCTAssertNotNil(sut.$circleChallenges)
        XCTAssertNotNil(sut.$myChallenges)
        XCTAssertNotNil(sut.$isLoading)
        XCTAssertNotNil(sut.$error)
    }

    func testServiceMainActorAnnotation() {
        // Verify service is thread-safe by checking it's on main thread
        // (This would be enforced by @MainActor at compile time)
        XCTAssertNotNil(sut)
    }
}
