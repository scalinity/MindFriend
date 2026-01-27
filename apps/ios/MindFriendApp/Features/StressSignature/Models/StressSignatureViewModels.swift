import Foundation

// MARK: - Stress Signature Models

/// Represents a user's aggregated stress signature from pattern analysis
struct StressSignature: Identifiable, Equatable {
    let id = UUID()
    let userId: UUID
    let generatedAt: Date
    let patterns: [SignaturePattern]

    /// Patterns categorized as stress triggers
    var stressTriggers: [SignaturePattern] {
        patterns.filter { $0.type == .stressTrigger }
    }

    /// Patterns categorized as coping strategies
    var copingStrategies: [SignaturePattern] {
        patterns.filter { $0.type == .copingStrategy }
    }

    /// Patterns categorized as time-based patterns
    var timePatterns: [SignaturePattern] {
        patterns.filter { $0.type == .timePattern }
    }

    /// Total number of patterns across all types
    var totalPatternCount: Int {
        patterns.count
    }

    /// Check if signature has sufficient data to display
    var hasSufficientData: Bool {
        patterns.count >= 3
    }
}

/// Individual pattern within a stress signature
struct SignaturePattern: Identifiable, Equatable {
    let id: UUID
    let category: String
    let type: SignaturePatternType
    let confidenceScore: Double
    let evidenceCount: Int
    let frequency: Double  // patterns per week
    let timeline: [TimelineDataPoint]
    let firstDetected: Date
    let lastDetected: Date
    let topExercises: [String]?
    let peakTimes: [String]?

    /// User-friendly description of pattern frequency
    var frequencyDescription: String {
        if frequency >= 5 {
            return "Very Common"
        } else if frequency >= 2 {
            return "Frequent"
        } else if frequency >= 0.5 {
            return "Occasional"
        } else {
            return "Rare"
        }
    }

    /// Duration in days between first and last detection
    var durationDays: Int {
        Calendar.current.dateComponents([.day], from: firstDetected, to: lastDetected).day ?? 0
    }

    /// Confidence as percentage (0-100)
    var confidencePercentage: Int {
        Int(confidenceScore * 100)
    }

    /// Badge color based on confidence score
    var confidenceColor: String {
        if confidenceScore >= 0.8 {
            return "green"
        } else if confidenceScore >= 0.6 {
            return "yellow"
        } else {
            return "orange"
        }
    }
}

/// Data point for timeline visualization
struct TimelineDataPoint: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let count: Int
}

/// Pattern type classification
enum SignaturePatternType: String, Codable {
    case stressTrigger = "signature_stress_trigger"
    case copingStrategy = "signature_coping_strategy"
    case timePattern = "signature_time_pattern"
    case other

    /// User-friendly display name
    var displayName: String {
        switch self {
        case .stressTrigger:
            return "Stress Trigger"
        case .copingStrategy:
            return "Coping Strategy"
        case .timePattern:
            return "Time Pattern"
        case .other:
            return "Other Pattern"
        }
    }

    /// SF Symbol icon name
    var iconName: String {
        switch self {
        case .stressTrigger:
            return "exclamationmark.triangle"
        case .copingStrategy:
            return "heart.circle"
        case .timePattern:
            return "clock"
        case .other:
            return "chart.bar"
        }
    }
}
