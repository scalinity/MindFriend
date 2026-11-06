import XCTest
import struct Supabase.Session
import struct Supabase.User
@testable import MindFriendApp

final class DurablePathwayKeyTests: XCTestCase {
    private var keychainService: String!
    private let firstOwner = UUID()
    private let secondOwner = UUID()

    override func setUp() {
        super.setUp()
        keychainService = "app.mindfriend.tests.pathway.\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        for identifier in ["legacy", firstOwner.uuidString, secondOwner.uuidString] {
            try SecureStorage(keychainService: keychainService, keyIdentifier: identifier).deleteEncryptionKey()
        }
        try super.tearDownWithError()
    }

    private func makeService(owner: UUID?) -> PathwayEncryptionService {
        let namespace = keychainService!
        return PathwayEncryptionService(
            secureStorage: SecureStorage(keychainService: namespace, keyIdentifier: "legacy"),
            userId: owner,
            storageForUser: { SecureStorage(keychainService: namespace, keyIdentifier: $0.uuidString) }
        )
    }

    func testJournalSurvivesLogoutAndServiceRecreation() throws {
        let service = makeService(owner: firstOwner)
        let ciphertext = try service.encryptString("Retained pathway journal")
        service.setCurrentUser(nil)
        XCTAssertThrowsError(try service.decryptString(ciphertext))

        let restored = makeService(owner: firstOwner)
        XCTAssertEqual(try restored.decryptString(ciphertext), "Retained pathway journal")
    }

    func testAnotherAccountCannotDecryptNewJournal() throws {
        let service = makeService(owner: firstOwner)
        let ciphertext = try service.encryptString("First account journal")
        service.setCurrentUser(secondOwner)
        XCTAssertThrowsError(try service.decryptString(ciphertext))
        let secondCiphertext = try service.encryptString("Second account journal")
        service.setCurrentUser(firstOwner)
        XCTAssertEqual(try service.decryptString(ciphertext), "First account journal")
        XCTAssertThrowsError(try service.decryptString(secondCiphertext))
    }

    func testLegacyJournalStillDecryptsAfterMemoryKeyEviction() throws {
        let legacy = SecureStorage(keychainService: keychainService, keyIdentifier: "legacy")
        let ciphertext = try legacy.encrypt("Legacy retained journal").base64EncodedString()
        legacy.clearCachedKey()
        XCTAssertEqual(try makeService(owner: firstOwner).decryptString(ciphertext), "Legacy retained journal")
    }
}

@MainActor
final class AccountBriefingIsolationTests: XCTestCase {
    func testAccountSwitchClearsBriefingAndIgnoresLatePriorAccountResult() async {
        let firstOwner = UUID(), secondOwner = UUID()
        var owner: UUID? = firstOwner
        let provider = SuspendedBriefingProvider()
        let model = DailyBriefingViewModel(briefingService: provider, calendarService: CalendarService(), currentUserId: { owner })
        let firstRequest = expectation(description: "First account request started")
        await provider.onRequest { firstRequest.fulfill() }
        let firstLoad = Task { await model.loadTodaysBriefing() }
        await fulfillment(of: [firstRequest], timeout: 2)

        owner = secondOwner
        model.resetForAccountChange(to: secondOwner)
        XCTAssertNil(model.briefing)
        XCTAssertNil(model.preferences)
        XCTAssertFalse(model.isLoading)
        let secondRequest = expectation(description: "Second account request started")
        await provider.onRequest { secondRequest.fulfill() }
        let secondLoad = Task { await model.loadTodaysBriefing() }
        await fulfillment(of: [secondRequest], timeout: 2)
        await provider.complete(1, with: Self.briefing(owner: secondOwner))
        await secondLoad.value
        await provider.complete(0, with: Self.briefing(owner: firstOwner))
        await firstLoad.value
        XCTAssertEqual(model.briefing?.userId, secondOwner)
        XCTAssertFalse(model.isLoading)
        await model.loadTodaysBriefing()
        let count = await provider.requestCount
        XCTAssertEqual(count, 2, "Only this account's same-day successful result may be reused")
    }

    func testSignOutInvalidatesInFlightBriefing() async {
        let firstOwner = UUID()
        var owner: UUID? = firstOwner
        let provider = SuspendedBriefingProvider()
        let model = DailyBriefingViewModel(briefingService: provider, calendarService: CalendarService(), currentUserId: { owner })
        let requested = expectation(description: "Request started")
        await provider.onRequest { requested.fulfill() }
        let load = Task { await model.loadTodaysBriefing() }
        await fulfillment(of: [requested], timeout: 2)
        owner = nil
        model.resetForAccountChange(to: nil)
        await provider.complete(0, with: Self.briefing(owner: firstOwner))
        await load.value
        XCTAssertNil(model.briefing)
        XCTAssertNil(model.preferences)
        XCTAssertFalse(model.isLoading)
    }

    private static func briefing(owner: UUID) -> DailyBriefing {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return DailyBriefing(id: UUID(), userId: owner, localDate: formatter.string(from: Date()),
                             greeting: "Fixture", predictedMood: nil, moodContext: nil, questId: nil,
                             questTitle: nil, calendarEvents: [], suggestion: "Fixture", generatedAt: Date(),
                             lastViewedAt: nil, wellnessScore: nil, importantDates: nil, audioText: nil,
                             audioUrl: nil, voicePlayed: nil)
    }
}

private actor SuspendedBriefingProvider: DailyBriefingProviding {
    private var pending: [Int: CheckedContinuation<DailyBriefing?, Error>] = [:]
    private var didRequest: (() -> Void)?
    private(set) var requestCount = 0

    func onRequest(_ action: @escaping () -> Void) { didRequest = action }
    func fetchTodaysBriefing() async throws -> DailyBriefing? {
        let request = requestCount
        requestCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            pending[request] = continuation
            didRequest?()
        }
    }
    func complete(_ request: Int, with briefing: DailyBriefing) {
        pending.removeValue(forKey: request)?.resume(returning: briefing)
    }
    func generateBriefing(localDate: String, timezone: String, calendarEvents: [BriefingCalendarEvent]) async throws -> DailyBriefing {
        throw CancellationError()
    }
    func markViewed(briefingId: UUID) async throws { }
    func fetchPreferences() async throws -> BriefingPreferences { .default }
    func updatePreferences(_ preferences: BriefingPreferences) async throws { }
}

@MainActor
final class LocalLogoutCompletionTests: XCTestCase {
    private enum FixtureError: Error { case remoteUnavailable, localRemovalFailed }

    func testRemoteFailureStillRemovesCredentialsAndAwaitsCleanup() async throws {
        var events: [String] = []
        let remoteFailed = try await SupabaseAuthService.finishLogout(
            revokeRemote: { events.append("remote"); throw FixtureError.remoteUnavailable },
            removeLocalCredentials: { events.append("credentials") },
            cleanup: { await Task.yield(); events.append("cleanup") }
        )
        XCTAssertTrue(remoteFailed)
        XCTAssertEqual(events, ["remote", "credentials", "cleanup"])
    }

    func testLocalCredentialFailureCannotReturnLogoutSuccess() async {
        var cleanupRan = false
        do {
            _ = try await SupabaseAuthService.finishLogout(
                revokeRemote: { },
                removeLocalCredentials: { throw FixtureError.localRemovalFailed },
                cleanup: { cleanupRan = true }
            )
            XCTFail("Local credential removal failure must remain visible")
        } catch FixtureError.localRemovalFailed { }
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertFalse(cleanupRan, "Keep the active UI until local credentials are actually removed")
    }

    func testConfirmedRevocationWaitsForLocalCleanup() async throws {
        var cleanupRan = false
        let remoteFailed = try await SupabaseAuthService.finishLogout(
            revokeRemote: { }, removeLocalCredentials: { },
            cleanup: { await Task.yield(); cleanupRan = true }
        )
        XCTAssertFalse(remoteFailed)
        XCTAssertTrue(cleanupRan)
    }
}

/// Tests for SupabaseAuthService authentication flows
/// Session fixtures do not initialize the shared client or read device credentials.
final class SupabaseAuthServiceTests: XCTestCase {
    
    // MARK: - Session Management Tests
    
    func testValidatedSession_WhenSDKCannotReadSession_ThrowsSessionUnavailable() {
        let signedIn = makeSession()

        assertSessionUnavailable(nil, expectedUserId: signedIn.user.id)
    }

    func testValidatedSession_WhenStoredUserDiffers_ThrowsSessionUnavailable() {
        assertSessionUnavailable(makeSession(), expectedUserId: UUID())
    }

    func testValidatedSession_WhenAccessTokenIsEmpty_ThrowsSessionUnavailable() {
        let stored = makeSession(accessToken: "")
        assertSessionUnavailable(stored, expectedUserId: stored.user.id)
    }

    func testValidatedSession_WhenExpiredOrInsideSDKExpiryBuffer_ThrowsSessionUnavailable() {
        for lifetime: TimeInterval in [-60, 10] {
            let stored = makeSession(expiresIn: lifetime)
            assertSessionUnavailable(stored, expectedUserId: stored.user.id)
        }
    }

    func testValidatedSession_WhenReadableAndValid_ReturnsStoredSession() throws {
        let stored = makeSession()

        let validated = try SupabaseAuthService.validatedSession(stored, expectedUserId: stored.user.id)

        XCTAssertEqual(validated, stored)
    }

    func testValidatedSession_WhenSameUserTokenRotates_AcceptsCurrentSDKSession() throws {
        let signedIn = makeSession()
        var refreshed = signedIn
        refreshed.accessToken = "synthetic-refreshed-access-token"
        refreshed.refreshToken = "synthetic-refreshed-refresh-token"
        refreshed.expiresAt += 3600

        let validated = try SupabaseAuthService.validatedSession(refreshed, expectedUserId: signedIn.user.id)

        XCTAssertEqual(validated, refreshed)
    }
    
    // MARK: - Input Validation Tests
    
    func testHandleValidation_ValidHandle_Passes() async {
        // Valid handles: lowercase letters, numbers, underscores, 3-30 chars
        let validHandles = ["user_123", "john_doe", "a1b2c3", "abc", "a".padding(toLength: 30, withPad: "b", startingAt: 0)]
        
        for handle in validHandles {
            let isValid = isValidHandle(handle)
            XCTAssertTrue(isValid, "Handle '\(handle)' should be valid")
        }
    }
    
    func testHandleValidation_InvalidHandle_Fails() async {
        // Invalid handles: too short, too long, uppercase, special chars
        let invalidHandles = [
            "ab",           // Too short
            "AB_CD",        // Uppercase
            "user-name",    // Hyphen not allowed
            "user.name",    // Period not allowed
            "user name",    // Space not allowed
            "user@name",    // Special char
            String(repeating: "a", count: 31)  // Too long
        ]
        
        for handle in invalidHandles {
            let isValid = isValidHandle(handle)
            XCTAssertFalse(isValid, "Handle '\(handle)' should be invalid")
        }
    }
    
    // MARK: - Error Type Tests
    
    func testAuthError_ErrorDescriptions_AreUserFriendly() {
        // Verify all auth errors have user-friendly descriptions
        let errors: [AuthError] = [
            .invalidCredentials,
            .missingIdToken,
            .emailConfirmationRequired,
            .userNotFound,
            .accountNotFound,
            .sessionExpired,
            .sessionUnavailable,
            .profileUnavailable,
            .handleTaken,
            .invalidHandle,
            .unknown("Test error")
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error \(error) should have description")
            XCTAssertFalse(error.errorDescription!.isEmpty, "Error description should not be empty")
        }
    }
    
    func testAuthError_InvalidCredentials_HasCorrectMessage() {
        let error = AuthError.invalidCredentials
        XCTAssertEqual(error.errorDescription, "Incorrect email or password. Please try again.")
    }
    
    func testAuthError_EmailConfirmationRequired_HasCorrectMessage() {
        let error = AuthError.emailConfirmationRequired
        XCTAssertEqual(error.errorDescription, "Please check your email to confirm your account")
    }
    
    func testAuthError_SessionExpired_HasCorrectMessage() {
        let error = AuthError.sessionExpired
        XCTAssertEqual(error.errorDescription, "Your session has expired. Please sign in again")
    }
    
    func testAuthError_SessionUnavailable_DoesNotClaimAccountIsMissing() {
        XCTAssertEqual(
            AuthError.sessionUnavailable.errorDescription,
            "Unable to keep you signed in. Please try signing in again."
        )
    }

    func testAuthError_ProfileUnavailableOffersRetryWithoutAccountClaim() {
        XCTAssertEqual(AuthError.profileUnavailable.errorDescription,
                       "We couldn't load your profile. Check your connection and try again.")
    }
    
    // MARK: - Helper Functions

    private func assertSessionUnavailable(_ stored: Session?, expectedUserId: UUID) {
        do {
            _ = try SupabaseAuthService.validatedSession(stored, expectedUserId: expectedUserId)
            XCTFail("Expected session unavailable")
        } catch AuthError.sessionUnavailable {
        } catch {
            XCTFail("Expected session unavailable, got \(error)")
        }
    }

    private func makeSession(accessToken: String = "synthetic-access-token", expiresIn: TimeInterval = 3600) -> Session {
        let now = Date()
        let user = User(
            id: UUID(),
            appMetadata: [:],
            userMetadata: [:],
            aud: "authenticated",
            createdAt: now,
            role: "authenticated",
            updatedAt: now
        )
        return Session(
            accessToken: accessToken,
            tokenType: "bearer",
            expiresIn: expiresIn,
            expiresAt: now.timeIntervalSince1970 + expiresIn,
            refreshToken: "synthetic-refresh-token",
            user: user
        )
    }
    
    private func isValidHandle(_ handle: String) -> Bool {
        let normalizedHandle = handle.lowercased().trimmingCharacters(in: .whitespaces)
        let handleRegex = /^[a-z0-9_]{3,30}$/
        return normalizedHandle.wholeMatch(of: handleRegex) != nil
    }
}

// MARK: - Mock Helpers (for future expansion)

/// Mock profile for testing
extension SupabaseAuthServiceTests {
    struct MockProfile {
        let id: String
        let handle: String
        let displayName: String
        let email: String?
        
        static let testUser = MockProfile(
            id: "test-user-id",
            handle: "test_user",
            displayName: "Test User",
            email: "test@example.com"
        )
    }
}
