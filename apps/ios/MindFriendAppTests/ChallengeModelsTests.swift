import XCTest
@testable import MindFriendApp

final class ChallengeModelsTests: XCTestCase {

    // MARK: - SocialChallengeType Tests

    func testChallengeTypeDisplayNames() {
        XCTAssertEqual(SocialChallengeType.streak.displayName, "Daily Streak")
        XCTAssertEqual(SocialChallengeType.minutes.displayName, "Exercise Minutes")
        XCTAssertEqual(SocialChallengeType.mood.displayName, "Mood Tracking")
        XCTAssertEqual(SocialChallengeType.quest.displayName, "Quest Challenge")
    }

    func testChallengeTypeIconNames() {
        XCTAssertEqual(SocialChallengeType.streak.iconName, "flame.fill")
        XCTAssertEqual(SocialChallengeType.minutes.iconName, "clock.fill")
        XCTAssertEqual(SocialChallengeType.mood.iconName, "smiley.fill")
        XCTAssertEqual(SocialChallengeType.quest.iconName, "checkmark.circle.fill")
    }

    func testChallengeTypeUnitLabels() {
        XCTAssertEqual(SocialChallengeType.streak.unitLabel, "days")
        XCTAssertEqual(SocialChallengeType.minutes.unitLabel, "minutes")
        XCTAssertEqual(SocialChallengeType.mood.unitLabel, "logs")
        XCTAssertEqual(SocialChallengeType.quest.unitLabel, "quests")
    }

    func testChallengeTypeAllCases() {
        XCTAssertEqual(SocialChallengeType.allCases.count, 4)
        XCTAssertTrue(SocialChallengeType.allCases.contains(.streak))
        XCTAssertTrue(SocialChallengeType.allCases.contains(.minutes))
        XCTAssertTrue(SocialChallengeType.allCases.contains(.mood))
        XCTAssertTrue(SocialChallengeType.allCases.contains(.quest))
    }

    // MARK: - ChallengeStatus Tests

    func testChallengeStatusForUpcomingChallenge() {
        let startDate = Date().addingTimeInterval(86400) // Tomorrow
        let endDate = Date().addingTimeInterval(172800) // Day after tomorrow

        let challenge = SocialChallenge(
            id: UUID(),
            title: "Test",
            description: "Test",
            challengeType: .streak,
            targetValue: 7,
            durationDays: 7,
            isPublic: true,
            circleId: nil,
            createdBy: UUID(),
            exerciseType: nil,
            startsAt: startDate,
            endsAt: endDate,
            finalized: false,
            finalizedAt: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        XCTAssertEqual(challenge.status, .upcoming)
        XCTAssertFalse(challenge.isActive)
    }

    func testChallengeStatusForActiveChallenge() {
        let startDate = Date().addingTimeInterval(-3600) // 1 hour ago
        let endDate = Date().addingTimeInterval(86400) // Tomorrow

        let challenge = SocialChallenge(
            id: UUID(),
            title: "Test",
            description: "Test",
            challengeType: .streak,
            targetValue: 7,
            durationDays: 7,
            isPublic: true,
            circleId: nil,
            createdBy: UUID(),
            exerciseType: nil,
            startsAt: startDate,
            endsAt: endDate,
            finalized: false,
            finalizedAt: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        XCTAssertEqual(challenge.status, .active)
        XCTAssertTrue(challenge.isActive)
    }

    func testChallengeStatusForEndedChallenge() {
        let startDate = Date().addingTimeInterval(-172800) // 2 days ago
        let endDate = Date().addingTimeInterval(-86400) // Yesterday

        let challenge = SocialChallenge(
            id: UUID(),
            title: "Test",
            description: "Test",
            challengeType: .streak,
            targetValue: 7,
            durationDays: 7,
            isPublic: true,
            circleId: nil,
            createdBy: UUID(),
            exerciseType: nil,
            startsAt: startDate,
            endsAt: endDate,
            finalized: true,
            finalizedAt: Date().addingTimeInterval(-86400),
            createdAt: Date(),
            updatedAt: Date()
        )

        XCTAssertEqual(challenge.status, .ended)
        XCTAssertFalse(challenge.isActive)
    }

    func testDaysRemainingForActiveChallenge() {
        let startDate = Date()
        let endDate = Date().addingTimeInterval(7 * 86400) // 7 days from now

        let challenge = SocialChallenge(
            id: UUID(),
            title: "Test",
            description: "Test",
            challengeType: .streak,
            targetValue: 7,
            durationDays: 7,
            isPublic: true,
            circleId: nil,
            createdBy: UUID(),
            exerciseType: nil,
            startsAt: startDate,
            endsAt: endDate,
            finalized: false,
            finalizedAt: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        // Days remaining should be approximately 7 (allowing for execution time)
        let daysRemaining = challenge.daysRemaining
        XCTAssertGreaterThanOrEqual(daysRemaining, 6)
        XCTAssertLessThanOrEqual(daysRemaining, 7)
    }

    // MARK: - ChallengeParticipant Tests

    func testParticipantProgressPercent() {
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

        let progressPercent = participant.progressPercent(targetValue: 10)
        XCTAssertEqual(progressPercent, 0.5, accuracy: 0.01)
    }

    func testParticipantProgressPercentZeroTarget() {
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

        let progressPercent = participant.progressPercent(targetValue: 0)
        XCTAssertEqual(progressPercent, 0.0)
    }

    func testParticipantProgressPercentComplete() {
        let participant = ChallengeParticipant(
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
        )

        let progressPercent = participant.progressPercent(targetValue: 10)
        XCTAssertEqual(progressPercent, 1.0, accuracy: 0.01)
    }

    // MARK: - ChallengeWithParticipation Tests

    func testChallengeWithParticipationIsJoined() {
        let challenge = SocialChallenge(
            id: UUID(),
            title: "Test",
            description: "Test",
            challengeType: .streak,
            targetValue: 7,
            durationDays: 7,
            isPublic: true,
            circleId: nil,
            createdBy: UUID(),
            exerciseType: nil,
            startsAt: Date(),
            endsAt: Date().addingTimeInterval(86400),
            finalized: false,
            finalizedAt: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        let participation = ChallengeParticipant(
            id: UUID(),
            challengeId: challenge.id,
            userId: UUID(),
            currentProgress: 5,
            completed: false,
            completedAt: nil,
            finalRank: nil,
            showOnLeaderboard: true,
            joinedAt: Date(),
            updatedAt: Date()
        )

        let wrapped = ChallengeWithParticipation(
            id: challenge.id,
            challenge: challenge,
            participation: participation,
            participantCount: 10
        )

        XCTAssertTrue(wrapped.isJoined)
        XCTAssertEqual(wrapped.progressPercent, 5.0/7.0, accuracy: 0.01)
    }

    func testChallengeWithParticipationNotJoined() {
        let challenge = SocialChallenge(
            id: UUID(),
            title: "Test",
            description: "Test",
            challengeType: .streak,
            targetValue: 7,
            durationDays: 7,
            isPublic: true,
            circleId: nil,
            createdBy: UUID(),
            exerciseType: nil,
            startsAt: Date(),
            endsAt: Date().addingTimeInterval(86400),
            finalized: false,
            finalizedAt: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        let wrapped = ChallengeWithParticipation(
            id: challenge.id,
            challenge: challenge,
            participation: nil,
            participantCount: 10
        )

        XCTAssertFalse(wrapped.isJoined)
        XCTAssertEqual(wrapped.progressPercent, 0.0)
    }

    // MARK: - LeaderboardEntry Tests

    func testLeaderboardEntry() {
        let userId = UUID()
        let participant = ChallengeParticipant(
            id: UUID(),
            challengeId: UUID(),
            userId: userId,
            currentProgress: 7,
            completed: true,
            completedAt: Date(),
            finalRank: 1,
            showOnLeaderboard: true,
            joinedAt: Date(),
            updatedAt: Date()
        )

        let profile = UserProfile(
            id: userId,
            displayName: "Test User",
            avatarUrl: "https://example.com/avatar.jpg",
            email: "test@example.com",
            createdAt: Date()
        )

        let entry = LeaderboardEntry(
            id: participant.id,
            rank: 1,
            participant: participant,
            userProfile: profile,
            isCurrentUser: true,
            isTied: false
        )

        XCTAssertEqual(entry.rank, 1)
        XCTAssertEqual(entry.userProfile.displayName, "Test User")
        XCTAssertTrue(entry.isCurrentUser)
        XCTAssertFalse(entry.isTied)
    }

    // MARK: - ExerciseType Tests

    func testExerciseTypeAllCases() {
        XCTAssertEqual(ExerciseType.allCases.count, 5)
        XCTAssertTrue(ExerciseType.allCases.contains(.breathing))
        XCTAssertTrue(ExerciseType.allCases.contains(.meditation))
        XCTAssertTrue(ExerciseType.allCases.contains(.grounding))
        XCTAssertTrue(ExerciseType.allCases.contains(.journaling))
        XCTAssertTrue(ExerciseType.allCases.contains(.movement))
    }

    // MARK: - ChallengeError Tests

    func testChallengeErrorLocalizedDescriptions() {
        XCTAssertNotNil(ChallengeError.notAuthenticated.errorDescription)
        XCTAssertNotNil(ChallengeError.invalidId.errorDescription)
        XCTAssertNotNil(ChallengeError.rateLimited.errorDescription)
        XCTAssertNotNil(ChallengeError.exerciseTypeRequired.errorDescription)
        XCTAssertNotNil(ChallengeError.loadFailed.errorDescription)
        XCTAssertNotNil(ChallengeError.alreadyJoined.errorDescription)
        XCTAssertNotNil(ChallengeError.challengeEnded.errorDescription)
        XCTAssertNotNil(ChallengeError.invalidChallenge.errorDescription)
    }

    // MARK: - JSON Coding Tests

    func testSocialChallengeJSONEncoding() throws {
        let challenge = SocialChallenge(
            id: UUID(),
            title: "Test Challenge",
            description: "Test Description",
            challengeType: .streak,
            targetValue: 7,
            durationDays: 7,
            isPublic: true,
            circleId: nil,
            createdBy: UUID(),
            exerciseType: nil,
            startsAt: Date(),
            endsAt: Date().addingTimeInterval(86400),
            finalized: false,
            finalizedAt: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(challenge)
        XCTAssertGreaterThan(data.count, 0)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SocialChallenge.self, from: data)
        XCTAssertEqual(decoded.id, challenge.id)
        XCTAssertEqual(decoded.title, challenge.title)
        XCTAssertEqual(decoded.challengeType, challenge.challengeType)
    }
}
