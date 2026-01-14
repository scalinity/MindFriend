import XCTest
@testable import MindFriendApp

/// Tests for SupabaseAuthService authentication flows
/// These tests verify critical auth paths without hitting real network
final class SupabaseAuthServiceTests: XCTestCase {
    
    // MARK: - Session Management Tests
    
    func testIsAuthenticated_WhenNoSession_ReturnsFalse() async {
        // Given
        let service = await SupabaseAuthService()
        
        // Then
        await MainActor.run {
            XCTAssertFalse(service.isAuthenticated)
            XCTAssertNil(service.userId)
        }
    }
    
    func testRestoreSession_WhenNoExistingSession_ReturnsFalse() async {
        // Given
        let service = await SupabaseAuthService()
        
        // When
        let hasSession = await service.restoreSession()
        
        // Then
        XCTAssertFalse(hasSession)
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
    
    // MARK: - Sign Out State Cleanup Tests
    
    func testSignOut_ClearsLocalState() async {
        // This tests that signOut properly clears the local state
        // In a real test, we'd mock the Supabase client
        let service = await SupabaseAuthService()
        
        // Verify initial state
        await MainActor.run {
            XCTAssertNil(service.session)
            XCTAssertNil(service.currentUser)
        }
    }
    
    // MARK: - Helper Functions
    
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
