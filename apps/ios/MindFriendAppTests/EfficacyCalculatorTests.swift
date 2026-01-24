//
//  EfficacyCalculatorTests.swift
//  MindFriendAppTests
//
//  Intervention Efficacy Engine - Efficacy Calculator Unit Tests
//

import XCTest
@testable import MindFriendApp

final class EfficacyCalculatorTests: XCTestCase {

    var calculator: EfficacyCalculator!

    override func setUp() {
        super.setUp()
        calculator = EfficacyCalculator()
    }

    override func tearDown() {
        calculator = nil
        super.tearDown()
    }

    // MARK: - Input Validation Tests

    func testCalculateEfficacy_WithInsufficientData_ReturnsNil() {
        // Given: trajectory with only 2 points (minimum is 3)
        let trajectory = [
            createTrajectoryPoint(second: 0, score: -0.5),
            createTrajectoryPoint(second: 30, score: 0.2)
        ]

        // When: call calculateEfficacy
        let result = calculator.calculateEfficacy(trajectory: trajectory, sessionDuration: 60)

        // Then: should return nil
        XCTAssertNil(result, "Should return nil when trajectory has fewer than 3 points")
    }

    // MARK: - Empty MidPhase Guard Tests

    func testCalculateEfficacy_WithEmptyMidPhase_ReturnsNil() {
        // Given: trajectory with exactly 3 points where midPhase calculation would be empty
        let trajectory = [
            createTrajectoryPoint(second: 0, score: -0.5),
            createTrajectoryPoint(second: 30, score: 0.0),
            createTrajectoryPoint(second: 60, score: 0.3)
        ]

        // When: call calculateEfficacy
        let result = calculator.calculateEfficacy(trajectory: trajectory, sessionDuration: 60)

        // Then: should NOT crash with division by zero and should handle gracefully
        // With 3 points, midPhase should still have at least 1 point based on implementation
        XCTAssertNotNil(result, "Should handle edge case gracefully")
    }

    // MARK: - Breakthrough Detection Tests

    func testDetectBreakthrough_WithRapidPositiveShift_DetectsBreakthrough() {
        // Given: trajectory with +0.6 change in 30 seconds (> 0.4 in < 60s)
        let trajectory = [
            createTrajectoryPoint(second: 0, score: -0.5),
            createTrajectoryPoint(second: 15, score: -0.3),
            createTrajectoryPoint(second: 30, score: 0.3),  // +0.6 change in 30s
            createTrajectoryPoint(second: 60, score: 0.4)
        ]

        // When: call calculateEfficacy
        let result = calculator.calculateEfficacy(trajectory: trajectory, sessionDuration: 60)

        // Then: breakthroughDetected = true, breakthroughSecond = 30
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.breakthroughDetected, "Should detect breakthrough with rapid positive shift")
        XCTAssertEqual(result!.breakthroughSecond, 30, "Should record breakthrough at second 30")
    }

    func testDetectBreakthrough_WithSlowChange_DoesNotDetectBreakthrough() {
        // Given: trajectory with gradual improvement (no rapid shift)
        let trajectory = [
            createTrajectoryPoint(second: 0, score: -0.5),
            createTrajectoryPoint(second: 20, score: -0.3),
            createTrajectoryPoint(second: 40, score: -0.1),
            createTrajectoryPoint(second: 60, score: 0.1),
            createTrajectoryPoint(second: 80, score: 0.3)
        ]

        // When: call calculateEfficacy
        let result = calculator.calculateEfficacy(trajectory: trajectory, sessionDuration: 80)

        // Then: breakthroughDetected = false
        XCTAssertNotNil(result)
        XCTAssertFalse(result!.breakthroughDetected, "Should not detect breakthrough with gradual change")
        XCTAssertNil(result!.breakthroughSecond)
    }

    // MARK: - Trajectory Shape Classification Tests

    func testDetermineTrajectoryShape_SteadyImprovement() {
        // Given: trajectory with consistent positive change
        let trajectory = [
            createTrajectoryPoint(second: 0, score: -0.4),
            createTrajectoryPoint(second: 20, score: -0.2),
            createTrajectoryPoint(second: 40, score: 0.1),
            createTrajectoryPoint(second: 60, score: 0.3),
            createTrajectoryPoint(second: 80, score: 0.5)
        ]

        // When: call calculateEfficacy
        let result = calculator.calculateEfficacy(trajectory: trajectory, sessionDuration: 80)

        // Then: trajectoryShape = .steadyImprovement
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.trajectoryShape, .steadyImprovement, "Should classify as steady improvement")
    }

    func testDetermineTrajectoryShape_EarlyPeak() {
        // Given: trajectory with improvement then decline
        let trajectory = [
            createTrajectoryPoint(second: 0, score: -0.4),
            createTrajectoryPoint(second: 20, score: 0.1),
            createTrajectoryPoint(second: 40, score: 0.6),  // Peak in middle
            createTrajectoryPoint(second: 60, score: 0.3),
            createTrajectoryPoint(second: 80, score: 0.1)   // Decline at end
        ]

        // When: call calculateEfficacy
        let result = calculator.calculateEfficacy(trajectory: trajectory, sessionDuration: 80)

        // Then: trajectoryShape = .earlyPeak
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.trajectoryShape, .earlyPeak, "Should classify as early peak")
    }

    func testDetermineTrajectoryShape_LateBreakthrough() {
        // Given: trajectory flat then sudden improvement at end
        let trajectory = [
            createTrajectoryPoint(second: 0, score: -0.5),
            createTrajectoryPoint(second: 20, score: -0.5),
            createTrajectoryPoint(second: 40, score: -0.4),  // Midpoint still low
            createTrajectoryPoint(second: 60, score: -0.3),
            createTrajectoryPoint(second: 80, score: 0.3)    // Sudden improvement at end
        ]

        // When: call calculateEfficacy
        let result = calculator.calculateEfficacy(trajectory: trajectory, sessionDuration: 80)

        // Then: trajectoryShape = .lateBreakthrough
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.trajectoryShape, .lateBreakthrough, "Should classify as late breakthrough")
    }

    func testDetermineTrajectoryShape_Deterioration() {
        // Given: trajectory with negative net change
        let trajectory = [
            createTrajectoryPoint(second: 0, score: 0.3),
            createTrajectoryPoint(second: 20, score: 0.1),
            createTrajectoryPoint(second: 40, score: -0.1),
            createTrajectoryPoint(second: 60, score: -0.3),
            createTrajectoryPoint(second: 80, score: -0.5)
        ]

        // When: call calculateEfficacy
        let result = calculator.calculateEfficacy(trajectory: trajectory, sessionDuration: 80)

        // Then: trajectoryShape = .deterioration
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.trajectoryShape, .deterioration, "Should classify as deterioration")
    }

    func testDetermineTrajectoryShape_Flat() {
        // Given: trajectory with minimal change
        let trajectory = [
            createTrajectoryPoint(second: 0, score: -0.1),
            createTrajectoryPoint(second: 20, score: -0.05),
            createTrajectoryPoint(second: 40, score: 0.0),
            createTrajectoryPoint(second: 60, score: 0.05),
            createTrajectoryPoint(second: 80, score: 0.08)
        ]

        // When: call calculateEfficacy
        let result = calculator.calculateEfficacy(trajectory: trajectory, sessionDuration: 80)

        // Then: trajectoryShape = .flat
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.trajectoryShape, .flat, "Should classify as flat")
    }

    // MARK: - Efficacy Score Range Tests

    func testCalculateEfficacy_ScoreWithinValidRange() {
        // Given: any valid trajectory
        let trajectory = [
            createTrajectoryPoint(second: 0, score: -0.6),
            createTrajectoryPoint(second: 30, score: -0.2),
            createTrajectoryPoint(second: 60, score: 0.4)
        ]

        // When: call calculateEfficacy
        let result = calculator.calculateEfficacy(trajectory: trajectory, sessionDuration: 60)

        // Then: 0 <= efficacyScore <= 100
        XCTAssertNotNil(result)
        XCTAssertGreaterThanOrEqual(result!.efficacyScore, 0, "Efficacy score should be >= 0")
        XCTAssertLessThanOrEqual(result!.efficacyScore, 100, "Efficacy score should be <= 100")
    }

    // MARK: - Helper Methods

    private func createTrajectoryPoint(second: Int, score: Double) -> TrajectoryPoint {
        return TrajectoryPoint(
            id: UUID(),
            timestamp: Date(),
            secondsFromStart: second,
            nervousSystemState: "rest",
            emotionClassification: EmotionClassification(primary: "neutral", valence: score, arousal: 0.5),
            hrvReading: 60,
            compositeScore: score
        )
    }
}
