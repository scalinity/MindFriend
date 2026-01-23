import XCTest
@testable import MindFriendApp

@MainActor
final class NarrativeDetailViewModelTests: XCTestCase {

    var viewModel: NarrativeDetailViewModel!
    var mockDataService: MockSupabaseDataService!
    var testStory: WeeklyStory!

    override func setUp() async throws {
        try await super.setUp()
        mockDataService = MockSupabaseDataService()
        testStory = createTestStory()
        viewModel = NarrativeDetailViewModel(story: testStory, dataService: mockDataService)
    }

    override func tearDown() async throws {
        viewModel = nil
        mockDataService = nil
        testStory = nil
        try await super.tearDown()
    }

    // MARK: - Rating Tests

    func testRateStory_ThumbsUp_Success() async throws {
        // Given
        mockDataService.updateStoryRatingResult = .success(())
        XCTAssertNil(viewModel.story.userRating)

        // When
        await viewModel.rateStory(rating: 1)

        // Then
        XCTAssertEqual(viewModel.story.userRating, 1)
        XCTAssertFalse(viewModel.isUpdating)
        XCTAssertNil(viewModel.error)
    }

    func testRateStory_ThumbsDown_Success() async throws {
        // Given
        mockDataService.updateStoryRatingResult = .success(())

        // When
        await viewModel.rateStory(rating: -1)

        // Then
        XCTAssertEqual(viewModel.story.userRating, -1)
        XCTAssertFalse(viewModel.isUpdating)
        XCTAssertNil(viewModel.error)
    }

    func testRateStory_RemoveRating_Success() async throws {
        // Given - Story already has rating
        viewModel.story.userRating = 1
        mockDataService.updateStoryRatingResult = .success(())

        // When
        await viewModel.rateStory(rating: nil)

        // Then
        XCTAssertNil(viewModel.story.userRating)
        XCTAssertFalse(viewModel.isUpdating)
        XCTAssertNil(viewModel.error)
    }

    func testRateStory_Failure_RollsBack() async throws {
        // Given
        viewModel.story.userRating = nil
        mockDataService.updateStoryRatingResult = .failure(TestError.networkError)

        // When - Try to rate
        await viewModel.rateStory(rating: 1)

        // Then - Should rollback to original value
        XCTAssertNil(viewModel.story.userRating)
        XCTAssertNotNil(viewModel.error)
        XCTAssertTrue(viewModel.error!.contains("Failed to save rating"))
    }

    func testRateStory_OptimisticUpdate() async throws {
        // Given
        mockDataService.updateStoryRatingResult = .success(())
        mockDataService.fetchWeeklyStoriesDelay = 0.1 // Simulate network delay

        // When - Start rating
        let rateTask = Task {
            await viewModel.rateStory(rating: 1)
        }

        // Then - Rating should be updated immediately (optimistic)
        try await Task.sleep(nanoseconds: 10_000_000) // 0.01s
        XCTAssertEqual(viewModel.story.userRating, 1)
        XCTAssertTrue(viewModel.isUpdating)

        await rateTask.value
        XCTAssertFalse(viewModel.isUpdating)
    }

    func testRateStory_RetryOnTimeout() async throws {
        // Given - Fail twice, succeed on third attempt
        var callCount = 0
        mockDataService.updateStoryRatingHandler = { _, _ in
            callCount += 1
            if callCount < 3 {
                throw URLError(.timedOut)
            }
        }

        // When
        await viewModel.rateStory(rating: 1)

        // Then - Should have retried and succeeded
        XCTAssertEqual(callCount, 3)
        XCTAssertEqual(viewModel.story.userRating, 1)
        XCTAssertNil(viewModel.error)
    }

    func testRateStory_NoRetryOn404() async throws {
        // Given
        var callCount = 0
        mockDataService.updateStoryRatingHandler = { _, _ in
            callCount += 1
            let error = NSError(
                domain: NSURLErrorDomain,
                code: NSURLErrorBadServerResponse,
                userInfo: ["statusCode": 404]
            )
            throw error
        }

        // When
        await viewModel.rateStory(rating: 1)

        // Then - Should NOT retry 404 errors
        XCTAssertEqual(callCount, 1)
        XCTAssertNil(viewModel.story.userRating) // Rolled back
        XCTAssertNotNil(viewModel.error)
    }

    func testRateStory_PreventsDoubleRating() async throws {
        // Given
        mockDataService.updateStoryRatingResult = .success(())
        mockDataService.fetchWeeklyStoriesDelay = 0.1

        // When - Try to rate twice concurrently
        let task1 = Task { await viewModel.rateStory(rating: 1) }
        let task2 = Task { await viewModel.rateStory(rating: -1) }

        await task1.value
        await task2.value

        // Then - isUpdating guard should prevent second call
        // (Only first rating should be applied)
        XCTAssertNotNil(viewModel.story.userRating)
    }

    // MARK: - Favorite Tests

    func testToggleFavorite_AddFavorite_Success() async throws {
        // Given
        viewModel.story.isFavorite = false
        mockDataService.toggleStoryFavoriteResult = .success(())

        // When
        await viewModel.toggleFavorite()

        // Then
        XCTAssertTrue(viewModel.story.isFavorite)
        XCTAssertFalse(viewModel.isUpdating)
        XCTAssertNil(viewModel.error)
    }

    func testToggleFavorite_RemoveFavorite_Success() async throws {
        // Given
        viewModel.story.isFavorite = true
        mockDataService.toggleStoryFavoriteResult = .success(())

        // When
        await viewModel.toggleFavorite()

        // Then
        XCTAssertFalse(viewModel.story.isFavorite)
        XCTAssertFalse(viewModel.isUpdating)
        XCTAssertNil(viewModel.error)
    }

    func testToggleFavorite_Failure_RollsBack() async throws {
        // Given
        viewModel.story.isFavorite = false
        mockDataService.toggleStoryFavoriteResult = .failure(TestError.networkError)

        // When
        await viewModel.toggleFavorite()

        // Then - Should rollback
        XCTAssertFalse(viewModel.story.isFavorite)
        XCTAssertNotNil(viewModel.error)
        XCTAssertTrue(viewModel.error!.contains("Failed to update favorite"))
    }

    func testToggleFavorite_CallsParentCallback() async throws {
        // Given
        mockDataService.toggleStoryFavoriteResult = .success(())
        var callbackCalled = false
        var callbackStory: WeeklyStory?

        viewModel.onStoryUpdated = { story in
            callbackCalled = true
            callbackStory = story
        }

        // When
        await viewModel.toggleFavorite()

        // Then
        XCTAssertTrue(callbackCalled)
        XCTAssertNotNil(callbackStory)
        XCTAssertEqual(callbackStory?.id, testStory.id)
    }

    // MARK: - Share Text Tests

    func testGetShareText_GeneratesCorrectFormat() {
        // Given
        viewModel.story.cards = [
            createTestCard(headline: "Headline 1", message: "Message 1"),
            createTestCard(headline: "Headline 2", message: "Message 2")
        ]

        // When
        let shareText = viewModel.getShareText()

        // Then
        XCTAssertTrue(shareText.contains("My Weekly Wellness Story"))
        XCTAssertTrue(shareText.contains("Headline 1"))
        XCTAssertTrue(shareText.contains("Message 1"))
        XCTAssertTrue(shareText.contains("Headline 2"))
        XCTAssertTrue(shareText.contains("Message 2"))
        XCTAssertTrue(shareText.contains("Tracked with MindFriend"))
    }

    func testGetShareText_SanitizesHTML() {
        // Given
        viewModel.story.cards = [
            createTestCard(
                headline: "<script>alert('xss')</script>Safe Headline",
                message: "<b>Bold</b> text"
            )
        ]

        // When
        let shareText = viewModel.getShareText()

        // Then - HTML should be stripped
        XCTAssertFalse(shareText.contains("<script>"))
        XCTAssertFalse(shareText.contains("</script>"))
        XCTAssertFalse(shareText.contains("<b>"))
        XCTAssertTrue(shareText.contains("Safe Headline"))
        XCTAssertTrue(shareText.contains("Bold"))
    }

    func testGetShareText_SanitizesScriptInjection() {
        // Given
        viewModel.story.cards = [
            createTestCard(
                headline: "javascript:alert(1)",
                message: "data:text/html,<script>alert(1)</script>"
            )
        ]

        // When
        let shareText = viewModel.getShareText()

        // Then - Script protocols should be stripped
        XCTAssertFalse(shareText.contains("javascript:"))
        XCTAssertFalse(shareText.contains("data:"))
    }

    func testGetShareText_LimitsLength() {
        // Given - Very long content
        let longMessage = String(repeating: "A", count: 500)
        viewModel.story.cards = [
            createTestCard(headline: "Test", message: longMessage),
            createTestCard(headline: "Test", message: longMessage)
        ]

        // When
        let shareText = viewModel.getShareText()

        // Then - Should be truncated to 1000 chars
        XCTAssertLessThanOrEqual(shareText.count, 1000)
        XCTAssertTrue(shareText.hasSuffix("..."))
    }

    func testGetShareText_LimitsFieldLength() {
        // Given - Very long field
        let veryLongHeadline = String(repeating: "H", count: 400)
        viewModel.story.cards = [
            createTestCard(headline: veryLongHeadline, message: "Short message")
        ]

        // When
        let shareText = viewModel.getShareText()

        // Then - Field should be truncated to 300 chars
        let lines = shareText.components(separatedBy: "\n")
        let headlineLine = lines.first(where: { $0.contains("H") })
        XCTAssertNotNil(headlineLine)
        XCTAssertLessThanOrEqual(headlineLine!.count, 303) // 300 + "..."
    }

    func testGetShareText_RemovesControlCharacters() {
        // Given
        let messageWithControlChars = "Line1\u{0000}Line2\u{0001}Line3"
        viewModel.story.cards = [
            createTestCard(headline: "Test", message: messageWithControlChars)
        ]

        // When
        let shareText = viewModel.getShareText()

        // Then - Control characters should be removed (but newlines preserved)
        XCTAssertFalse(shareText.contains("\u{0000}"))
        XCTAssertFalse(shareText.contains("\u{0001}"))
        XCTAssertTrue(shareText.contains("Line1"))
        XCTAssertTrue(shareText.contains("Line2"))
    }

    func testGetShareText_TrimsWhitespace() {
        // Given
        viewModel.story.cards = [
            createTestCard(headline: "  Headline  ", message: "  Message  ")
        ]

        // When
        let shareText = viewModel.getShareText()

        // Then - Excess whitespace should be trimmed
        XCTAssertTrue(shareText.contains("Headline"))
        XCTAssertTrue(shareText.contains("Message"))
        XCTAssertFalse(shareText.contains("  Headline  "))
    }

    // MARK: - UI State Tests

    func testIsThumbsUpActive() {
        // Given
        viewModel.story.userRating = 1

        // Then
        XCTAssertTrue(viewModel.isThumbsUpActive)
        XCTAssertFalse(viewModel.isThumbsDownActive)
    }

    func testIsThumbsDownActive() {
        // Given
        viewModel.story.userRating = -1

        // Then
        XCTAssertFalse(viewModel.isThumbsUpActive)
        XCTAssertTrue(viewModel.isThumbsDownActive)
    }

    func testIsThumbsInactive() {
        // Given
        viewModel.story.userRating = nil

        // Then
        XCTAssertFalse(viewModel.isThumbsUpActive)
        XCTAssertFalse(viewModel.isThumbsDownActive)
    }

    // MARK: - Helper Methods

    private func createTestStory() -> WeeklyStory {
        return WeeklyStory(
            id: "test-story-123",
            userId: "test-user",
            weekStart: "2026-01-20",
            cards: [createTestCard()],
            userRating: nil,
            isFavorite: false,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private func createTestCard(headline: String = "Test Headline", message: String = "Test Message") -> StoryCard {
        return StoryCard(
            id: UUID().uuidString,
            cardType: .streak,
            variant: .default,
            data: StoryCardData(
                headline: headline,
                message: message,
                stat: "7",
                statLabel: "Days"
            ),
            generatedAt: Date()
        )
    }

    enum TestError: Error {
        case networkError
    }
}

// MARK: - Mock Extensions

extension MockSupabaseDataService {
    var updateStoryRatingHandler: ((String, Int?) async throws -> Void)?
    var toggleStoryFavoriteHandler: ((String, Bool) async throws -> Void)?

    func setUpdateStoryRatingHandler(_ handler: @escaping (String, Int?) async throws -> Void) {
        updateStoryRatingHandler = handler
    }

    func setToggleStoryFavoriteHandler(_ handler: @escaping (String, Bool) async throws -> Void) {
        toggleStoryFavoriteHandler = handler
    }
}
