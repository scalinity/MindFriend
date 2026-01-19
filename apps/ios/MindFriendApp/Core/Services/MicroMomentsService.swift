import Foundation
import Supabase

/// Service for micro-moments: quick breathing, check-ins, grounding exercises
@MainActor
final class MicroMomentsService: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var templates: [MicroMomentTemplate] = []
    @Published private(set) var suggestions: [MicroMomentTemplate] = []
    @Published private(set) var streak: MicroStreak?
    @Published private(set) var recentCompletions: [MicroMomentCompletion] = []
    @Published private(set) var recentCheckIns: [QuickCheckIn] = []
    @Published private(set) var deliveryPreferences: MicroDeliveryPreferences = .default
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    // MARK: - Private Properties

    private let supabase: SupabaseClient

    // MARK: - Initialization

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    // MARK: - Load All Data

    /// Load all micro-moments data for the hub view
    func loadData() async {
        isLoading = true
        error = nil

        async let templatesTask = fetchTemplates()
        async let suggestionsTask = fetchSuggestions()
        async let streakTask = fetchStreak()
        async let completionsTask = fetchRecentCompletions()
        async let checkInsTask = fetchRecentCheckIns()
        async let prefsTask = fetchDeliveryPreferences()

        // Track if any critical fetch failed
        var criticalFailure = false
        var lastError: Error?

        // Await all tasks, handling errors gracefully
        do {
            templates = try await templatesTask
        } catch {
            Log.quests.error("Failed to fetch templates", error: error)
            criticalFailure = true
            lastError = error
        }

        do {
            suggestions = try await suggestionsTask
        } catch {
            Log.quests.error("Failed to fetch suggestions", error: error)
            // Suggestions failure is non-critical
        }

        do {
            streak = try await streakTask
        } catch {
            Log.quests.error("Failed to fetch streak", error: error)
            // Streak failure is non-critical
        }

        do {
            recentCompletions = try await completionsTask
        } catch {
            Log.quests.error("Failed to fetch completions", error: error)
            // Completions failure is non-critical
        }

        do {
            recentCheckIns = try await checkInsTask
        } catch {
            Log.quests.error("Failed to fetch check-ins", error: error)
            // Check-ins failure is non-critical
        }

        do {
            if let prefs = try await prefsTask {
                deliveryPreferences = prefs
            }
        } catch {
            Log.quests.error("Failed to fetch preferences", error: error)
            // Preferences failure is non-critical
        }

        // Set error state if critical data failed to load
        if criticalFailure, let lastError = lastError {
            self.error = lastError.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Templates

    /// Fetch all active micro-moment templates
    func fetchTemplates(type: MicroMomentType? = nil) async throws -> [MicroMomentTemplate] {
        var query = supabase
            .from("micro_moment_templates")
            .select()
            .eq("is_active", value: true)

        if let type = type {
            query = query.eq("type", value: type.rawValue)
        }

        let response: [MicroMomentTemplate] = try await query
            .order("sort_order", ascending: true)
            .execute()
            .value

        return response
    }

    /// Fetch personalized suggestions
    func fetchSuggestions(
        context: String? = nil,
        maxDuration: Int? = nil,
        energyPreference: EnergyEffect? = nil
    ) async throws -> [MicroMomentTemplate] {
        var body: [String: Any] = [:]

        if let context = context {
            body["context"] = context
        }
        if let maxDuration = maxDuration {
            body["maxDuration"] = maxDuration
        }
        if let energy = energyPreference {
            body["energyPreference"] = energy.rawValue
        }

        let response: MicroSuggestionResponse = try await supabase.functions
            .invoke(
                "get-micro-suggestions",
                options: .init(body: body)
            )

        return response.suggestions
    }

    // MARK: - Completions

    /// Record a micro-moment completion
    func recordCompletion(_ data: MicroCompletionData) async throws -> MicroCompletionResponse {
        let formatter = ISO8601DateFormatter()

        var body: [String: Any] = [
            "templateId": data.templateId,
            "triggerSource": data.triggerSource.rawValue,
            "startedAt": formatter.string(from: data.startedAt),
            "completedAt": formatter.string(from: data.completedAt),
            "durationActualSeconds": data.durationActualSeconds
        ]

        if let context = data.context {
            body["context"] = context
        }
        if let feltHelpful = data.feltHelpful {
            body["feltHelpful"] = feltHelpful
        }

        let response: MicroCompletionResponse = try await supabase.functions
            .invoke(
                "complete-micro-moment",
                options: .init(body: body)
            )

        // Update local streak
        streak = MicroStreak(
            id: streak?.id ?? UUID().uuidString,
            userId: streak?.userId ?? "",
            currentStreak: response.streak.currentStreak,
            longestStreak: response.streak.longestStreak,
            lastMicroDate: response.streak.lastMicroDate,
            totalMicroMoments: response.streak.totalMicroMoments,
            totalCheckIns: response.streak.totalCheckIns,
            totalSecondsPracticed: response.streak.totalSecondsPracticed,
            achievementsUnlocked: response.streak.achievementsUnlocked,
            createdAt: streak?.createdAt ?? formatter.string(from: Date()),
            updatedAt: formatter.string(from: Date())
        )

        // Refresh recent completions
        if let completions = try? await fetchRecentCompletions() {
            recentCompletions = completions
        }

        return response
    }

    /// Fetch recent completions for history
    func fetchRecentCompletions(limit: Int = 10) async throws -> [MicroMomentCompletion] {
        guard let userId = supabase.auth.currentUser?.id else {
            throw MicroMomentsError.notAuthenticated
        }

        let completions: [MicroMomentCompletion] = try await supabase
            .from("micro_moment_completions")
            .select()
            .eq("user_id", value: userId)
            .eq("completed", value: true)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        return completions
    }

    // MARK: - Quick Check-Ins

    /// Save a quick check-in (mood, energy, gratitude, etc.)
    func saveCheckIn(_ data: QuickCheckInData) async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw MicroMomentsError.notAuthenticated
        }

        var checkIn: [String: Any] = [
            "user_id": userId.uuidString,
            "type": data.type.rawValue,
            "source": "app"
        ]

        if let numeric = data.valueNumeric {
            checkIn["value_numeric"] = numeric
        }
        if let emoji = data.valueEmoji {
            checkIn["value_emoji"] = emoji
        }
        if let text = data.valueText {
            checkIn["value_text"] = text
        }
        if !data.contextTags.isEmpty {
            checkIn["context_tags"] = data.contextTags
        }

        try await supabase
            .from("quick_check_ins")
            .insert(checkIn)
            .execute()

        // Refresh check-ins
        if let checkIns = try? await fetchRecentCheckIns() {
            recentCheckIns = checkIns
        }

        // Refresh streak (trigger updates it)
        if let newStreak = try? await fetchStreak() {
            streak = newStreak
        }
    }

    /// Fetch recent check-ins
    func fetchRecentCheckIns(type: CheckInType? = nil, limit: Int = 20) async throws -> [QuickCheckIn] {
        guard let userId = supabase.auth.currentUser?.id else {
            throw MicroMomentsError.notAuthenticated
        }

        var query = supabase
            .from("quick_check_ins")
            .select()
            .eq("user_id", value: userId)

        if let type = type {
            query = query.eq("type", value: type.rawValue)
        }

        let checkIns: [QuickCheckIn] = try await query
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        return checkIns
    }

    /// Fetch check-in trends for visualization
    func fetchCheckInTrends(days: Int = 7) async throws -> [CheckInTrend] {
        guard let userId = supabase.auth.currentUser?.id else {
            throw MicroMomentsError.notAuthenticated
        }

        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date().addingTimeInterval(Double(-days) * 24 * 3600)
        let formatter = ISO8601DateFormatter()

        let checkIns: [QuickCheckIn] = try await supabase
            .from("quick_check_ins")
            .select()
            .eq("user_id", value: userId)
            .gte("created_at", value: formatter.string(from: startDate))
            .order("created_at", ascending: true)
            .execute()
            .value

        // Group by date
        var groupedByDate: [String: [QuickCheckIn]] = [:]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for checkIn in checkIns {
            let dateStr = String(checkIn.createdAt.prefix(10))
            groupedByDate[dateStr, default: []].append(checkIn)
        }

        // Calculate averages
        return groupedByDate.map { date, dayCheckIns in
            let moodCheckIns = dayCheckIns.filter { $0.type == .mood }
            let energyCheckIns = dayCheckIns.filter { $0.type == .energy }

            // Calculate mood average - divide by count of check-ins WITH values, not total count
            let moodValues = moodCheckIns.compactMap { $0.valueNumeric }
            let moodAvg: Double? = moodValues.isEmpty ? nil : Double(moodValues.reduce(0, +)) / Double(moodValues.count)

            // Calculate energy average - divide by count of check-ins WITH values, not total count
            let energyValues = energyCheckIns.compactMap { $0.valueNumeric }
            let energyAvg: Double? = energyValues.isEmpty ? nil : Double(energyValues.reduce(0, +)) / Double(energyValues.count)

            return CheckInTrend(
                date: date,
                moodAverage: moodAvg,
                energyAverage: energyAvg,
                count: dayCheckIns.count
            )
        }.sorted { $0.date < $1.date }
    }

    // MARK: - Streak

    /// Fetch the user's micro-moment streak
    func fetchStreak() async throws -> MicroStreak? {
        guard let userId = supabase.auth.currentUser?.id else {
            throw MicroMomentsError.notAuthenticated
        }

        let streaks: [MicroStreak] = try await supabase
            .from("micro_streaks")
            .select()
            .eq("user_id", value: userId)
            .execute()
            .value

        return streaks.first
    }

    // MARK: - Delivery Preferences

    /// Fetch user's delivery preferences
    func fetchDeliveryPreferences() async throws -> MicroDeliveryPreferences? {
        guard let userId = supabase.auth.currentUser?.id else {
            throw MicroMomentsError.notAuthenticated
        }

        struct DBPreferences: Codable {
            let morningCheckinEnabled: Bool
            let morningCheckinTime: String?
            let eveningCheckinEnabled: Bool
            let eveningCheckinTime: String?
            let preMeetingReminder: Bool
            let preMeetingMinutes: Int
            let postMeetingSuggestion: Bool
            let maxSuggestionsPerDay: Int
            let minHoursBetweenSuggestions: Double
            let preferredTypes: [String]?
            let preferredDurations: [Int]?
            let silentModeOnly: Bool

            enum CodingKeys: String, CodingKey {
                case morningCheckinEnabled = "morning_checkin_enabled"
                case morningCheckinTime = "morning_checkin_time"
                case eveningCheckinEnabled = "evening_checkin_enabled"
                case eveningCheckinTime = "evening_checkin_time"
                case preMeetingReminder = "pre_meeting_reminder"
                case preMeetingMinutes = "pre_meeting_minutes"
                case postMeetingSuggestion = "post_meeting_suggestion"
                case maxSuggestionsPerDay = "max_suggestions_per_day"
                case minHoursBetweenSuggestions = "min_hours_between_suggestions"
                case preferredTypes = "preferred_types"
                case preferredDurations = "preferred_durations"
                case silentModeOnly = "silent_mode_only"
            }
        }

        let prefs: [DBPreferences] = try await supabase
            .from("micro_delivery_preferences")
            .select()
            .eq("user_id", value: userId)
            .execute()
            .value

        guard let pref = prefs.first else { return nil }

        return MicroDeliveryPreferences(
            morningCheckinEnabled: pref.morningCheckinEnabled,
            morningCheckinTime: pref.morningCheckinTime,
            eveningCheckinEnabled: pref.eveningCheckinEnabled,
            eveningCheckinTime: pref.eveningCheckinTime,
            preMeetingReminder: pref.preMeetingReminder,
            preMeetingMinutes: pref.preMeetingMinutes,
            postMeetingSuggestion: pref.postMeetingSuggestion,
            maxSuggestionsPerDay: pref.maxSuggestionsPerDay,
            minHoursBetweenSuggestions: pref.minHoursBetweenSuggestions,
            preferredTypes: pref.preferredTypes?.compactMap { MicroMomentType(rawValue: $0) },
            preferredDurations: pref.preferredDurations,
            silentModeOnly: pref.silentModeOnly
        )
    }

    /// Update delivery preferences
    func updateDeliveryPreferences(_ preferences: MicroDeliveryPreferences) async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw MicroMomentsError.notAuthenticated
        }

        let formatter = ISO8601DateFormatter()

        var update: [String: Any] = [
            "user_id": userId.uuidString,
            "morning_checkin_enabled": preferences.morningCheckinEnabled,
            "evening_checkin_enabled": preferences.eveningCheckinEnabled,
            "pre_meeting_reminder": preferences.preMeetingReminder,
            "pre_meeting_minutes": preferences.preMeetingMinutes,
            "post_meeting_suggestion": preferences.postMeetingSuggestion,
            "max_suggestions_per_day": preferences.maxSuggestionsPerDay,
            "min_hours_between_suggestions": preferences.minHoursBetweenSuggestions,
            "silent_mode_only": preferences.silentModeOnly,
            "updated_at": formatter.string(from: Date())
        ]

        if let time = preferences.morningCheckinTime {
            update["morning_checkin_time"] = time
        }
        if let time = preferences.eveningCheckinTime {
            update["evening_checkin_time"] = time
        }
        if let types = preferences.preferredTypes {
            update["preferred_types"] = types.map { $0.rawValue }
        }
        if let durations = preferences.preferredDurations {
            update["preferred_durations"] = durations
        }

        try await supabase
            .from("micro_delivery_preferences")
            .upsert(update)
            .execute()

        deliveryPreferences = preferences
    }
}

// MARK: - Errors

enum MicroMomentsError: LocalizedError {
    case notAuthenticated
    case templateNotFound
    case saveFailed
    case networkError

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Please sign in to continue"
        case .templateNotFound:
            return "Exercise not found"
        case .saveFailed:
            return "Failed to save. Please try again."
        case .networkError:
            return "Network error. Please check your connection."
        }
    }
}
