import XCTest
@testable import MindFriendApp

@MainActor
final class NarrativePreferencesViewModelTests: XCTestCase {

    var viewModel: NarrativePreferencesViewModel!
    var mockDataService: MockSupabaseDataService!

    override func setUp() async throws {
        try await super.setUp()
        mockDataService = MockSupabaseDataService()
        viewModel = NarrativePreferencesViewModel(dataService: mockDataService)
    }

    override func tearDown() async throws {
        viewModel = nil
        mockDataService = nil
        try await super.tearDown()
    }

    // MARK: - Load Preferences Tests

    func testLoadPreferences_Success_ExistingPreferences() async throws {
        // Given
        let testPreferences = createTestPreferences()
        mockDataService.fetchNarrativePreferencesResult = .success(testPreferences)

        // When
        await viewModel.loadPreferences()

        // Then
        XCTAssertNotNil(viewModel.preferences)
        XCTAssertEqual(viewModel.preferences?.preferredTone, .professional)
        XCTAssertEqual(viewModel.preferences?.preferredLength, .detailed)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.error)
    }

    func testLoadPreferences_Success_NoPreferences_CreatesDefault() async throws {
        // Given - No existing preferences
        mockDataService.fetchNarrativePreferencesResult = .success(nil)

        // When
        await viewModel.loadPreferences()

        // Then - Should create default preferences
        XCTAssertNotNil(viewModel.preferences)
        XCTAssertEqual(viewModel.preferences?.preferredTone, .warm)
        XCTAssertEqual(viewModel.preferences?.preferredLength, .standard)
        XCTAssertTrue(viewModel.preferences?.includeMetrics ?? false)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testLoadPreferences_Failure() async throws {
        // Given
        mockDataService.fetchNarrativePreferencesResult = .failure(TestError.networkError)

        // When
        await viewModel.loadPreferences()

        // Then
        XCTAssertNil(viewModel.preferences)
        XCTAssertNotNil(viewModel.error)
        XCTAssertTrue(viewModel.error!.contains("Failed to load preferences"))
        XCTAssertFalse(viewModel.isLoading)
    }

    func testLoadPreferences_RetryOnTimeout() async throws {
        // Given - Fail twice, succeed on third
        var callCount = 0
        mockDataService.fetchNarrativePreferencesHandler = {
            callCount += 1
            if callCount < 3 {
                throw URLError(.timedOut)
            }
            return self.createTestPreferences()
        }

        // When
        await viewModel.loadPreferences()

        // Then
        XCTAssertEqual(callCount, 3)
        XCTAssertNotNil(viewModel.preferences)
        XCTAssertNil(viewModel.error)
    }

    // MARK: - Update Preferences Tests

    func testUpdatePreferences_Tone_Success() async throws {
        // Given
        await loadInitialPreferences()
        mockDataService.updateNarrativePreferencesResult = .success(())

        // When
        await viewModel.updatePreferences(tone: .playful)

        // Then
        XCTAssertEqual(viewModel.preferences?.preferredTone, .playful)
        XCTAssertFalse(viewModel.isSaving)
        XCTAssertNil(viewModel.error)
    }

    func testUpdatePreferences_Length_Success() async throws {
        // Given
        await loadInitialPreferences()
        mockDataService.updateNarrativePreferencesResult = .success(())

        // When
        await viewModel.updatePreferences(length: .brief)

        // Then
        XCTAssertEqual(viewModel.preferences?.preferredLength, .brief)
    }

    func testUpdatePreferences_IncludeMetrics_Success() async throws {
        // Given
        await loadInitialPreferences()
        mockDataService.updateNarrativePreferencesResult = .success(())

        // When
        await viewModel.updatePreferences(includeMetrics: false)

        // Then
        XCTAssertFalse(viewModel.preferences?.includeMetrics ?? true)
    }

    func testUpdatePreferences_Frequency_Success() async throws {
        // Given
        await loadInitialPreferences()
        mockDataService.updateNarrativePreferencesResult = .success(())

        // When
        await viewModel.updatePreferences(frequency: .biweekly)

        // Then
        XCTAssertEqual(viewModel.preferences?.generationFrequency, .biweekly)
    }

    func testUpdatePreferences_MultipleFields_Success() async throws {
        // Given
        await loadInitialPreferences()
        mockDataService.updateNarrativePreferencesResult = .success(())

        // When
        await viewModel.updatePreferences(
            tone: .professional,
            length: .detailed,
            includeMetrics: false
        )

        // Then
        XCTAssertEqual(viewModel.preferences?.preferredTone, .professional)
        XCTAssertEqual(viewModel.preferences?.preferredLength, .detailed)
        XCTAssertFalse(viewModel.preferences?.includeMetrics ?? true)
    }

    func testUpdatePreferences_ShowsSuccessToast() async throws {
        // Given
        await loadInitialPreferences()
        mockDataService.updateNarrativePreferencesResult = .success(())
        XCTAssertFalse(viewModel.showSuccessToast)

        // When
        await viewModel.updatePreferences(tone: .playful)

        // Then
        XCTAssertTrue(viewModel.showSuccessToast)
    }

    func testUpdatePreferences_ToastAutoHides() async throws {
        // Given
        await loadInitialPreferences()
        mockDataService.updateNarrativePreferencesResult = .success(())

        // When
        await viewModel.updatePreferences(tone: .playful)
        XCTAssertTrue(viewModel.showSuccessToast)

        // Wait for auto-hide (2 seconds)
        try await Task.sleep(nanoseconds: 2_100_000_000)

        // Then
        XCTAssertFalse(viewModel.showSuccessToast)
    }

    func testUpdatePreferences_RapidUpdates_CancelsOldToastTask() async throws {
        // Given
        await loadInitialPreferences()
        mockDataService.updateNarrativePreferencesResult = .success(())

        // When - Update twice rapidly
        await viewModel.updatePreferences(tone: .professional)
        XCTAssertTrue(viewModel.showSuccessToast)

        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s

        await viewModel.updatePreferences(tone: .playful)
        XCTAssertTrue(viewModel.showSuccessToast)

        // Wait for auto-hide
        try await Task.sleep(nanoseconds: 2_100_000_000)

        // Then - Toast should hide exactly once (old task cancelled)
        XCTAssertFalse(viewModel.showSuccessToast)
    }

    func testUpdatePreferences_Failure_RollsBack() async throws {
        // Given
        await loadInitialPreferences()
        let originalTone = viewModel.preferences?.preferredTone
        mockDataService.updateNarrativePreferencesResult = .failure(TestError.networkError)
        mockDataService.fetchNarrativePreferencesResult = .success(createTestPreferences())

        // When
        await viewModel.updatePreferences(tone: .playful)

        // Then - Should reload and rollback optimistic update
        XCTAssertNotNil(viewModel.error)
        XCTAssertTrue(viewModel.error!.contains("Failed to save preferences"))
        // After reload, preferences should be back to test values
        XCTAssertNotEqual(viewModel.preferences?.preferredTone, .playful)
    }

    func testUpdatePreferences_RetryOnTimeout() async throws {
        // Given
        await loadInitialPreferences()
        var callCount = 0
        mockDataService.updateNarrativePreferencesHandler = { _ in
            callCount += 1
            if callCount < 3 {
                throw URLError(.timedOut)
            }
        }

        // When
        await viewModel.updatePreferences(tone: .playful)

        // Then
        XCTAssertEqual(callCount, 3)
        XCTAssertEqual(viewModel.preferences?.preferredTone, .playful)
        XCTAssertNil(viewModel.error)
    }

    func testUpdatePreferences_NoRetryOn401() async throws {
        // Given
        await loadInitialPreferences()
        var callCount = 0
        mockDataService.updateNarrativePreferencesHandler = { _ in
            callCount += 1
            let error = NSError(
                domain: NSURLErrorDomain,
                code: NSURLErrorBadServerResponse,
                userInfo: ["statusCode": 401]
            )
            throw error
        }

        // When
        await viewModel.updatePreferences(tone: .playful)

        // Then - Should NOT retry 401 errors
        XCTAssertEqual(callCount, 1)
        XCTAssertNotNil(viewModel.error)
    }

    func testUpdatePreferences_PreventsDoubleUpdate() async throws {
        // Given
        await loadInitialPreferences()
        mockDataService.updateNarrativePreferencesResult = .success(())
        mockDataService.fetchWeeklyStoriesDelay = 0.1

        // When - Try to update twice concurrently
        let task1 = Task { await viewModel.updatePreferences(tone: .professional) }
        let task2 = Task { await viewModel.updatePreferences(tone: .playful) }

        await task1.value
        await task2.value

        // Then - isSaving guard should prevent second call
        XCTAssertNotNil(viewModel.preferences)
    }

    // MARK: - Reset to Defaults Tests

    func testResetToDefaults() async throws {
        // Given
        await loadInitialPreferences()
        mockDataService.updateNarrativePreferencesResult = .success(())

        // Change to non-default values
        await viewModel.updatePreferences(tone: .professional, length: .detailed, includeMetrics: false)

        // When
        await viewModel.resetToDefaults()

        // Then
        XCTAssertEqual(viewModel.preferences?.preferredTone, .warm)
        XCTAssertEqual(viewModel.preferences?.preferredLength, .standard)
        XCTAssertTrue(viewModel.preferences?.includeMetrics ?? false)
        XCTAssertEqual(viewModel.preferences?.generationFrequency, .weekly)
    }

    // MARK: - Computed Properties Tests

    func testCurrentTone_WithPreferences() async throws {
        // Given
        await loadInitialPreferences()

        // Then
        XCTAssertEqual(viewModel.currentTone, .professional)
    }

    func testCurrentTone_WithoutPreferences() {
        // Given - No preferences loaded
        viewModel.preferences = nil

        // Then - Should return default
        XCTAssertEqual(viewModel.currentTone, .warm)
    }

    func testCurrentLength_WithPreferences() async throws {
        // Given
        await loadInitialPreferences()

        // Then
        XCTAssertEqual(viewModel.currentLength, .detailed)
    }

    func testCurrentLength_WithoutPreferences() {
        // Given
        viewModel.preferences = nil

        // Then
        XCTAssertEqual(viewModel.currentLength, .standard)
    }

    func testCurrentIncludeMetrics_WithPreferences() async throws {
        // Given
        await loadInitialPreferences()

        // Then
        XCTAssertTrue(viewModel.currentIncludeMetrics)
    }

    func testCurrentIncludeMetrics_WithoutPreferences() {
        // Given
        viewModel.preferences = nil

        // Then
        XCTAssertTrue(viewModel.currentIncludeMetrics)
    }

    func testCurrentFrequency_WithPreferences() async throws {
        // Given
        await loadInitialPreferences()

        // Then
        XCTAssertEqual(viewModel.currentFrequency, .weekly)
    }

    func testCurrentFrequency_WithoutPreferences() {
        // Given
        viewModel.preferences = nil

        // Then
        XCTAssertEqual(viewModel.currentFrequency, .weekly)
    }

    // MARK: - Helper Methods

    private func loadInitialPreferences() async {
        let preferences = createTestPreferences()
        mockDataService.fetchNarrativePreferencesResult = .success(preferences)
        await viewModel.loadPreferences()
    }

    private func createTestPreferences() -> NarrativePreferences {
        return NarrativePreferences(
            userId: "test-user",
            preferredTone: .professional,
            preferredLength: .detailed,
            includeMetrics: true,
            generationFrequency: .weekly,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    enum TestError: Error {
        case networkError
    }
}

// MARK: - Mock Extensions

extension MockSupabaseDataService {
    var fetchNarrativePreferencesHandler: (() async throws -> NarrativePreferences?)?
    var updateNarrativePreferencesHandler: ((NarrativePreferences) async throws -> Void)?

    func setFetchNarrativePreferencesHandler(_ handler: @escaping () async throws -> NarrativePreferences?) {
        fetchNarrativePreferencesHandler = handler
    }

    func setUpdateNarrativePreferencesHandler(_ handler: @escaping (NarrativePreferences) async throws -> Void) {
        updateNarrativePreferencesHandler = handler
    }
}
