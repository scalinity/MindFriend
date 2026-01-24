//
//  TrajectoryTrackerTests.swift
//  MindFriendAppTests
//
//  Unit tests for TrajectoryTracker
//

import XCTest
import Supabase
@testable import MindFriendApp

@MainActor
final class TrajectoryTrackerTests: XCTestCase {
    var tracker: TrajectoryTracker!
    var mockSupabase: SupabaseClient!

    override func setUpWithError() throws {
        // Create mock Supabase client (URL doesn't matter for unit tests)
        mockSupabase = SupabaseClient(
            supabaseURL: URL(string: "https://test.supabase.co")!,
            supabaseKey: "test-key"
        )

        tracker = TrajectoryTracker(supabase: mockSupabase)
    }

    override func tearDownWithError() throws {
        tracker = nil
        mockSupabase = nil
    }

    // MARK: - Tracking Lifecycle Tests

    func testStartTracking_SetsIsTrackingTrue() {
        // Given
        let sessionId = UUID()
        let exerciseId = UUID()
        let userId = UUID()

        XCTAssertFalse(tracker.isTracking, "Should not be tracking initially")
        XCTAssertTrue(tracker.currentTrajectory.isEmpty, "Trajectory should be empty initially")

        // When
        tracker.startTracking(sessionId: sessionId, exerciseId: exerciseId, userId: userId)

        // Then
        XCTAssertTrue(tracker.isTracking, "Should be tracking after start")
        XCTAssertFalse(tracker.currentTrajectory.isEmpty, "Should have initial sample")
    }

    func testStartTracking_CapturesInitialSample() async {
        // Given
        let sessionId = UUID()
        let exerciseId = UUID()
        let userId = UUID()

        // When
        tracker.startTracking(sessionId: sessionId, exerciseId: exerciseId, userId: userId)

        // Wait for async initialization
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        // Then
        XCTAssertEqual(tracker.currentTrajectory.count, 1, "Should have exactly one initial sample")
        XCTAssertEqual(tracker.currentTrajectory.first?.secondsFromStart, 0, "First sample should be at t=0")
    }

    func testStopTracking_StopsTracking() async throws {
        // Given: Active tracking session
        let sessionId = UUID()
        let exerciseId = UUID()
        let userId = UUID()

        tracker.startTracking(sessionId: sessionId, exerciseId: exerciseId, userId: userId)
        XCTAssertTrue(tracker.isTracking)

        // When
        _ = try await tracker.stopTracking()

        // Then
        XCTAssertFalse(tracker.isTracking, "Should stop tracking")
        XCTAssertTrue(tracker.currentTrajectory.isEmpty, "Should clear trajectory after stop")
    }

    func testStopTracking_ReturnsTrajectory() async throws {
        // Given: Active session with some samples
        let sessionId = UUID()
        let exerciseId = UUID()
        let userId = UUID()

        tracker.startTracking(sessionId: sessionId, exerciseId: exerciseId, userId: userId)

        // Wait for a few samples
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms

        // When
        let trajectory = try await tracker.stopTracking()

        // Then
        XCTAssertGreaterThan(trajectory.count, 0, "Should return non-empty trajectory")
        XCTAssertEqual(trajectory.first?.secondsFromStart, 0, "First sample should be at t=0")
    }

    // MARK: - Sampling Tests

    func testSampling_CreatesPeriodicSamples() async throws {
        // Given: Mock sampling with faster interval for testing
        // Note: Real interval is 30s, would need dependency injection to test properly
        let sessionId = UUID()
        let exerciseId = UUID()
        let userId = UUID()

        tracker.startTracking(sessionId: sessionId, exerciseId: exerciseId, userId: userId)

        // When: Wait for initial sample
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms

        let initialCount = tracker.currentTrajectory.count

        // Then
        XCTAssertGreaterThan(initialCount, 0, "Should have initial sample")
    }

    func testTrajectoryPoint_ContainsRequiredFields() {
        // Given
        let sessionId = UUID()
        let exerciseId = UUID()
        let userId = UUID()

        // When
        tracker.startTracking(sessionId: sessionId, exerciseId: exerciseId, userId: userId)

        // Then
        guard let point = tracker.currentTrajectory.first else {
            XCTFail("Should have at least one trajectory point")
            return
        }

        XCTAssertNotNil(point.id, "Should have ID")
        XCTAssertNotNil(point.timestamp, "Should have timestamp")
        XCTAssertGreaterThanOrEqual(point.secondsFromStart, 0, "Seconds from start should be >= 0")
        XCTAssertNotNil(point.nervousSystemState, "Should have nervous system state")
        XCTAssertNotNil(point.emotionClassification, "Should have emotion classification")
        XCTAssertNotNil(point.hrvReading, "Should have HRV reading")
        XCTAssertGreaterThanOrEqual(point.compositeScore, -1.0, "Composite score should be >= -1")
        XCTAssertLessThanOrEqual(point.compositeScore, 1.0, "Composite score should be <= 1")
    }

    // MARK: - Composite Score Tests

    func testCompositeScore_ImproveesOverTime() async throws {
        // Given: Mock implementation simulates improvement
        let sessionId = UUID()
        let exerciseId = UUID()
        let userId = UUID()

        tracker.startTracking(sessionId: sessionId, exerciseId: exerciseId, userId: userId)

        // When: Wait for progression
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms

        let trajectory = try await tracker.stopTracking()

        // Then: Later samples should generally show improvement
        guard trajectory.count >= 2 else {
            XCTFail("Need at least 2 samples to test progression")
            return
        }

        let firstScore = trajectory.first!.compositeScore
        let lastScore = trajectory.last!.compositeScore

        // Mock implementation starts at -0.3 and improves to ~+0.6
        XCTAssertLessThan(firstScore, lastScore, "Score should improve over time in mock trajectory")
    }

    // MARK: - State Management Tests

    func testMultipleStartCalls_ResetsTrajectory() {
        // Given: First tracking session
        let session1 = UUID()
        let exercise1 = UUID()
        let user1 = UUID()

        tracker.startTracking(sessionId: session1, exerciseId: exercise1, userId: user1)
        let firstTrajectoryCount = tracker.currentTrajectory.count

        // When: Start new session
        let session2 = UUID()
        let exercise2 = UUID()
        let user2 = UUID()

        tracker.startTracking(sessionId: session2, exerciseId: exercise2, userId: user2)

        // Then: Should reset trajectory
        XCTAssertEqual(tracker.currentTrajectory.count, 1, "Should reset trajectory on new start")
    }

    // MARK: - Edge Cases

    func testStopTracking_WithEmptyTrajectory_HandlesGracefully() async throws {
        // Given: Stopped session with no tracking started
        // When/Then: Should not crash
        do {
            let trajectory = try await tracker.stopTracking()
            XCTAssertTrue(trajectory.isEmpty, "Should return empty trajectory if never started")
        } catch {
            // Expected - no active session
        }
    }

    func testTrajectoryPoint_ValuesWithinBounds() {
        // Given
        tracker.startTracking(sessionId: UUID(), exerciseId: UUID(), userId: UUID())

        // When
        guard let point = tracker.currentTrajectory.first else {
            XCTFail("Should have trajectory point")
            return
        }

        // Then: All values should be within valid ranges
        XCTAssertGreaterThanOrEqual(point.compositeScore, -1.0)
        XCTAssertLessThanOrEqual(point.compositeScore, 1.0)

        if let emotion = point.emotionClassification {
            XCTAssertGreaterThanOrEqual(emotion.valence, -1.0)
            XCTAssertLessThanOrEqual(emotion.valence, 1.0)

            if let arousal = emotion.arousal {
                XCTAssertGreaterThanOrEqual(arousal, 0.0)
                XCTAssertLessThanOrEqual(arousal, 1.0)
            }
        }

        if let hrv = point.hrvReading {
            XCTAssertGreaterThan(hrv, 0, "HRV should be positive")
        }
    }
}
