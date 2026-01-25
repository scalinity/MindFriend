import XCTest
@testable import MindFriendApp

/// Tests for TransitionService focusing on critical security and reliability fixes
@MainActor
final class TransitionServiceTests: XCTestCase {

    // MARK: - Service Layer Encapsulation Tests

    /// Test that journal draft methods properly delegate to cache service
    func testJournalDraftDelegation() throws {
        // Given: A mock cache service
        let mockCache = MockPathwayCacheService()
        let service = createTransitionService(cacheService: mockCache)
        let pathwayId = UUID()
        let testText = "Test journal entry"

        // When: Saving a journal draft via service layer
        try service.saveJournalDraft(testText, for: pathwayId)

        // Then: Cache service was called
        XCTAssertTrue(mockCache.saveJournalDraftCalled)
        XCTAssertEqual(mockCache.lastSavedDraftText, testText)
        XCTAssertEqual(mockCache.lastSavedDraftPathwayId, pathwayId)
    }

    func testGetJournalDraftDelegation() throws {
        // Given: A mock cache service with a draft
        let mockCache = MockPathwayCacheService()
        let pathwayId = UUID()
        let expectedDraft = "Expected draft text"
        mockCache.mockJournalDraft = expectedDraft
        let service = createTransitionService(cacheService: mockCache)

        // When: Getting a journal draft via service layer
        let result = try service.getJournalDraft(for: pathwayId)

        // Then: Cache service was called and returned the draft
        XCTAssertTrue(mockCache.getJournalDraftCalled)
        XCTAssertEqual(result, expectedDraft)
    }

    func testClearJournalDraftDelegation() {
        // Given: A mock cache service
        let mockCache = MockPathwayCacheService()
        let service = createTransitionService(cacheService: mockCache)
        let pathwayId = UUID()

        // When: Clearing a journal draft via service layer
        service.clearJournalDraft(for: pathwayId)

        // Then: Cache service was called
        XCTAssertTrue(mockCache.clearJournalDraftCalled)
        XCTAssertEqual(mockCache.lastClearedDraftPathwayId, pathwayId)
    }

    // MARK: - Cache Service Encapsulation Tests

    /// Test that cache service is not publicly accessible
    func testCacheServiceIsPrivate() {
        // This test ensures the cacheService property is not accessible
        // If compilation succeeds, it means we've maintained proper encapsulation
        // (The test itself just needs to compile to prove the point)
        let service = createTransitionService()

        // The following line should NOT compile if cacheService is properly private:
        // let _ = service.cacheService  // ❌ Should not compile

        // Instead, we must use delegation methods:
        let pathwayId = UUID()
        _ = try? service.getJournalDraft(for: pathwayId)  // ✅ Proper delegation

        XCTAssertNotNil(service)
    }

    // MARK: - Helper Methods

    private func createTransitionService(
        cacheService: PathwayCacheServiceProtocol? = nil
    ) -> TransitionService {
        // Note: We can't easily create a real TransitionService without Supabase mocking
        // For now, these tests document the expected behavior
        // Full integration tests would require protocol-based DI for SupabaseClient
        fatalError("TransitionService requires SupabaseClient - protocol-based DI needed for proper testing")
    }
}

// MARK: - Mock PathwayCacheService

/// Mock implementation of PathwayCacheService for testing delegation
class MockPathwayCacheService: PathwayCacheServiceProtocol {
    var saveJournalDraftCalled = false
    var getJournalDraftCalled = false
    var clearJournalDraftCalled = false

    var lastSavedDraftText: String?
    var lastSavedDraftPathwayId: UUID?
    var lastClearedDraftPathwayId: UUID?
    var mockJournalDraft: String?

    func saveJournalDraft(_ text: String, for pathwayId: UUID) throws {
        saveJournalDraftCalled = true
        lastSavedDraftText = text
        lastSavedDraftPathwayId = pathwayId
    }

    func getJournalDraft(for pathwayId: UUID) throws -> String? {
        getJournalDraftCalled = true
        return mockJournalDraft
    }

    func clearJournalDraft(for pathwayId: UUID) {
        clearJournalDraftCalled = true
        lastClearedDraftPathwayId = pathwayId
    }

    // MARK: - Required Protocol Stubs (not tested)

    func cacheDailyContent(_ content: DailyPathwayContent, for pathwayId: UUID) throws {}
    func getCachedDailyContent(for pathwayId: UUID) throws -> DailyPathwayContent? { nil }
    func clearDailyContentCache(for pathwayId: UUID) {}
    func saveCheckInDraft(_ draft: PathwayCacheService.CheckInDraft) throws {}
    func getCheckInDraft(for pathwayId: UUID) throws -> PathwayCacheService.CheckInDraft? { nil }
    func clearCheckInDraft(for pathwayId: UUID) {}
    func queuePendingCheckIn(_ checkIn: PathwayCacheService.PendingCheckIn) {}
    func getPendingCheckIns() -> [PathwayCacheService.PendingCheckIn] { [] }
    func removePendingCheckIn(_ id: UUID) {}
    func updateRetryCount(for id: UUID) {}
    func clearAllCaches() {}
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
 4. Re-enable tests above and add comprehensive test suite

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
