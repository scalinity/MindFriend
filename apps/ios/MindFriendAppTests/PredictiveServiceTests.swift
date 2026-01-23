import XCTest
@testable import MindFriendApp

final class PredictiveServiceTests: XCTestCase {

    // MARK: - MoodPrediction Model Tests

    func testMoodPrediction_OutlookLabel_HighMood() {
        let prediction = MoodPrediction(
            id: UUID(),
            userId: UUID(),
            predictedFor: Date(),
            predictedMood: 8.5,
            confidence: 0.85,
            factors: [],
            modelVersion: "v1.0",
            featuresUsed: nil,
            actualMood: nil,
            predictionAccuracy: nil,
            notificationSent: false,
            notificationSentAt: nil,
            createdAt: Date()
        )

        XCTAssertEqual(prediction.outlookLabel, "Looking Good")
        XCTAssertFalse(prediction.isLowMoodPredicted)
    }

    func testMoodPrediction_OutlookLabel_NeutralMood() {
        let prediction = MoodPrediction(
            id: UUID(),
            userId: UUID(),
            predictedFor: Date(),
            predictedMood: 5.5,
            confidence: 0.70,
            factors: [],
            modelVersion: "v1.0",
            featuresUsed: nil,
            actualMood: nil,
            predictionAccuracy: nil,
            notificationSent: false,
            notificationSentAt: nil,
            createdAt: Date()
        )

        XCTAssertEqual(prediction.outlookLabel, "Neutral")
        XCTAssertFalse(prediction.isLowMoodPredicted)
    }

    func testMoodPrediction_OutlookLabel_ChallengingMood() {
        let prediction = MoodPrediction(
            id: UUID(),
            userId: UUID(),
            predictedFor: Date(),
            predictedMood: 3.5,
            confidence: 0.65,
            factors: [],
            modelVersion: "v1.0",
            featuresUsed: nil,
            actualMood: nil,
            predictionAccuracy: nil,
            notificationSent: false,
            notificationSentAt: nil,
            createdAt: Date()
        )

        XCTAssertEqual(prediction.outlookLabel, "May Be Challenging")
        XCTAssertTrue(prediction.isLowMoodPredicted)
    }

    func testMoodPrediction_ConfidenceLabels() {
        // Low confidence
        let lowConfidence = MoodPrediction(
            id: UUID(),
            userId: UUID(),
            predictedFor: Date(),
            predictedMood: 5.0,
            confidence: 0.40,
            factors: [],
            modelVersion: "v1.0",
            featuresUsed: nil,
            actualMood: nil,
            predictionAccuracy: nil,
            notificationSent: false,
            notificationSentAt: nil,
            createdAt: Date()
        )
        XCTAssertEqual(lowConfidence.confidenceLabel, "Low")
        XCTAssertEqual(lowConfidence.confidencePercent, 40)

        // Medium confidence
        let mediumConfidence = MoodPrediction(
            id: UUID(),
            userId: UUID(),
            predictedFor: Date(),
            predictedMood: 5.0,
            confidence: 0.65,
            factors: [],
            modelVersion: "v1.0",
            featuresUsed: nil,
            actualMood: nil,
            predictionAccuracy: nil,
            notificationSent: false,
            notificationSentAt: nil,
            createdAt: Date()
        )
        XCTAssertEqual(mediumConfidence.confidenceLabel, "Medium")
        XCTAssertEqual(mediumConfidence.confidencePercent, 65)

        // High confidence
        let highConfidence = MoodPrediction(
            id: UUID(),
            userId: UUID(),
            predictedFor: Date(),
            predictedMood: 5.0,
            confidence: 0.85,
            factors: [],
            modelVersion: "v1.0",
            featuresUsed: nil,
            actualMood: nil,
            predictionAccuracy: nil,
            notificationSent: false,
            notificationSentAt: nil,
            createdAt: Date()
        )
        XCTAssertEqual(highConfidence.confidenceLabel, "High")
        XCTAssertEqual(highConfidence.confidencePercent, 85)
    }

    func testMoodPrediction_MoodValueConversion() {
        let prediction = MoodPrediction(
            id: UUID(),
            userId: UUID(),
            predictedFor: Date(),
            predictedMood: 7.25,
            confidence: 0.75,
            factors: [],
            modelVersion: "v1.0",
            featuresUsed: nil,
            actualMood: nil,
            predictionAccuracy: nil,
            notificationSent: false,
            notificationSentAt: nil,
            createdAt: Date()
        )

        XCTAssertEqual(prediction.predictedMoodValue, 7.25, accuracy: 0.001)
    }

    // MARK: - MoodPredictionFactor Tests

    func testMoodPredictionFactor_PositiveImpact() {
        let factor = MoodPredictionFactor(
            factor: "sleep_hours",
            impact: 0.8,
            description: "Good sleep: 7.5h last night"
        )

        XCTAssertTrue(factor.isPositive)
        XCTAssertEqual(factor.impactLabel, "+0.8")
    }

    func testMoodPredictionFactor_NegativeImpact() {
        let factor = MoodPredictionFactor(
            factor: "sleep_hours",
            impact: -1.2,
            description: "Only 5h sleep last night"
        )

        XCTAssertFalse(factor.isPositive)
        XCTAssertEqual(factor.impactLabel, "-1.2")
    }

    func testMoodPredictionFactor_IconForKnownFactors() {
        let sleepFactor = MoodPredictionFactor(
            factor: "sleep_hours",
            impact: 0.5,
            description: "Sleep"
        )
        XCTAssertEqual(sleepFactor.icon, "moon.zzz.fill")

        let moodTrendFactor = MoodPredictionFactor(
            factor: "mood_trend",
            impact: -0.5,
            description: "Trend"
        )
        XCTAssertEqual(moodTrendFactor.icon, "chart.line.uptrend.xyaxis")

        let dayFactor = MoodPredictionFactor(
            factor: "day_of_week",
            impact: 0.2,
            description: "Day"
        )
        XCTAssertEqual(dayFactor.icon, "calendar")

        let streakFactor = MoodPredictionFactor(
            factor: "streak",
            impact: 0.3,
            description: "Streak"
        )
        XCTAssertEqual(streakFactor.icon, "flame.fill")

        let stepsFactor = MoodPredictionFactor(
            factor: "steps_yesterday",
            impact: 0.4,
            description: "Steps"
        )
        XCTAssertEqual(stepsFactor.icon, "figure.walk")
    }

    func testMoodPredictionFactor_UnknownFactorUsesDefaultIcon() {
        let unknownFactor = MoodPredictionFactor(
            factor: "custom_metric",
            impact: 0.1,
            description: "Custom"
        )
        XCTAssertEqual(unknownFactor.icon, "circle.fill")
    }

    // MARK: - PreemptiveIntervention Tests

    func testPreemptiveIntervention_TypeProperties() {
        let restType = PreemptiveInterventionType.restSuggestion
        XCTAssertEqual(restType.title, "Rest Suggested")
        XCTAssertEqual(restType.icon, "moon.zzz.fill")

        let movementType = PreemptiveInterventionType.movementSuggestion
        XCTAssertEqual(movementType.title, "Movement Break")
        XCTAssertEqual(movementType.icon, "figure.walk")

        let patternType = PreemptiveInterventionType.patternBreak
        XCTAssertEqual(patternType.title, "Break the Pattern")
        XCTAssertEqual(patternType.icon, "arrow.triangle.swap")

        let generalType = PreemptiveInterventionType.generalSupport
        XCTAssertEqual(generalType.title, "Support Available")
        XCTAssertEqual(generalType.icon, "heart.fill")
    }

    func testPreemptiveIntervention_StatusValues() {
        XCTAssertEqual(PreemptiveInterventionStatus.pending.rawValue, "pending")
        XCTAssertEqual(PreemptiveInterventionStatus.delivered.rawValue, "delivered")
        XCTAssertEqual(PreemptiveInterventionStatus.accepted.rawValue, "accepted")
        XCTAssertEqual(PreemptiveInterventionStatus.dismissed.rawValue, "dismissed")
        XCTAssertEqual(PreemptiveInterventionStatus.expired.rawValue, "expired")
    }

    // MARK: - PredictionSettings Tests

    func testPredictionSettings_DefaultValues() {
        let defaults = PredictionSettings.defaults

        XCTAssertFalse(defaults.predictionsEnabled)
        XCTAssertTrue(defaults.useMoodData)
        XCTAssertTrue(defaults.useChatSentiment)
        XCTAssertFalse(defaults.useBiometrics)
        XCTAssertTrue(defaults.useAppUsage)
        XCTAssertFalse(defaults.useSleepData)
        XCTAssertTrue(defaults.allowGentleNudges)
        XCTAssertFalse(defaults.allowActiveCheckins)
        XCTAssertFalse(defaults.allowFamilyAlerts)
        XCTAssertEqual(defaults.familyAlertThreshold, .high)
    }

    // MARK: - JSON Decoding Tests

    func testMoodPrediction_JSONDecoding() throws {
        let json = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440000",
            "user_id": "550e8400-e29b-41d4-a716-446655440001",
            "predicted_for": "2026-01-23",
            "predicted_mood": 6.5,
            "confidence": 0.72,
            "factors": [
                {
                    "factor": "sleep_hours",
                    "impact": -0.8,
                    "description": "Low sleep detected"
                }
            ],
            "model_version": "v1.0",
            "features_used": null,
            "actual_mood": null,
            "prediction_accuracy": null,
            "notification_sent": true,
            "notification_sent_at": "2026-01-23T06:00:00Z",
            "created_at": "2026-01-23T05:55:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        let prediction = try decoder.decode(MoodPrediction.self, from: json)

        XCTAssertEqual(prediction.predictedMoodValue, 6.5, accuracy: 0.001)
        XCTAssertEqual(prediction.confidencePercent, 72)
        XCTAssertEqual(prediction.factors.count, 1)
        XCTAssertEqual(prediction.factors.first?.factor, "sleep_hours")
        XCTAssertEqual(prediction.modelVersion, "v1.0")
        XCTAssertTrue(prediction.notificationSent)
    }

    func testPreemptiveIntervention_JSONDecoding() throws {
        let json = """
        {
            "id": "550e8400-e29b-41d4-a716-446655440002",
            "user_id": "550e8400-e29b-41d4-a716-446655440001",
            "prediction_id": "550e8400-e29b-41d4-a716-446655440000",
            "intervention_type": "rest_suggestion",
            "content": "Based on your sleep patterns, today might be challenging.",
            "suggested_exercise_id": null,
            "status": "delivered",
            "delivered_at": "2026-01-23T06:00:00Z",
            "user_response": null,
            "response_recorded_at": null,
            "created_at": "2026-01-23T05:55:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        let intervention = try decoder.decode(PreemptiveIntervention.self, from: json)

        XCTAssertEqual(intervention.interventionType, .restSuggestion)
        XCTAssertEqual(intervention.status, .delivered)
        XCTAssertNotNil(intervention.deliveredAt)
        XCTAssertNil(intervention.userResponse)
    }
}
