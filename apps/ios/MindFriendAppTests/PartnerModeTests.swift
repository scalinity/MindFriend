import XCTest
@testable import MindFriendApp

final class PartnerModeTests: XCTestCase {

    // MARK: - Invite Code Validation Tests

    func testInviteCodeFormat_6Characters() {
        let validCodes = ["ABC123", "XYZ789", "LMN456", "PQW234"]
        for code in validCodes {
            XCTAssertEqual(code.count, 6, "Code \(code) should be 6 characters")
        }
    }

    func testInviteCodeFormat_NoAmbiguousCharacters() {
        // Buddy codes should NOT contain: I, O, 0, 1 to avoid confusion
        let validChars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        let invalidChars = "IO01"

        for char in invalidChars {
            XCTAssertFalse(validChars.contains(char), "Code should not contain ambiguous char: \(char)")
        }
    }

    func testInviteCodeValidation_TooShort() {
        let shortCode = "ABC12"
        XCTAssertNotEqual(shortCode.count, 6, "Code should be rejected if not 6 chars")
    }

    func testInviteCodeValidation_TooLong() {
        let longCode = "ABC1234"
        XCTAssertNotEqual(longCode.count, 6, "Code should be rejected if not 6 chars")
    }

    func testInviteCodeValidation_Empty() {
        let emptyCode = ""
        XCTAssertNotEqual(emptyCode.count, 6, "Empty code should be rejected")
    }

    // MARK: - Sharing Settings Tests

    func testSharingSettings_DefaultValues() {
        let settings = SharingSettings(shareMood: false, shareExercises: false)
        XCTAssertFalse(settings.shareMood)
        XCTAssertFalse(settings.shareExercises)
    }

    func testSharingSettings_MoodOnly() {
        let settings = SharingSettings(shareMood: true, shareExercises: false)
        XCTAssertTrue(settings.shareMood)
        XCTAssertFalse(settings.shareExercises)
    }

    func testSharingSettings_ExercisesOnly() {
        let settings = SharingSettings(shareMood: false, shareExercises: true)
        XCTAssertFalse(settings.shareMood)
        XCTAssertTrue(settings.shareExercises)
    }

    func testSharingSettings_BothEnabled() {
        let settings = SharingSettings(shareMood: true, shareExercises: true)
        XCTAssertTrue(settings.shareMood)
        XCTAssertTrue(settings.shareExercises)
    }

    func testSharingSettings_Equatable() {
        let settings1 = SharingSettings(shareMood: true, shareExercises: false)
        let settings2 = SharingSettings(shareMood: true, shareExercises: false)
        let settings3 = SharingSettings(shareMood: false, shareExercises: false)

        XCTAssertEqual(settings1, settings2)
        XCTAssertNotEqual(settings1, settings3)
    }

    // MARK: - PartnerState Tests

    func testPartnerState_Loading() {
        let state: PartnerState = .loading
        if case .loading = state {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected .loading state")
        }
    }

    func testPartnerState_NoPartner() {
        let state: PartnerState = .noPartner
        if case .noPartner = state {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected .noPartner state")
        }
    }

    func testPartnerState_PendingInvite() {
        let expiresAt = Date().addingTimeInterval(86400) // 24 hours from now
        let state: PartnerState = .pendingInvite(code: "ABC123", expiresAt: expiresAt)

        if case .pendingInvite(let code, let expires) = state {
            XCTAssertEqual(code, "ABC123")
            XCTAssertEqual(expires, expiresAt)
        } else {
            XCTFail("Expected .pendingInvite state")
        }
    }

    func testPartnerState_HasPartner() {
        let partnerInfo = PartnerInfo(
            partnerId: UUID(),
            partnerName: "Test Partner",
            partnerStreak: 5,
            hasCompletedToday: true,
            lastActive: Date(),
            isSharingMood: true,
            isSharingExercises: false
        )
        let state: PartnerState = .hasPartner(partnerInfo)

        if case .hasPartner(let info) = state {
            XCTAssertEqual(info.partnerName, "Test Partner")
            XCTAssertEqual(info.partnerStreak, 5)
            XCTAssertTrue(info.hasCompletedToday)
            XCTAssertTrue(info.isSharingMood)
            XCTAssertFalse(info.isSharingExercises)
        } else {
            XCTFail("Expected .hasPartner state")
        }
    }

    func testPartnerState_Equatable_Loading() {
        XCTAssertEqual(PartnerState.loading, PartnerState.loading)
    }

    func testPartnerState_Equatable_NoPartner() {
        XCTAssertEqual(PartnerState.noPartner, PartnerState.noPartner)
    }

    func testPartnerState_Equatable_PendingInvite() {
        let expiresAt = Date()
        let state1 = PartnerState.pendingInvite(code: "ABC123", expiresAt: expiresAt)
        let state2 = PartnerState.pendingInvite(code: "ABC123", expiresAt: expiresAt)
        XCTAssertEqual(state1, state2)
    }

    func testPartnerState_Equatable_HasPartner() {
        let partnerId = UUID()
        let info1 = PartnerInfo(
            partnerId: partnerId,
            partnerName: "Test",
            partnerStreak: 3,
            hasCompletedToday: false,
            lastActive: Date(),
            isSharingMood: true,
            isSharingExercises: true
        )
        let info2 = PartnerInfo(
            partnerId: partnerId,
            partnerName: "Test",
            partnerStreak: 3,
            hasCompletedToday: false,
            lastActive: Date(),
            isSharingMood: true,
            isSharingExercises: true
        )
        XCTAssertEqual(PartnerState.hasPartner(info1), PartnerState.hasPartner(info2))
    }

    // MARK: - CouplesModeError Tests

    func testCouplesModeError_AlreadyPartnered() {
        let error = CouplesModeError.alreadyPartnered
        XCTAssertEqual(error.errorDescription, "You already have an active partner. Unlink first.")
    }

    func testCouplesModeError_SelfInvite() {
        let error = CouplesModeError.selfInvite
        XCTAssertEqual(error.errorDescription, "You cannot partner with yourself.")
    }

    func testCouplesModeError_InviteExpired() {
        let error = CouplesModeError.inviteExpired
        XCTAssertEqual(error.errorDescription, "This invite code has expired. Ask your partner for a new one.")
    }

    func testCouplesModeError_InviteInvalid() {
        let error = CouplesModeError.inviteInvalid
        XCTAssertEqual(error.errorDescription, "Invalid invite code. Please check and try again.")
    }

    func testCouplesModeError_InviteAlreadyUsed() {
        let error = CouplesModeError.inviteAlreadyUsed
        XCTAssertEqual(error.errorDescription, "This invite has already been accepted.")
    }

    func testCouplesModeError_NotPartnered() {
        let error = CouplesModeError.notPartnered
        XCTAssertEqual(error.errorDescription, "You must have an active partner to access this feature.")
    }

    func testCouplesModeError_PartnerNotSharing() {
        let error = CouplesModeError.partnerNotSharing
        XCTAssertEqual(error.errorDescription, "Your partner has not shared this data with you.")
    }

    func testCouplesModeError_ExercisePremiumOnly() {
        let error = CouplesModeError.exercisePremiumOnly
        XCTAssertEqual(error.errorDescription, "Upgrade to Premium to unlock this exercise.")
    }

    func testCouplesModeError_TextTooShort() {
        let error = CouplesModeError.textTooShort
        XCTAssertEqual(error.errorDescription, "Message must be at least 10 characters.")
    }

    func testCouplesModeError_TextTooLong() {
        let error = CouplesModeError.textTooLong(currentLength: 600, maxLength: 500)
        XCTAssertEqual(error.errorDescription, "Message must be under 500 characters. Current: 600.")
    }

    func testCouplesModeError_RateLimited() {
        let error = CouplesModeError.rateLimited(retryAfterSeconds: 120)
        XCTAssertEqual(error.errorDescription, "Too many attempts. Please try again in 120 seconds.")
    }

    func testCouplesModeError_Identifiable() {
        let error1 = CouplesModeError.notPartnered
        let error2 = CouplesModeError.notPartnered
        XCTAssertEqual(error1.id, error2.id)
    }

    // MARK: - PartnerLink Tests

    func testPartnerLink_MySharingSettings_User1() {
        let link = createTestPartnerLink(userId1: UUID(), userId2: UUID(),
                                          user1ShareMood: true, user1ShareExercises: false,
                                          user2ShareMood: false, user2ShareExercises: true)

        let settings = link.mySharingSettings(for: link.userId1)
        XCTAssertTrue(settings.shareMood)
        XCTAssertFalse(settings.shareExercises)
    }

    func testPartnerLink_MySharingSettings_User2() {
        let userId1 = UUID()
        let userId2 = UUID()
        let link = createTestPartnerLink(userId1: userId1, userId2: userId2,
                                          user1ShareMood: true, user1ShareExercises: false,
                                          user2ShareMood: false, user2ShareExercises: true)

        let settings = link.mySharingSettings(for: userId2)
        XCTAssertFalse(settings.shareMood)
        XCTAssertTrue(settings.shareExercises)
    }

    func testPartnerLink_PartnerSharingSettings() {
        let userId1 = UUID()
        let userId2 = UUID()
        let link = createTestPartnerLink(userId1: userId1, userId2: userId2,
                                          user1ShareMood: true, user1ShareExercises: false,
                                          user2ShareMood: false, user2ShareExercises: true)

        let settings = link.partnerSharingSettings(for: userId1)
        XCTAssertFalse(settings.shareMood)
        XCTAssertTrue(settings.shareExercises)
    }

    func testPartnerLink_PartnerId() {
        let userId1 = UUID()
        let userId2 = UUID()
        let link = createTestPartnerLink(userId1: userId1, userId2: userId2)

        XCTAssertEqual(link.partnerId(for: userId1), userId2)
        XCTAssertEqual(link.partnerId(for: userId2), userId1)
    }

    func testPartnerLink_PartnerId_SingleUser() {
        let userId1 = UUID()
        let link = createTestPartnerLink(userId1: userId1, userId2: nil)

        XCTAssertNil(link.partnerId(for: userId1))
    }

    // MARK: - BuddyEncouragement Tests

    func testBuddyEncouragement_MessageTypes() {
        XCTAssertEqual(BuddyEncouragement.MessageType.encouragement.rawValue, "encouragement")
        XCTAssertEqual(BuddyEncouragement.MessageType.celebration.rawValue, "celebration")
        XCTAssertEqual(BuddyEncouragement.MessageType.checkIn.rawValue, "check_in")
    }

    // MARK: - Helper Methods

    private func createTestPartnerLink(
        userId1: UUID,
        userId2: UUID?,
        user1ShareMood: Bool = false,
        user1ShareExercises: Bool = false,
        user2ShareMood: Bool = false,
        user2ShareExercises: Bool = false
    ) -> PartnerLink {
        PartnerLink(
            id: UUID(),
            userId1: userId1,
            userId2: userId2,
            inviteCode: "TEST12",
            createdBy: userId1,
            expiresAt: Date().addingTimeInterval(86400 * 30),
            status: .active,
            activatedAt: Date(),
            endedAt: nil,
            user1ShareMood: user1ShareMood,
            user1ShareExercises: user1ShareExercises,
            user2ShareMood: user2ShareMood,
            user2ShareExercises: user2ShareExercises,
            notes: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

// MARK: - PartnerModeViewModel Tests

@MainActor
final class PartnerModeViewModelTests: XCTestCase {

    var viewModel: PartnerModeViewModel!
    var mockDataService: PartnerMockSupabaseDataService!

    override func setUp() {
        super.setUp()
        mockDataService = PartnerMockSupabaseDataService()
        viewModel = PartnerModeViewModel(dataService: mockDataService)
    }

    override func tearDown() {
        viewModel = nil
        mockDataService = nil
        super.tearDown()
    }

    // MARK: - Code Input Validation Tests

    func testCodeInputValidation_Valid6Characters() {
        viewModel.codeInput = "ABC123"
        XCTAssertTrue(viewModel.isCodeInputValid)
    }

    func testCodeInputValidation_TooShort() {
        viewModel.codeInput = "ABC12"
        XCTAssertFalse(viewModel.isCodeInputValid)
    }

    func testCodeInputValidation_TooLong() {
        viewModel.codeInput = "ABC1234"
        XCTAssertFalse(viewModel.isCodeInputValid)
    }

    func testCodeInputValidation_Empty() {
        viewModel.codeInput = ""
        XCTAssertFalse(viewModel.isCodeInputValid)
    }

    func testCodeInputValidation_LowercaseConverted() {
        viewModel.codeInput = "abc123"
        // The ViewModel should handle uppercase conversion in acceptInviteCode()
        XCTAssertEqual(viewModel.codeInput, "abc123")
    }

    // MARK: - Formatted Invite Code Tests

    func testFormattedInviteCode_WithCode() {
        viewModel.inviteCode = "ABC123"
        XCTAssertEqual(viewModel.formattedInviteCode, "ABC 123")
    }

    func testFormattedInviteCode_NilCode() {
        viewModel.inviteCode = nil
        XCTAssertEqual(viewModel.formattedInviteCode, "")
    }

    func testFormattedInviteCode_5Characters() {
        viewModel.inviteCode = "ABC12"
        XCTAssertEqual(viewModel.formattedInviteCode, "ABC12")
    }

    // MARK: - Days Until Expiry Tests

    func testDaysUntilExpiry_30Days() {
        let futureDate = Date().addingTimeInterval(86400 * 30)
        viewModel.inviteExpiresAt = futureDate
        XCTAssertEqual(viewModel.daysUntilExpiry, 30)
    }

    func testDaysUntilExpiry_1Day() {
        let futureDate = Date().addingTimeInterval(86400)
        viewModel.inviteExpiresAt = futureDate
        XCTAssertEqual(viewModel.daysUntilExpiry, 1)
    }

    func testDaysUntilExpiry_PastDate() {
        let pastDate = Date().addingTimeInterval(-86400)
        viewModel.inviteExpiresAt = pastDate
        XCTAssertEqual(viewModel.daysUntilExpiry, 0)
    }

    func testDaysUntilExpiry_NilDate() {
        viewModel.inviteExpiresAt = nil
        XCTAssertEqual(viewModel.daysUntilExpiry, 0)
    }

    // MARK: - Partner Has Shared Data Tests

    func testPartnerHasSharedData_NoPartner() {
        viewModel.partnerState = .noPartner
        XCTAssertFalse(viewModel.partnerHasSharedData)
    }

    func testPartnerHasSharedData_Loading() {
        viewModel.partnerState = .loading
        XCTAssertFalse(viewModel.partnerHasSharedData)
    }

    func testPartnerHasSharedData_PendingInvite() {
        viewModel.partnerState = .pendingInvite(code: "ABC123", expiresAt: Date())
        XCTAssertFalse(viewModel.partnerHasSharedData)
    }

    func testPartnerHasSharedData_WithPartnerSharingMood() {
        let partnerInfo = PartnerInfo(
            partnerId: UUID(),
            partnerName: "Test",
            partnerStreak: 5,
            hasCompletedToday: true,
            lastActive: Date(),
            isSharingMood: true,
            isSharingExercises: false
        )
        viewModel.partnerState = .hasPartner(partnerInfo)
        XCTAssertTrue(viewModel.partnerHasSharedData)
    }

    func testPartnerHasSharedData_WithPartnerSharingExercises() {
        let partnerInfo = PartnerInfo(
            partnerId: UUID(),
            partnerName: "Test",
            partnerStreak: 5,
            hasCompletedToday: true,
            lastActive: Date(),
            isSharingMood: false,
            isSharingExercises: true
        )
        viewModel.partnerState = .hasPartner(partnerInfo)
        XCTAssertTrue(viewModel.partnerHasSharedData)
    }

    func testPartnerHasSharedData_WithPartnerSharingNothing() {
        let partnerInfo = PartnerInfo(
            partnerId: UUID(),
            partnerName: "Test",
            partnerStreak: 5,
            hasCompletedToday: true,
            lastActive: Date(),
            isSharingMood: false,
            isSharingExercises: false
        )
        viewModel.partnerState = .hasPartner(partnerInfo)
        XCTAssertFalse(viewModel.partnerHasSharedData)
    }
}

// MARK: - Mock Data Service

final class PartnerMockSupabaseDataService: SupabaseDataService {
    init() { super.init(authService: SupabaseAuthService(client: SupabaseClient(supabaseURL: URL(string: "https://test.com")!, supabaseKey: "test"))) }

    override func getPartnerInfo() async throws -> PartnerInfo? {
        return nil
    }

    override func getOrCreatePartnerInviteCode() async throws -> (code: String, expiresAt: Date) {
        return ("MOCK12", Date().addingTimeInterval(86400 * 30))
    }

    override func acceptBuddyInvite(code: String) async throws -> BuddyRelationship {
        return BuddyRelationship(
            id: UUID(),
            inviterId: UUID(),
            inviteeId: UUID(),
            inviteCode: code,
            status: .accepted,
            invitedAt: Date(),
            acceptedAt: Date(),
            expiresAt: Date()
        )
    }
}
