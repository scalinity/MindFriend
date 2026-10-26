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

    var isSupportedForAccounting: Bool {
        !(category == .socialIsolation && source == .inferred)
    }

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

/// The selected number of complete calendar days in the current time zone.
struct DebtTransactionWindow {
    let start: String
    let end: String
    let timezone: String

    init(days: Int, now: Date = Date(), timeZone: TimeZone = .autoupdatingCurrent) {
        timezone = timeZone.identifier
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let endDate = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
        let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: endDate)!
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        start = formatter.string(from: startDate)
        end = formatter.string(from: endDate)
    }

    static func dateString(_ date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func accounted(_ records: [WellbeingTransaction], owner: String) -> [WellbeingTransaction] {
        records.filter {
            $0.userId.lowercased() == owner.lowercased() && $0.date >= start && $0.date <= end &&
            $0.isSupportedForAccounting
        }
    }
}

enum DebtTrendDirection: String, Codable {
    case improving
    case worsening
    case stable
}

struct TrendData: Codable, Equatable {
    let direction: DebtTrendDirection
    let velocity: Decimal // Points per day
    let projection7Day: Decimal // Non-negative estimated rolling debt in 7 days
    var available: Bool? = nil
    var observedDays: Int? = nil
    var accountingVersion: Int? = nil
    var calculatedAt: String? = nil
    var sourceTransactions: [WellbeingTransaction]? = nil
    var timeZone: String? = nil

    enum CodingKeys: String, CodingKey {
        case direction
        case velocity
        case projection7Day = "projection_7day"
        case available
        case observedDays = "observed_days"
        case accountingVersion = "accounting_version"
        case calculatedAt = "calculated_at"
        case sourceTransactions = "source_transactions"
        case timeZone = "time_zone"
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
    var sourceTransactions: [WellbeingTransaction]? = nil

    var calculationTransactions: [WellbeingTransaction]? { sourceTransactions ?? trend.sourceTransactions }

    func isCurrentSourceCalculation(now: Date = Date(), requireSnapshot: Bool = false) -> Bool {
        isSourceCalculation(for: DebtTransactionWindow(days: 1, now: now).end, requireSnapshot: requireSnapshot, timeZone: TimeZone.autoupdatingCurrent.identifier)
    }

    func isSourceCalculation(for expectedDate: String, requireSnapshot: Bool, timeZone: String? = nil) -> Bool {
        if let timeZone, trend.timeZone != timeZone { return false }
        guard date == expectedDate, trend.accountingVersion == 2, trend.calculatedAt != nil,
              rollingDebt7Day >= 0, rollingDebt14Day >= 0, rollingDebt30Day >= 0,
              trend.projection7Day >= 0, thresholdStatus.currentDebt == rollingDebt14Day else { return false }
        guard requireSnapshot else { return true }
        guard let records = calculationTransactions, !records.isEmpty else { return false }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        guard let end = formatter.date(from: date) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = formatter.string(from: calendar.date(byAdding: .day, value: -29, to: end)!)
        guard records.allSatisfy({ $0.userId.lowercased() == userId.lowercased() &&
            $0.date >= start && $0.date <= date && $0.isSupportedForAccounting && !$0.amount.isNaN && $0.amount >= 0
        }) else { return false }
        for (days, value) in [(7, rollingDebt7Day), (14, rollingDebt14Day), (30, rollingDebt30Day)] {
            let first = formatter.string(from: calendar.date(byAdding: .day, value: -(days - 1), to: end)!)
            let debt = records.filter { $0.date >= first }.reduce(Decimal.zero) {
                $0 + ($1.type == .withdrawal ? $1.amount : -$1.amount)
            }
            if max(0, debt) != value { return false }
        }
        return true
    }

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
        case sourceTransactions = "source_transactions"
    }
}

// MARK: - User Profile Models

struct CrashEvent: Codable, Equatable {
    let date: String
    let debtAtCrash: Decimal
    let moodScore: Int?

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
        case personalThreshold = "learned_threshold"
        case crashHistory = "crash_history"
        case topDrains = "top_drains"
        case topDeposits = "top_deposits"
        case updatedAt = "updated_at"
    }
}

extension CrashHistory {
    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let events = try? single.decode([CrashEvent].self) {
            self.init(crashes: events, lastUpdated: nil)
        } else {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            self.init(crashes: try values.decode([CrashEvent].self, forKey: .crashes),
                lastUpdated: try values.decodeIfPresent(String.self, forKey: .lastUpdated))
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.singleValueContainer()
        try values.encode(crashes)
    }
}

extension WellbeingDebtProfile {
    private enum LegacyCodingKeys: String, CodingKey { case personalThreshold = "personal_threshold" }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        self.init(id: try values.decodeIfPresent(UUID.self, forKey: .id),
            userId: try values.decode(String.self, forKey: .userId),
            personalThreshold: try values.decodeIfPresent(Decimal.self, forKey: .personalThreshold) ??
                legacy.decodeIfPresent(Decimal.self, forKey: .personalThreshold),
            crashHistory: try values.decodeIfPresent(CrashHistory.self, forKey: .crashHistory) ?? CrashHistory(crashes: [], lastUpdated: nil),
            topDrains: try values.decode(TopCategories.self, forKey: .topDrains),
            topDeposits: try values.decode(TopCategories.self, forKey: .topDeposits),
            updatedAt: try values.decodeIfPresent(Date.self, forKey: .updatedAt))
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

// MARK: - Response Types

struct CalculateResponse: Codable {
    let success: Bool
    let score: DebtScore?
}

struct RecoveryProgramResponse: Codable {
    let success: Bool
    let program: RecoveryProgram?
    let error: String?
    let needsMoreData: Bool?
}

// MARK: - Error Types

enum WellbeingDebtError: LocalizedError {
    case noDebtScoreAvailable
    case profileNotFound
    case generationFailed(String)
    case invalidDate(String)
    case needsMoreData(String)

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
        case .needsMoreData(let message):
            return message
        }
    }
}
