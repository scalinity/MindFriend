// BiofeedbackModels.swift
// MindFriendApp
// Models for biofeedback adaptation system

import Foundation
import SwiftUI

// MARK: - Physiological Constants

enum PhysiologicalConstants {
    /// Minimum physiologically plausible heart rate (BPM)
    static let minHeartRate: Double = 30
    /// Maximum physiologically plausible heart rate (BPM)
    static let maxHeartRate: Double = 220
    /// Minimum range between resting and stress HR to calculate stress level (BPM)
    static let minStressRangeForCalculation: Double = 5.0
    /// Minimum sample count for reliable baseline
    static let minSamplesForReliableBaseline = 10
    /// Minimum confidence score for reliable baseline
    static let minConfidenceForReliableBaseline: Double = 0.7

    // Stress level thresholds (as ratio of range from resting to stress HR)
    static let relaxedThreshold: Double = 0.2
    static let calmThreshold: Double = 0.4
    static let moderateThreshold: Double = 0.6
    static let elevatedThreshold: Double = 0.8
}

// MARK: - Biofeedback Baseline

struct BiofeedbackBaseline: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    var restingHeartRate: Double?
    var restingHRV: Double?
    var exerciseRecoveryRate: Double?
    var stressHRThreshold: Double?
    var relaxedHRThreshold: Double?
    let calculatedAt: Date
    var sampleCount: Int
    var confidenceScore: Double
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case restingHeartRate = "resting_heart_rate"
        case restingHRV = "resting_hrv"
        case exerciseRecoveryRate = "exercise_recovery_rate"
        case stressHRThreshold = "stress_hr_threshold"
        case relaxedHRThreshold = "relaxed_hr_threshold"
        case calculatedAt = "calculated_at"
        case sampleCount = "sample_count"
        case confidenceScore = "confidence_score"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var isReliable: Bool {
        confidenceScore >= PhysiologicalConstants.minConfidenceForReliableBaseline &&
        sampleCount >= PhysiologicalConstants.minSamplesForReliableBaseline
    }

    func stressLevel(forHeartRate hr: Double) -> BiofeedbackStressLevel {
        // Validate input - heart rate must be physiologically plausible
        guard hr >= PhysiologicalConstants.minHeartRate,
              hr <= PhysiologicalConstants.maxHeartRate else {
            return .unknown
        }

        guard let resting = restingHeartRate,
              let stress = stressHRThreshold,
              stress > resting else {
            return .unknown
        }

        let range = stress - resting

        // Prevent division by zero and handle edge case where thresholds are too close
        guard range >= PhysiologicalConstants.minStressRangeForCalculation else {
            return .unknown
        }

        let current = hr - resting

        // Handle heart rate below resting (very relaxed state)
        if current < 0 {
            return .relaxed
        }

        let ratio = current / range

        if ratio <= PhysiologicalConstants.relaxedThreshold { return .relaxed }
        if ratio <= PhysiologicalConstants.calmThreshold { return .calm }
        if ratio <= PhysiologicalConstants.moderateThreshold { return .moderate }
        if ratio <= PhysiologicalConstants.elevatedThreshold { return .elevated }
        return .high
    }
}

// MARK: - Biofeedback Stress Level

enum BiofeedbackStressLevel: String, Codable, CaseIterable {
    case relaxed
    case calm
    case moderate
    case elevated
    case high
    case unknown

    var color: Color {
        switch self {
        case .relaxed: return .green
        case .calm: return .teal
        case .moderate: return .yellow
        case .elevated: return .orange
        case .high: return .red
        case .unknown: return .gray
        }
    }

    var displayName: String {
        switch self {
        case .relaxed: return "Relaxed"
        case .calm: return "Calm"
        case .moderate: return "Moderate"
        case .elevated: return "Elevated"
        case .high: return "High"
        case .unknown: return "Unknown"
        }
    }

    var icon: String {
        switch self {
        case .relaxed: return "leaf.fill"
        case .calm: return "wind"
        case .moderate: return "equal.circle.fill"
        case .elevated: return "exclamationmark.triangle"
        case .high: return "flame.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

// MARK: - Physiological State

enum PhysiologicalState: String, Codable {
    case baseline
    case elevated
    case stressed
    case relaxing
    case recovered

    var displayName: String {
        switch self {
        case .baseline: return "Normal"
        case .elevated: return "Slightly Elevated"
        case .stressed: return "Stressed"
        case .relaxing: return "Relaxing"
        case .recovered: return "Recovered"
        }
    }

    var color: Color {
        switch self {
        case .baseline: return .blue
        case .elevated: return .orange
        case .stressed: return .red
        case .relaxing: return .teal
        case .recovered: return .green
        }
    }
}

// MARK: - Biofeedback Session

struct BiofeedbackSession: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let exerciseSessionId: UUID?
    let startedAt: Date
    var completedAt: Date?
    var durationSeconds: Int?
    var wasExtended: Bool
    var extensionSeconds: Int
    let adaptationMode: AdaptationMode
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case exerciseSessionId = "exercise_session_id"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case durationSeconds = "duration_seconds"
        case wasExtended = "was_extended"
        case extensionSeconds = "extension_seconds"
        case adaptationMode = "adaptation_mode"
        case createdAt = "created_at"
    }
}

// MARK: - Adaptation Mode

enum AdaptationMode: String, Codable, CaseIterable {
    case auto
    case gentle
    case aggressive
    case off

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .gentle: return "Gentle"
        case .aggressive: return "Aggressive"
        case .off: return "Off"
        }
    }

    var description: String {
        switch self {
        case .auto: return "Adapts based on your stress level"
        case .gentle: return "Only adapts when stress is high"
        case .aggressive: return "Constantly optimizes for relaxation"
        case .off: return "No automatic adaptations"
        }
    }
}

// MARK: - Biofeedback Reading

struct BiofeedbackReading: Codable, Identifiable {
    let id: UUID
    let sessionId: UUID
    let timestamp: Date
    let heartRate: Double
    let hrvSdnn: Double?
    let hrvRmssd: Double?
    let relativeStressLevel: Double?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case timestamp
        case heartRate = "heart_rate"
        case hrvSdnn = "hrv_sdnn"
        case hrvRmssd = "hrv_rmssd"
        case relativeStressLevel = "relative_stress_level"
        case createdAt = "created_at"
    }
}

// MARK: - Biofeedback Adaptation

struct BiofeedbackAdaptation: Codable, Identifiable {
    let id: UUID
    let sessionId: UUID
    let timestamp: Date
    let adaptationType: AdaptationType
    let triggerReason: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case timestamp
        case adaptationType = "adaptation_type"
        case triggerReason = "trigger_reason"
        case createdAt = "created_at"
    }
}

// MARK: - Adaptation Type

enum AdaptationType: String, Codable {
    case breathingPace = "breathing_pace"
    case exerciseExtension = "exercise_extension"
    case intensityReduction = "intensity_reduction"
    case guidanceFrequency = "guidance_frequency"
    case visualFeedback = "visual_feedback"
    case audioTempo = "audio_tempo"

    var displayName: String {
        switch self {
        case .breathingPace: return "Breathing Pace"
        case .exerciseExtension: return "Extended Duration"
        case .intensityReduction: return "Reduced Intensity"
        case .guidanceFrequency: return "Guidance Frequency"
        case .visualFeedback: return "Visual Feedback"
        case .audioTempo: return "Audio Tempo"
        }
    }
}

// MARK: - Biofeedback Summary

struct BiofeedbackSummary: Codable, Identifiable {
    let id: UUID
    let sessionId: UUID
    let startingHeartRate: Double?
    let endingHeartRate: Double?
    let lowestHeartRate: Double?
    let highestHeartRate: Double?
    let averageHeartRate: Double?
    let startingHRV: Double?
    let endingHRV: Double?
    let hrvImprovementPercent: Double?
    let timeToRelaxationSeconds: Int?
    let totalAdaptations: Int
    let effectivenessScore: Double?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case startingHeartRate = "starting_heart_rate"
        case endingHeartRate = "ending_heart_rate"
        case lowestHeartRate = "lowest_heart_rate"
        case highestHeartRate = "highest_heart_rate"
        case averageHeartRate = "average_heart_rate"
        case startingHRV = "starting_hrv"
        case endingHRV = "ending_hrv"
        case hrvImprovementPercent = "hrv_improvement_percent"
        case timeToRelaxationSeconds = "time_to_relaxation_seconds"
        case totalAdaptations = "total_adaptations"
        case effectivenessScore = "effectiveness_score"
        case createdAt = "created_at"
    }

    var heartRateChange: Double? {
        guard let start = startingHeartRate, let end = endingHeartRate else { return nil }
        return end - start
    }

    var heartRateChangePercent: Double? {
        guard let start = startingHeartRate, let change = heartRateChange, start > 0 else { return nil }
        return (change / start) * 100
    }
}

// MARK: - Live Biometric Data

struct LiveBiometricData {
    let heartRate: Double
    let hrvRMSSD: Double?
    let timestamp: Date

    var isValid: Bool {
        heartRate >= PhysiologicalConstants.minHeartRate &&
        heartRate <= PhysiologicalConstants.maxHeartRate
    }
}

// MARK: - Adaptation Parameters

struct AdaptationParameters: Codable, Equatable {
    var breathingInhaleSeconds: Double
    var breathingHoldSeconds: Double
    var breathingExhaleSeconds: Double
    var breathingPauseSeconds: Double
    var guidanceVerbosity: GuidanceVerbosity
    var visualIntensity: Double
    var audioTempo: Double

    enum GuidanceVerbosity: String, Codable {
        case minimal
        case moderate
        case detailed
    }

    static var `default`: AdaptationParameters {
        AdaptationParameters(
            breathingInhaleSeconds: 4,
            breathingHoldSeconds: 4,
            breathingExhaleSeconds: 4,
            breathingPauseSeconds: 2,
            guidanceVerbosity: .moderate,
            visualIntensity: 0.7,
            audioTempo: 60
        )
    }

    var breathingPattern: BiofeedbackBreathingPattern {
        BiofeedbackBreathingPattern(
            inhale: breathingInhaleSeconds,
            hold: breathingHoldSeconds,
            exhale: breathingExhaleSeconds,
            pause: breathingPauseSeconds
        )
    }
}

// MARK: - Biofeedback Breathing Pattern

struct BiofeedbackBreathingPattern: Equatable, Codable {
    let inhale: Double
    let hold: Double
    let exhale: Double
    let pause: Double

    var totalCycleDuration: Double {
        inhale + hold + exhale + pause
    }

    var displayName: String {
        "\(Int(inhale))-\(Int(hold))-\(Int(exhale))"
    }

    static var relaxed: BiofeedbackBreathingPattern {
        BiofeedbackBreathingPattern(inhale: 5, hold: 7, exhale: 8, pause: 3)
    }

    static var calm: BiofeedbackBreathingPattern {
        BiofeedbackBreathingPattern(inhale: 4, hold: 6, exhale: 6, pause: 2)
    }

    static var moderate: BiofeedbackBreathingPattern {
        BiofeedbackBreathingPattern(inhale: 4, hold: 4, exhale: 4, pause: 2)
    }

    static var elevated: BiofeedbackBreathingPattern {
        BiofeedbackBreathingPattern(inhale: 4, hold: 4, exhale: 6, pause: 2)
    }

    static var stressed: BiofeedbackBreathingPattern {
        BiofeedbackBreathingPattern(inhale: 3, hold: 2, exhale: 5, pause: 1)
    }

    /// Compare two patterns with a tolerance to avoid floating point comparison issues
    func isApproximatelyEqual(to other: BiofeedbackBreathingPattern, tolerance: Double = 0.1) -> Bool {
        abs(inhale - other.inhale) <= tolerance &&
        abs(hold - other.hold) <= tolerance &&
        abs(exhale - other.exhale) <= tolerance &&
        abs(pause - other.pause) <= tolerance
    }
}

// MARK: - Biometric Analysis Response

struct BiometricAnalysisResponse: Codable {
    let success: Bool
    let analysis: BiometricAnalysis?
}

struct BiometricAnalysis: Codable {
    let physiologicalState: String
    let stressLevel: Double
    let trend: String
    let adaptations: [AdaptationSuggestion]
    let shouldExtend: Bool
    let extensionReason: String?

    enum CodingKeys: String, CodingKey {
        case physiologicalState = "physiological_state"
        case stressLevel = "stress_level"
        case trend
        case adaptations
        case shouldExtend = "should_extend"
        case extensionReason = "extension_reason"
    }

    var state: PhysiologicalState {
        PhysiologicalState(rawValue: physiologicalState) ?? .baseline
    }

    var trendDirection: BiofeedbackTrendDirection {
        BiofeedbackTrendDirection(rawValue: trend) ?? .stable
    }
}

struct AdaptationSuggestion: Codable {
    let type: String
    let priority: String
    let reason: String
    let params: [String: Double]?

    var adaptationType: AdaptationType? {
        AdaptationType(rawValue: type)
    }
}

enum BiofeedbackTrendDirection: String, Codable {
    case improving
    case stable
    case worsening

    var icon: String {
        switch self {
        case .improving: return "arrow.down"
        case .stable: return "minus"
        case .worsening: return "arrow.up"
        }
    }

    var color: Color {
        switch self {
        case .improving: return .green
        case .stable: return .blue
        case .worsening: return .orange
        }
    }
}

// MARK: - Extension Recommendation

enum ExtensionRecommendation {
    case notNeeded
    case optional(additionalSeconds: Int, reason: String)
    case recommended(additionalSeconds: Int, reason: String)

    var shouldShow: Bool {
        switch self {
        case .notNeeded: return false
        default: return true
        }
    }
}

// MARK: - HealthKit Sample Storage

struct HealthKitHeartRateSample: Codable {
    let userId: UUID
    let value: Double
    let timestamp: Date
    let context: HeartRateContext
    let sourceDevice: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case value
        case timestamp
        case context
        case sourceDevice = "source_device"
    }
}

enum HeartRateContext: String, Codable {
    case resting
    case active
    case sleep
    case workout
    case unknown
}

struct HealthKitHRVSample: Codable {
    let userId: UUID
    let value: Double
    let timestamp: Date
    let measurementType: HRVMeasurementType
    let sourceDevice: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case value
        case timestamp
        case measurementType = "measurement_type"
        case sourceDevice = "source_device"
    }
}

enum HRVMeasurementType: String, Codable {
    case sdnn
    case rmssd
}

// MARK: - Baseline Calculation Response

struct BaselineCalculationResponse: Codable {
    let success: Bool
    let baseline: BaselineData?
    let meta: BaselineMeta?

    struct BaselineData: Codable {
        let restingHeartRate: Double?
        let restingHRV: Double?
        let exerciseRecoveryRate: Double?
        let stressHRThreshold: Double?
        let relaxedHRThreshold: Double?
        let confidenceScore: Double
        let sampleCount: Int

        enum CodingKeys: String, CodingKey {
            case restingHeartRate = "resting_heart_rate"
            case restingHRV = "resting_hrv"
            case exerciseRecoveryRate = "exercise_recovery_rate"
            case stressHRThreshold = "stress_hr_threshold"
            case relaxedHRThreshold = "relaxed_hr_threshold"
            case confidenceScore = "confidence_score"
            case sampleCount = "sample_count"
        }
    }

    struct BaselineMeta: Codable {
        let lookbackDays: Int
        let heartRateSamples: Int
        let hrvSamples: Int
        let restingContextSamples: Int

        enum CodingKeys: String, CodingKey {
            case lookbackDays = "lookback_days"
            case heartRateSamples = "heart_rate_samples"
            case hrvSamples = "hrv_samples"
            case restingContextSamples = "resting_context_samples"
        }
    }
}
