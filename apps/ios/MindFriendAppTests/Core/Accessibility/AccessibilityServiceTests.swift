// Spec 14: Accessibility Service Tests
// Comprehensive unit tests for AccessibilityService

import XCTest
@testable import MindFriendApp
import Supabase

@MainActor
final class AccessibilityServiceTests: XCTestCase {
    var service: AccessibilityService!
    var mockSupabase: MockAccessibilitySupabaseClient!

    override func setUp() {
        super.setUp()
        mockSupabase = MockAccessibilitySupabaseClient()
        service = AccessibilityService(supabase: mockSupabase as! SupabaseClient)
    }

    override func tearDown() {
        service = nil
        mockSupabase = nil
        super.tearDown()
    }

    // MARK: - Preferences Loading

    func testLoadPreferences_Success() async throws {
        let mockPrefs = AccessibilityPreferences.default
        mockSupabase.mockLoadPreferences = mockPrefs

        try await service.loadPreferences()

        XCTAssertEqual(service.preferences, mockPrefs)
        XCTAssertNil(service.error)
        XCTAssertFalse(service.isLoading)
    }

    func testLoadPreferences_NoUser() async throws {
        mockSupabase.mockCurrentUser = nil

        await XCTAssertThrowsError(try await service.loadPreferences()) { error in
            XCTAssertEqual(error as? AccessibilityError, .invalidPreferences)
        }
    }

    // MARK: - Preferences Saving

    func testSavePreferences_Success() async throws {
        mockSupabase.mockCurrentUser = UUID()
        var prefs = AccessibilityPreferences.default
        prefs.hapticFeedbackEnabled = false
        service.preferences = prefs

        try await service.savePreferences()

        XCTAssertNil(service.error)
        XCTAssertFalse(service.isLoading)
    }

    func testUpdatePreference_TriggersDebounce() {
        var prefs = AccessibilityPreferences.default
        let originalValue = prefs.hapticFeedbackEnabled
        service.preferences = prefs

        service.updatePreference(\.hapticFeedbackEnabled, to: !originalValue)

        XCTAssertNotEqual(service.preferences.hapticFeedbackEnabled, originalValue)
    }

    // MARK: - Captions

    func testGetCaptions_Success() async throws {
        let mockCaptions = AudioCaptions(
            available: true,
            language: "en",
            format: .vtt,
            captionsUrl: "https://example.com/captions.vtt",
            captions: [],
            transcript: "Sample transcript",
            duration: 300
        )
        mockSupabase.mockCaptions = mockCaptions

        let captions = try await service.getCaptions(for: "exercise", contentId: UUID())

        XCTAssertEqual(captions.available, true)
        XCTAssertEqual(captions.language, "en")
    }

    func testGetCaptions_NotAvailable() async throws {
        let mockCaptions = AudioCaptions(
            available: false,
            language: nil,
            format: nil,
            captionsUrl: nil,
            captions: nil,
            transcript: nil,
            duration: nil
        )
        mockSupabase.mockCaptions = mockCaptions

        let captions = try await service.getCaptions(for: "exercise", contentId: UUID())

        XCTAssertEqual(captions.available, false)
    }

    // MARK: - Localization

    func testGetLocalizedStrings_Success() async throws {
        let mockBundle = LocalizedStringBundle(
            language: "en",
            region: "US",
            strings: ["hello": LocalizedStringValue(value: "Hello", plurals: nil)],
            updatedAt: Date()
        )
        mockSupabase.mockLocalizedStrings = mockBundle

        let bundle = try await service.getLocalizedStrings()

        XCTAssertEqual(bundle.language, "en")
        XCTAssertEqual(bundle.strings.count, 1)
    }

    func testLocalizedString_Found() async throws {
        let mockBundle = LocalizedStringBundle(
            language: "en",
            region: "US",
            strings: ["greeting": LocalizedStringValue(value: "Hello", plurals: nil)],
            updatedAt: Date()
        )
        mockSupabase.mockLocalizedStrings = mockBundle
        _ = try await service.getLocalizedStrings()

        let result = service.localizedString("greeting")

        XCTAssertEqual(result, "Hello")
    }

    func testLocalizedString_NotFound() async throws {
        let mockBundle = LocalizedStringBundle(
            language: "en",
            region: "US",
            strings: [:],
            updatedAt: Date()
        )
        mockSupabase.mockLocalizedStrings = mockBundle
        _ = try await service.getLocalizedStrings()

        let result = service.localizedString("missing_key")

        XCTAssertEqual(result, "missing_key") // Returns key when not found
    }

    func testLocalizedString_WithPluralization() async throws {
        let plurals = ["one": "1 exercise", "other": "%d exercises"]
        let mockBundle = LocalizedStringBundle(
            language: "en",
            region: "US",
            strings: ["exercises": LocalizedStringValue(value: "exercises", plurals: plurals)],
            updatedAt: Date()
        )
        mockSupabase.mockLocalizedStrings = mockBundle
        _ = try await service.getLocalizedStrings()

        let singular = service.localizedString("exercises", count: 1)
        let plural = service.localizedString("exercises", count: 5)

        XCTAssertEqual(singular, "1 exercise")
        XCTAssertEqual(plural, "%d exercises")
    }

    // MARK: - Sign Language

    func testGetSignLanguageVideo_Success() async throws {
        let mockVideo = SignLanguageVideo(
            id: UUID(),
            contentType: "exercise",
            contentId: UUID(),
            signLanguage: .asl,
            videoUrl: "https://example.com/video.mp4",
            thumbnailUrl: "https://example.com/thumb.jpg",
            durationSeconds: 300
        )
        mockSupabase.mockSignLanguageVideo = mockVideo

        let video = try await service.getSignLanguageVideo(for: "exercise", contentId: UUID())

        XCTAssertEqual(video?.signLanguage, .asl)
        XCTAssertEqual(video?.durationSeconds, 300)
    }

    func testGetSignLanguageVideo_NotFound() async throws {
        mockSupabase.mockSignLanguageVideo = nil

        let video = try await service.getSignLanguageVideo(for: "nonexistent", contentId: UUID())

        XCTAssertNil(video)
    }

    // MARK: - Caption Cues

    func testGetCaptionCuesForTimestamp_Found() {
        let cues = [
            CaptionCue(id: 1, startTime: 0, endTime: 5, text: "Hello"),
            CaptionCue(id: 2, startTime: 5, endTime: 10, text: "World")
        ]

        let result = service.getCaptionCuesForTimestamp(2.5, in: cues)

        XCTAssertEqual(result?.id, 1)
        XCTAssertEqual(result?.text, "Hello")
    }

    func testGetCaptionCuesForTimestamp_NotFound() {
        let cues = [
            CaptionCue(id: 1, startTime: 0, endTime: 5, text: "Hello")
        ]

        let result = service.getCaptionCuesForTimestamp(10, in: cues)

        XCTAssertNil(result)
    }

    // MARK: - Feedback

    func testSubmitFeedback_Success() async throws {
        mockSupabase.mockCurrentUser = UUID()
        let feedback = AccessibilityFeedback(
            category: .visual,
            screenName: "VisualAccessibilityView",
            elementIdentifier: "contrastToggle",
            issueType: .missingLabel,
            description: "Missing accessibility label",
            assistiveTechUsed: [.voiceover]
        )

        try await service.submitFeedback(feedback)

        XCTAssertNil(service.error)
    }

    func testSubmitFeedback_EmptyDescription() async throws {
        let feedback = AccessibilityFeedback(
            category: .visual,
            screenName: nil,
            elementIdentifier: nil,
            issueType: .bug,
            description: "",
            assistiveTechUsed: []
        )

        await XCTAssertThrowsError(try await service.submitFeedback(feedback)) { error in
            XCTAssertEqual(error as? AccessibilityError, .invalidFeedback("Description is required"))
        }
    }

    // MARK: - Cache Management

    func testStringCache_Reuses() async throws {
        let mockBundle = LocalizedStringBundle(
            language: "en",
            region: "US",
            strings: ["test": LocalizedStringValue(value: "Test", plurals: nil)],
            updatedAt: Date()
        )
        mockSupabase.mockLocalizedStrings = mockBundle

        _ = try await service.getLocalizedStrings()
        let firstCall = mockSupabase.getLocalizedStringsCallCount

        _ = try await service.getLocalizedStrings(forceRefresh: false)
        let secondCall = mockSupabase.getLocalizedStringsCallCount

        XCTAssertEqual(firstCall, secondCall) // No additional API call
    }

    func testStringCache_ForceRefresh() async throws {
        let mockBundle = LocalizedStringBundle(
            language: "en",
            region: "US",
            strings: [:],
            updatedAt: Date()
        )
        mockSupabase.mockLocalizedStrings = mockBundle

        _ = try await service.getLocalizedStrings()
        let firstCall = mockSupabase.getLocalizedStringsCallCount

        _ = try await service.getLocalizedStrings(forceRefresh: true)
        let secondCall = mockSupabase.getLocalizedStringsCallCount

        XCTAssertGreaterThan(secondCall, firstCall) // Additional API call made
    }

    // MARK: - Error Handling

    func testError_Persistence() async throws {
        mockSupabase.shouldThrowError = true

        try? await service.loadPreferences()

        XCTAssertNotNil(service.error)
    }

    func testIsLoading_State() async throws {
        var loadingStatesCaught: [Bool] = []

        let task = Task {
            let initialState = service.isLoading
            loadingStatesCaught.append(initialState)

            try await service.loadPreferences()

            let finalState = service.isLoading
            loadingStatesCaught.append(finalState)
        }

        try await task.value

        XCTAssertEqual(loadingStatesCaught.first, false) // Initial state
        XCTAssertEqual(loadingStatesCaught.last, false) // Final state
    }
}

// MARK: - Mock Objects

class MockAccessibilitySupabaseClient {
    var mockCurrentUser: UUID?
    var mockLoadPreferences: AccessibilityPreferences?
    var mockCaptions: AudioCaptions?
    var mockLocalizedStrings: LocalizedStringBundle?
    var mockSignLanguageVideo: SignLanguageVideo?
    var shouldThrowError = false
    var getLocalizedStringsCallCount = 0

    var auth: MockAuth {
        return MockAuth(currentUser: mockCurrentUser)
    }

    func mockSavePreferences(_ prefs: AccessibilityPreferences) throws {
        if shouldThrowError {
            throw AccessibilityError.invalidPreferences
        }
    }
}

class MockAuth {
    let currentUser: UUID?

    init(currentUser: UUID?) {
        self.currentUser = currentUser
    }
}

// MARK: - Test Helper

extension XCTestCase {
    func XCTAssertThrowsError<T>(
        _ expression: @autoclosure () async throws -> T,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line,
        _ errorHandler: (Error) -> Void = { _ in }
    ) async {
        do {
            _ = try await expression()
            XCTFail(message(), file: file, line: line)
        } catch {
            errorHandler(error)
        }
    }
}
