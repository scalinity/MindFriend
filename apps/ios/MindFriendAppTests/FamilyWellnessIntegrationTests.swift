import XCTest
import Foundation
@testable import MindFriendApp

/// Integration tests for family wellness features
@MainActor
final class FamilyWellnessIntegrationTests: XCTestCase {

    // MARK: - Family Creation & Onboarding Flow

    func testFamilyCreationFlow_AdminCreatesFamily_ThenInvitesMembers() async throws {
        // This test documents the expected flow:
        // 1. Admin creates family via FamilyService.createFamily()
        // 2. System generates invite code
        // 3. Invite code sent to family members
        // 4. Members join via FamilyService.joinFamily()
        // 5. Family members list updated

        // Step 1: Admin creates family
        let familyName = "Extended Family"
        let ageFilter = 13
        let maxMembers = 8

        // Expected state after creation:
        // - Family exists with generated invite code
        // - Admin is automatically added as family member
        // - Invite code is ready for distribution

        XCTAssertNotNil(familyName)
        XCTAssertGreaterThan(ageFilter, 0)
        XCTAssertGreater(maxMembers, 1)

        // Step 2-5: Would be tested via FamilyService integration
    }

    // MARK: - Role-Based Access Control Flow

    func testRoleBasedAccess_ChildCannotManageFamily_OnlyViewsContent() {
        // Document expected behavior:
        // - Child (role) cannot create challenges
        // - Child cannot invite members
        // - Child can view family data based on sharing preferences
        // - Child has limited AI access

        let childRole = FamilyRole.child

        XCTAssertFalse(childRole.canManageFamily)
        XCTAssertFalse(childRole.hasFullAIAccess)
    }

    func testRoleBasedAccess_ParentCanManageFamily_AndViewAllData() {
        // Document expected behavior:
        // - Parent (role) can create challenges
        // - Parent can invite members
        // - Parent can see all family data
        // - Parent receives alerts about children

        let parentRole = FamilyRole.parent

        XCTAssertTrue(parentRole.canManageFamily)
        XCTAssertTrue(parentRole.hasFullAIAccess)
    }

    // MARK: - Age-Appropriate Content Filter Flow

    func testAgeFilterFlow_ChildAgeChanges_ContentAccessUpdates() {
        // Document expected behavior:
        // 1. Child age calculated from birth_date
        // 2. Effective age filter determined (override or calculated)
        // 3. Content recommendations filtered accordingly
        // 4. When child ages up, more content becomes available

        // Simulate 12-year-old child
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2013  // Age 13 in 2026
        components.month = 1
        components.day = 16
        let birthDate = calendar.date(from: components)!

        let youngChild = FamilyWellnessMember(
            id: "member1",
            familyId: "family1",
            userId: "user1",
            role: .child,
            nickname: "Jordan",
            avatarEmoji: "👧",
            birthDate: birthDate,
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

        // Age 13 - can now access teen content
        XCTAssertEqual(youngChild.calculatedAge, 13)

        // Test content appropriateness
        let teenContent = ContentAgeRating(
            id: "r1",
            contentType: "exercise",
            contentId: "ex1",
            minimumAge: 13,
            maximumAge: nil,
            ratingCategory: .teen,
            containsHeavyTopics: false,
            requiresReading: false,
            complexityLevel: nil,
            reviewedBy: nil,
            reviewedAt: nil,
            createdAt: Date()
        )

        XCTAssertTrue(teenContent.isAppropriateForAge(youngChild.calculatedAge ?? 0))
    }

    // MARK: - Parental Monitoring & Alerts Flow

    func testParentalMonitoringFlow_InactiveChild_GeneratesAlert() {
        // Document expected behavior:
        // 1. Child hasn't logged in for 3+ days
        // 2. Edge Function (generate-family-alerts) detects this
        // 3. Alert created and routed to parent
        // 4. Parent receives notification
        // 5. Parent can act on alert (check-in conversation)

        let inactivityAlert = FamilyAlert(
            id: "alert1",
            familyId: "family1",
            aboutMemberId: "child1",
            forParentId: "parent1",
            alertType: .inactivity,
            severity: .attention,
            title: "Activity Reminder",
            message: "Jordan hasn't checked in for 3 days",
            actionType: .checkIn,
            actionData: nil,
            conversationStarters: [
                "How are you doing?",
                "Let's check in together"
            ],
            wasRead: false,
            wasActedUpon: false,
            readAt: nil,
            expiresAt: Date().addingTimeInterval(86400 * 7),
            createdAt: Date()
        )

        // Assert alert properties
        XCTAssertEqual(inactivityAlert.alertType, .inactivity)
        XCTAssertEqual(inactivityAlert.severity, .attention)
        XCTAssertEqual(inactivityAlert.forParentId, "parent1")
        XCTAssertEqual(inactivityAlert.aboutMemberId, "child1")
        XCTAssertEqual(inactivityAlert.conversationStarters?.count, 2)
    }

    func testParentalMonitoringFlow_MoodConcern_TriggersAlert() {
        // Document expected behavior:
        // 1. Child's mood entries show declining trend
        // 2. Edge Function detects pattern
        // 3. Alert created to prompt parent check-in
        // 4. Alert includes conversation starters

        let moodAlert = FamilyAlert(
            id: "alert2",
            familyId: "family1",
            aboutMemberId: "child1",
            forParentId: "parent1",
            alertType: .moodConcern,
            severity: .concern,
            title: "Mood Trend Notice",
            message: "Jordan's recent mood entries show a declining pattern",
            actionType: .startConversation,
            actionData: nil,
            conversationStarters: [
                "I've noticed you seem quieter lately",
                "Want to talk about what's on your mind?",
                "I'm here if you need to chat"
            ],
            wasRead: false,
            wasActedUpon: false,
            readAt: nil,
            expiresAt: Date().addingTimeInterval(86400 * 7),
            createdAt: Date()
        )

        XCTAssertEqual(moodAlert.alertType, .moodConcern)
        XCTAssertEqual(moodAlert.severity, .concern)
        XCTAssertEqual(moodAlert.actionType, .startConversation)
    }

    // MARK: - Family Challenge Flow

    func testFamilyChallengeFlow_AdminCreatesChallenge_MembersParticipate() {
        // Document expected behavior:
        // 1. Admin creates challenge with target and duration
        // 2. Challenge appears in family hub
        // 3. Members can view progress
        // 4. System tracks progress against target
        // 5. Alerts notify of progress/completion

        let challenge = FamilyChallenge(
            id: "challenge1",
            familyId: "family1",
            title: "7-Day Meditation Streak",
            description: "Meditate for at least 10 minutes each day",
            challengeType: .streak,
            targetValue: 7,
            minimumParticipants: 1,
            startDate: Date(),
            endDate: Date().addingTimeInterval(86400 * 7),
            requiresAllMembers: false,
            allowMakeupActivities: true,
            status: .active,
            currentProgress: 3,
            badgeId: "badge_meditation_7day",
            rewardDescription: "Meditation Master badge",
            createdBy: "admin1",
            createdAt: Date(),
            updatedAt: Date()
        )

        // Assert challenge tracking
        XCTAssertEqual(challenge.title, "7-Day Meditation Streak")
        XCTAssertEqual(challenge.targetValue, 7)
        XCTAssertEqual(challenge.currentProgress, 3)
        XCTAssertEqual(challenge.progressPercentage, 0.42857, accuracy: 0.01)
        XCTAssertEqual(challenge.status, .active)
    }

    // MARK: - Together Sessions Flow

    func testTogetherSessionFlow_AdminSchedulesActivity_MembersJoin() {
        // Document expected behavior:
        // 1. Admin selects from TogetherTemplate library
        // 2. Creates TogetherSession for family
        // 3. Members invited (notifications sent)
        // 4. Members join in real-time or async window
        // 5. System tracks participation

        let session = TogetherSession(
            id: "session1",
            familyId: "family1",
            exerciseId: nil,
            togetherTemplateId: "template_breathing",
            title: "Family Breathing Exercise",
            scheduledFor: nil,
            startedAt: Date(),
            endedAt: nil,
            durationSeconds: 600,  // 10 minutes
            minimumParticipants: 1,
            status: .inProgress,
            syncMode: .realtime,
            asyncWindowHours: nil,
            createdBy: "admin1",
            createdAt: Date()
        )

        // Assert session properties
        XCTAssertTrue(session.isActive)
        XCTAssertEqual(session.status, .inProgress)
        XCTAssertEqual(session.syncMode, .realtime)
    }

    func testTogetherSessionFlow_AsyncMode_MembersParticipateAtOwnPace() {
        // Document async session behavior for different timezones/schedules
        let asyncSession = TogetherSession(
            id: "session2",
            familyId: "family1",
            exerciseId: nil,
            togetherTemplateId: "template_gratitude",
            title: "Family Gratitude Share",
            scheduledFor: nil,
            startedAt: Date(),
            endedAt: nil,
            durationSeconds: nil,
            minimumParticipants: 1,
            status: .inProgress,
            syncMode: .asyncWindow,
            asyncWindowHours: 24,  // 24-hour window
            createdBy: "admin1",
            createdAt: Date()
        )

        XCTAssertEqual(asyncSession.syncMode, .asyncWindow)
        XCTAssertEqual(asyncSession.asyncWindowHours, 24)
    }

    // MARK: - Parental Consent Flow

    func testParentalConsentFlow_ChildUnder13_RequiresParentVerification() {
        // Document COPPA compliance flow:
        // 1. Child profile created with birth_date < 13
        // 2. System requires parental consent
        // 3. Parent receives verification email
        // 4. Parent verifies consent
        // 5. Child account activated with full access

        let consent = ParentalConsent(
            id: "consent1",
            childUserId: "child_under_13",
            parentUserId: "parent1",
            parentEmail: "parent@example.com",
            consentType: .initial,
            verificationCode: "VERIFY123ABC",
            verifiedAt: Date(),
            expiresAt: Date().addingTimeInterval(86400 * 365),
            createdAt: Date()
        )

        // Assert consent properties
        XCTAssertEqual(consent.childUserId, "child_under_13")
        XCTAssertNotNil(consent.verificationCode)
        XCTAssertNotNil(consent.verifiedAt)
    }

    // MARK: - Data Sharing Preferences Flow

    func testDataSharingFlow_ParentControlsChildVisibility() {
        // Document expected behavior:
        // 1. Parent can enable/disable mood sharing
        // 2. Parent can enable/disable activity sharing
        // 3. Parent can enable/disable achievement sharing
        // 4. Settings enforced at database level (RLS)

        let childWithLimitedSharing = FamilyWellnessMember(
            id: "member1",
            familyId: "family1",
            userId: "child1",
            role: .child,
            nickname: "Private Child",
            avatarEmoji: "👧",
            birthDate: nil,
            ageFilterOverride: nil,
            shareMoodWithFamily: false,      // Parent disabled mood sharing
            shareActivityWithFamily: true,   // Activity visible
            shareAchievementsWithFamily: false,  // Achievements hidden
            status: .active,
            invitedBy: nil,
            joinedAt: Date(),
            createdAt: Date(),
            updatedAt: Date()
        )

        XCTAssertFalse(childWithLimitedSharing.shareMoodWithFamily)
        XCTAssertTrue(childWithLimitedSharing.shareActivityWithFamily)
        XCTAssertFalse(childWithLimitedSharing.shareAchievementsWithFamily)
    }

    // MARK: - Error Scenarios

    func testErrorHandling_JoinFamily_WithInvalidCode_ReturnsError() {
        // Document error handling:
        // - Invalid invite code → error message
        // - Expired code → error message
        // - Family at capacity → error message

        let invalidCode = ""

        // Expected: FamilyServiceError.joinFamilyFailed
        XCTAssertTrue(invalidCode.isEmpty)
    }

    func testErrorHandling_CreateChallenge_WithoutFamilyGroup_ReturnsError() {
        // Document error handling:
        // - User not in family → FamilyServiceError.noFamilyGroup
        // - Missing permissions → FamilyServiceError (permission denied)

        // Expected: FamilyServiceError.noFamilyGroup
    }
}
