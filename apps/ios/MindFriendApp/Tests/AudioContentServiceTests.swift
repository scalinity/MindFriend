import XCTest
@testable import MindFriendApp

final class AudioContentServiceTests: XCTestCase {
    var sut: AudioContentService!
    var mockSupabase: MockSupabaseClient!

    override func setUp() {
        super.setUp()
        mockSupabase = MockSupabaseClient()
        sut = AudioContentService(supabase: mockSupabase)
    }

    override func tearDown() {
        sut = nil
        mockSupabase = nil
        super.tearDown()
    }

    // MARK: - Fetch All Tracks Tests

    func testFetchAllTracksReturnsAudioTracks() async throws {
        // Given
        let dbTracks = [
            createMockDBAudioTrack(id: "1", title: "Track 1"),
            createMockDBAudioTrack(id: "2", title: "Track 2")
        ]
        mockSupabase.mockTracks = dbTracks

        // When
        let result = try await sut.fetchAllTracks()

        // Then
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].title, "Track 1")
        XCTAssertEqual(result[1].title, "Track 2")
    }

    func testFetchAllTracksOnlyReturnActiveTracks() async throws {
        // Given
        let dbTracks = [
            createMockDBAudioTrack(id: "1", title: "Active Track", isActive: true),
            createMockDBAudioTrack(id: "2", title: "Inactive Track", isActive: false)
        ]
        mockSupabase.mockTracks = dbTracks.filter { $0.isActive }

        // When
        let result = try await sut.fetchAllTracks()

        // Then
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].title, "Active Track")
    }

    // MARK: - Fetch Tracks by Category Tests

    func testFetchTracksByCategoryFiltersCorrectly() async throws {
        // Given
        let dbTracks = [
            createMockDBAudioTrack(id: "1", title: "Meditation 1", category: "meditation"),
            createMockDBAudioTrack(id: "2", title: "Meditation 2", category: "meditation"),
            createMockDBAudioTrack(id: "3", title: "Sleep Story 1", category: "sleep_story")
        ]
        mockSupabase.mockTracks = dbTracks

        // When
        let result = try await sut.fetchTracksByCategory(.meditation)

        // Then
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy { $0.category == .meditation })
    }

    // MARK: - Featured Tracks Tests

    func testFetchFeaturedTracksReturnsFeaturedOnly() async throws {
        // Given
        let dbTracks = [
            createMockDBAudioTrack(id: "1", title: "Featured 1", isFeatured: true),
            createMockDBAudioTrack(id: "2", title: "Featured 2", isFeatured: true),
            createMockDBAudioTrack(id: "3", title: "Regular 1", isFeatured: false)
        ]
        mockSupabase.mockTracks = dbTracks.filter { $0.isFeatured }

        // When
        let result = try await sut.fetchFeaturedTracks()

        // Then
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy { $0.isFeatured })
    }

    func testFetchFeaturedTracksRespectsLimit() async throws {
        // Given
        let dbTracks = Array(0..<15).map {
            createMockDBAudioTrack(id: String($0), title: "Featured \($0)", isFeatured: true)
        }
        mockSupabase.mockTracks = dbTracks

        // When
        let result = try await sut.fetchFeaturedTracks(limit: 8)

        // Then
        XCTAssertEqual(result.count, 8)
    }

    // MARK: - Search Tests

    func testSearchTracksFiltersByTitle() async throws {
        // Given
        let dbTracks = [
            createMockDBAudioTrack(id: "1", title: "Calm Meditation"),
            createMockDBAudioTrack(id: "2", title: "Sleep Stories"),
            createMockDBAudioTrack(id: "3", title: "Calm Breathing")
        ]
        mockSupabase.mockTracks = dbTracks.filter {
            $0.title.localizedCaseInsensitiveContains("Calm")
        }

        // When
        let result = try await sut.searchTracks(query: "Calm")

        // Then
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy { $0.title.localizedCaseInsensitiveContains("Calm") })
    }

    // MARK: - Ratings Tests

    func testRateTrackValidatesRatingRange() async throws {
        // When & Then - Valid rating
        XCTAssertNoThrow(try await sut.rateTrack(trackId: "test-1", rating: 3))

        // When & Then - Invalid rating
        do {
            try await sut.rateTrack(trackId: "test-1", rating: 6)
            XCTFail("Should have thrown invalidRating error")
        } catch let error as AudioServiceError {
            XCTAssertEqual(error, .invalidRating)
        }
    }

    func testRateTrackAcceptsRatingsBetween1And5() async throws {
        // When & Then
        for rating in 1...5 {
            XCTAssertNoThrow(try await sut.rateTrack(trackId: "test-\(rating)", rating: rating))
        }
    }

    // MARK: - Helper Methods

    private func createMockDBAudioTrack(
        id: String = UUID().uuidString,
        title: String = "Test Track",
        category: String = "meditation",
        isFeatured: Bool = false,
        isActive: Bool = true
    ) -> DBAudioTrack {
        DBAudioTrack(
            id: id,
            title: title,
            slug: title.lowercased().replacingOccurrences(of: " ", with: "-"),
            description: "A test track",
            category: category,
            subcategory: nil,
            tags: ["test"],
            audioUrl: "https://example.com/audio.mp3",
            audioDurationSeconds: 600,
            audioFormat: "mp3",
            audioQuality: "high",
            fileSizeBytes: 15000000,
            previewUrl: nil,
            previewDurationSeconds: nil,
            coverImageUrl: nil,
            backgroundImageUrl: nil,
            colorScheme: nil,
            narratorId: nil,
            creatorType: "professional",
            language: "en",
            isLoopable: true,
            hasBackgroundMusic: true,
            energyLevel: "calming",
            isPremium: false,
            isFeatured: isFeatured,
            isActive: isActive,
            releasedAt: nil,
            courseId: nil,
            courseOrder: nil,
            playCount: 100,
            completionCount: 50,
            averageRating: 4.5,
            ratingCount: 20,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            narrator: nil
        )
    }
}

// MARK: - Extended Mock

extension MockSupabaseClient {
    var mockTracks: [DBAudioTrack] = []

    func setMockTracks(_ tracks: [DBAudioTrack]) {
        self.mockTracks = tracks
    }
}
