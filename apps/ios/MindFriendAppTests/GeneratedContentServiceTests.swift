import XCTest
@testable import MindFriendApp

@MainActor
final class GeneratedContentServiceTests: XCTestCase {

    // MARK: - Content Type Tests

    func testContentTypeDisplayNames() {
        XCTAssertEqual(GeneratedContentType.sleepStory.displayName, "Sleep Story")
        XCTAssertEqual(GeneratedContentType.meditation.displayName, "Meditation")
        XCTAssertEqual(GeneratedContentType.breathing.displayName, "Breathing Exercise")
        XCTAssertEqual(GeneratedContentType.grounding.displayName, "Grounding Exercise")
        XCTAssertEqual(GeneratedContentType.mindfulness.displayName, "Mindfulness")
        XCTAssertEqual(GeneratedContentType.cbt.displayName, "CBT Exercise")
        XCTAssertEqual(GeneratedContentType.journaling.displayName, "Journaling Prompt")
        XCTAssertEqual(GeneratedContentType.affirmation.displayName, "Affirmation")
    }

    func testContentTypeIcons() {
        XCTAssertEqual(GeneratedContentType.sleepStory.icon, "moon.stars.fill")
        XCTAssertEqual(GeneratedContentType.meditation.icon, "brain.head.profile")
        XCTAssertEqual(GeneratedContentType.breathing.icon, "wind")
        XCTAssertEqual(GeneratedContentType.grounding.icon, "leaf.fill")
    }

    func testContentTypeSupportsAudio() {
        // These types support audio
        XCTAssertTrue(GeneratedContentType.sleepStory.supportsAudio)
        XCTAssertTrue(GeneratedContentType.meditation.supportsAudio)
        XCTAssertTrue(GeneratedContentType.breathing.supportsAudio)
        XCTAssertTrue(GeneratedContentType.grounding.supportsAudio)
        XCTAssertTrue(GeneratedContentType.mindfulness.supportsAudio)
        XCTAssertTrue(GeneratedContentType.affirmation.supportsAudio)

        // These types do not support audio
        XCTAssertFalse(GeneratedContentType.cbt.supportsAudio)
        XCTAssertFalse(GeneratedContentType.journaling.supportsAudio)
    }

    func testContentTypeDefaultDurations() {
        XCTAssertEqual(GeneratedContentType.sleepStory.defaultDuration, 20)
        XCTAssertEqual(GeneratedContentType.meditation.defaultDuration, 10)
        XCTAssertEqual(GeneratedContentType.breathing.defaultDuration, 5)
        XCTAssertEqual(GeneratedContentType.grounding.defaultDuration, 5)
        XCTAssertEqual(GeneratedContentType.cbt.defaultDuration, 15)
        XCTAssertEqual(GeneratedContentType.journaling.defaultDuration, 10)
    }

    // MARK: - GeneratedContent Tests

    func testGeneratedContentFormattedDuration() {
        let contentWithDuration = createTestContent(duration: 600)
        XCTAssertEqual(contentWithDuration.formattedDuration, "10 min")

        let contentWithSeconds = createTestContent(duration: 90)
        XCTAssertEqual(contentWithSeconds.formattedDuration, "1m 30s")

        let contentWithoutDuration = createTestContent(duration: nil)
        XCTAssertEqual(contentWithoutDuration.formattedDuration, "--")
    }

    func testGeneratedContentHasAudio() {
        let contentWithAudio = createTestContent(audioUrl: "https://example.com/audio.mp3")
        XCTAssertTrue(contentWithAudio.hasAudio)

        let contentWithoutAudio = createTestContent(audioUrl: nil)
        XCTAssertFalse(contentWithoutAudio.hasAudio)

        let contentWithEmptyAudio = createTestContent(audioUrl: "")
        XCTAssertFalse(contentWithEmptyAudio.hasAudio)
    }

    // MARK: - ContentQuotaStatus Tests

    func testQuotaStatusRemaining() {
        let status = ContentQuotaStatus(used: 1, limit: 3, isPremium: false, resetsAt: nil)
        XCTAssertEqual(status.remaining, 2)

        let exhaustedStatus = ContentQuotaStatus(used: 3, limit: 3, isPremium: false, resetsAt: nil)
        XCTAssertEqual(exhaustedStatus.remaining, 0)
    }

    func testQuotaStatusPercentUsed() {
        let status = ContentQuotaStatus(used: 1, limit: 4, isPremium: false, resetsAt: nil)
        XCTAssertEqual(status.percentUsed, 0.25, accuracy: 0.01)
    }

    func testQuotaStatusIsExhausted() {
        let notExhausted = ContentQuotaStatus(used: 2, limit: 3, isPremium: false, resetsAt: nil)
        XCTAssertFalse(notExhausted.isExhausted)

        let exhausted = ContentQuotaStatus(used: 3, limit: 3, isPremium: false, resetsAt: nil)
        XCTAssertTrue(exhausted.isExhausted)
    }

    // MARK: - Voice Tests

    func testDefaultVoiceAllContainsExpectedVoices() {
        let voices = DefaultVoice.all
        XCTAssertEqual(voices.count, 5)

        let voiceIds = voices.map { $0.id }
        XCTAssertTrue(voiceIds.contains(DefaultVoice.sarah.id))
        XCTAssertTrue(voiceIds.contains(DefaultVoice.josh.id))
        XCTAssertTrue(voiceIds.contains(DefaultVoice.adam.id))
        XCTAssertTrue(voiceIds.contains(DefaultVoice.rachel.id))
        XCTAssertTrue(voiceIds.contains(DefaultVoice.elli.id))
    }

    func testDefaultVoiceLookup() {
        let voice = DefaultVoice.voice(for: DefaultVoice.sarah.id)
        XCTAssertNotNil(voice)
        XCTAssertEqual(voice?.name, "Sarah")
        XCTAssertEqual(voice?.gender, .female)

        let unknownVoice = DefaultVoice.voice(for: "unknown-id")
        XCTAssertNil(unknownVoice)
    }

    // MARK: - Background Sound Tests

    func testBackgroundSoundDisplayNames() {
        XCTAssertEqual(BackgroundSoundType.rain.displayName, "Rain")
        XCTAssertEqual(BackgroundSoundType.ocean.displayName, "Ocean Waves")
        XCTAssertEqual(BackgroundSoundType.forest.displayName, "Forest")
        XCTAssertEqual(BackgroundSoundType.fireplace.displayName, "Fireplace")
        XCTAssertEqual(BackgroundSoundType.whiteNoise.displayName, "White Noise")
        XCTAssertEqual(BackgroundSoundType.silence.displayName, "Silence")
    }

    func testBackgroundSoundIcons() {
        XCTAssertEqual(BackgroundSoundType.rain.icon, "cloud.rain.fill")
        XCTAssertEqual(BackgroundSoundType.ocean.icon, "water.waves")
        XCTAssertEqual(BackgroundSoundType.forest.icon, "tree.fill")
        XCTAssertEqual(BackgroundSoundType.silence.icon, "speaker.slash.fill")
    }

    // MARK: - Content Flag Reason Tests

    func testContentFlagReasonDisplayNames() {
        XCTAssertEqual(ContentFlagReason.inappropriate.displayName, "Inappropriate")
        XCTAssertEqual(ContentFlagReason.inaccurate.displayName, "Inaccurate")
        XCTAssertEqual(ContentFlagReason.harmful.displayName, "Harmful")
        XCTAssertEqual(ContentFlagReason.offensive.displayName, "Offensive")
        XCTAssertEqual(ContentFlagReason.triggering.displayName, "Triggering")
    }

    // MARK: - Generate Content Request Tests

    func testGenerateContentRequestParams() {
        let params = GenerateContentParams(
            duration: 10,
            voiceId: "test-voice-id",
            backgroundSound: .ocean,
            theme: "peaceful",
            focus: "sleep",
            approach: "mindfulness",
            customPrompt: "Make it relaxing"
        )

        XCTAssertEqual(params.duration, 10)
        XCTAssertEqual(params.voiceId, "test-voice-id")
        XCTAssertEqual(params.backgroundSound, .ocean)
        XCTAssertEqual(params.theme, "peaceful")
        XCTAssertEqual(params.focus, "sleep")
        XCTAssertEqual(params.approach, "mindfulness")
        XCTAssertEqual(params.customPrompt, "Make it relaxing")
    }

    // MARK: - Generated Content Series Tests

    func testSeriesProgress() {
        let series = GeneratedContentSeries(
            id: UUID(),
            userId: UUID(),
            title: "7-Day Meditation",
            description: "A week-long meditation journey",
            contentType: .meditation,
            totalParts: 7,
            completedParts: 3,
            theme: "anxiety",
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        XCTAssertEqual(series.progress, 3.0 / 7.0, accuracy: 0.01)
        XCTAssertFalse(series.isComplete)

        let completedSeries = GeneratedContentSeries(
            id: UUID(),
            userId: UUID(),
            title: "Completed Series",
            description: nil,
            contentType: .meditation,
            totalParts: 5,
            completedParts: 5,
            theme: nil,
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        XCTAssertEqual(completedSeries.progress, 1.0)
        XCTAssertTrue(completedSeries.isComplete)
    }

    // MARK: - Helper Methods

    private func createTestContent(
        id: UUID = UUID(),
        userId: UUID = UUID(),
        contentType: GeneratedContentType = .meditation,
        title: String = "Test Content",
        textContent: String = "Test text content",
        audioUrl: String? = nil,
        duration: Int? = 300,
        status: GeneratedContentStatus = .completed
    ) -> GeneratedContent {
        GeneratedContent(
            id: id,
            userId: userId,
            contentType: contentType,
            title: title,
            textContent: textContent,
            audioUrl: audioUrl,
            voiceId: nil,
            duration: duration,
            qualityScore: nil,
            status: status,
            generationPrompt: nil,
            aiModel: nil,
            processingTimeMs: nil,
            triggerWarnings: nil,
            averageRating: nil,
            ratingCount: 0,
            seriesId: nil,
            seriesOrder: nil,
            isFavorite: false,
            playCount: 0,
            lastPlayedAt: nil,
            generationContext: nil,
            userRating: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

// MARK: - Content Validation Tests

@MainActor
final class ContentValidationTests: XCTestCase {

    func testContentDisclaimerStandard() {
        let disclaimer = ContentDisclaimer.standard
        XCTAssertTrue(disclaimer.contains("AI-generated"))
        XCTAssertTrue(disclaimer.contains("wellness"))
        XCTAssertTrue(disclaimer.contains("not a substitute"))
        XCTAssertTrue(disclaimer.contains("988"))
    }
}
