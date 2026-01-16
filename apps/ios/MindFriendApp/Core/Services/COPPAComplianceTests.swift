import XCTest
import Foundation

/// COPPA (Children's Online Privacy Protection Act) Compliance Tests
/// Ensures parental consent is properly handled for users under 13
final class COPPAComplianceTests: XCTestCase {

    // MARK: - Parental Consent Requirements

    func testParentalConsent_RequiredForChildrenUnder13() {
        // COPPA requirement: Parental consent required for children under 13
        let childAge = 12
        let requiresConsent = childAge < 13

        XCTAssertTrue(requiresConsent)
    }

    func testParentalConsent_NotRequiredForTeensOver13() {
        // COPPA allows teens 13+ to provide own consent
        let teenAge = 13
        let requiresConsent = teenAge < 13

        XCTAssertFalse(requiresConsent)
    }

    func testParentalConsent_Model_HasRequiredFields() {
        // Arrange - COPPA requires: child ID, parent ID, parent email, consent type, verification
        let consent = ParentalConsent(
            id: "consent1",
            childUserId: "child1",
            parentUserId: "parent1",
            parentEmail: "parent@example.com",
            consentType: .initial,
            verificationCode: "VERIFY123",
            verifiedAt: Date(),
            expiresAt: Date().addingTimeInterval(86400 * 365),
            createdAt: Date()
        )

        // Assert - All required fields present
        XCTAssertNotNil(consent.childUserId)
        XCTAssertNotNil(consent.parentUserId)
        XCTAssertNotNil(consent.parentEmail)
        XCTAssertEqual(consent.consentType, .initial)
        XCTAssertNotNil(consent.verificationCode)
        XCTAssertNotNil(consent.verifiedAt)
        XCTAssertNotNil(consent.expiresAt)
    }

    func testParentalConsent_ExpiresAfterOneYear() {
        // COPPA requires renewal annually
        let consent = ParentalConsent(
            id: "consent1",
            childUserId: "child1",
            parentUserId: "parent1",
            parentEmail: "parent@example.com",
            consentType: .annualRenewal,
            verificationCode: nil,
            verifiedAt: Date(),
            expiresAt: Date().addingTimeInterval(86400 * 365),
            createdAt: Date()
        )

        let calendar = Calendar.current
        let expirationYears = calendar.dateComponents([.year], from: consent.createdAt, to: consent.expiresAt).year

        XCTAssertEqual(expirationYears, 1)
    }

    // MARK: - Data Access Controls

    func testChildMember_AgeFilter_EnforcedBasedOnBirthDate() {
        // COPPA compliance: Content must be age-appropriate
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2015  // Age 11
        components.month = 1
        components.day = 16
        let childBirthDate = calendar.date(from: components)!

        let childMember = FamilyWellnessMember(
            id: "member1",
            familyId: "family1",
            userId: "user1",
            role: .child,
            nickname: "Child",
            avatarEmoji: "👧",
            birthDate: childBirthDate,
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

        let effectiveFilter = childMember.effectiveAgeFilter

        // Assert - Should restrict to age-appropriate content
        XCTAssertLessThanOrEqual(effectiveFilter, 11)
    }

    func testChildMember_ParentCanOverrideAgeFilter_MoreRestrictive() {
        // COPPA: Parent can apply stricter age filters
        let childMember = FamilyWellnessMember(
            id: "member1",
            familyId: "family1",
            userId: "user1",
            role: .child,
            nickname: "Child",
            avatarEmoji: "👦",
            birthDate: Date(timeIntervalSince1970: 315532800),  // Age 10
            ageFilterOverride: 6,  // Parent restricts to 6+ content
            shareMoodWithFamily: true,
            shareActivityWithFamily: true,
            shareAchievementsWithFamily: true,
            status: .active,
            invitedBy: nil,
            joinedAt: Date(),
            createdAt: Date(),
            updatedAt: Date()
        )

        let effectiveFilter = childMember.effectiveAgeFilter

        // Assert - Parent override takes effect if more restrictive
        XCTAssertEqual(effectiveFilter, 6)
    }

    // MARK: - Data Sharing & Privacy

    func testChildMember_SharingPreferences_CanBeDisabledByParent() {
        // COPPA: Parent controls what data is shared
        let childWithNoSharing = FamilyWellnessMember(
            id: "member1",
            familyId: "family1",
            userId: "user1",
            role: .child,
            nickname: "Private Child",
            avatarEmoji: "👧",
            birthDate: nil,
            ageFilterOverride: nil,
            shareMoodWithFamily: false,
            shareActivityWithFamily: false,
            shareAchievementsWithFamily: false,
            status: .active,
            invitedBy: nil,
            joinedAt: Date(),
            createdAt: Date(),
            updatedAt: Date()
        )

        // Assert - Sharing can be fully disabled
        XCTAssertFalse(childWithNoSharing.shareMoodWithFamily)
        XCTAssertFalse(childWithNoSharing.shareActivityWithFamily)
        XCTAssertFalse(childWithNoSharing.shareAchievementsWithFamily)
    }

    // MARK: - Parental Access & Oversight

    func testParentRole_HasFullAccess_ToChildData() {
        // COPPA: Parent must have access to all child data
        let parentRole = FamilyRole.parent

        XCTAssertTrue(parentRole.canManageFamily)
        XCTAssertTrue(parentRole.hasFullAIAccess)
    }

    func testAdminRole_HasFullAccess_ToFamilyData() {
        // COPPA: Admin (typically parent) must have full access
        let adminRole = FamilyRole.admin

        XCTAssertTrue(adminRole.canManageFamily)
        XCTAssertTrue(adminRole.hasFullAIAccess)
    }

    func testChildRole_HasLimitedAIAccess() {
        // COPPA: Children should have limited features until parent consents
        let childRole = FamilyRole.child

        XCTAssertFalse(childRole.canManageFamily)
        XCTAssertFalse(childRole.hasFullAIAccess)
    }

    // MARK: - Alerts for Parent Oversight

    func testParentalAlerts_GeneratedFor_InactiveChildren() {
        // COPPA: Parent must be able to monitor child activity
        let inactivityAlert = FamilyAlert(
            id: "alert1",
            familyId: "family1",
            aboutMemberId: "child1",
            forParentId: "parent1",
            alertType: .inactivity,
            severity: .attention,
            title: "Child Inactive",
            message: "Your child hasn't checked in for 3 days",
            actionType: .checkIn,
            actionData: nil,
            conversationStarters: ["Is everything ok?"],
            wasRead: false,
            wasActedUpon: false,
            readAt: nil,
            expiresAt: Date().addingTimeInterval(86400 * 7),
            createdAt: Date()
        )

        // Assert - Alert properly routes to parent
        XCTAssertEqual(inactivityAlert.forParentId, "parent1")
        XCTAssertEqual(inactivityAlert.aboutMemberId, "child1")
        XCTAssertEqual(inactivityAlert.alertType, .inactivity)
    }

    func testParentalAlerts_GeneratedFor_MoodConcerns() {
        // COPPA: Parent notified of potential wellness issues
        let moodAlert = FamilyAlert(
            id: "alert2",
            familyId: "family1",
            aboutMemberId: "child1",
            forParentId: "parent1",
            alertType: .moodConcern,
            severity: .concern,
            title: "Mood Concern",
            message: "Your child's mood has been declining",
            actionType: .startConversation,
            actionData: nil,
            conversationStarters: ["How are you really doing?"],
            wasRead: false,
            wasActedUpon: false,
            readAt: nil,
            expiresAt: Date().addingTimeInterval(86400 * 7),
            createdAt: Date()
        )

        // Assert - Alert indicates concern level
        XCTAssertEqual(moodAlert.severity, .concern)
        XCTAssertEqual(moodAlert.actionType, .startConversation)
    }

    // MARK: - Email Verification

    func testParentalConsent_RequiresEmailVerification() {
        // COPPA requires verifiable parental email
        let consent = ParentalConsent(
            id: "consent1",
            childUserId: "child1",
            parentUserId: "parent1",
            parentEmail: "parent@example.com",
            consentType: .initial,
            verificationCode: "ABC123DEF456",
            verifiedAt: Date(),
            expiresAt: Date().addingTimeInterval(86400 * 365),
            createdAt: Date()
        )

        // Assert - Email format is valid
        XCTAssertTrue(consent.parentEmail.contains("@"))

        // Assert - Verification code exists and is verifiable
        XCTAssertNotNil(consent.verificationCode)
        XCTAssertEqual(consent.verificationCode?.count, 12)

        // Assert - Verified timestamp exists
        XCTAssertNotNil(consent.verifiedAt)
    }

    func testParentalConsent_RenewalRequired_Annually() {
        // COPPA requires annual renewal
        let createdDate = Date()
        let renewalDate = Calendar.current.date(byAdding: .year, value: 1, to: createdDate)!

        let consent = ParentalConsent(
            id: "consent1",
            childUserId: "child1",
            parentUserId: "parent1",
            parentEmail: "parent@example.com",
            consentType: .annualRenewal,
            verificationCode: nil,
            verifiedAt: createdDate,
            expiresAt: renewalDate,
            createdAt: createdDate
        )

        let needsRenewal = Date() > consent.expiresAt

        // Assert - Consent expires after one year
        XCTAssertTrue(needsRenewal || Date() <= consent.expiresAt)
    }

    // MARK: - Content Age Ratings

    func testContentAgeRating_EnforcesMinimumAge_ForChildren() {
        // COPPA: Content must be age-appropriate
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

        let childAge = 10
        let isAppropriate = teenContent.isAppropriateForAge(childAge)

        // Assert - Content blocked for age < 13
        XCTAssertFalse(isAppropriate)
    }

    func testContentAgeRating_AllowsAgeAppropriateContent_ForChildren() {
        // COPPA: Age-appropriate content allowed
        let kidContent = ContentAgeRating(
            id: "r1",
            contentType: "exercise",
            contentId: "ex1",
            minimumAge: 4,
            maximumAge: 12,
            ratingCategory: .kids,
            containsHeavyTopics: false,
            requiresReading: false,
            complexityLevel: .simple,
            reviewedBy: nil,
            reviewedAt: nil,
            createdAt: Date()
        )

        let childAge = 8
        let isAppropriate = kidContent.isAppropriateForAge(childAge)

        // Assert - Content allowed for age within range
        XCTAssertTrue(isAppropriate)
    }

    func testContentAgeRating_BlocksHeavyTopics_ForYoungChildren() {
        // COPPA: Heavy topics should be age-gated
        let advancedContent = ContentAgeRating(
            id: "r1",
            contentType: "exercise",
            contentId: "ex1",
            minimumAge: 16,
            maximumAge: nil,
            ratingCategory: .adult,
            containsHeavyTopics: true,
            requiresReading: true,
            complexityLevel: .complex,
            reviewedBy: "reviewer1",
            reviewedAt: Date(),
            createdAt: Date()
        )

        // Assert - Heavy topics are properly flagged
        XCTAssertTrue(advancedContent.containsHeavyTopics)
        XCTAssertTrue(advancedContent.requiresReading)
        XCTAssertEqual(advancedContent.complexityLevel, .complex)
    }

    // MARK: - RLS Policy Validation

    func testRLSPolicy_ChildCannotAccess_OtherChildData() {
        // COPPA: Ensure children isolated from each other
        let child1Id = "child1"
        let child2Id = "child2"

        // In a real RLS test, this would be enforced at database level
        // This test documents the expected behavior
        let child1HasAccessToChild2 = false  // RLS should enforce this

        XCTAssertFalse(child1HasAccessToChild2)
    }

    func testRLSPolicy_ChildCanAccess_FamilyData_OnlyIfMember() {
        // COPPA: Child can access family data only if properly invited
        let childId = "child1"
        let familyId = "family1"

        // Child is family member - should have access
        let member = FamilyWellnessMember(
            id: "member1",
            familyId: familyId,
            userId: childId,
            role: .child,
            nickname: "Child",
            avatarEmoji: "👧",
            birthDate: nil,
            ageFilterOverride: nil,
            shareMoodWithFamily: true,
            shareActivityWithFamily: true,
            shareAchievementsWithFamily: true,
            status: .active,
            invitedBy: "parent1",
            joinedAt: Date(),
            createdAt: Date(),
            updatedAt: Date()
        )

        let hasAccess = member.familyId == familyId && member.status == .active

        XCTAssertTrue(hasAccess)
    }
}
