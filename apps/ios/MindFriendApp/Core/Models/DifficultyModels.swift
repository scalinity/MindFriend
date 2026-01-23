import Foundation
import SwiftUI

// MARK: - Configuration Constants

/// Constants for capacity difficulty calculations
/// SHARED WITH: supabase/functions/calculate-capacity/algorithms.ts
/// These values MUST stay in sync between Swift and TypeScript implementations
private enum CapacityConstants {
    // Capacity level thresholds (aligned with spec)
    static let thresholdLow: Int = 35      // 0-35 is "low"
    static let thresholdModerate: Int = 70  // 35-70 is "moderate", 70-100 is "high"

    // Difficulty multipliers for quest/exercise adjustment
    static let multiplierLow: Double = 0.5      // Easier/shorter content
    static let multiplierModerate: Double = 1.0  // Standard content
    static let multiplierHigh: Double = 1.25    // Challenging/longer content

    // Override target scores
    static let overrideRestScore: Int = 25       // Rest mode target
    static let overrideNormalScore: Int = 50     // Normal mode target
    static let overrideChallengeScore: Int = 75  // Challenge mode target

    // Staleness threshold
    static let stalenessThresholdSeconds: TimeInterval = 12 * 3600  // 12 hours

    // Score bounds
    static let scoreMin: Int = 0
    static let scoreMax: Int = 100
}

// MARK: - Capacity Level

/// Capacity level based on capacity score
/// Aligned with spec thresholds: low 0-35, moderate 35-70, high 70-100
enum CapacityLevel: String, Codable, CaseIterable {
    case low = "low"
    case moderate = "moderate"
    case high = "high"
    
    /// Display name for UI
    var displayName: String {
        switch self {
        case .low: return "Low Energy"
        case .moderate: return "Moderate Energy"
        case .high: return "High Energy"
        }
    }
    
    /// Color for UI indicators
    var color: Color {
        switch self {
        case .low: return .blue
        case .moderate: return .green
        case .high: return .orange
        }
    }
    
    /// Icon for UI indicators
    var icon: String {
        switch self {
        case .low: return "leaf.fill"
        case .moderate: return "circle.grid.2x2.fill"
        case .high: return "flame.fill"
        }
    }
    
    /// Difficulty multiplier for quest/exercise adjustment
    /// Low: easier/shorter content
    /// Moderate: standard content
    /// High: challenging/longer content
    var difficultyMultiplier: Double {
        switch self {
        case .low: return CapacityConstants.multiplierLow
        case .moderate: return CapacityConstants.multiplierModerate
        case .high: return CapacityConstants.multiplierHigh
        }
    }

    /// Initialize from capacity score
    /// UPDATED: Thresholds aligned with spec
    init(score: Int) {
        switch score {
        case CapacityConstants.scoreMin..<CapacityConstants.thresholdLow:
            self = .low
        case CapacityConstants.thresholdLow..<CapacityConstants.thresholdModerate:
            self = .moderate
        default:
            self = .high
        }
    }
}

// MARK: - Component Score

/// Individual component contributing to overall capacity score
struct ComponentScore: Codable, Identifiable {
    var id: ComponentType { type }

    let type: ComponentType
    let score: Int        // 0-100
    let weight: Double    // 0.0-1.0

    /// Weighted contribution to final capacity score
    var contribution: Double {
        Double(score) * weight
    }

    enum ComponentType: String, Codable {
        case sleep
        case mood
        case streak
        case completion

        var displayName: String {
            switch self {
            case .sleep: return NSLocalizedString("difficulty.component.sleep", value: "Recent Sleep", comment: "Sleep component")
            case .mood: return NSLocalizedString("difficulty.component.mood", value: "Current Mood", comment: "Mood component")
            case .streak: return NSLocalizedString("difficulty.component.streak", value: "Streak Momentum", comment: "Streak component")
            case .completion: return NSLocalizedString("difficulty.component.completion", value: "Completion Rate", comment: "Completion component")
            }
        }

        var icon: String {
            switch self {
            case .sleep: return "moon.zzz.fill"
            case .mood: return "face.smiling.fill"
            case .streak: return "flame.fill"
            case .completion: return "checkmark.circle.fill"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case type
        case score
        case weight
    }
}

// MARK: - Capacity Components

/// Breakdown of all components contributing to capacity score
struct CapacityComponents: Codable {
    let sleep: ComponentScore
    let mood: ComponentScore
    let streak: ComponentScore
    let completion: ComponentScore

    /// All components as array for iteration
    var all: [ComponentScore] {
        [sleep, mood, streak, completion]
    }

    enum CodingKeys: String, CodingKey {
        case sleep
        case mood
        case streak
        case completion
    }
}

// MARK: - Capacity Score

/// Complete capacity score calculation result
struct CapacityScore: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let score: Int                  // 0-100
    let level: CapacityLevel        // Derived from score
    let components: CapacityComponents
    let localDate: String           // YYYY-MM-DD in user's timezone
    let calculatedAt: Date
    let expiresAt: Date             // Midnight in user's timezone
    let hasOverride: Bool
    let previousScore: Int?

    /// Whether this capacity score is still valid
    var isValid: Bool {
        Date() < expiresAt
    }

    /// Whether this score is stale (calculated >threshold ago)
    var isStale: Bool {
        Date().timeIntervalSince(calculatedAt) > CapacityConstants.stalenessThresholdSeconds
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case score
        case level
        case components
        case localDate = "local_date"
        case calculatedAt = "calculated_at"
        case expiresAt = "expires_at"
        case hasOverride = "has_override"
        case previousScore = "previous_score"
    }
}

// MARK: - Capacity Override

/// User-initiated manual difficulty override
struct CapacityOverride: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let overrideLevel: OverrideLevel
    let expiresAt: Date
    let isActive: Bool
    let createdAt: Date

    /// Target capacity level for this override
    var capacityLevel: CapacityLevel {
        CapacityLevel(score: targetScore)
    }

    /// Target capacity score based on override level
    var targetScore: Int {
        switch overrideLevel {
        case .rest: return CapacityConstants.overrideRestScore
        case .normal: return CapacityConstants.overrideNormalScore
        case .challenge: return CapacityConstants.overrideChallengeScore
        }
    }

    enum OverrideLevel: String, Codable {
        case rest = "rest"          // Force capacity to low (score ~25)
        case normal = "normal"      // Force capacity to moderate (score ~50)
        case challenge = "challenge" // Force capacity to high (score ~75)

        var displayName: String {
            switch self {
            case .rest: return NSLocalizedString("difficulty.override.rest", value: "Rest Mode", comment: "Rest override")
            case .normal: return NSLocalizedString("difficulty.override.normal", value: "Normal Mode", comment: "Normal override")
            case .challenge: return NSLocalizedString("difficulty.override.challenge", value: "Challenge Mode", comment: "Challenge override")
            }
        }

        var icon: String {
            switch self {
            case .rest: return "leaf.fill"
            case .normal: return "circle.grid.2x2.fill"
            case .challenge: return "flame.fill"
            }
        }
    }

    /// Whether this override is still active
    var isCurrentlyActive: Bool {
        isActive && Date() < expiresAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case overrideLevel = "override_level"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case isActive = "is_active"
    }
}

// MARK: - Quest Difficulty Mapping

/// Database mapping of quest types to difficulty multipliers
struct QuestDifficultyMapping: Codable {
    let id: UUID
    let capacityLevel: CapacityLevel
    let questType: String
    let difficultyMultiplier: Double
    let recommended: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case capacityLevel = "capacity_level"
        case questType = "quest_type"
        case difficultyMultiplier = "difficulty_multiplier"
        case recommended
        case createdAt = "created_at"
    }
}

// MARK: - Calculation Request/Response

/// Request sent to calculate-capacity Edge Function
struct CalculateCapacityRequest: Codable {
    let localDate: String   // YYYY-MM-DD
    let timezone: String    // e.g., "America/Los_Angeles"
}

/// Response from calculate-capacity Edge Function
struct CalculateCapacityResponse: Codable {
    let score: Int
    let level: String
    let components: ComponentsResponse
    let localDate: String     // YYYY-MM-DD
    let calculatedAt: String  // ISO 8601
    let expiresAt: String     // ISO 8601
    let hasOverride: Bool

    struct ComponentsResponse: Codable {
        let sleep: ComponentResponse
        let mood: ComponentResponse
        let streak: ComponentResponse
        let completion: ComponentResponse
    }

    struct ComponentResponse: Codable {
        let score: Int
        let weight: Double
        let contribution: Double
    }

    enum CodingKeys: String, CodingKey {
        case score
        case level
        case components
        case localDate = "local_date"
        case calculatedAt = "calculated_at"
        case expiresAt = "expires_at"
        case hasOverride = "has_override"
    }

    /// Convert to CapacityScore model
    func toCapacityScore(userId: UUID) -> CapacityScore? {
        // Validate that level string is valid
        guard CapacityLevel(rawValue: level) != nil else {
            return nil
        }

        // Use level derived from score for consistency
        let capacityLevel = CapacityLevel(score: score)

        // SAFETY: Parse dates with validation
        let formatter = ISO8601DateFormatter()
        guard let calculatedDate = formatter.date(from: calculatedAt),
              let expiresDate = formatter.date(from: expiresAt) else {
            #if DEBUG
            print("Failed to parse capacity dates: calculatedAt=\(calculatedAt), expiresAt=\(expiresAt)")
            #endif
            return nil // Reject invalid response instead of using fallback
        }

        return CapacityScore(
            id: UUID(),
            userId: userId,
            score: score,
            level: capacityLevel,
            components: CapacityComponents(
                sleep: ComponentScore(type: .sleep, score: components.sleep.score, weight: components.sleep.weight),
                mood: ComponentScore(type: .mood, score: components.mood.score, weight: components.mood.weight),
                streak: ComponentScore(type: .streak, score: components.streak.score, weight: components.streak.weight),
                completion: ComponentScore(type: .completion, score: components.completion.score, weight: components.completion.weight)
            ),
            localDate: localDate,
            calculatedAt: calculatedDate,
            expiresAt: expiresDate,
            hasOverride: hasOverride,
            previousScore: nil
        )
    }
}

// MARK: - Errors

enum DifficultyError: LocalizedError {
    case calculationFailed(String)
    case invalidResponse
    case networkError(Error)
    case cacheExpired
    case overrideFailed(String)

    var errorDescription: String? {
        switch self {
        case .calculationFailed(let message):
            return NSLocalizedString("difficulty.error.calculation", value: "Couldn't calculate capacity: \(message)", comment: "Calculation error")
        case .invalidResponse:
            return NSLocalizedString("difficulty.error.invalid", value: "Received invalid capacity data", comment: "Invalid response error")
        case .networkError(let error):
            return NSLocalizedString("difficulty.error.network", value: "Network error: \(error.localizedDescription)", comment: "Network error")
        case .cacheExpired:
            return NSLocalizedString("difficulty.error.cache", value: "Capacity data expired", comment: "Cache expired error")
        case .overrideFailed(let message):
            return NSLocalizedString("difficulty.error.override", value: "Couldn't apply override: \(message)", comment: "Override error")
        }
    }
}
