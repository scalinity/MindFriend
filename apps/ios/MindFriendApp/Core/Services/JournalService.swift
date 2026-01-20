import Foundation
import Supabase

// MARK: - Journal Service Error

enum JournalServiceError: LocalizedError {
    case notAuthenticated
    case entryNotFound
    case analysisNotFound
    case quotaExceeded
    case analysisInProgress
    case analysisFailed(String)
    case promptNotFound
    case draftNotFound
    case exportFailed
    case invalidContent

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to use journaling features"
        case .entryNotFound:
            return "Journal entry not found"
        case .analysisNotFound:
            return "Analysis not found for this entry"
        case .quotaExceeded:
            return "You've reached your daily analysis limit. Upgrade to Premium for unlimited analyses."
        case .analysisInProgress:
            return "Analysis is already in progress"
        case .analysisFailed(let reason):
            return "Analysis failed: \(reason)"
        case .promptNotFound:
            return "Prompt not found"
        case .draftNotFound:
            return "Draft not found"
        case .exportFailed:
            return "Failed to export journal entries"
        case .invalidContent:
            return "Journal content is invalid or too short"
        }
    }
}

// MARK: - Journal Entry Filter

struct JournalEntryFilter {
    var startDate: Date?
    var endDate: Date?
    var moodRange: ClosedRange<Int>?
    var hasAnalysis: Bool?
    var promptCategory: JournalPromptCategory?
    var searchText: String?
    var limit: Int = 50

    static var recent: JournalEntryFilter {
        JournalEntryFilter(limit: 20)
    }

    static var thisWeek: JournalEntryFilter {
        let calendar = Calendar.current
        let now = Date()
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)
        return JournalEntryFilter(startDate: weekAgo, endDate: now)
    }

    static var thisMonth: JournalEntryFilter {
        let calendar = Calendar.current
        let now = Date()
        let monthAgo = calendar.date(byAdding: .month, value: -1, to: now)
        return JournalEntryFilter(startDate: monthAgo, endDate: now)
    }
}

// MARK: - Journal Service

@MainActor
final class JournalService {
    private let supabase: SupabaseClient

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    // MARK: - Helper Methods

    private func getCurrentUserId() async throws -> String {
        guard let user = try? await supabase.auth.session.user else {
            throw JournalServiceError.notAuthenticated
        }
        return user.id.uuidString
    }

    // MARK: - Journal Entries

    /// Fetch all journal entries for the current user
    func fetchEntries(filter: JournalEntryFilter = .recent) async throws -> [JournalEntry] {
        let userId = try await getCurrentUserId()

        var query = supabase
            .from("journal_entries")
            .select()
            .eq("user_id", value: userId)

        if let startDate = filter.startDate {
            query = query.gte("created_at", value: ISO8601DateFormatter().string(from: startDate))
        }

        if let endDate = filter.endDate {
            query = query.lte("created_at", value: ISO8601DateFormatter().string(from: endDate))
        }

        if let moodRange = filter.moodRange {
            query = query.gte("mood_before", value: moodRange.lowerBound)
            query = query.lte("mood_before", value: moodRange.upperBound)
        }

        let entries: [JournalEntry] = try await query
            .order("created_at", ascending: false)
            .limit(filter.limit)
            .execute()
            .value

        // Apply search filter locally if provided
        if let searchText = filter.searchText, !searchText.isEmpty {
            let lowercasedSearch = searchText.lowercased()
            return entries.filter { entry in
                entry.content.lowercased().contains(lowercasedSearch) ||
                (entry.title?.lowercased().contains(lowercasedSearch) ?? false)
            }
        }

        return entries
    }

    /// Fetch a single journal entry by ID
    func fetchEntry(id: String) async throws -> JournalEntry {
        let userId = try await getCurrentUserId()

        let entries: [JournalEntry] = try await supabase
            .from("journal_entries")
            .select()
            .eq("id", value: id)
            .eq("user_id", value: userId)
            .limit(1)
            .execute()
            .value

        guard let entry = entries.first else {
            throw JournalServiceError.entryNotFound
        }

        return entry
    }

    /// Fetch entry with its analysis
    func fetchEntryWithAnalysis(id: String) async throws -> JournalEntryWithAnalysis {
        let entry = try await fetchEntry(id: id)
        let analysis = try? await fetchAnalysis(forEntryId: id)
        let prompt: JournalPrompt? = entry.promptId != nil ? try? await fetchPrompt(id: entry.promptId!) : nil

        return JournalEntryWithAnalysis(entry: entry, analysis: analysis, prompt: prompt)
    }

    /// Create a new journal entry
    func createEntry(
        title: String?,
        content: String,
        moodBefore: Int?,
        moodAfter: Int? = nil,
        promptId: String? = nil
    ) async throws -> JournalEntry {
        let userId = try await getCurrentUserId()

        // Validate content
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty, trimmedContent.count >= 10 else {
            throw JournalServiceError.invalidContent
        }

        let wordCount = trimmedContent.split(separator: " ").count

        struct NewEntry: Encodable {
            let user_id: String
            let title: String?
            let content: String
            let mood_before: Int?
            let mood_after: Int?
            let prompt_id: String?
            let word_count: Int
        }

        let newEntry = NewEntry(
            user_id: userId,
            title: title,
            content: trimmedContent,
            mood_before: moodBefore,
            mood_after: moodAfter,
            prompt_id: promptId,
            word_count: wordCount
        )

        let entry: JournalEntry = try await supabase
            .from("journal_entries")
            .insert(newEntry)
            .select()
            .single()
            .execute()
            .value

        // Clear any draft after successful save
        try? await deleteDraft()

        // Record prompt usage if a prompt was used
        if let promptId = promptId {
            try? await recordPromptUsage(promptId: promptId)
        }

        return entry
    }

    /// Update an existing journal entry
    func updateEntry(id: String, title: String?, content: String, moodBefore: Int?, moodAfter: Int? = nil) async throws -> JournalEntry {
        let userId = try await getCurrentUserId()

        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            throw JournalServiceError.invalidContent
        }

        let wordCount = trimmedContent.split(separator: " ").count

        struct UpdateEntry: Encodable {
            let title: String?
            let content: String
            let mood_before: Int?
            let mood_after: Int?
            let word_count: Int
            let updated_at: String
        }

        let update = UpdateEntry(
            title: title,
            content: trimmedContent,
            mood_before: moodBefore,
            mood_after: moodAfter,
            word_count: wordCount,
            updated_at: ISO8601DateFormatter().string(from: Date())
        )

        let entry: JournalEntry = try await supabase
            .from("journal_entries")
            .update(update)
            .eq("id", value: id)
            .eq("user_id", value: userId)
            .select()
            .single()
            .execute()
            .value

        return entry
    }

    /// Delete a journal entry
    func deleteEntry(id: String) async throws {
        let userId = try await getCurrentUserId()

        try await supabase
            .from("journal_entries")
            .delete()
            .eq("id", value: id)
            .eq("user_id", value: userId)
            .execute()
    }

    // MARK: - AI Analysis

    /// Fetch analysis for a journal entry
    func fetchAnalysis(forEntryId entryId: String) async throws -> JournalAnalysis {
        let userId = try await getCurrentUserId()

        let analyses: [JournalAnalysis] = try await supabase
            .from("journal_analyses")
            .select()
            .eq("entry_id", value: entryId)
            .eq("user_id", value: userId)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value

        guard let analysis = analyses.first else {
            throw JournalServiceError.analysisNotFound
        }

        return analysis
    }

    /// Request AI analysis for a journal entry
    func requestAnalysis(forEntryId entryId: String) async throws -> JournalAnalysis {
        let userId = try await getCurrentUserId()

        // Call the analyze-journal Edge Function
        let response: JournalAnalysisResponse = try await supabase.functions
            .invoke(
                "analyze-journal",
                options: FunctionInvokeOptions(
                    body: ["entryId": entryId]
                )
            )

        // Handle quota exceeded
        if response.quotaRemaining == 0 && response.analysisId == nil {
            throw JournalServiceError.quotaExceeded
        }

        // Convert response to JournalAnalysis
        guard let analysis = response.toAnalysis(entryId: entryId, userId: userId) else {
            throw JournalServiceError.analysisFailed("Failed to parse analysis response")
        }

        return analysis
    }

    /// Check remaining analysis quota
    func checkAnalysisQuota() async throws -> Int {
        let userId = try await getCurrentUserId()
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)

        struct UsageRow: Decodable {
            let analyses_used: Int
        }

        let usage: [UsageRow] = try await supabase
            .from("journal_daily_usage")
            .select("analyses_used")
            .eq("user_id", value: userId)
            .eq("date", value: String(today))
            .limit(1)
            .execute()
            .value

        let usedToday = usage.first?.analyses_used ?? 0

        // Check if user is premium (unlimited)
        struct SubscriptionRow: Decodable {
            let tier: String
        }

        let subs: [SubscriptionRow] = try await supabase
            .from("subscriptions")
            .select("tier")
            .eq("user_id", value: userId)
            .limit(1)
            .execute()
            .value

        let tier = subs.first?.tier ?? "free"
        if tier == "premium" || tier == "premium_annual" {
            return -1 // Unlimited
        }

        // Free tier: 3 analyses per day
        return max(0, 3 - usedToday)
    }

    // MARK: - Prompts

    /// Fetch all active prompts
    func fetchPrompts(category: JournalPromptCategory? = nil, isPremiumOnly: Bool = false) async throws -> [JournalPrompt] {
        var query = supabase
            .from("journal_prompts")
            .select()
            .eq("is_active", value: true)

        if let category = category {
            query = query.eq("category", value: category.rawValue)
        }

        if isPremiumOnly {
            query = query.eq("is_premium", value: true)
        }

        let prompts: [JournalPrompt] = try await query
            .order("usage_count", ascending: true)
            .execute()
            .value

        return prompts
    }

    /// Fetch a single prompt by ID
    func fetchPrompt(id: String) async throws -> JournalPrompt {
        let prompts: [JournalPrompt] = try await supabase
            .from("journal_prompts")
            .select()
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value

        guard let prompt = prompts.first else {
            throw JournalServiceError.promptNotFound
        }

        return prompt
    }

    /// Fetch personalized prompts based on current mood
    func fetchPromptsForMood(_ mood: Int, limit: Int = 5) async throws -> [JournalPrompt] {
        let userId = try await getCurrentUserId()

        // Use the database function for personalized prompts
        struct PromptResult: Decodable {
            let id: String
            let category: JournalPromptCategory
            let prompt_text: String
            let mood_affinity: [Int]?
            let is_premium: Bool
            let usage_count: Int
            let is_active: Bool
            let created_at: Date
        }

        struct RPCParams: Encodable {
            let p_user_id: String
            let p_mood: Int
            let p_limit: Int
        }

        let params = RPCParams(p_user_id: userId, p_mood: mood, p_limit: limit)

        let results: [PromptResult] = try await supabase
            .rpc("get_journal_prompts_for_mood", params: params)
            .execute()
            .value

        // Convert to JournalPrompt
        return results.map { result in
            JournalPrompt(
                id: result.id,
                category: result.category,
                promptText: result.prompt_text,
                moodAffinity: result.mood_affinity,
                isPremium: result.is_premium,
                usageCount: result.usage_count,
                isActive: result.is_active,
                createdAt: result.created_at
            )
        }
    }

    /// Record that a prompt was used
    private func recordPromptUsage(promptId: String) async throws {
        let userId = try await getCurrentUserId()
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)

        struct PromptHistoryEntry: Encodable {
            let user_id: String
            let prompt_id: String
            let used_date: String
        }

        let entry = PromptHistoryEntry(
            user_id: userId,
            prompt_id: promptId,
            used_date: String(today)
        )

        // Insert, ignore conflict (already used today)
        try? await supabase
            .from("journal_prompt_history")
            .upsert(entry, onConflict: "user_id,prompt_id,used_date")
            .execute()
    }

    // MARK: - Settings

    /// Fetch user's journal settings
    func fetchSettings() async throws -> JournalSettings {
        let userId = try await getCurrentUserId()

        let settings: [JournalSettings] = try await supabase
            .from("journal_settings")
            .select()
            .eq("user_id", value: userId)
            .limit(1)
            .execute()
            .value

        if let existingSettings = settings.first {
            return existingSettings
        }

        // Create default settings if none exist
        return try await createDefaultSettings()
    }

    /// Create default settings for a new user
    private func createDefaultSettings() async throws -> JournalSettings {
        let userId = try await getCurrentUserId()

        struct NewSettings: Encodable {
            let user_id: String
            let daily_reminder_enabled: Bool
            let reminder_time: String
            let auto_analyze: Bool
            let show_word_count: Bool
            let default_mood_tracking: Bool
            let preferred_prompt_categories: [String]?
        }

        let newSettings = NewSettings(
            user_id: userId,
            daily_reminder_enabled: false,
            reminder_time: "21:00",
            auto_analyze: true,
            show_word_count: true,
            default_mood_tracking: true,
            preferred_prompt_categories: nil
        )

        let settings: JournalSettings = try await supabase
            .from("journal_settings")
            .insert(newSettings)
            .select()
            .single()
            .execute()
            .value

        return settings
    }

    /// Update user's journal settings
    func updateSettings(_ settings: JournalSettings) async throws -> JournalSettings {
        let userId = try await getCurrentUserId()

        struct UpdateSettings: Encodable {
            let daily_reminder_enabled: Bool
            let reminder_time: String?
            let auto_analyze: Bool
            let show_word_count: Bool
            let default_mood_tracking: Bool
            let preferred_prompt_categories: [String]?
            let updated_at: String
        }

        let update = UpdateSettings(
            daily_reminder_enabled: settings.dailyReminderEnabled,
            reminder_time: settings.reminderTime,
            auto_analyze: settings.autoAnalyze,
            show_word_count: settings.showWordCount,
            default_mood_tracking: settings.defaultMoodTracking,
            preferred_prompt_categories: settings.preferredPromptCategories,
            updated_at: ISO8601DateFormatter().string(from: Date())
        )

        let updatedSettings: JournalSettings = try await supabase
            .from("journal_settings")
            .update(update)
            .eq("user_id", value: userId)
            .select()
            .single()
            .execute()
            .value

        return updatedSettings
    }

    // MARK: - Streaks

    /// Fetch user's journal streak
    func fetchStreak() async throws -> JournalStreak {
        let userId = try await getCurrentUserId()

        let streaks: [JournalStreak] = try await supabase
            .from("journal_streaks")
            .select()
            .eq("user_id", value: userId)
            .limit(1)
            .execute()
            .value

        if let streak = streaks.first {
            return streak
        }

        // Return empty streak if none exists (will be created on first entry)
        return JournalStreak(userId: userId)
    }

    // MARK: - Drafts

    /// Fetch user's current draft (if any)
    func fetchDraft() async throws -> JournalDraft? {
        let userId = try await getCurrentUserId()

        let drafts: [JournalDraft] = try await supabase
            .from("journal_drafts")
            .select()
            .eq("user_id", value: userId)
            .limit(1)
            .execute()
            .value

        return drafts.first
    }

    /// Save or update draft
    func saveDraft(title: String?, content: String, moodBefore: Int?, promptId: String?) async throws -> JournalDraft {
        let userId = try await getCurrentUserId()

        struct UpsertDraft: Encodable {
            let user_id: String
            let title: String?
            let content: String
            let mood_before: Int?
            let prompt_id: String?
            let last_saved_at: String
        }

        let draft = UpsertDraft(
            user_id: userId,
            title: title,
            content: content,
            mood_before: moodBefore,
            prompt_id: promptId,
            last_saved_at: ISO8601DateFormatter().string(from: Date())
        )

        let savedDraft: JournalDraft = try await supabase
            .from("journal_drafts")
            .upsert(draft, onConflict: "user_id")
            .select()
            .single()
            .execute()
            .value

        return savedDraft
    }

    /// Delete user's draft
    func deleteDraft() async throws {
        let userId = try await getCurrentUserId()

        try await supabase
            .from("journal_drafts")
            .delete()
            .eq("user_id", value: userId)
            .execute()
    }

    // MARK: - Distortion Feedback

    /// Submit feedback on a detected cognitive distortion
    func submitDistortionFeedback(
        analysisId: String,
        distortionType: String,
        action: DistortionFeedbackAction
    ) async throws {
        let userId = try await getCurrentUserId()

        struct FeedbackEntry: Encodable {
            let user_id: String
            let analysis_id: String
            let distortion_type: String
            let user_action: String
        }

        let feedback = FeedbackEntry(
            user_id: userId,
            analysis_id: analysisId,
            distortion_type: distortionType,
            user_action: action.rawValue
        )

        try await supabase
            .from("journal_distortion_feedback")
            .insert(feedback)
            .execute()
    }

    // MARK: - Export

    /// Export journal entries to a structured format
    func exportEntries(
        filter: JournalEntryFilter = JournalEntryFilter(),
        format: ExportFormat = .json
    ) async throws -> Data {
        let entries = try await fetchEntries(filter: filter)

        switch format {
        case .json:
            return try exportAsJSON(entries: entries)
        case .markdown:
            return try exportAsMarkdown(entries: entries)
        case .csv:
            return try exportAsCSV(entries: entries)
        }
    }

    enum ExportFormat {
        case json
        case markdown
        case csv
    }

    private func exportAsJSON(entries: [JournalEntry]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(entries)
    }

    private func exportAsMarkdown(entries: [JournalEntry]) throws -> Data {
        var markdown = "# My Journal Entries\n\n"
        markdown += "Exported on \(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short))\n\n"
        markdown += "---\n\n"

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short

        for entry in entries {
            let date = dateFormatter.string(from: entry.createdAt)
            let title = entry.title ?? "Untitled"
            let mood = entry.mood.map { "Mood: \($0)/5" } ?? ""

            markdown += "## \(title)\n"
            markdown += "*\(date)*"
            if !mood.isEmpty {
                markdown += " | \(mood)"
            }
            markdown += "\n\n"
            markdown += entry.content
            markdown += "\n\n---\n\n"
        }

        guard let data = markdown.data(using: .utf8) else {
            throw JournalServiceError.exportFailed
        }
        return data
    }

    private func exportAsCSV(entries: [JournalEntry]) throws -> Data {
        var csv = "Date,Title,Mood,Word Count,Content\n"

        let dateFormatter = ISO8601DateFormatter()

        for entry in entries {
            let date = dateFormatter.string(from: entry.createdAt)
            let title = (entry.title ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            let mood = entry.mood.map { String($0) } ?? ""
            let content = entry.content.replacingOccurrences(of: "\"", with: "\"\"")

            csv += "\"\(date)\",\"\(title)\",\(mood),\(entry.wordCount),\"\(content)\"\n"
        }

        guard let data = csv.data(using: .utf8) else {
            throw JournalServiceError.exportFailed
        }
        return data
    }

    // MARK: - Statistics

    /// Get journal statistics for the user
    func fetchStatistics() async throws -> JournalStatistics {
        let streak = try await fetchStreak()
        let thisWeek = try await fetchEntries(filter: .thisWeek)
        let thisMonth = try await fetchEntries(filter: .thisMonth)

        // Calculate mood average
        let moodsThisWeek = thisWeek.compactMap { $0.mood }
        let averageMood = moodsThisWeek.isEmpty ? nil : Double(moodsThisWeek.reduce(0, +)) / Double(moodsThisWeek.count)

        // Calculate word count average
        let totalWords = thisMonth.reduce(0) { $0 + $1.wordCount }
        let averageWords = thisMonth.isEmpty ? 0 : totalWords / thisMonth.count

        return JournalStatistics(
            currentStreak: streak.currentStreak,
            longestStreak: streak.longestStreak,
            totalEntries: streak.totalEntries,
            entriesThisWeek: thisWeek.count,
            entriesThisMonth: thisMonth.count,
            averageMoodThisWeek: averageMood,
            averageWordCount: averageWords,
            journaledToday: streak.journaledToday
        )
    }
}

// MARK: - Journal Statistics

struct JournalStatistics {
    let currentStreak: Int
    let longestStreak: Int
    let totalEntries: Int
    let entriesThisWeek: Int
    let entriesThisMonth: Int
    let averageMoodThisWeek: Double?
    let averageWordCount: Int
    let journaledToday: Bool
}
