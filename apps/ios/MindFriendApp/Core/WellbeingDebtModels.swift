//
//  WellbeingDebtModels.swift
//  MindFriendApp
//
//  N006: Wellbeing Debt Calculator
//  Swift models for wellbeing debt tracking, transactions, and recovery programs
//

import Foundation

// MARK: - Transaction Models

enum TransactionType: String, Codable {
    case deposit
    case withdrawal
}

enum TransactionCategory: String, Codable {
    // Deposits
    case sleepQuality = "sleep_quality"
    case exerciseCompletion = "exercise_completion"
    case socialConnection = "social_connection"
    case meditation
    case outdoorTime = "outdoor_time"
    case questCompletion = "quest_completion"
    case positiveEvent = "positive_event"

    // Withdrawals
    case poorSleep = "poor_sleep"
    case missedSleep = "missed_sleep"
    case workStress = "work_stress"
    case conflict
    case socialIsolation = "social_isolation"
    case negativeMood = "negative_mood"
    case healthIssue = "health_issue"
    case circadianDisruption = "circadian_disruption"
}

enum TransactionSource: String, Codable {
    case healthkit
    case moodLog = "mood_log"
    case exerciseSessions = "exercise_sessions"
    case circlePosts = "circle_posts"
    case quests
    case circadianShield = "circadian_shield"
    case userLogged = "user_logged"
    case inferred
}

struct WellbeingTransaction: Identifiable, Codable, Equatable {
    let id: UUID?
    let userId: String
    let date: String // ISO date (YYYY-MM-DD)
    let type: TransactionType
    let category: TransactionCategory
    let amount: Decimal
    let source: TransactionSource
    let description: String?
    let metadata: [String: WellbeingAnyCodable]?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case type
        case category
        case amount
        case source
        case description
        case metadata
        case createdAt = "created_at"
    }
}

// MARK: - Debt Score Models

enum DebtTrendDirection: String, Codable {
    case improving
    case worsening
    case stable
}

struct TrendData: Codable, Equatable {
    let direction: DebtTrendDirection
    let velocity: Decimal // Points per day
    let projection7Day: Decimal // Projected debt in 7 days

    enum CodingKeys: String, CodingKey {
        case direction
        case velocity
        case projection7Day = "projection_7day"
    }
}

enum ThresholdSeverity: String, Codable {
    case safe
    case warning
    case danger

    var color: String {
        switch self {
        case .safe: return "green"
        case .warning: return "yellow"
        case .danger: return "red"
        }
    }

    var displayName: String {
        switch self {
        case .safe: return "Safe"
        case .warning: return "Warning"
        case .danger: return "Danger"
        }
    }
}

struct ThresholdStatus: Codable, Equatable {
    let currentDebt: Decimal
    let threshold: Decimal?
    let severity: ThresholdSeverity
    let daysUntilCrash: Int?
    let confidence: Decimal // 0-1 scale

    enum CodingKeys: String, CodingKey {
        case currentDebt = "current_debt"
        case threshold
        case severity
        case daysUntilCrash = "days_until_crash"
        case confidence
    }
}

struct DebtScore: Identifiable, Codable, Equatable {
    let id: UUID?
    let userId: String
    let date: String
    let dailyBalance: Decimal
    let rollingDebt7Day: Decimal
    let rollingDebt14Day: Decimal
    let rollingDebt30Day: Decimal
    let trend: TrendData
    let thresholdStatus: ThresholdStatus
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case dailyBalance = "daily_balance"
        case rollingDebt7Day = "rolling_debt_7day"
        case rollingDebt14Day = "rolling_debt_14day"
        case rollingDebt30Day = "rolling_debt_30day"
        case trend
        case thresholdStatus = "threshold_status"
        case createdAt = "created_at"
    }
}

// MARK: - User Profile Models

struct CrashEvent: Codable, Equatable {
    let date: String
    let debtAtCrash: Decimal
    let moodScore: Int

    enum CodingKeys: String, CodingKey {
        case date
        case debtAtCrash = "debt_at_crash"
        case moodScore = "mood_score"
    }
}

struct CrashHistory: Codable, Equatable {
    let crashes: [CrashEvent]
    let lastUpdated: String?

    enum CodingKeys: String, CodingKey {
        case crashes
        case lastUpdated = "last_updated"
    }
}

struct CategoryStats: Codable, Equatable {
    let category: String
    let totalAmount: Decimal
    let frequency: Int

    enum CodingKeys: String, CodingKey {
        case category
        case totalAmount = "total_amount"
        case frequency
    }
}

struct TopCategories: Codable, Equatable {
    let categories: [CategoryStats]
    let lastUpdated: String?

    enum CodingKeys: String, CodingKey {
        case categories
        case lastUpdated = "last_updated"
    }
}

struct WellbeingDebtProfile: Identifiable, Codable, Equatable {
    let id: UUID?
    let userId: String
    let personalThreshold: Decimal?
    let crashHistory: CrashHistory
    let topDrains: TopCategories
    let topDeposits: TopCategories
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case personalThreshold = "personal_threshold"
        case crashHistory = "crash_history"
        case topDrains = "top_drains"
        case topDeposits = "top_deposits"
        case updatedAt = "updated_at"
    }
}

// MARK: - Recovery Program Models

struct RecoveryAction: Codable, Equatable {
    let category: TransactionCategory
    let action: String
    let targetPoints: Int
    let source: TransactionSource

    enum CodingKeys: String, CodingKey {
        case category
        case action
        case targetPoints = "target_points"
        case source
    }
}

struct DailyActions: Codable, Equatable {
    let day: Int
    let date: String
    let focusArea: String
    let actions: [RecoveryAction]

    enum CodingKeys: String, CodingKey {
        case day
        case date
        case focusArea = "focus_area"
        case actions
    }
}

struct RecoveryProgram: Codable, Equatable {
    let userId: String
    let generatedAt: String
    let targetDebtReduction: Decimal
    let dailyActions: [DailyActions]

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case generatedAt = "generated_at"
        case targetDebtReduction = "target_debt_reduction"
        case dailyActions = "daily_actions"
    }
}

// MARK: - Helper Types

/// Type-erased wrapper for encoding/decoding mixed-type dictionaries
struct WellbeingAnyCodable: Codable, Equatable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([WellbeingAnyCodable].self) {
            value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: WellbeingAnyCodable].self) {
            value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "WellbeingAnyCodable cannot decode value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { WellbeingAnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { WellbeingAnyCodable($0) })
        default:
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(codingPath: container.codingPath, debugDescription: "WellbeingAnyCodable cannot encode value")
            )
        }
    }

    static func == (lhs: WellbeingAnyCodable, rhs: WellbeingAnyCodable) -> Bool {
        // Simple equality check (can be enhanced)
        return String(describing: lhs.value) == String(describing: rhs.value)
    }
}

// MARK: - Error Types

enum WellbeingDebtError: LocalizedError {
    case noDebtScoreAvailable
    case profileNotFound
    case generationFailed(String)
    case invalidDate(String)

    var errorDescription: String? {
        switch self {
        case .noDebtScoreAvailable:
            return "No debt score available. Check back tomorrow."
        case .profileNotFound:
            return "User profile not found."
        case .generationFailed(let reason):
            return "Recovery program generation failed: \(reason)"
        case .invalidDate(let date):
            return "Invalid date format: \(date)"
        }
    }
}
