//
//  EfficacyCalculatorTests.swift
//  MindFriendAppTests
//
//  Unit tests for EfficacyCalculator
//

import XCTest
@testable import MindFriendApp

final class EfficacyCalculatorTests: XCTestCase {
    var calculator: EfficacyCalculator!

    override func setUpWithError() throws {
        calculator = EfficacyCalculator()
    }

    override func tearDownWithError() throws {
        calculator = nil
    }

    // MARK: - Basic Functionality Tests

    func testCalculateEfficacy_WithSufficientData_ReturnsResult() {
        // Given: A trajectory with improvement
        let trajectory = createMockTrajectory(
            startScore: -0.3,
            endScore: 0.6,
            numPoints: 10
        )

        // When
        let result = calculator.calculateEfficacy(
            trajectory: trajectory,
            sessionDuration: 300
        )

        // Then
        XCTAssertNotNil(result, "Should return efficacy result with sufficient data")
        XCTAssertGreaterThan(result!.efficacyScore, 0, "Improved trajectory should have positive efficacy")
        XCTAssertGreaterThan(result!.netEmotionalChange, 0, "Net change should be positive")
    }

    func testCalculateEfficacy_WithInsufficientData_ReturnsNil() {
        // Given: Trajectory with < 3 points
        let trajectory = [
            createTrajectoryPoint(secondsFromStart: 0, compositeScore: 0.0),
            createTrajectoryPoint(secondsFromStart: 30, compositeScore: 0.1)
        ]

        // When
        let result = calculator.calculateEfficacy(
            trajectory: trajectory,
            sessionDuration: 60
        )

        // Then
        XCTAssertNil(result, "Should return nil with insufficient data")
    }

    // MARK: - Trajectory Shape Detection Tests

    func testTrajectoryShape_SteadyImprovement() {
        // Given: Consistent upward trajectory
        let trajectory = createMockTrajectory(
            startScore: -0.2,
            endScore: 0.6,
            numPoints: 10
        )

        // When
        let result = calculator.calculateEfficacy(
            trajectory: trajectory,
            sessionDuration: 300
        )

        // Then
        XCTAssertEqual(result?.trajectoryShape, .steadyImprovement)
    }

    func testTrajectoryShape_EarlyPeak() {
        // Given: Peak in middle, decline at end
        let trajectory = [
            createTrajectoryPoint(secondsFromStart: 0, compositeScore: -0.2),
            createTrajectoryPoint(secondsFromStart: 30, compositeScore: 0.1),
            createTrajectoryPoint(secondsFromStart: 60, compositeScore: 0.5), // Peak
            createTrajectoryPoint(secondsFromStart: 90, compositeScore: 0.3),
            createTrajectoryPoint(secondsFromStart: 120, compositeScore: 0.2)
        ]

        // When
        let result = calculator.calculateEfficacy(
            trajectory: trajectory,
            sessionDuration: 120
        )

        // Then
        XCTAssertEqual(result?.trajectoryShape, .earlyPeak,
                      "Should detect early peak when midpoint > start and midpoint > end")
    }

    func testTrajectoryShape_LateBreakthrough() {
        // Given: Flat start, sudden improvement at end
        let trajectory = [
            createTrajectoryPoint(secondsFromStart: 0, compositeScore: -0.3),
            createTrajectoryPoint(secondsFromStart: 30, compositeScore: -0.2),
            createTrajectoryPoint(secondsFromStart: 60, compositeScore: -0.2),
            createTrajectoryPoint(secondsFromStart: 90, compositeScore: 0.0),
            createTrajectoryPoint(secondsFromStart: 120, compositeScore: 0.5)
        ]

        // When
        let result = calculator.calculateEfficacy(
            trajectory: trajectory,
            sessionDuration: 120
        )

        // Then
        XCTAssertEqual(result?.trajectoryShape, .lateBreakthrough)
    }

    func testTrajectoryShape_Deterioration() {
        // Given: Downward trajectory
        let trajectory = createMockTrajectory(
            startScore: 0.3,
            endScore: -0.3,
            numPoints: 10
        )

        // When
        let result = calculator.calculateEfficacy(
            trajectory: trajectory,
            sessionDuration: 300
        )

        // Then
        XCTAssertEqual(result?.trajectoryShape, .deterioration)
    }

    func testTrajectoryShape_Flat() {
        // Given: Minimal change trajectory
        let trajectory = createMockTrajectory(
            startScore: 0.1,
            endScore: 0.15,
            numPoints: 10
        )

        // When
        let result = calculator.calculateEfficacy(
            trajectory: trajectory,
            sessionDuration: 300
        )

        // Then
        XCTAssertEqual(result?.trajectoryShape, .flat)
    }

    // MARK: - Breakthrough Detection Tests

    func testBreakthroughDetection_LargeRapidChange_DetectsBreakthrough() {
        // Given: Trajectory with sudden +0.5 change in 30 seconds
        let trajectory = [
            createTrajectoryPoint(secondsFromStart: 0, compositeScore: -0.3),
            createTrajectoryPoint(secondsFromStart: 30, compositeScore: -0.3),
            createTrajectoryPoint(secondsFromStart: 60, compositeScore: 0.3), // Breakthrough (+0.6 in 30s)
            createTrajectoryPoint(secondsFromStart: 90, compositeScore: 0.4)
        ]

        // When
        let result = calculator.calculateEfficacy(
            trajectory: trajectory,
            sessionDuration: 90
        )

        // Then
        XCTAssertTrue(result!.breakthroughDetected, "Should detect breakthrough on large rapid change")
        XCTAssertEqual(result!.breakthroughSecond, 60, "Should record correct breakthrough timestamp")
    }

    func testBreakthroughDetection_GradualChange_NoBreakthrough() {
        // Given: Trajectory with gradual improvement
        let trajectory = createMockTrajectory(
            startScore: -0.3,
            endScore: 0.6,
            numPoints: 10
        )

        // When
        let result = calculator.calculateEfficacy(
            trajectory: trajectory,
            sessionDuration: 300
        )

        // Then
        XCTAssertFalse(result!.breakthroughDetected, "Should not detect breakthrough on gradual change")
        XCTAssertNil(result!.breakthroughSecond)
    }

    // MARK: - Efficacy Score Calculation Tests

    func testEfficacyScore_BoundedTo0To100() {
        // Given: Extreme trajectories
        let veryBad = createMockTrajectory(startScore: 0.5, endScore: -0.9, numPoints: 10)
        let veryGood = createMockTrajectory(startScore: -0.9, endScore: 0.9, numPoints: 10)

        // When
        let badResult = calculator.calculateEfficacy(trajectory: veryBad, sessionDuration: 300)
        let goodResult = calculator.calculateEfficacy(trajectory: veryGood, sessionDuration: 300)

        // Then
        XCTAssertGreaterThanOrEqual(badResult!.efficacyScore, 0, "Efficacy score should be >= 0")
        XCTAssertLessThanOrEqual(badResult!.efficacyScore, 100, "Efficacy score should be <= 100")
        XCTAssertGreaterThanOrEqual(goodResult!.efficacyScore, 0, "Efficacy score should be >= 0")
        XCTAssertLessThanOrEqual(goodResult!.efficacyScore, 100, "Efficacy score should be <= 100")
    }

    func testEfficacyScore_BreakthroughBonus() {
        // Given: Two identical trajectories, one with breakthrough
        let withoutBreakthrough = createMockTrajectory(startScore: -0.3, endScore: 0.3, numPoints: 10)

        let withBreakthrough = [
            createTrajectoryPoint(secondsFromStart: 0, compositeScore: -0.3),
            createTrajectoryPoint(secondsFromStart: 30, compositeScore: -0.3),
            createTrajectoryPoint(secondsFromStart: 60, compositeScore: 0.3), // Breakthrough
            createTrajectoryPoint(secondsFromStart: 90, compositeScore: 0.3)
        ]

        // When
        let resultWithout = calculator.calculateEfficacy(trajectory: withoutBreakthrough, sessionDuration: 300)
        let resultWith = calculator.calculateEfficacy(trajectory: withBreakthrough, sessionDuration: 90)

        // Then
        XCTAssertGreaterThan(
            resultWith!.efficacyScore,
            resultWithout!.efficacyScore,
            "Breakthrough should increase efficacy score by ~10 points"
        )
    }

    // MARK: - Net Emotional Change Tests

    func testNetEmotionalChange_ClampedToRange() {
        // Given: Trajectory with extreme change
        let trajectory = [
            createTrajectoryPoint(secondsFromStart: 0, compositeScore: -1.0),
            createTrajectoryPoint(secondsFromStart: 30, compositeScore: -0.5),
            createTrajectoryPoint(secondsFromStart: 60, compositeScore: 1.0)
        ]

        // When
        let result = calculator.calculateEfficacy(trajectory: trajectory, sessionDuration: 60)

        // Then
        XCTAssertGreaterThanOrEqual(result!.netEmotionalChange, -1.0, "Net change should be >= -1")
        XCTAssertLessThanOrEqual(result!.netEmotionalChange, 1.0, "Net change should be <= 1")
    }

    // MARK: - Helper Methods

    private func createMockTrajectory(
        startScore: Double,
        endScore: Double,
        numPoints: Int
    ) -> [TrajectoryPoint] {
        let scoreRange = endScore - startScore
        let scoreIncrement = scoreRange / Double(numPoints - 1)

        return (0..<numPoints).map { index in
            let secondsFromStart = index * 30
            let compositeScore = startScore + (scoreIncrement * Double(index))

            return createTrajectoryPoint(
                secondsFromStart: secondsFromStart,
                compositeScore: compositeScore
            )
        }
    }

    private func createTrajectoryPoint(
        secondsFromStart: Int,
        compositeScore: Double
    ) -> TrajectoryPoint {
        TrajectoryPoint(
            id: UUID(),
            timestamp: Date().addingTimeInterval(TimeInterval(secondsFromStart)),
            secondsFromStart: secondsFromStart,
            nervousSystemState: "test_state",
            emotionClassification: EmotionClassification(primary: "test", valence: compositeScore, arousal: 0.5),
            hrvReading: 60.0,
            compositeScore: compositeScore
        )
    }
}
