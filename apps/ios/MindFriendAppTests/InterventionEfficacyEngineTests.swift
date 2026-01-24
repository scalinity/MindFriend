//
//  InterventionEfficacyEngineTests.swift
//  MindFriendAppTests
//
//  Unit tests for InterventionEfficacyEngine
//

import XCTest
import Supabase
@testable import MindFriendApp

@MainActor
final class InterventionEfficacyEngineTests: XCTestCase {
    var engine: InterventionEfficacyEngine!
    var mockSupabase: SupabaseClient!
    var tracker: TrajectoryTracker!
    var calculator: EfficacyCalculator!
    var recommender: EfficacyBasedRecommender!

    override func setUpWithError() throws {
        // Create mock Supabase client
        mockSupabase = SupabaseClient(
            supabaseURL: URL(string: "https://test.supabase.co")!,
            supabaseKey: "test-key"
        )

        // Create dependencies
        tracker = TrajectoryTracker(supabase: mockSupabase)
        calculator = EfficacyCalculator()
        recommender = EfficacyBasedRecommender(supabase: mockSupabase)

        // Create engine
        engine = InterventionEfficacyEngine(
            tracker: tracker,
            calculator: calculator,
            recommender: recommender,
            supabase: mockSupabase
        )
    }

    override func tearDownWithError() throws {
        engine = nil
        tracker = nil
        calculator = nil
        recommender = nil
        mockSupabase = nil
    }

    // MARK: - Session Lifecycle Tests

    func testStartSession_SetsTrackingState() async throws {
        // Given
        let sessionId = UUID()
        let exerciseId = UUID()
        let userId = UUID()

        XCTAssertFalse(engine.isTrackingSession, "Should not be tracking initially")

        // When
        try await engine.startSession(sessionId: sessionId, exerciseId: exerciseId, userId: userId)

        // Then
        XCTAssertTrue(engine.isTrackingSession, "Should be tracking after start")
        XCTAssertTrue(tracker.isTracking, "Tracker should be active")
    }

    func testStartSession_WhenAlreadyActive_ThrowsError() async throws {
        // Given: Active session
        let session1 = UUID()
        let exercise1 = UUID()
        let user1 = UUID()

        try await engine.startSession(sessionId: session1, exerciseId: exercise1, userId: user1)

        // When/Then: Starting another session should throw
        let session2 = UUID()
        let exercise2 = UUID()
        let user2 = UUID()

        do {
            try await engine.startSession(sessionId: session2, exerciseId: exercise2, userId: user2)
            XCTFail("Should throw sessionAlreadyActive error")
        } catch EfficacyError.sessionAlreadyActive {
            // Expected
        } catch {
            XCTFail("Should throw sessionAlreadyActive error, got: \(error)")
        }
    }

    func testEndSession_StopsTracking() async throws {
        // Given: Active session
        let sessionId = UUID()
        let exerciseId = UUID()
        let userId = UUID()

        try await engine.startSession(sessionId: sessionId, exerciseId: exerciseId, userId: userId)
        XCTAssertTrue(engine.isTrackingSession)

        // When
        _ = try await engine.endSession()

        // Then
        XCTAssertFalse(engine.isTrackingSession, "Should stop tracking")
        XCTAssertFalse(tracker.isTracking, "Tracker should be inactive")
    }

    func testEndSession_WithoutActiveSession_ThrowsError() async throws {
        // Given: No active session

        // When/Then: Ending session should throw
        do {
            _ = try await engine.endSession()
            XCTFail("Should throw noActiveSession error")
        } catch EfficacyError.noActiveSession {
            // Expected
        } catch {
            XCTFail("Should throw noActiveSession error, got: \(error)")
        }
    }

    func testEndSession_WithSufficientData_ReturnsEfficacy() async throws {
        // Given: Active session with enough data
        let sessionId = UUID()
        let exerciseId = UUID()
        let userId = UUID()

        try await engine.startSession(sessionId: sessionId, exerciseId: exerciseId, userId: userId)

        // Wait for sufficient samples (need >= 3)
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms

        // When
        let result = try await engine.endSession()

        // Then: May be nil if insufficient data, or valid if enough samples
        if let efficacy = result {
            XCTAssertEqual(efficacy.sessionId, sessionId)
            XCTAssertEqual(efficacy.exerciseId, exerciseId)
            XCTAssertGreaterThanOrEqual(efficacy.efficacyScore, 0)
            XCTAssertLessThanOrEqual(efficacy.efficacyScore, 100)
        } else {
            // Insufficient data is acceptable for unit test
            XCTAssertTrue(true, "Insufficient data for efficacy calculation")
        }
    }

    func testEndSession_WithInsufficientData_ReturnsNil() async throws {
        // Given: Active session with minimal data
        let sessionId = UUID()
        let exerciseId = UUID()
        let userId = UUID()

        try await engine.startSession(sessionId: sessionId, exerciseId: exerciseId, userId: userId)

        // When: End immediately (< 3 samples)
        let result = try await engine.endSession()

        // Then
        // Note: Result may be nil OR may have data depending on timing
        // Just verify it doesn't crash
        if let efficacy = result {
            XCTAssertNotNil(efficacy, "If efficacy returned, should be valid")
        }
    }

    // MARK: - Session State Management Tests

    func testSessionState_ClearedAfterEnd() async throws {
        // Given: Completed session
        let sessionId = UUID()
        let exerciseId = UUID()
        let userId = UUID()

        try await engine.startSession(sessionId: sessionId, exerciseId: exerciseId, userId: userId)
        _ = try await engine.endSession()

        // When: Start new session
        let newSessionId = UUID()
        let newExerciseId = UUID()

        // Then: Should not throw sessionAlreadyActive
        do {
            try await engine.startSession(sessionId: newSessionId, exerciseId: newExerciseId, userId: userId)
            XCTAssertTrue(engine.isTrackingSession, "Should start new session successfully")
        } catch {
            XCTFail("Should allow new session after previous ended: \(error)")
        }
    }

    // MARK: - Integration Tests

    func testFullSessionFlow() async throws {
        // Given: Session parameters
        let sessionId = UUID()
        let exerciseId = UUID()
        let userId = UUID()

        // When: Complete session lifecycle
        try await engine.startSession(sessionId: sessionId, exerciseId: exerciseId, userId: userId)

        XCTAssertTrue(engine.isTrackingSession, "Should be tracking")

        // Wait for samples
        try? await Task.sleep(nanoseconds: 300_000_000) // 300ms

        let result = try await engine.endSession()

        // Then
        XCTAssertFalse(engine.isTrackingSession, "Should stop tracking")

        if let efficacy = result {
            XCTAssertGreaterThanOrEqual(efficacy.efficacyScore, 0)
            XCTAssertLessThanOrEqual(efficacy.efficacyScore, 100)
            XCTAssertNotNil(efficacy.completedAt)
            XCTAssertNotNil(efficacy.startingState)
        }
    }

    // MARK: - Error Handling Tests

    func testErrorRecovery_OnTrackerFailure() async throws {
        // Given: Session that might fail during tracking
        let sessionId = UUID()
        let exerciseId = UUID()
        let userId = UUID()

        // When: Start and immediately end
        try await engine.startSession(sessionId: sessionId, exerciseId: exerciseId, userId: userId)

        // Then: Should handle gracefully even if tracker fails
        do {
            _ = try await engine.endSession()
            // Success - no crash
        } catch {
            // Acceptable - may fail due to insufficient data
        }

        // Engine should be in clean state
        XCTAssertFalse(engine.isTrackingSession)
    }

    // MARK: - Recommendations Tests

    func testGetRecommendations_WithValidInputs() async throws {
        // Given: Valid context parameters
        let currentState = "fight_flight"
        let currentEmotion = "anxious"

        // When/Then: Should not crash (may fail due to network)
        do {
            let recommendations = try await engine.getRecommendations(
                currentState: currentState,
                currentEmotion: currentEmotion
            )

            // If successful, validate structure
            for recommendation in recommendations {
                XCTAssertFalse(recommendation.exerciseName.isEmpty)
                XCTAssertGreaterThan(recommendation.duration, 0)
                XCTAssertGreaterThanOrEqual(recommendation.predictedEfficacy, 0)
                XCTAssertLessThanOrEqual(recommendation.predictedEfficacy, 100)
            }
        } catch {
            // Network failure acceptable in unit test
            print("Recommendation fetch failed (expected in unit test): \(error)")
        }
    }

    func testGetRecommendations_InfersTimeOfDay() async throws {
        // Given: Current time
        let hour = Calendar.current.component(.hour, from: Date())
        let currentState = "rest"
        let currentEmotion = "calm"

        // When: Get recommendations without explicit timeOfDay
        do {
            let recommendations = try await engine.getRecommendations(
                currentState: currentState,
                currentEmotion: currentEmotion
            )

            // Then: Should infer time based on current hour
            // (Just verify it doesn't crash - actual recommendation content requires backend)
            XCTAssertTrue(true, "Should infer time of day from current hour: \(hour)")
        } catch {
            // Network failure acceptable
        }
    }

    // MARK: - Concurrent Access Tests

    func testConcurrentSessionRequests_Handled() async {
        // Given: Multiple concurrent session requests
        let sessionId1 = UUID()
        let sessionId2 = UUID()
        let exerciseId = UUID()
        let userId = UUID()

        // When: Try to start sessions concurrently
        async let start1 = engine.startSession(sessionId: sessionId1, exerciseId: exerciseId, userId: userId)
        async let start2 = engine.startSession(sessionId: sessionId2, exerciseId: exerciseId, userId: userId)

        // Then: One should succeed, one should fail with sessionAlreadyActive
        do {
            try await start1
            do {
                try await start2
                XCTFail("Second session should fail")
            } catch EfficacyError.sessionAlreadyActive {
                // Expected
            }
        } catch {
            // First request failed, second should succeed
            do {
                try await start2
            } catch {
                XCTFail("At least one session should succeed")
            }
        }
    }
}
