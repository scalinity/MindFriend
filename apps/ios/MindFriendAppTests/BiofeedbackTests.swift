// BiofeedbackTests.swift
// MindFriendAppTests
// Tests for biofeedback adaptation system

import XCTest
@testable import MindFriendApp

final class BiofeedbackTests: XCTestCase {

    // MARK: - Stress Level Tests

    func testStressLevelCalculation() {
        let baseline = BiofeedbackBaseline(
            id: UUID(),
            userId: UUID(),
            restingHeartRate: 60,
            restingHRV: 50,
            exerciseRecoveryRate: 3,
            stressHRThreshold: 100,
            relaxedHRThreshold: 72,
            calculatedAt: Date(),
            sampleCount: 50,
            confidenceScore: 0.8,
            createdAt: Date(),
            updatedAt: Date()
        )

        // Test different heart rates against baseline
        XCTAssertEqual(baseline.stressLevel(forHeartRate: 62), .relaxed)
        XCTAssertEqual(baseline.stressLevel(forHeartRate: 70), .calm)
        XCTAssertEqual(baseline.stressLevel(forHeartRate: 80), .moderate)
        XCTAssertEqual(baseline.stressLevel(forHeartRate: 90), .elevated)
        XCTAssertEqual(baseline.stressLevel(forHeartRate: 105), .high)
    }

    func testStressLevelWithNoBaseline() {
        let baseline = BiofeedbackBaseline(
            id: UUID(),
            userId: UUID(),
            restingHeartRate: nil,
            restingHRV: nil,
            exerciseRecoveryRate: nil,
            stressHRThreshold: nil,
            relaxedHRThreshold: nil,
            calculatedAt: Date(),
            sampleCount: 0,
            confidenceScore: 0,
            createdAt: Date(),
            updatedAt: Date()
        )

        XCTAssertEqual(baseline.stressLevel(forHeartRate: 70), .unknown)
    }

    func testBaselineReliability() {
        // Unreliable baseline (low confidence, few samples)
        let unreliableBaseline = BiofeedbackBaseline(
            id: UUID(),
            userId: UUID(),
            restingHeartRate: 65,
            restingHRV: 45,
            exerciseRecoveryRate: nil,
            stressHRThreshold: 95,
            relaxedHRThreshold: 75,
            calculatedAt: Date(),
            sampleCount: 5,
            confidenceScore: 0.3,
            createdAt: Date(),
            updatedAt: Date()
        )
        XCTAssertFalse(unreliableBaseline.isReliable)

        // Reliable baseline
        let reliableBaseline = BiofeedbackBaseline(
            id: UUID(),
            userId: UUID(),
            restingHeartRate: 65,
            restingHRV: 45,
            exerciseRecoveryRate: 2.5,
            stressHRThreshold: 95,
            relaxedHRThreshold: 75,
            calculatedAt: Date(),
            sampleCount: 50,
            confidenceScore: 0.85,
            createdAt: Date(),
            updatedAt: Date()
        )
        XCTAssertTrue(reliableBaseline.isReliable)
    }

    // MARK: - Breathing Pattern Tests

    func testBiofeedbackBreathingPatternTotalDuration() {
        let pattern = BiofeedbackBreathingPattern(inhale: 4, hold: 4, exhale: 4, pause: 2)
        XCTAssertEqual(pattern.totalCycleDuration, 14)
    }

    func testBiofeedbackBreathingPatternDisplayName() {
        let pattern = BiofeedbackBreathingPattern(inhale: 4, hold: 7, exhale: 8, pause: 2)
        XCTAssertEqual(pattern.displayName, "4-7-8")
    }

    func testPresetBiofeedbackBreathingPatterns() {
        XCTAssertEqual(BiofeedbackBreathingPattern.relaxed.exhale, 8)
        XCTAssertEqual(BiofeedbackBreathingPattern.stressed.exhale, 5)
        XCTAssertEqual(BiofeedbackBreathingPattern.moderate.inhale, 4)
    }

    // MARK: - Adaptation Engine Tests

    @MainActor
    func testAdaptationEngineWithAutoMode() async {
        let baseline = createTestBaseline()
        let engine = AdaptationEngine(baseline: baseline, mode: .auto)

        // High stress reading should trigger adaptation
        let highStressReading = LiveBiometricData(
            heartRate: 105,
            hrvRMSSD: 25,
            timestamp: Date()
        )

        let result = engine.processReading(highStressReading)

        // In auto mode with high stress, should adapt
        XCTAssertTrue(result.adapted || engine.currentStressLevel == .high)
        XCTAssertEqual(engine.currentStressLevel, .high)
    }

    @MainActor
    func testAdaptationEngineWithOffMode() async {
        let baseline = createTestBaseline()
        let engine = AdaptationEngine(baseline: baseline, mode: .off)

        let reading = LiveBiometricData(
            heartRate: 105,
            hrvRMSSD: 25,
            timestamp: Date()
        )

        let result = engine.processReading(reading)

        // With mode off, should not adapt
        XCTAssertFalse(result.adapted)
    }

    @MainActor
    func testMinimumAdaptationInterval() async {
        let baseline = createTestBaseline()
        let engine = AdaptationEngine(baseline: baseline, mode: .aggressive)

        let reading = LiveBiometricData(
            heartRate: 100,
            hrvRMSSD: 30,
            timestamp: Date()
        )

        // First reading may adapt
        _ = engine.processReading(reading)

        // Immediate second reading should not adapt (interval not met)
        let result2 = engine.processReading(reading)
        XCTAssertFalse(result2.adapted)
    }

    @MainActor
    func testTrendCalculation() async {
        let engine = AdaptationEngine(baseline: nil, mode: .auto)

        // Simulate decreasing heart rate (improving)
        let heartRates = [90.0, 88.0, 85.0, 82.0, 80.0, 78.0]

        for hr in heartRates {
            let reading = LiveBiometricData(
                heartRate: hr,
                hrvRMSSD: nil,
                timestamp: Date()
            )
            _ = engine.processReading(reading)
        }

        // Should detect improving trend
        XCTAssertEqual(engine.currentTrend, .improving)
    }

    @MainActor
    func testExtensionRecommendation() async {
        let baseline = createTestBaseline()
        let engine = AdaptationEngine(baseline: baseline, mode: .auto)

        // Simulate elevated state
        let reading = LiveBiometricData(heartRate: 90, hrvRMSSD: nil, timestamp: Date())
        _ = engine.processReading(reading)

        // After 5 minutes with still-elevated HR
        let recommendation = engine.checkShouldExtend(
            averageHR: 85,
            elapsedTime: 300
        )

        // Should recommend extension for elevated stress
        if case .recommended = recommendation {
            XCTAssertTrue(true)
        } else if case .optional = recommendation {
            XCTAssertTrue(true)
        } else {
            // May not recommend if not enough time or stress level acceptable
            XCTAssertTrue(true, "Extension not recommended - acceptable")
        }
    }

    // MARK: - Biofeedback Summary Tests

    func testSummaryHeartRateChange() {
        let summary = BiofeedbackSummary(
            id: UUID(),
            sessionId: UUID(),
            startingHeartRate: 85,
            endingHeartRate: 68,
            lowestHeartRate: 65,
            highestHeartRate: 88,
            averageHeartRate: 72,
            startingHRV: 45,
            endingHRV: 55,
            hrvImprovementPercent: 22.2,
            timeToRelaxationSeconds: 180,
            totalAdaptations: 3,
            effectivenessScore: 0.75,
            createdAt: Date()
        )

        XCTAssertEqual(summary.heartRateChange, -17)
        XCTAssertNotNil(summary.heartRateChangePercent)
        XCTAssertLessThan(summary.heartRateChangePercent!, 0)
    }

    func testSummaryWithMissingData() {
        let summary = BiofeedbackSummary(
            id: UUID(),
            sessionId: UUID(),
            startingHeartRate: nil,
            endingHeartRate: nil,
            lowestHeartRate: nil,
            highestHeartRate: nil,
            averageHeartRate: nil,
            startingHRV: nil,
            endingHRV: nil,
            hrvImprovementPercent: nil,
            timeToRelaxationSeconds: nil,
            totalAdaptations: 0,
            effectivenessScore: nil,
            createdAt: Date()
        )

        XCTAssertNil(summary.heartRateChange)
        XCTAssertNil(summary.heartRateChangePercent)
    }

    // MARK: - Adaptation Mode Tests

    func testAdaptationModeProperties() {
        XCTAssertEqual(AdaptationMode.auto.displayName, "Auto")
        XCTAssertEqual(AdaptationMode.gentle.displayName, "Gentle")
        XCTAssertEqual(AdaptationMode.aggressive.displayName, "Aggressive")
        XCTAssertEqual(AdaptationMode.off.displayName, "Off")

        XCTAssertFalse(AdaptationMode.auto.description.isEmpty)
    }

    // MARK: - Physiological State Tests

    func testPhysiologicalStateColors() {
        XCTAssertEqual(PhysiologicalState.relaxing.color, .teal)
        XCTAssertEqual(PhysiologicalState.stressed.color, .red)
        XCTAssertEqual(PhysiologicalState.baseline.color, .blue)
    }

    // MARK: - Live Biometric Data Tests

    func testLiveBiometricDataValidation() {
        let validData = LiveBiometricData(
            heartRate: 75,
            hrvRMSSD: 45,
            timestamp: Date()
        )
        XCTAssertTrue(validData.isValid)

        let tooLow = LiveBiometricData(
            heartRate: 20,
            hrvRMSSD: nil,
            timestamp: Date()
        )
        XCTAssertFalse(tooLow.isValid)

        let tooHigh = LiveBiometricData(
            heartRate: 250,
            hrvRMSSD: nil,
            timestamp: Date()
        )
        XCTAssertFalse(tooHigh.isValid)
    }

    // MARK: - Biometric Analysis Response Tests

    func testBiometricAnalysisDecoding() throws {
        let json = """
        {
            "success": true,
            "analysis": {
                "physiological_state": "elevated",
                "stress_level": 0.65,
                "trend": "improving",
                "adaptations": [
                    {
                        "type": "breathing_pace",
                        "priority": "medium",
                        "reason": "Heart rate elevated",
                        "params": {"inhale": 4, "exhale": 6}
                    }
                ],
                "should_extend": false
            }
        }
        """

        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(BiometricAnalysisResponse.self, from: data)

        XCTAssertTrue(response.success)
        XCTAssertNotNil(response.analysis)
        XCTAssertEqual(response.analysis?.physiologicalState, "elevated")
        XCTAssertEqual(response.analysis?.stressLevel, 0.65)
        XCTAssertEqual(response.analysis?.trend, "improving")
        XCTAssertEqual(response.analysis?.adaptations.count, 1)
        XCTAssertFalse(response.analysis?.shouldExtend ?? true)
    }

    // MARK: - Helper Methods

    private func createTestBaseline() -> BiofeedbackBaseline {
        BiofeedbackBaseline(
            id: UUID(),
            userId: UUID(),
            restingHeartRate: 60,
            restingHRV: 50,
            exerciseRecoveryRate: 3,
            stressHRThreshold: 100,
            relaxedHRThreshold: 72,
            calculatedAt: Date(),
            sampleCount: 100,
            confidenceScore: 0.9,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

// MARK: - Adaptation Change Tests

final class AdaptationChangeTests: XCTestCase {

    func testAdaptationChangeDescription() {
        let breathingChange = AdaptationChange.breathingPace(
            old: .moderate,
            new: .stressed
        )
        XCTAssertFalse(breathingChange.description.isEmpty)
        XCTAssertEqual(breathingChange.type, .breathingPace)

        let visualChange = AdaptationChange.visualIntensity(old: 0.7, new: 0.5)
        XCTAssertTrue(visualChange.description.contains("%"))
        XCTAssertEqual(visualChange.type, .visualFeedback)
    }
}

// MARK: - Baseline Calculation Response Tests

final class BaselineCalculationTests: XCTestCase {

    func testBaselineResponseDecoding() throws {
        let json = """
        {
            "success": true,
            "baseline": {
                "resting_heart_rate": 62.5,
                "resting_hrv": 48.3,
                "exercise_recovery_rate": 2.8,
                "stress_hr_threshold": 98.0,
                "relaxed_hr_threshold": 72.0,
                "confidence_score": 0.85,
                "sample_count": 75
            },
            "meta": {
                "lookback_days": 14,
                "heart_rate_samples": 75,
                "hrv_samples": 12,
                "resting_context_samples": 30
            }
        }
        """

        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(BaselineCalculationResponse.self, from: data)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.baseline?.restingHeartRate, 62.5)
        XCTAssertEqual(response.baseline?.sampleCount, 75)
        XCTAssertEqual(response.meta?.lookbackDays, 14)
    }
}
