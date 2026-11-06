import XCTest
import Supabase
@testable import MindFriendApp

final class PartnerModeTests: XCTestCase {

    // MARK: - Invite Code Validation Tests

    func testPartnerInviteCodeUsesEightCaseSensitiveBase58Characters() {
        XCTAssertTrue(PartnerModeViewModel.isValidInviteCode("Ab7x2Qp9"))
        XCTAssertTrue(PartnerModeViewModel.isValidInviteCode("11111111"))
        XCTAssertFalse(PartnerModeViewModel.isValidInviteCode("ABC123"))
        XCTAssertFalse(PartnerModeViewModel.isValidInviteCode("Ab7x2Qp90"))
        XCTAssertFalse(PartnerModeViewModel.isValidInviteCode("Ab7x2Qp0"))
        XCTAssertFalse(PartnerModeViewModel.isValidInviteCode("Ab7x2Qpl"))
        XCTAssertFalse(PartnerModeViewModel.isValidInviteCode(""))
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

// MARK: - Actual partner invitation route regressions

@MainActor
final class PartnerInvitationRouteTests: XCTestCase {
    func testGenerateAndAcceptUseCouplesEndpointsAndPreserveCodeCase() async throws {
        PartnerInviteURLProtocol.requests = []
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PartnerInviteURLProtocol.self]
        let client = SupabaseClient(supabaseURL: URL(string: "https://partner-fixture.invalid")!, supabaseKey: "synthetic-anon",
            options: .init(auth: .init(storage: PartnerInviteStorage(), autoRefreshToken: false),
                           global: .init(session: URLSession(configuration: config))))
        let api = PartnerInvitationClient(client: client)
        let invitation = try await api.create()
        XCTAssertEqual(invitation.code, "Ab7x2Qp9")
        XCTAssertGreaterThan(invitation.expiresAt, Date())
        XCTAssertEqual(PartnerInviteURLProtocol.requests.first?.url?.lastPathComponent, "couples-partner-links")
        try await api.accept(code: invitation.code)
        let accepted = try XCTUnwrap(PartnerInviteURLProtocol.requests.last)
        XCTAssertEqual(accepted.url?.lastPathComponent, "couples-partner-links-accept")
        let body = try XCTUnwrap(accepted.httpBody)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: body) as? [String: String], ["inviteCode": "Ab7x2Qp9"])
        XCTAssertEqual(PartnerInviteURLProtocol.requests.count, 2, "No buddy mutation or external account request")
    }
}

private struct PartnerInviteStorage: AuthLocalStorage {
    func store(key: String, value: Data) throws {}
    func retrieve(key: String) throws -> Data? { nil }
    func remove(key: String) throws {}
}
private final class PartnerInviteURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var recorded: [URLRequest] = []
    static var requests: [URLRequest] {
        get { lock.lock(); defer { lock.unlock() }; return recorded }
        set { lock.lock(); defer { lock.unlock() }; recorded = newValue }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var captured = request
        if captured.httpBody == nil, let stream = captured.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            captured.httpBody = data
        }
        Self.lock.lock(); Self.recorded.append(captured); Self.lock.unlock()
        let response: [String: String]
        switch request.url?.lastPathComponent {
        case "couples-partner-links":
            response = ["inviteCode": "Ab7x2Qp9", "expiresAt": ISO8601DateFormatter.string(from: Date().addingTimeInterval(3600), timeZone: .init(secondsFromGMT: 0)!, formatOptions: [.withInternetDateTime, .withFractionalSeconds])]
        case "couples-partner-links-accept": response = ["status": "active"]
        default:
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: response))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
