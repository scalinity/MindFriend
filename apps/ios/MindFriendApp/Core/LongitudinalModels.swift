import Foundation

// MARK: - Weekly Statistics

struct WeeklyStat: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    let weekStart: Date
    let avgMood: Double?
    let moodVariance: Double?
    let activeDays: Int?
    let exercisesCompleted: Int
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case weekStart = "week_start"
        case avgMood = "avg_mood"
        case moodVariance = "mood_variance"
        case activeDays = "active_days"
        case exercisesCompleted = "exercises_completed"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var formattedWeekStart: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: weekStart)
    }

    var formattedMood: String {
        guard let mood = avgMood else { return "—" }
        return String(format: "%.1f", mood)
    }
}

// MARK: - Monthly Statistics

struct MonthlyStat: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    let monthStart: Date
    let avgMood: Double?
    let moodTrend: MoodTrend?
    let activeDaysPct: Double?
    let notableEvents: [NotableEvent]
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case monthStart = "month_start"
        case avgMood = "avg_mood"
        case moodTrend = "mood_trend"
        case activeDaysPct = "active_days_pct"
        case notableEvents = "notable_events"
        case createdAt = "created_at"
    }

    var formattedMonth: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: monthStart)
    }

    var trendIcon: String {
        switch moodTrend {
        case .improving: return "arrow.up.right"
        case .declining: return "arrow.down.right"
        case .stable: return "arrow.right"
        case .baseline, .insufficientData, .none: return "minus"
        }
    }

    var trendColor: String {
        switch moodTrend {
        case .improving: return "green"
        case .declining: return "red"
        case .stable, .baseline, .insufficientData, .none: return "gray"
        }
    }
}

// MoodTrend is defined in FamilyWellnessModels.swift

struct NotableEvent: Codable, Hashable {
    let eventId: UUID
    let eventType: String
    let eventDate: String

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case eventType = "event_type"
        case eventDate = "event_date"
    }
}

// MARK: - Yearly Statistics

struct YearlyStat: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    let year: Int
    let quarterlyMoods: [Double?]
    let seasonalPatterns: SeasonalPatterns?
    let yearlyComparison: YearlyComparison?
    let milestonesAchieved: [Milestone]
    let isPartial: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case year
        case quarterlyMoods = "quarterly_moods"
        case seasonalPatterns = "seasonal_patterns"
        case yearlyComparison = "yearly_comparison"
        case milestonesAchieved = "milestones_achieved"
        case isPartial = "is_partial"
        case createdAt = "created_at"
    }

    var formattedYear: String {
        "\(year)"
    }

    var quarterNames: [String] {
        ["Q1", "Q2", "Q3", "Q4"]
    }
}

struct SeasonalPatterns: Codable, Hashable {
    let winter: Double?
    let spring: Double?
    let summer: Double?
    let fall: Double?
    let lowestSeason: String?
    let highestSeason: String?

    enum CodingKeys: String, CodingKey {
        case winter, spring, summer, fall
        case lowestSeason = "lowest_season"
        case highestSeason = "highest_season"
    }

    var allSeasons: [(name: String, value: Double)] {
        var seasons: [(String, Double)] = []
        if let w = winter { seasons.append(("Winter", w)) }
        if let sp = spring { seasons.append(("Spring", sp)) }
        if let su = summer { seasons.append(("Summer", su)) }
        if let f = fall { seasons.append(("Fall", f)) }
        return seasons
    }
}

struct YearlyComparison: Codable, Hashable {
    let moodDelta: Double?
    let activeDaysDelta: Double?
    let exercisesDelta: Int?

    enum CodingKeys: String, CodingKey {
        case moodDelta = "mood_delta"
        case activeDaysDelta = "active_days_delta"
        case exercisesDelta = "exercises_delta"
    }

    var moodDeltaFormatted: String {
        guard let delta = moodDelta else { return "—" }
        let sign = delta >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", delta))"
    }

    var isImprovement: Bool {
        (moodDelta ?? 0) > 0
    }
}

struct Milestone: Codable, Hashable {
    let type: String
    let name: String
    let achievedDate: String

    enum CodingKeys: String, CodingKey {
        case type, name
        case achievedDate = "achieved_date"
    }
}

// MARK: - Patterns

struct LongitudinalPattern: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    let patternType: LongitudinalPatternType
    let patternDescription: String
    let confidence: Double
    let firstDetected: Date
    let lastDetected: Date
    let occurrences: Int
    let isActive: Bool
    let metadata: [String: String]?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case patternType = "pattern_type"
        case patternDescription = "pattern_description"
        case confidence
        case firstDetected = "first_detected"
        case lastDetected = "last_detected"
        case occurrences
        case isActive = "is_active"
        case metadata
        case createdAt = "created_at"
    }

    var confidencePercentage: Int {
        Int(confidence * 100)
    }

    var confidenceLabel: String {
        if confidence >= 0.9 { return "Very High" }
        if confidence >= 0.7 { return "High" }
        if confidence >= 0.5 { return "Medium" }
        return "Low"
    }

    var patternIcon: String {
        switch patternType {
        case .seasonalMood: return "sun.max"
        case .weeklyRhythm: return "calendar"
        case .eventResponse: return "exclamationmark.circle"
        case .improvementTrend: return "chart.line.uptrend.xyaxis"
        }
    }
}

enum LongitudinalPatternType: String, Codable, Hashable, CaseIterable {
    case seasonalMood = "seasonal_mood"
    case weeklyRhythm = "weekly_rhythm"
    case eventResponse = "event_response"
    case improvementTrend = "improvement_trend"

    var displayName: String {
        switch self {
        case .seasonalMood: return "Seasonal Mood"
        case .weeklyRhythm: return "Weekly Rhythm"
        case .eventResponse: return "Event Response"
        case .improvementTrend: return "Improvement Trend"
        }
    }

    var icon: String {
        switch self {
        case .seasonalMood: return "sun.max"
        case .weeklyRhythm: return "calendar"
        case .eventResponse: return "bolt"
        case .improvementTrend: return "arrow.up.right"
        }
    }
}

// MARK: - Life Events

struct LifeEvent: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    let eventType: EventType
    let eventDate: Date
    let impactScore: Double?
    let beforeMetrics: EventMetrics?
    let afterMetrics: EventMetrics?
    let recoveryDays: Int?
    let isOngoing: Bool
    let notes: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case eventType = "event_type"
        case eventDate = "event_date"
        case impactScore = "impact_score"
        case beforeMetrics = "before_metrics"
        case afterMetrics = "after_metrics"
        case recoveryDays = "recovery_days"
        case isOngoing = "is_ongoing"
        case notes
        case createdAt = "created_at"
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: eventDate)
    }

    var impactIcon: String {
        guard let score = impactScore else { return "minus.circle" }
        if score > 0 { return "arrow.up.circle.fill" }
        if score < 0 { return "arrow.down.circle.fill" }
        return "minus.circle"
    }

    var impactColor: String {
        guard let score = impactScore else { return "gray" }
        if score > 0 { return "green" }
        if score < 0 { return "red" }
        return "gray"
    }
}

enum EventType: String, Codable, Hashable, CaseIterable {
    case relationshipChange = "relationship_change"
    case careerChange = "career_change"
    case healthIssue = "health_issue"
    case loss
    case achievement
    case relocation
    case other

    var displayName: String {
        switch self {
        case .relationshipChange: return "Relationship Change"
        case .careerChange: return "Career Change"
        case .healthIssue: return "Health Issue"
        case .loss: return "Loss"
        case .achievement: return "Achievement"
        case .relocation: return "Relocation"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .relationshipChange: return "heart"
        case .careerChange: return "briefcase"
        case .healthIssue: return "cross.circle"
        case .loss: return "leaf"
        case .achievement: return "star"
        case .relocation: return "house"
        case .other: return "ellipsis.circle"
        }
    }
}

struct EventMetrics: Codable, Hashable {
    let avgMood: Double
    let activeDays: Int
    let exercisesCompleted: Int

    enum CodingKeys: String, CodingKey {
        case avgMood = "avg_mood"
        case activeDays = "active_days"
        case exercisesCompleted = "exercises_completed"
    }
}

// MARK: - Reports

struct LongitudinalReport: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    let reportType: ReportType
    let timePeriod: TimePeriod
    let contentJson: ReportContent
    let generatedAt: Date
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case reportType = "report_type"
        case timePeriod = "time_period"
        case contentJson = "content_json"
        case generatedAt = "generated_at"
        case expiresAt = "expires_at"
    }

    var formattedGeneratedAt: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: generatedAt)
    }

    var formattedPeriod: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return "\(formatter.string(from: timePeriod.start)) - \(formatter.string(from: timePeriod.end))"
    }
}

enum ReportType: String, Codable, Hashable, CaseIterable {
    case quarterly
    case annual
    case custom

    var displayName: String {
        switch self {
        case .quarterly: return "Quarterly Report"
        case .annual: return "Annual Report"
        case .custom: return "Custom Report"
        }
    }

    var icon: String {
        switch self {
        case .quarterly: return "calendar.badge.clock"
        case .annual: return "calendar"
        case .custom: return "slider.horizontal.3"
        }
    }
}

struct TimePeriod: Codable, Hashable {
    let start: Date
    let end: Date

    enum CodingKeys: String, CodingKey {
        case start, end
    }

    init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let startString = try container.decode(String.self, forKey: .start)
        let endString = try container.decode(String.self, forKey: .end)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        if let s = formatter.date(from: startString) {
            self.start = s
        } else {
            self.start = Date()
        }

        if let e = formatter.date(from: endString) {
            self.end = e
        } else {
            self.end = Date()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        try container.encode(formatter.string(from: start), forKey: .start)
        try container.encode(formatter.string(from: end), forKey: .end)
    }
}

struct ReportContent: Codable, Hashable {
    let summary: String
    let keyInsights: [String]
    let chartsData: ChartsData
    let recommendations: [String]

    enum CodingKeys: String, CodingKey {
        case summary
        case keyInsights = "key_insights"
        case chartsData = "charts_data"
        case recommendations
    }
}

struct ChartsData: Codable, Hashable {
    let moodTrend: [MoodDataPoint]
    let activityHeatmap: [ActivityDataPoint]
    let seasonalComparison: [String: Double]

    enum CodingKeys: String, CodingKey {
        case moodTrend = "mood_trend"
        case activityHeatmap = "activity_heatmap"
        case seasonalComparison = "seasonal_comparison"
    }
}

struct MoodDataPoint: Codable, Hashable {
    let date: String
    let value: Double
}

struct ActivityDataPoint: Codable, Hashable {
    let week: String
    let days: Int
}

// MARK: - Input Types

struct LifeEventInput: Codable {
    let eventType: EventType
    let eventDate: Date
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case eventDate = "event_date"
        case notes
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(eventType.rawValue, forKey: .eventType)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        try container.encode(formatter.string(from: eventDate), forKey: .eventDate)
        try container.encodeIfPresent(notes, forKey: .notes)
    }
}

struct LongitudinalReportRequest: Codable {
    let reportType: ReportType
    let timePeriod: TimePeriod?

    enum CodingKeys: String, CodingKey {
        case reportType = "report_type"
        case timePeriod = "time_period"
    }
}

// MARK: - AnyCodable Helper
// Note: AnyCodableValue is defined in Models.swift - use that instead
