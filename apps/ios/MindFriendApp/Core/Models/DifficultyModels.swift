import Foundation
import SwiftUI

// MARK: - Capacity Level

/// Represents the user's current capacity level based on their capacity score
enum CapacityLevel: String, Codable, CaseIterable {
    case low = "low"           // Score 0-40: Rest mode, easier activities
    case moderate = "moderate" // Score 41-70: Balanced, standard activities
    case high = "high"         // Score 71-100: Challenge mode, harder activities

    /// User-facing display name
    var displayName: String {
        switch self {
        case .low: return NSLocalizedString("difficulty.level.low", value: "Taking it easy", comment: "Low capacity level")
        case .moderate: return NSLocalizedString("difficulty.level.moderate", value: "Balanced", comment: "Moderate capacity level")
        case .high: return NSLocalizedString("difficulty.level.high", value: "Ready for a challenge", comment: "High capacity level")
        }
    }

    /// SF Symbol icon name
    var icon: String {
        switch self {
        case .low: return "leaf.fill"
        case .moderate: return "circle.grid.2x2.fill"
        case .high: return "flame.fill"
        }
    }

    /// Color for UI display
    var color: Color {
        switch self {
        case .low: return .blue
        case .moderate: return .green
        case .high: return .orange
        }
    }

    /// Difficulty multiplier for quest duration/intensity
    var difficultyMultiplier: Double {
        switch self {
        case .low: return 0.5   // Halve duration
        case .moderate: return 1.0 // Standard duration
        case .high: return 1.25    // Extend duration by 25%
        }
    }

    /// Convert numeric score to capacity level
    static func from(score: Int) -> CapacityLevel {
        switch score {
        case 0...40: return .low
        case 41...70: return .moderate
        default: return .high
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

        var displayName: String {
            switch self {
            case .sleep: return NSLocalizedString("difficulty.component.sleep", value: "Recent Sleep", comment: "Sleep component")
            case .mood: return NSLocalizedString("difficulty.component.mood", value: "Current Mood", comment: "Mood component")
            case .streak: return NSLocalizedString("difficulty.component.streak", value: "Streak Momentum", comment: "Streak component")
            }
        }

        var icon: String {
            switch self {
            case .sleep: return "moon.zzz.fill"
            case .mood: return "face.smiling.fill"
            case .streak: return "flame.fill"
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

    /// All components as array for iteration
    var all: [ComponentScore] {
        [sleep, mood, streak]
    }

    enum CodingKeys: String, CodingKey {
        case sleep
        case mood
        case streak
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

    /// Whether this score is stale (calculated >12h ago)
    var isStale: Bool {
        Date().timeIntervalSince(calculatedAt) > 12 * 3600
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
    let createdAt: Date
    let expiresAt: Date
    let isActive: Bool

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

        var targetScore: Int {
            switch self {
            case .rest: return 25
            case .normal: return 50
            case .challenge: return 75
            }
        }

        var capacityLevel: CapacityLevel {
            CapacityLevel.from(score: targetScore)
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
    let calculatedAt: String  // ISO 8601
    let expiresAt: String     // ISO 8601
    let hasOverride: Bool

    struct ComponentsResponse: Codable {
        let sleep: ComponentResponse
        let mood: ComponentResponse
        let streak: ComponentResponse
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
        case calculatedAt = "calculated_at"
        case expiresAt = "expires_at"
        case hasOverride = "has_override"
    }

    /// Convert to CapacityScore model
    func toCapacityScore(userId: UUID) -> CapacityScore? {
        guard let level = CapacityLevel(rawValue: level),
              let calculatedDate = ISO8601DateFormatter().date(from: calculatedAt),
              let expiresDate = ISO8601DateFormatter().date(from: expiresAt) else {
            return nil
        }

        // Get local date (YYYY-MM-DD)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone.current
        let localDateString = dateFormatter.string(from: calculatedDate)

        return CapacityScore(
            id: UUID(),
            userId: userId,
            score: score,
            level: level,
            components: CapacityComponents(
                sleep: ComponentScore(type: .sleep, score: components.sleep.score, weight: components.sleep.weight),
                mood: ComponentScore(type: .mood, score: components.mood.score, weight: components.mood.weight),
                streak: ComponentScore(type: .streak, score: components.streak.score, weight: components.streak.weight)
            ),
            localDate: localDateString,
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
