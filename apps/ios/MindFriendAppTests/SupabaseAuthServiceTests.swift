import XCTest
import struct Supabase.Session
import struct Supabase.User
@testable import MindFriendApp

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
