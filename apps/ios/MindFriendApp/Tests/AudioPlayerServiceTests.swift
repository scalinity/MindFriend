import XCTest
@testable import MindFriendApp

final class AudioPlayerServiceTests: XCTestCase {
    var sut: AudioPlayerService!
    var mockSupabase: MockSupabaseClient!

    override func setUp() {
        super.setUp()
        mockSupabase = MockSupabaseClient()
        sut = AudioPlayerService(supabase: mockSupabase)
    }

    override func tearDown() {
        sut = nil
        mockSupabase = nil
        super.tearDown()
    }

    // MARK: - Playback Control Tests

    func testPlayTrackSetsIsPlayingTrue() async {
        // Given
        let track = createMockTrack()

        // When
        await sut.play(track, context: "test")

        // Then
        XCTAssertTrue(sut.state.isPlaying)
        XCTAssertEqual(sut.state.track?.id, track.id)
    }

    func testPauseSetsIsPlayingFalse() async {
        // Given
        let track = createMockTrack()
        await sut.play(track)

        // When
        sut.pause()

        // Then
        XCTAssertFalse(sut.state.isPlaying)
    }

    func testTogglePlayPauseTogglesState() async {
        // Given
        let track = createMockTrack()
        await sut.play(track)
        XCTAssertTrue(sut.state.isPlaying)

        // When
        sut.togglePlayPause()

        // Then
        XCTAssertFalse(sut.state.isPlaying)

        // When
        sut.togglePlayPause()

        // Then
        XCTAssertTrue(sut.state.isPlaying)
    }

    func testSeekUpdatesCurrentTime() {
        // Given
        let targetTime: TimeInterval = 120

        // When
        sut.seek(to: targetTime)

        // Then
        XCTAssertEqual(sut.state.currentTime, targetTime)
    }

    func testSeekForwardIncreasesTime() {
        // Given
        sut.state.currentTime = 100
        sut.state.duration = 600

        // When
        sut.seekForward(15)

        // Then
        XCTAssertEqual(sut.state.currentTime, 115)
    }

    func testSeekForwardCapsAtDuration() {
        // Given
        sut.state.currentTime = 590
        sut.state.duration = 600

        // When
        sut.seekForward(20)

        // Then
        XCTAssertEqual(sut.state.currentTime, 600)
    }

    func testSeekBackwardDecreasesTime() {
        // Given
        sut.state.currentTime = 100

        // When
        sut.seekBackward(15)

        // Then
        XCTAssertEqual(sut.state.currentTime, 85)
    }

    func testSeekBackwardCapsAtZero() {
        // Given
        sut.state.currentTime = 10

        // When
        sut.seekBackward(20)

        // Then
        XCTAssertEqual(sut.state.currentTime, 0)
    }

    func testStopClearsPlayerState() async {
        // Given
        let track = createMockTrack()
        await sut.play(track)

        // When
        sut.stop()

        // Then
        XCTAssertNil(sut.state.track)
        XCTAssertFalse(sut.state.isPlaying)
        XCTAssertEqual(sut.state.currentTime, 0)
    }

    // MARK: - Sleep Timer Tests

    func testSetSleepTimerStartsTimer() {
        // Given
        let duration = SleepTimerDuration.fifteenMinutes

        // When
        sut.setSleepTimer(duration)

        // Then
        XCTAssertNotNil(sut.sleepTimer)
        XCTAssertEqual(sut.sleepTimerRemaining, TimeInterval(15 * 60))
    }

    func testCancelSleepTimerStopsTimer() {
        // Given
        sut.setSleepTimer(.thirtyMinutes)

        // When
        sut.cancelSleepTimer()

        // Then
        XCTAssertNil(sut.sleepTimer)
        XCTAssertEqual(sut.sleepTimerRemaining, 0)
    }

    func testSleepTimerEndOfTrackDoesNotStartTimer() {
        // Given
        let duration = SleepTimerDuration.endOfTrack

        // When
        sut.setSleepTimer(duration)

        // Then
        XCTAssertNil(sut.sleepTimer)
    }

    // MARK: - Favorites Tests

    func testIsFavoritReturnsTrueForFavoritedTrack() {
        // Given
        let track = createMockTrack()
        sut.favorites.insert(track.id)

        // When
        let result = sut.isFavorite(track)

        // Then
        XCTAssertTrue(result)
    }

    func testIsFavoritReturnsFalseForUnfavoritedTrack() {
        // Given
        let track = createMockTrack()

        // When
        let result = sut.isFavorite(track)

        // Then
        XCTAssertFalse(result)
    }

    func testToggleFavoriteAddsToFavorites() async {
        // Given
        let track = createMockTrack()
        XCTAssertFalse(sut.isFavorite(track))

        // When
        await sut.toggleFavorite(track)

        // Then
        XCTAssertTrue(sut.isFavorite(track))
    }

    func testToggleFavoriteRemovesFromFavorites() async {
        // Given
        let track = createMockTrack()
        sut.favorites.insert(track.id)

        // When
        await sut.toggleFavorite(track)

        // Then
        XCTAssertFalse(sut.isFavorite(track))
    }

    // MARK: - Cache Tests

    func testDownloadForOfflineCachesTrack() async throws {
        // Given
        let track = createMockTrack()

        // When
        try await sut.downloadForOffline(track)

        // Then
        XCTAssertTrue(sut.isDownloadedOffline(track))
    }

    func testRemoveOfflineDownloadDeletesTrack() throws {
        // Given
        let track = createMockTrack()
        sut.isOfflineCached = true

        // When
        try sut.removeOfflineDownload(track)

        // Then
        XCTAssertFalse(sut.isOfflineCached)
    }

    // MARK: - Helper Methods

    private func createMockTrack() -> AudioTrack {
        AudioTrack(
            id: "test-track-\(UUID().uuidString)",
            title: "Test Track",
            slug: "test-track",
            description: "A test track",
            category: .meditation,
            subcategory: nil,
            tags: ["test"],
            audioUrl: URL(string: "https://example.com/audio.mp3")!,
            duration: 600,
            audioFormat: "mp3",
            audioQuality: "high",
            fileSizeBytes: 15000000,
            previewUrl: nil,
            coverImageUrl: nil,
            backgroundImageUrl: nil,
            primaryColor: nil,
            secondaryColor: nil,
            narrator: nil,
            creatorType: .professional,
            language: "en",
            isLoopable: true,
            hasBackgroundMusic: true,
            energyLevel: .calming,
            isPremium: false,
            isFeatured: false,
            playCount: 100,
            completionCount: 50,
            averageRating: 4.5,
            ratingCount: 20
        )
    }
}

// MARK: - Mock Supabase Client

class MockSupabaseClient: SupabaseClient {
    override init(supabaseURL: URL, supabaseKey: String) {
        super.init(supabaseURL: supabaseURL, supabaseKey: supabaseKey)
    }

    // Add mock implementations as needed
}
