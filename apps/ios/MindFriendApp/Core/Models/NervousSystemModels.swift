import Foundation
import SwiftUI

// MARK: - Core State Models

/// Nervous system states based on Polyvagal Theory
enum NervousSystemState: String, Codable, CaseIterable {
    case ventral = "ventral"       // Safe & Social (ventral vagal complex)
    case sympathetic = "sympathetic" // Mobilized (fight/flight)
    case dorsal = "dorsal"          // Shutdown (dorsal vagal complex)
    case mixed = "mixed"            // Mixed activation
    case unknown = "unknown"        // Insufficient data

    var displayName: String {
        switch self {
        case .ventral: return "Safe & Social"
        case .sympathetic: return "Mobilized"
        case .dorsal: return "Shutdown"
        case .mixed: return "Mixed Activation"
        case .unknown: return "Uncertain"
        }
    }

    var description: String {
        switch self {
        case .ventral:
            return "Your nervous system is in a state of safety and social engagement. You're able to connect, learn, and rest."
        case .sympathetic:
            return "Your nervous system is activated for action. This mobilization helps you respond to challenges."
        case .dorsal:
            return "Your nervous system has moved into a protective shutdown state. This is a sign to slow down and be gentle with yourself."
        case .mixed:
            return "Your nervous system shows mixed signals. Multiple activation patterns are present."
        case .unknown:
            return "We don't have enough data to determine your nervous system state right now."
        }
    }

    var color: Color {
        switch self {
        case .ventral: return .green
        case .sympathetic: return .orange
        case .dorsal: return .blue
        case .mixed: return .purple
        case .unknown: return .gray
        }
    }

    var iconName: String {
        switch self {
        case .ventral: return "heart.fill"
        case .sympathetic: return "bolt.fill"
        case .dorsal: return "moon.fill"
        case .mixed: return "waveform.path"
        case .unknown: return "questionmark"
        }
    }

    /// Polyvagal value for cascade detection (higher = more regulated)
    var polyvagalValue: Int {
        switch self {
        case .ventral: return 2
        case .sympathetic: return 1
        case .dorsal: return 0
        case .mixed: return 1
        case .unknown: return 1
        }
    }
}

/// Recorded nervous system state classification
struct NervousSystemStateRecord: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let state: NervousSystemState
    let confidence: Double

    let voiceFeatures: PolyvagalVoiceFeatures?
    let hrvFeatures: PolyvagalHRVFeatures?
    let behavioralFeatures: PolyvagalBehavioralFeatures?

    let latencyMs: Int?
    let source: ClassificationSource
    let classifiedAt: Date
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case state
        case confidence
        case voiceFeatures = "voice_features"
        case hrvFeatures = "hrv_features"
        case behavioralFeatures = "behavioral_features"
        case latencyMs = "latency_ms"
        case source
        case classifiedAt = "classified_at"
        case createdAt = "created_at"
    }
}

/// Source of nervous system state classification
enum ClassificationSource: String, Codable {
    case voiceSession = "voice_session"
    case passiveForeground = "passive_foreground"
}

// MARK: - Feature Structures

/// Voice-based polyvagal features
struct PolyvagalVoiceFeatures: Codable {
    let pitchVariability: Double       // Hz std dev
    let speechRate: Double              // words/min
    let voiceIntensity: Double          // dB
    let positiveEmotionRatio: Double    // 0-1
    let negativeEmotionRatio: Double    // 0-1
    let arousalLevel: Double            // 0-1 (calm to agitated)
    let socialEngagementScore: Double   // 0-1 (joy, contentment)
    let threatActivationScore: Double   // 0-1 (fear, anger)
    let shutdownRiskScore: Double       // 0-1 (sadness, fatigue)

    enum CodingKeys: String, CodingKey {
        case pitchVariability = "pitch_variability"
        case speechRate = "speech_rate"
        case voiceIntensity = "voice_intensity"
        case positiveEmotionRatio = "positive_emotion_ratio"
        case negativeEmotionRatio = "negative_emotion_ratio"
        case arousalLevel = "arousal_level"
        case socialEngagementScore = "social_engagement_score"
        case threatActivationScore = "threat_activation_score"
        case shutdownRiskScore = "shutdown_risk_score"
    }
}

/// HRV-based polyvagal features
struct PolyvagalHRVFeatures: Codable {
    let rmssd: Double      // ms (root mean square of successive differences)
    let sdnn: Double       // ms (standard deviation of NN intervals)
    let timestamp: Date

    /// Vagal tone score (normalized RMSSD)
    var vagalToneScore: Double {
        min(1.0, rmssd / 50.0)
    }

    /// Sympathetic activation score
    var sympatheticActivationScore: Double {
        if sdnn < 30 {
            return 1.0
        }
        return max(0, (50 - sdnn) / 20.0)
    }
}

/// Behavioral polyvagal features
struct PolyvagalBehavioralFeatures: Codable {
    let recentActivityLevel: Double         // 0-1 (interactions/min)
    let socialEngagementLevel: Double       // 0-1 (circles, chat activity)
    let selfCareLevel: Double               // 0-1 (exercises, quests, moods)
    let sessionDuration: TimeInterval       // current foreground session
    let timeSinceLastInteraction: TimeInterval
    let consecutiveBackgroundingSessions: Int

    enum CodingKeys: String, CodingKey {
        case recentActivityLevel = "recent_activity_level"
        case socialEngagementLevel = "social_engagement_level"
        case selfCareLevel = "self_care_level"
        case sessionDuration = "session_duration"
        case timeSinceLastInteraction = "time_since_last_interaction"
        case consecutiveBackgroundingSessions = "consecutive_backgrounding_sessions"
    }
}

// MARK: - Cascade Events

/// Detected cascade event (rapid deterioration)
struct CascadeEvent: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let startedAt: Date
    let endedAt: Date
    let stateSequence: [NervousSystemState]
    let severity: CascadeSeverity
    let transitionCount: Int
    let detectedAt: Date
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case stateSequence = "state_sequence"
        case severity
        case transitionCount = "transition_count"
        case detectedAt = "detected_at"
        case createdAt = "created_at"
    }
}

/// Cascade severity levels
enum CascadeSeverity: String, Codable {
    case mild = "mild"         // 3 transitions
    case moderate = "moderate" // 4-5 transitions
    case severe = "severe"     // 6+ transitions

    var color: Color {
        switch self {
        case .mild: return .yellow
        case .moderate: return .orange
        case .severe: return .red
        }
    }

    var displayName: String {
        switch self {
        case .mild: return "Mild Dysregulation"
        case .moderate: return "Moderate Dysregulation"
        case .severe: return "Severe Dysregulation"
        }
    }
}

// MARK: - Interventions

/// Intervention recommendation
struct InterventionRecommendation: Identifiable, Codable {
    let id: UUID
    let type: InterventionType
    let title: String
    let description: String
    let estimatedDuration: TimeInterval
    let urgency: InterventionUrgency
    let efficacyScore: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case title
        case description
        case estimatedDuration = "estimated_duration"
        case urgency
        case efficacyScore = "efficacy_score"
    }
}

/// Types of interventions
enum InterventionType: String, Codable, CaseIterable {
    case breathing = "breathing"
    case grounding = "grounding"
    case movement = "movement"
    case socialConnection = "social_connection"
    case professionalSupport = "professional_support"

    var displayName: String {
        switch self {
        case .breathing: return "Breathing"
        case .grounding: return "Grounding"
        case .movement: return "Movement"
        case .socialConnection: return "Social Connection"
        case .professionalSupport: return "Professional Support"
        }
    }

    var iconName: String {
        switch self {
        case .breathing: return "wind"
        case .grounding: return "hand.raised.fill"
        case .movement: return "figure.walk"
        case .socialConnection: return "person.2.fill"
        case .professionalSupport: return "stethoscope"
        }
    }
}

/// Intervention urgency levels
enum InterventionUrgency: String, Codable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"

    var color: Color {
        switch self {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .orange
        case .critical: return .red
        }
    }
}

/// State intervention record
struct StateIntervention: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let stateRecordId: UUID?
    let cascadeEventId: UUID?
    let interventionType: InterventionType
    let title: String
    let description: String?
    let urgency: InterventionUrgency
    let recommendedAt: Date
    var completedAt: Date?
    var efficacyRating: Double?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case stateRecordId = "state_record_id"
        case cascadeEventId = "cascade_event_id"
        case interventionType = "intervention_type"
        case title
        case description
        case urgency
        case recommendedAt = "recommended_at"
        case completedAt = "completed_at"
        case efficacyRating = "efficacy_rating"
        case createdAt = "created_at"
    }
}

// MARK: - Errors

/// Nervous system engine errors
enum NervousSystemError: LocalizedError {
    case insufficientData
    case classificationTimeout
    case storageFailure(Error)
    case invalidFeatures
    case healthKitUnauthorized
    case databaseError(String)

    var errorDescription: String? {
        switch self {
        case .insufficientData:
            return "Not enough data available for state classification"
        case .classificationTimeout:
            return "Classification took too long (>800ms)"
        case .storageFailure(let error):
            return "Failed to store state: \(error.localizedDescription)"
        case .invalidFeatures:
            return "Invalid polyvagal features"
        case .healthKitUnauthorized:
            return "HealthKit authorization required for HRV data"
        case .databaseError(let message):
            return "Database error: \(message)"
        }
    }
}

// MARK: - Result Types

/// Classification result
struct NervousSystemStateResult {
    let state: NervousSystemState
    let confidence: Double
    let contributingFactors: [String: Double]
    let latency: TimeInterval

    var latencyMs: Int {
        Int(latency * 1000)
    }
}
