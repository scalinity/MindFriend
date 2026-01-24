import Foundation

// MARK: - Sleep Entry

/// Represents a daily sleep log (HealthKit sync or manual entry)
struct SleepEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let date: Date
    let source: SleepSource

    // Timing
    let bedtime: Date
    let wakeTime: Date
    let timeInBedMinutes: Int
    let timeAsleepMinutes: Int?

    // Sleep Stages (from wearables)
    let deepSleepMinutes: Int?
    let remSleepMinutes: Int?
    let lightSleepMinutes: Int?
    let awakeMinutes: Int?

    // Quality Metrics
    let sleepEfficiency: Double? // Percentage (0-100)
    let heartRateAvg: Int?
    let heartRateMin: Int?
    let hrvAvg: Double?
    let respiratoryRate: Double?

    // User Input
    var userRating: Int? // 1-5 stars
    var dreamNotes: String?
    var notes: String?

    // Calculated
    var sleepScore: Int? // 0-100
    var scoreBreakdown: SleepScoreBreakdown?

    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case source
        case bedtime
        case wakeTime = "wake_time"
        case timeInBedMinutes = "time_in_bed_minutes"
        case timeAsleepMinutes = "time_asleep_minutes"
        case deepSleepMinutes = "deep_sleep_minutes"
        case remSleepMinutes = "rem_sleep_minutes"
        case lightSleepMinutes = "light_sleep_minutes"
        case awakeMinutes = "awake_minutes"
        case sleepEfficiency = "sleep_efficiency"
        case heartRateAvg = "heart_rate_avg"
        case heartRateMin = "heart_rate_min"
        case hrvAvg = "hrv_avg"
        case respiratoryRate = "respiratory_rate"
        case userRating = "user_rating"
        case dreamNotes = "dream_notes"
        case notes
        case sleepScore = "sleep_score"
        case scoreBreakdown = "score_breakdown"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // MARK: - Computed Properties

    var durationFormatted: String {
        let minutes = timeAsleepMinutes ?? timeInBedMinutes
        let hours = minutes / 60
        let mins = minutes % 60
        return "\(hours)h \(mins)m"
    }

    var hasWearableData: Bool {
        deepSleepMinutes != nil || remSleepMinutes != nil
    }

    var qualityLabel: String {
        guard let score = sleepScore else { return "Unknown" }
        switch score {
        case 85...100: return "Excellent"
        case 70..<85: return "Good"
        case 55..<70: return "Fair"
        default: return "Poor"
        }
    }
}

// MARK: - Sleep Source

enum SleepSource: String, Codable, CaseIterable {
    case healthkit
    case manual
    case appleWatch = "apple_watch"

    var displayName: String {
        switch self {
        case .healthkit: return "Health App"
        case .manual: return "Manual Entry"
        case .appleWatch: return "Apple Watch"
        }
    }
}

// MARK: - Sleep Score Breakdown

struct SleepScoreBreakdown: Codable, Equatable {
    let duration: Int // 0-25 points
    let efficiency: Int // 0-25 points
    let timing: Int // 0-20 points
    let stages: Int // 0-20 points
    let restfulness: Int // 0-10 points

    var total: Int {
        duration + efficiency + timing + stages + restfulness
    }

    /// Returns the lowest scoring component (the area needing improvement)
    var primaryFactor: String {
        let factors: [(String, Int)] = [
            ("Duration", duration),
            ("Efficiency", efficiency),
            ("Timing", timing),
            ("Sleep Stages", stages),
            ("Restfulness", restfulness)
        ]
        return factors.min(by: { $0.1 < $1.1 })?.0 ?? "Duration"
    }

    /// Returns explanation for each component score
    func explanation(for component: String) -> String {
        switch component {
        case "Duration":
            return "How close your sleep duration was to your target"
        case "Efficiency":
            return "Percentage of time in bed actually asleep"
        case "Timing":
            return "Consistency with your target bedtime"
        case "Sleep Stages":
            return "Quality of deep and REM sleep cycles"
        case "Restfulness":
            return "How often you woke during the night"
        default:
            return "Unknown component"
        }
    }
}

// MARK: - Sleep Goals

struct SleepGoals: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    var targetBedtime: Date? // Time component only
    var targetWakeTime: Date?
    var targetDurationMinutes: Int // Default: 480 (8 hours)
    var windDownDurationMinutes: Int // Default: 30
    var bedtimeReminderEnabled: Bool
    var bedtimeReminderOffsetMinutes: Int // Default: 60 (1 hour before)
    var preferredWindDownTypes: [String] // ["breathing", "meditation", etc.]
    var sleepEnvironmentPrefs: SleepEnvironmentPrefs
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case targetBedtime = "target_bedtime"
        case targetWakeTime = "target_wake_time"
        case targetDurationMinutes = "target_duration_minutes"
        case windDownDurationMinutes = "wind_down_duration_minutes"
        case bedtimeReminderEnabled = "bedtime_reminder_enabled"
        case bedtimeReminderOffsetMinutes = "bedtime_reminder_offset_minutes"
        case preferredWindDownTypes = "preferred_wind_down_types"
        case sleepEnvironmentPrefs = "sleep_environment_prefs"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // MARK: - Computed Properties

    var targetDurationFormatted: String {
        let hours = targetDurationMinutes / 60
        let mins = targetDurationMinutes % 60
        return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h"
    }

    var bedtimeFormatted: String? {
        guard let bedtime = targetBedtime else { return nil }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: bedtime)
    }

    var wakeTimeFormatted: String? {
        guard let wakeTime = targetWakeTime else { return nil }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: wakeTime)
    }
}

// MARK: - Sleep Environment Preferences

struct SleepEnvironmentPrefs: Codable, Equatable {
    var prefersDarkRoom: Bool?
    var prefersCoolRoom: Bool?
    var usesWhiteNoise: Bool?
    var hasBlueLight: Bool?

    init(
        prefersDarkRoom: Bool? = nil,
        prefersCoolRoom: Bool? = nil,
        usesWhiteNoise: Bool? = nil,
        hasBlueLight: Bool? = nil
    ) {
        self.prefersDarkRoom = prefersDarkRoom
        self.prefersCoolRoom = prefersCoolRoom
        self.usesWhiteNoise = usesWhiteNoise
        self.hasBlueLight = hasBlueLight
    }
}

// MARK: - Sleep Debt

struct SleepDebt: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    var currentDebtMinutes: Int
    let weekAvgDurationMinutes: Int?
    let optimalDurationMinutes: Int
    let lastCalculated: Date
    let debtHistory: [DailyDebt]
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case currentDebtMinutes = "current_debt_minutes"
        case weekAvgDurationMinutes = "week_avg_duration_minutes"
        case optimalDurationMinutes = "optimal_duration_minutes"
        case lastCalculated = "last_calculated"
        case debtHistory = "debt_history"
        case createdAt = "created_at"
    }

    // MARK: - Computed Properties

    var debtHours: Double {
        Double(currentDebtMinutes) / 60.0
    }

    var isInDebt: Bool {
        currentDebtMinutes > 30 // More than 30 minutes debt
    }

    var debtFormatted: String {
        let hours = abs(currentDebtMinutes) / 60
        let mins = abs(currentDebtMinutes) % 60

        if currentDebtMinutes < 0 {
            return "+\(hours)h \(mins)m" // Sleep surplus
        } else if currentDebtMinutes > 0 {
            return "-\(hours)h \(mins)m" // Sleep debt
        } else {
            return "0h" // No debt
        }
    }

    /// Estimate nights needed to recover (assuming 1 hour extra sleep per night)
    var recoveryNights: Int {
        guard currentDebtMinutes > 0 else { return 0 }
        return Int(ceil(Double(currentDebtMinutes) / 60.0))
    }
}

struct DailyDebt: Codable, Equatable {
    let date: Date
    let debtMinutes: Int
}

// MARK: - Wind-Down Session

struct WindDownSession: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let startedAt: Date
    var completedAt: Date?
    let routine: [WindDownActivity]
    let durationPlannedMinutes: Int
    var durationActualMinutes: Int?
    var completed: Bool
    var sleepEntryId: UUID?
    var feedbackRating: Int? // 1-5 stars
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case routine
        case durationPlannedMinutes = "duration_planned_minutes"
        case durationActualMinutes = "duration_actual_minutes"
        case completed
        case sleepEntryId = "sleep_entry_id"
        case feedbackRating = "feedback_rating"
        case createdAt = "created_at"
    }

    // MARK: - Computed Properties

    var progress: Double {
        let completedCount = routine.filter { $0.completed }.count
        return Double(completedCount) / Double(routine.count)
    }

    var progressFormatted: String {
        let completedCount = routine.filter { $0.completed }.count
        return "\(completedCount)/\(routine.count) activities"
    }

    var nextActivity: WindDownActivity? {
        routine.first { !$0.completed }
    }
}

struct WindDownActivity: Codable, Identifiable, Equatable {
    let id: UUID
    let type: String // "breathing", "meditation", "journaling", "stretching"
    let exerciseId: UUID?
    let name: String
    let durationMinutes: Int
    var completed: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case exerciseId = "exercise_id"
        case name
        case durationMinutes = "duration_minutes"
        case completed
    }

    var icon: String {
        switch type {
        case "breathing": return "wind"
        case "meditation": return "brain.head.profile"
        case "journaling": return "book.pages"
        case "stretching": return "figure.flexibility"
        default: return "moon.stars.fill"
        }
    }
}

// MARK: - Sleep Insight

struct SleepInsight: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let insightType: SleepInsightType
    let insightData: SleepInsightData
    let generatedAt: Date
    let validUntil: Date
    var viewed: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case insightType = "insight_type"
        case insightData = "insight_data"
        case generatedAt = "generated_at"
        case validUntil = "valid_until"
        case viewed
        case createdAt = "created_at"
    }

    var isValid: Bool {
        validUntil > Date()
    }
}

enum SleepInsightType: String, Codable, CaseIterable {
    case weeklyReport = "weekly_report"
    case moodCorrelation = "mood_correlation"
    case patternDetected = "pattern_detected"
    case improvement = "improvement"
    case concern = "concern"

    var icon: String {
        switch self {
        case .weeklyReport: return "chart.bar.fill"
        case .moodCorrelation: return "arrow.triangle.branch"
        case .patternDetected: return "waveform.path.ecg"
        case .improvement: return "arrow.up.circle.fill"
        case .concern: return "exclamationmark.triangle.fill"
        }
    }

    var color: String {
        switch self {
        case .weeklyReport: return "blue"
        case .moodCorrelation: return "purple"
        case .patternDetected: return "orange"
        case .improvement: return "green"
        case .concern: return "red"
        }
    }
}

struct SleepInsightData: Codable, Equatable {
    let title: String
    let message: String
    let metric: String?
    let value: Double?
    let trend: String? // "improving", "declining", "stable"
    let recommendation: String?

    var trendIcon: String? {
        guard let trend = trend else { return nil }
        switch trend {
        case "improving": return "arrow.up.right"
        case "declining": return "arrow.down.right"
        case "stable": return "arrow.right"
        default: return nil
        }
    }
}

// MARK: - Sleep Weekly Stats (for insights)

struct SleepWeeklyStats: Codable, Equatable {
    let avgDuration: Int // Average sleep duration in minutes
    let avgScore: Int // Average sleep score (0-100)
    let avgBedtime: String // Average bedtime (HH:MM format)
    let avgWakeTime: String // Average wake time (HH:MM format)
    let consistency: Double // Consistency score (0-1)
    let totalNights: Int

    enum CodingKeys: String, CodingKey {
        case avgDuration = "avg_duration"
        case avgScore = "avg_score"
        case avgBedtime = "avg_bedtime"
        case avgWakeTime = "avg_wake_time"
        case consistency
        case totalNights = "total_nights"
    }
}

// MARK: - Create/Update DTOs

struct CreateSleepEntryDTO: Encodable {
    let date: String // YYYY-MM-DD
    let source: String
    let bedtime: String // ISO 8601
    let wakeTime: String // ISO 8601
    let timeInBedMinutes: Int
    let timeAsleepMinutes: Int?
    let deepSleepMinutes: Int?
    let remSleepMinutes: Int?
    let lightSleepMinutes: Int?
    let awakeMinutes: Int?
    let sleepEfficiency: Double?
    let heartRateAvg: Int?
    let heartRateMin: Int?
    let hrvAvg: Double?
    let respiratoryRate: Double?
    let userRating: Int?
    let dreamNotes: String?
    let notes: String?
    let sleepScore: Int?
    let scoreBreakdown: SleepScoreBreakdown?

    enum CodingKeys: String, CodingKey {
        case date, source, bedtime
        case wakeTime = "wake_time"
        case timeInBedMinutes = "time_in_bed_minutes"
        case timeAsleepMinutes = "time_asleep_minutes"
        case deepSleepMinutes = "deep_sleep_minutes"
        case remSleepMinutes = "rem_sleep_minutes"
        case lightSleepMinutes = "light_sleep_minutes"
        case awakeMinutes = "awake_minutes"
        case sleepEfficiency = "sleep_efficiency"
        case heartRateAvg = "heart_rate_avg"
        case heartRateMin = "heart_rate_min"
        case hrvAvg = "hrv_avg"
        case respiratoryRate = "respiratory_rate"
        case userRating = "user_rating"
        case dreamNotes = "dream_notes"
        case notes
        case sleepScore = "sleep_score"
        case scoreBreakdown = "score_breakdown"
    }
}

struct UpdateSleepEntryDTO: Encodable {
    let userRating: Int?
    let dreamNotes: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case userRating = "user_rating"
        case dreamNotes = "dream_notes"
        case notes
    }
}
