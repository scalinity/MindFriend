import Foundation
import Supabase

/// Service for managing sleep tracking data (entries, goals, insights)
@MainActor
final class SleepTrackingService: ObservableObject {

    // MARK: - Properties

    private let supabase: SupabaseClient
    private let calculator = SleepScoreCalculator()
    private let notificationService: BedtimeNotificationServicing?

    // MARK: - Initialization

    init(supabase: SupabaseClient, notificationService: BedtimeNotificationServicing? = nil) {
        self.supabase = supabase
        self.notificationService = notificationService
    }

    // MARK: - Sleep Entries

    /// Create a new sleep entry with calculated score
    func createEntry(_ entry: SleepEntry, goals: SleepGoals) async throws -> SleepEntry {
        // Calculate sleep score
        var mutableEntry = entry
        let scoreBreakdown = calculator.calculateScore(entry: entry, goals: goals)
        mutableEntry.sleepScore = scoreBreakdown.total
        mutableEntry.scoreBreakdown = scoreBreakdown

        // Prepare DTO
        let dto = CreateSleepEntryDTO(
            date: formatDate(mutableEntry.date),
            source: mutableEntry.source.rawValue,
            bedtime: mutableEntry.bedtime.ISO8601Format(),
            wakeTime: mutableEntry.wakeTime.ISO8601Format(),
            timeInBedMinutes: mutableEntry.timeInBedMinutes,
            timeAsleepMinutes: mutableEntry.timeAsleepMinutes,
            deepSleepMinutes: mutableEntry.deepSleepMinutes,
            remSleepMinutes: mutableEntry.remSleepMinutes,
            lightSleepMinutes: mutableEntry.lightSleepMinutes,
            awakeMinutes: mutableEntry.awakeMinutes,
            sleepEfficiency: mutableEntry.sleepEfficiency,
            heartRateAvg: mutableEntry.heartRateAvg,
            heartRateMin: mutableEntry.heartRateMin,
            hrvAvg: mutableEntry.hrvAvg,
            respiratoryRate: mutableEntry.respiratoryRate,
            userRating: mutableEntry.userRating,
            dreamNotes: mutableEntry.dreamNotes,
            notes: mutableEntry.notes,
            sleepScore: mutableEntry.sleepScore,
            scoreBreakdown: mutableEntry.scoreBreakdown
        )

        // Insert into database
        let response: SleepEntry = try await supabase
            .from("sleep_entries")
            .insert(dto)
            .select()
            .single()
            .execute()
            .value

        return response
    }

    /// Fetch sleep entries for a date range
    func fetchEntries(from startDate: Date, to endDate: Date) async throws -> [SleepEntry] {
        let response: [SleepEntry] = try await supabase
            .from("sleep_entries")
            .select()
            .gte("date", value: formatDate(startDate))
            .lte("date", value: formatDate(endDate))
            .order("date", ascending: false)
            .execute()
            .value

        return response
    }

    /// Fetch the most recent sleep entry
    func fetchLatestEntry() async throws -> SleepEntry? {
        let response: [SleepEntry] = try await supabase
            .from("sleep_entries")
            .select()
            .order("date", ascending: false)
            .limit(1)
            .execute()
            .value

        return response.first
    }

    /// Update sleep entry with user feedback (rating, notes)
    func updateEntry(id: UUID, rating: Int?, dreamNotes: String?, notes: String?) async throws {
        let dto = UpdateSleepEntryDTO(
            userRating: rating,
            dreamNotes: dreamNotes,
            notes: notes
        )

        try await supabase
            .from("sleep_entries")
            .update(dto)
            .eq("id", value: id.uuidString)
            .execute()
    }

    /// Delete a sleep entry
    func deleteEntry(id: UUID) async throws {
        try await supabase
            .from("sleep_entries")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    // MARK: - Sleep Goals

    /// Fetch user's sleep goals (creates default if none exist)
    func fetchGoals() async throws -> SleepGoals {
        let response: [SleepGoals] = try await supabase
            .from("sleep_goals")
            .select()
            .execute()
            .value

        if let existing = response.first {
            return existing
        }

        // No goals exist, create defaults
        return try await createDefaultGoals()
    }

    /// Upsert (update or insert) sleep goals
    func upsertGoals(_ goals: SleepGoals) async throws -> SleepGoals {
        let response: SleepGoals = try await supabase
            .from("sleep_goals")
            .upsert(goals)
            .select()
            .single()
            .execute()
            .value

        // Update bedtime reminder notifications
        if response.bedtimeReminderEnabled, let targetBedtime = response.targetBedtime {
            // Schedule/update bedtime reminder
            let routineSuggestion = response.preferredWindDownTypes.isEmpty
                ? "Start your wind-down routine"
                : "Tonight's routine: \(response.preferredWindDownTypes.prefix(2).joined(separator: ", "))"

            do {
                try await notificationService?.updateReminderSchedule(
                    newBedtime: targetBedtime,
                    windDownMinutes: response.windDownDurationMinutes,
                    routineSuggestion: routineSuggestion
                )
            } catch {
                // Log error but don't fail the goals update
                print("⚠️ Failed to update bedtime reminder notification: \(error.localizedDescription)")
            }
        } else {
            // Cancel reminders if disabled
            await notificationService?.cancelBedtimeReminder()
        }

        return response
    }

    /// Create default sleep goals for a new user
    private func createDefaultGoals() async throws -> SleepGoals {
        let calendar = Calendar.current
        let now = Date()

        // Default: 11 PM bedtime, 7 AM wake time, 8 hours sleep
        let bedtime = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: now)
        let wakeTime = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: now)

        let goals = SleepGoals(
            id: UUID(),
            userId: UUID(), // Will be set by RLS
            targetBedtime: bedtime,
            targetWakeTime: wakeTime,
            targetDurationMinutes: 480, // 8 hours
            windDownDurationMinutes: 30,
            bedtimeReminderEnabled: true,
            bedtimeReminderOffsetMinutes: 60,
            preferredWindDownTypes: ["breathing", "meditation"],
            sleepEnvironmentPrefs: SleepEnvironmentPrefs(),
            createdAt: now,
            updatedAt: now
        )

        return try await upsertGoals(goals)
    }

    // MARK: - Sleep Insights

    /// Fetch valid sleep insights (not expired, ordered by recency)
    func fetchInsights() async throws -> [SleepInsight] {
        let now = Date()

        let response: [SleepInsight] = try await supabase
            .from("sleep_insights")
            .select()
            .gte("valid_until", value: now.ISO8601Format())
            .order("generated_at", ascending: false)
            .execute()
            .value

        return response
    }

    /// Mark an insight as viewed
    func markInsightViewed(id: UUID) async throws {
        try await supabase
            .from("sleep_insights")
            .update(["viewed": true])
            .eq("id", value: id.uuidString)
            .execute()
    }

    // MARK: - Wind-Down Sessions

    /// Generate a personalized wind-down routine (calls Edge Function)
    func generateWindDown(
        targetBedtime: Date,
        availableMinutes: Int,
        preferences: [String]? = nil
    ) async throws -> WindDownSession {
        let prefs = preferences ?? ["breathing", "meditation"]

        struct GenerateWindDownRequest: Encodable {
            let targetBedtime: String
            let availableMinutes: Int
            let preferences: [String]
        }

        let request = GenerateWindDownRequest(
            targetBedtime: targetBedtime.ISO8601Format(),
            availableMinutes: availableMinutes,
            preferences: prefs
        )

        struct GenerateWindDownResponse: Codable {
            let session: WindDownSession
        }

        let response: GenerateWindDownResponse = try await supabase.functions.invoke(
            "generate-wind-down",
            options: FunctionInvokeOptions(body: request)
        )

        return response.session
    }

    /// Complete a wind-down activity
    func completeWindDownActivity(sessionId: UUID, activityId: UUID) async throws {
        // Fetch current session
        let response: [WindDownSession] = try await supabase
            .from("wind_down_sessions")
            .select()
            .eq("id", value: sessionId.uuidString)
            .execute()
            .value

        guard var session = response.first else {
            throw SleepTrackingError.sessionNotFound
        }

        // Update activity completion status
        var updatedRoutine = session.routine
        if let index = updatedRoutine.firstIndex(where: { $0.id == activityId }) {
            updatedRoutine[index].completed = true
        }

        // Check if all activities completed
        let allCompleted = updatedRoutine.allSatisfy { $0.completed }

        // Update session
        struct WindDownUpdateRequest: Encodable {
            let routine: [WindDownActivity]
            let completed: Bool
            let completed_at: String?
        }

        let updates = WindDownUpdateRequest(
            routine: updatedRoutine,
            completed: allCompleted,
            completed_at: allCompleted ? Date().ISO8601Format() : nil
        )

        try await supabase
            .from("wind_down_sessions")
            .update(updates)
            .eq("id", value: sessionId.uuidString)
            .execute()
    }

    /// Rate a completed wind-down session
    func rateWindDownSession(sessionId: UUID, rating: Int) async throws {
        guard rating >= 1 && rating <= 5 else {
            throw SleepTrackingError.invalidRating
        }

        try await supabase
            .from("wind_down_sessions")
            .update(["feedback_rating": rating])
            .eq("id", value: sessionId.uuidString)
            .execute()
    }

    // MARK: - Analytics

    /// Request sleep pattern analysis (calls Edge Function)
    func analyzeSleepPatterns() async throws -> SleepAnalysisResponse {
        struct EmptyRequest: Encodable {}

        let response: SleepAnalysisResponse = try await supabase.functions.invoke(
            "analyze-sleep-patterns",
            options: FunctionInvokeOptions(body: EmptyRequest())
        )

        return response
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: - Supporting Types

struct SleepAnalysisResponse: Codable {
    let weeklyStats: SleepWeeklyStats
    let sleepDebt: SleepDebtResponse?
    let moodCorrelation: MoodCorrelationResponse?
    let patterns: [SleepPattern]
    let recommendations: [String]

    enum CodingKeys: String, CodingKey {
        case weeklyStats = "weeklyStats"
        case sleepDebt = "sleepDebt"
        case moodCorrelation = "moodCorrelation"
        case patterns
        case recommendations
    }
}

struct SleepDebtResponse: Codable {
    let currentMinutes: Int
    let trend: String // "increasing", "decreasing", "stable"

    enum CodingKeys: String, CodingKey {
        case currentMinutes = "currentMinutes"
        case trend
    }
}

struct MoodCorrelationResponse: Codable {
    let coefficient: Double
    let insight: String

    enum CodingKeys: String, CodingKey {
        case coefficient
        case insight
    }
}

struct SleepPattern: Codable {
    let type: String
    let description: String
    let impact: String // "positive", "negative", "neutral"
    let recommendation: String
}

// MARK: - Errors

enum SleepTrackingError: Error, LocalizedError {
    case windDownGenerationFailed
    case sessionNotFound
    case invalidRating
    case analysisGenerationFailed

    var errorDescription: String? {
        switch self {
        case .windDownGenerationFailed:
            return "Failed to generate wind-down routine. Please try again."
        case .sessionNotFound:
            return "Wind-down session not found."
        case .invalidRating:
            return "Rating must be between 1 and 5."
        case .analysisGenerationFailed:
            return "Failed to analyze sleep patterns. Please try again."
        }
    }
}
