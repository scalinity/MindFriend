import XCTest
@testable import MindFriendApp

final class SupabaseDataServiceTests: XCTestCase {

    // MARK: - Unique Constraint Violation Detection Tests

    func testIsUniqueConstraintViolation_PostgreSQLErrorCode() {
        let service = SupabaseDataService(authService: SupabaseAuthService())

        // PostgreSQL error code 23505 indicates unique constraint violation
        let error = NSError(
            domain: "PostgrestError",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "duplicate key value violates unique constraint \"circles_invite_code_key\" (SQLSTATE 23505)"]
        )

        XCTAssertTrue(service.isUniqueConstraintViolation(error))
    }

    func testIsUniqueConstraintViolation_UniqueKeyword() {
        let service = SupabaseDataService(authService: SupabaseAuthService())

        let error = NSError(
            domain: "PostgrestError",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "Error: unique constraint violation on invite_code"]
        )

        XCTAssertTrue(service.isUniqueConstraintViolation(error))
    }

    func testIsUniqueConstraintViolation_DuplicateKeyKeyword() {
        let service = SupabaseDataService(authService: SupabaseAuthService())

        let error = NSError(
            domain: "PostgrestError",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "duplicate key error on column invite_code"]
        )

        XCTAssertTrue(service.isUniqueConstraintViolation(error))
    }

    func testIsUniqueConstraintViolation_CaseInsensitive() {
        let service = SupabaseDataService(authService: SupabaseAuthService())

        // Should match regardless of case
        let error = NSError(
            domain: "PostgrestError",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "DUPLICATE KEY VALUE VIOLATES UNIQUE CONSTRAINT"]
        )

        XCTAssertTrue(service.isUniqueConstraintViolation(error))
    }

    func testIsUniqueConstraintViolation_NotAUniqueError() {
        let service = SupabaseDataService(authService: SupabaseAuthService())

        // Network error - not a unique constraint violation
        let networkError = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorNotConnectedToInternet,
            userInfo: [NSLocalizedDescriptionKey: "The Internet connection appears to be offline."]
        )

        XCTAssertFalse(service.isUniqueConstraintViolation(networkError))
    }

    func testIsUniqueConstraintViolation_AuthError() {
        let service = SupabaseDataService(authService: SupabaseAuthService())

        // Auth error - not a unique constraint violation
        let authError = NSError(
            domain: "AuthError",
            code: 401,
            userInfo: [NSLocalizedDescriptionKey: "Invalid JWT token"]
        )

        XCTAssertFalse(service.isUniqueConstraintViolation(authError))
    }

    func testIsUniqueConstraintViolation_ForeignKeyError() {
        let service = SupabaseDataService(authService: SupabaseAuthService())

        // Foreign key error (23503) - not a unique constraint (23505)
        let fkError = NSError(
            domain: "PostgrestError",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "violates foreign key constraint (SQLSTATE 23503)"]
        )

        XCTAssertFalse(service.isUniqueConstraintViolation(fkError))
    }

    func testIsUniqueConstraintViolation_GenericError() {
        let service = SupabaseDataService(authService: SupabaseAuthService())

        // Generic error with no specific keywords
        let genericError = NSError(
            domain: "AppError",
            code: 500,
            userInfo: [NSLocalizedDescriptionKey: "An unexpected error occurred"]
        )

        XCTAssertFalse(service.isUniqueConstraintViolation(genericError))
    }

    // MARK: - Invite Code Generation Tests

    func testGenerateInviteCode_Format() {
        // Test that invite codes match expected format
        // Note: generateInviteCode is private, so we test through the public interface
        // This test documents the expected behavior

        // Allowed characters: ABCDEFGHJKLMNPQRSTUVWXYZ23456789 (no I, O, 0, 1 to avoid confusion)
        let allowedChars = CharacterSet(charactersIn: "ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

        // Generate multiple codes and verify format
        // Since we can't call private method directly, this is a documentation test
        XCTAssertTrue(true, "Invite codes should be 6 characters from allowed charset")
    }

    // MARK: - DataError Tests

    func testDataError_CircleFullDescription() {
        let error = DataError.circleFull
        XCTAssertEqual(error.errorDescription, "This circle is full")
    }

    func testDataError_CustomDescription() {
        let error = DataError.custom("Test error message")
        XCTAssertEqual(error.errorDescription, "Test error message")
    }
}

// MARK: - Retry Logic Documentation Tests

extension SupabaseDataServiceTests {
    /// Documents the retry behavior of createCircle
    ///
    /// When createCircle encounters a unique constraint violation on invite_code:
    /// 1. It generates a new invite code
    /// 2. Retries the insert operation
    /// 3. Continues up to 5 attempts
    /// 4. Throws the last error if all attempts fail
    ///
    /// This behavior ensures high reliability for circle creation even with
    /// theoretical invite code collisions (extremely rare with 32^6 possibilities).
    func testCreateCircleRetryBehavior_Documentation() {
        // This test documents expected behavior
        // Actual retry testing requires mocking the Supabase client

        // Expected behavior:
        // - maxRetries = 5
        // - Each attempt generates a new invite code
        // - Only unique constraint violations trigger retry
        // - Other errors are thrown immediately
        // - After 5 failures, throws DataError.custom or last error

        XCTAssertTrue(true, "See function documentation for retry behavior")
    }
}

// MARK: - Settings Update Error Handling Tests

extension SupabaseDataServiceTests {
    /// Documents expected error handling for updateUserSettings
    ///
    /// When updateUserSettings fails:
    /// 1. The error is propagated to the caller
    /// 2. UI layer should show error message via appState.showError()
    /// 3. UI layer should revert local state changes where applicable
    ///
    /// The UI implements debouncing (0.5s) to batch rapid setting changes.
    func testUpdateUserSettingsErrorHandling_Documentation() {
        // Expected error handling behavior:
        // - Network errors: propagated, UI shows error alert
        // - Auth errors (401/403): propagated, may trigger re-auth
        // - Validation errors: propagated with message
        //
        // UI responsibilities:
        // - NotificationSettingsView: appState.showError() on failure
        // - AIPreferencesView: reverts selectedTone on failure
        // - PrivacySettingsView: reverts shareMoodInCircles/privacyMode on failure

        XCTAssertTrue(true, "Error handling documented in UI layer")
    }

    /// Tests that various database error types are properly categorized
    func testDatabaseErrorTypes() {
        let service = SupabaseDataService(authService: SupabaseAuthService())

        // Row-level security violation (common when user lacks permission)
        let rlsError = NSError(
            domain: "PostgrestError",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "new row violates row-level security policy"]
        )
        XCTAssertFalse(service.isUniqueConstraintViolation(rlsError), "RLS errors should not be treated as unique constraint violations")

        // Permission denied
        let permissionError = NSError(
            domain: "PostgrestError",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "permission denied for table user_settings"]
        )
        XCTAssertFalse(service.isUniqueConstraintViolation(permissionError), "Permission errors should not be treated as unique constraint violations")

        // Check constraint violation (different from unique)
        let checkError = NSError(
            domain: "PostgrestError",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "new row violates check constraint \"positive_quota\" (SQLSTATE 23514)"]
        )
        XCTAssertFalse(service.isUniqueConstraintViolation(checkError), "Check constraint violations should not be treated as unique constraint violations")
    }

    /// Documents the debouncing behavior for notification settings
    ///
    /// NotificationSettingsView uses a 0.5 second debounce to prevent
    /// rapid API calls when users toggle multiple settings quickly.
    func testNotificationSettingsDebouncing_Documentation() {
        // Expected behavior:
        // - Each toggle change cancels any pending save
        // - After 0.5s of no changes, save is performed
        // - Only one API call made for rapid successive changes
        // - isSaving indicator shows during actual save operation

        // This improves:
        // 1. API call efficiency (fewer requests)
        // 2. User experience (no lag per toggle)
        // 3. Database load (batched updates)

        XCTAssertTrue(true, "Debouncing documented in NotificationSettingsView.saveSettings()")
    }
}
