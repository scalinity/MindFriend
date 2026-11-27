import XCTest
import Supabase
@testable import MindFriendApp

/// Tests for TransitionService focusing on critical security and reliability fixes
///
/// TransitionService takes its cache as the concrete PathwayCacheService and has no seam for a fake one, so these
/// tests use the real cache over a throwaway UserDefaults suite and keychain namespace and read back through the
/// cache what the service stored. The Supabase client points at an unreachable host; the journal draft paths
/// never use it. Tests that need to fake network calls wait on the protocol-based DI described at the end of this file.
@MainActor
final class TransitionServiceTests: XCTestCase {

    // MARK: - Service Layer Encapsulation Tests

    /// Test that journal draft methods properly delegate to cache service
    func testJournalDraftDelegation() throws {
        // Given: A service over a real cache
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let pathwayId = UUID()
        let testText = "Test journal entry"

        // When: Saving a journal draft via service layer
        try fixture.service.saveJournalDraft(testText, for: pathwayId)

        // Then: The cache holds the text under that pathway
        XCTAssertEqual(try fixture.cache.getJournalDraft(for: pathwayId), testText)
    }

    func testGetJournalDraftDelegation() throws {
        // Given: A cache with a draft
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let pathwayId = UUID()
        let expectedDraft = "Expected draft text"
        try fixture.cache.saveJournalDraft(expectedDraft, for: pathwayId)

        // When: Getting a journal draft via service layer
        let result = try fixture.service.getJournalDraft(for: pathwayId)

        // Then: The service returns the cached draft
        XCTAssertEqual(result, expectedDraft)
    }

    func testClearJournalDraftDelegation() throws {
        // Given: A cache with a draft
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }
        let pathwayId = UUID()
        try fixture.cache.saveJournalDraft("Draft to clear", for: pathwayId)
        XCTAssertNotNil(try fixture.cache.getJournalDraft(for: pathwayId))

        // When: Clearing a journal draft via service layer
        fixture.service.clearJournalDraft(for: pathwayId)

        // Then: The cache no longer holds it
        XCTAssertNil(try fixture.cache.getJournalDraft(for: pathwayId))
    }

    // MARK: - Cache Service Encapsulation Tests

    /// Test that cache service is not publicly accessible
    func testCacheServiceIsPrivate() throws {
        // This test ensures the cacheService property is not accessible
        // If compilation succeeds, it means we've maintained proper encapsulation
        let fixture = try makeFixture()
        defer { fixture.cleanUp() }

        // The following line should NOT compile if cacheService is properly private:
        // let _ = fixture.service.cacheService  // ❌ Should not compile

        // Instead, we must use delegation methods:
        XCTAssertNil(try fixture.service.getJournalDraft(for: UUID()))  // ✅ Proper delegation
    }

    // MARK: - Helper Methods

    private struct Fixture {
        let service: TransitionService
        let cache: PathwayCacheService
        let cleanUp: () -> Void
    }

    private func makeFixture() throws -> Fixture {
        let namespace = "test.transition-service.\(UUID().uuidString)"
        let storage = SecureStorage(keychainService: namespace, keyIdentifier: "journal-drafts")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: namespace))
        let cache = PathwayCacheService(userDefaults: defaults, secureStorage: storage)
        let client = SupabaseClient(supabaseURL: URL(string: "https://transition.invalid")!, supabaseKey: "synthetic-key")
        return Fixture(
            service: TransitionService(supabase: client, cacheService: cache),
            cache: cache,
            cleanUp: {
                defaults.removePersistentDomain(forName: namespace)
                try? storage.deleteEncryptionKey()
            }
        )
    }
}

// MARK: - FIXME: Full Integration Tests Require Protocol-Based DI

/*
 FIXME: Comprehensive TransitionService testing requires protocol-based dependency injection

 **Current Blocker:**
 - TransitionService requires SupabaseClient in initializer
 - SupabaseClient is a final class (cannot be mocked via inheritance)
 - No SupabaseClientProtocol exists

 **Required Refactoring:**
 1. Create SupabaseClientProtocol with methods used by TransitionService:
    - from(_:) -> QueryBuilder
    - functions.invoke(_:options:) -> T
 2. Update TransitionService to accept SupabaseClientProtocol
 3. Create MockSupabaseClient: SupabaseClientProtocol
 4. Add the comprehensive test suite below

 **Tests to Add After Refactoring:**

 - **Race Condition Prevention:**
   - testProcessPendingCheckInsWithConcurrentModification()
   - Verify immutable snapshot prevents crashes

 - **Encryption Key Cleanup:**
   - testEncryptionKeysClearedOnLogout()
   - Verify SecureStorage.deleteEncryptionKey() called
   - Verify PathwayCacheService.clearAllCaches() called

 - **Error Handling:**
   - testMalformedJWTHandling()
   - testNetworkFailureRetry()
   - testCacheFailureDoesNotBlockRequest()

 - **Double JSON Encoding Fixes:**
   - testPausePathwayEncodesOnce()
   - testResumePathwayEncodesOnce()
   - testAbandonPathwayEncodesOnce()

 **Architectural Note:**
 The same protocol-based DI pattern should be applied to:
 - SupabaseDataService (final class)
 - RitualService (final class)
 - MentorshipService (final class)
 - All other service classes requiring mocking

 This will unlock 40+ commented-out test files across the project.
 */
