import Foundation

// Note: CognitiveDistortionType is defined in TherapeuticModels.swift

// MARK: - Distortion Feedback Action

/// Action a user can take on a cognitive distortion insight
enum DistortionFeedbackAction: String, Codable {
    case helpful
    case notHelpful = "not_helpful"
    case dismiss
}

// MARK: - Journal Entry

/// A user's journal entry
struct JournalEntry: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let userId: String
    let title: String?
    let content: String
    let wordCount: Int
    let moodBefore: Int?
    let moodAfter: Int?
    let isAnalyzed: Bool
    let promptId: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case content
        case wordCount = "word_count"
        case moodBefore = "mood_before"
        case moodAfter = "mood_after"
        case isAnalyzed = "is_analyzed"
        case promptId = "prompt_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Convenience property to get the primary mood (before journaling)
    var mood: Int? { moodBefore }

    /// Character count of the content
    var characterCount: Int { content.count }
}

// MARK: - Cognitive Distortion Instance

/// A specific instance of a cognitive distortion detected in a journal entry
struct CognitiveDistortionInstance: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let distortionType: String
    let displayName: String
    let quote: String
    let explanation: String
    let alternativePerspective: String

    enum CodingKeys: String, CodingKey {
        case distortionType = "type"
        case displayName
        case quote
        case explanation
        case alternativePerspective
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.distortionType = try container.decode(String.self, forKey: .distortionType)
        self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? distortionType.replacingOccurrences(of: "_", with: " ").capitalized
        self.quote = try container.decodeIfPresent(String.self, forKey: .quote) ?? ""
        self.explanation = try container.decodeIfPresent(String.self, forKey: .explanation) ?? ""
        self.alternativePerspective = try container.decodeIfPresent(String.self, forKey: .alternativePerspective) ?? ""
        // Generate stable ID from type and quote
        self.id = "\(distortionType)-\(quote.hashValue)"
    }

    init(distortionType: String, displayName: String, quote: String, explanation: String, alternativePerspective: String) {
        self.distortionType = distortionType
        self.displayName = displayName
        self.quote = quote
        self.explanation = explanation
        self.alternativePerspective = alternativePerspective
        self.id = "\(distortionType)-\(quote.hashValue)"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(distortionType, forKey: .distortionType)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(quote, forKey: .quote)
        try container.encode(explanation, forKey: .explanation)
        try container.encode(alternativePerspective, forKey: .alternativePerspective)
    }

    /// Original text from entry (alias for quote)
    var originalText: String { quote }

    /// Suggested reframe (alias for alternativePerspective)
    var suggestedReframe: String { alternativePerspective }

    /// The distortion type as an enum (for accessing icon, supportiveDescription, etc.)
    var distortionTypeEnum: CognitiveDistortionType? {
        CognitiveDistortionType(rawValue: distortionType)
    }

    /// Confidence level description based on explanation length/detail
    var confidenceLevel: String {
        // Simple heuristic based on explanation length
        if explanation.count > 100 {
            return "High confidence"
        } else if explanation.count > 50 {
            return "Moderate confidence"
        } else {
            return "Low confidence"
        }
    }
}

// MARK: - Suggested Reframe

/// A suggested reframe from AI analysis
struct SuggestedReframe: Identifiable, Codable, Equatable, Hashable {
    var id: String { "\(original.hashValue)" }
    let original: String
    let reframe: String
    let rationale: String

    init(original: String = "", reframe: String, rationale: String = "") {
        self.original = original
        self.reframe = reframe
        self.rationale = rationale
    }
}

// MARK: - Journal Analysis

/// AI-generated analysis of a journal entry
struct JournalAnalysis: Identifiable, Codable, Equatable {
    let id: String
    let entryId: String
    let userId: String
    let emotionalThemes: [String]
    let suggestedReframes: [SuggestedReframe]
    let patternsIdentified: [String]
    let cognitiveDistortions: [CognitiveDistortionInstance]
    let supportiveSummary: String
    let aiModel: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case entryId = "entry_id"
        case userId = "user_id"
        case emotionalThemes = "emotional_themes"
        case suggestedReframes = "suggested_reframes"
        case patternsIdentified = "patterns_identified"
        case cognitiveDistortions = "cognitive_distortions"
        case supportiveSummary = "supportive_summary"
        case aiModel = "ai_model"
        case createdAt = "created_at"
    }

    /// Primary emotion detected
    var primaryEmotion: String? {
        emotionalThemes.first
    }

    /// Whether any distortions were detected
    var hasDistortions: Bool {
        !cognitiveDistortions.isEmpty
    }

    /// Number of distortions detected
    var distortionCount: Int {
        cognitiveDistortions.count
    }

    /// Supportive insight (alias for supportiveSummary)
    var supportiveInsight: String { supportiveSummary }

    /// Overall sentiment derived from emotional themes
    var overallSentiment: String {
        guard let primary = primaryEmotion else { return "neutral" }
        return primary
    }

    static func == (lhs: JournalAnalysis, rhs: JournalAnalysis) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Journal Prompt Category

/// Categories of journal prompts
enum JournalPromptCategory: String, Codable, CaseIterable, Identifiable {
    case gratitude
    case reflection
    case growth
    case emotions
    case relationships
    case selfCompassion = "self_compassion"
    case mindfulness
    case goals
    case challenges
    case creativity

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gratitude: return "Gratitude"
        case .reflection: return "Reflection"
        case .growth: return "Growth"
        case .emotions: return "Emotions"
        case .relationships: return "Relationships"
        case .selfCompassion: return "Self-Compassion"
        case .mindfulness: return "Mindfulness"
        case .goals: return "Goals"
        case .challenges: return "Challenges"
        case .creativity: return "Creativity"
        }
    }

    var icon: String {
        switch self {
        case .gratitude: return "heart.fill"
        case .reflection: return "bubble.left.and.bubble.right.fill"
        case .growth: return "leaf.fill"
        case .emotions: return "face.smiling"
        case .relationships: return "person.2.fill"
        case .selfCompassion: return "hand.raised.fill"
        case .mindfulness: return "brain"
        case .goals: return "target"
        case .challenges: return "mountain.2.fill"
        case .creativity: return "paintbrush.fill"
        }
    }

    var description: String {
        switch self {
        case .gratitude: return "Prompts to help you appreciate the good in your life"
        case .reflection: return "Prompts for thoughtful self-examination"
        case .growth: return "Prompts to inspire personal development"
        case .emotions: return "Prompts to explore and understand your feelings"
        case .relationships: return "Prompts about connections with others"
        case .selfCompassion: return "Prompts to practice kindness toward yourself"
        case .mindfulness: return "Prompts for present-moment awareness"
        case .goals: return "Prompts to clarify and pursue your aspirations"
        case .challenges: return "Prompts to work through difficult times"
        case .creativity: return "Prompts for creative expression"
        }
    }
}

// MARK: - Journal Prompt

/// A writing prompt for journal entries
struct JournalPrompt: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let category: JournalPromptCategory
    let promptText: String
    let moodAffinity: [Int]?
    let isPremium: Bool
    let usageCount: Int
    let isActive: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case category
        case promptText = "prompt_text"
        case moodAffinity = "mood_affinity"
        case isPremium = "is_premium"
        case usageCount = "usage_count"
        case isActive = "is_active"
        case createdAt = "created_at"
    }

    /// Whether this prompt is good for the given mood (1-5 scale)
    func isGoodForMood(_ mood: Int) -> Bool {
        guard let affinity = moodAffinity else { return true }
        return affinity.contains(mood)
    }
}

// MARK: - Journal Settings

/// User's journaling preferences
struct JournalSettings: Identifiable, Codable, Equatable {
    var id: String { userId }
    let userId: String
    var dailyReminderEnabled: Bool
    var reminderTime: String?
    var preferredPromptCategories: [String]?
    var autoAnalyze: Bool
    var showWordCount: Bool
    var defaultMoodTracking: Bool
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case dailyReminderEnabled = "daily_reminder_enabled"
        case reminderTime = "reminder_time"
        case preferredPromptCategories = "preferred_prompt_categories"
        case autoAnalyze = "auto_analyze"
        case showWordCount = "show_word_count"
        case defaultMoodTracking = "default_mood_tracking"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Default settings for new users
    static var defaultSettings: JournalSettings {
        JournalSettings(
            userId: "",
            dailyReminderEnabled: false,
            reminderTime: "20:00",
            preferredPromptCategories: nil,
            autoAnalyze: false,
            showWordCount: true,
            defaultMoodTracking: true,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    // Backwards compatibility aliases
    var reminderEnabled: Bool {
        get { dailyReminderEnabled }
        set { dailyReminderEnabled = newValue }
    }

    var showAnalysisAutomatically: Bool {
        get { autoAnalyze }
        set { autoAnalyze = newValue }
    }
}

// MARK: - Journal Streak

/// User's journaling streak data
struct JournalStreak: Identifiable, Codable, Equatable {
    var id: String { uniqueId }
    let uniqueId: String
    let userId: String
    let currentStreak: Int
    let longestStreak: Int
    let lastEntryDate: Date?
    let streakStartedAt: Date?
    let totalEntries: Int
    let timezone: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case currentStreak = "current_streak"
        case longestStreak = "longest_streak"
        case lastEntryDate = "last_entry_date"
        case streakStartedAt = "streak_started_at"
        case totalEntries = "total_entries"
        case timezone
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let userIdValue = try container.decode(String.self, forKey: .userId)
        self.uniqueId = userIdValue
        self.userId = userIdValue
        self.currentStreak = try container.decode(Int.self, forKey: .currentStreak)
        self.longestStreak = try container.decode(Int.self, forKey: .longestStreak)
        self.lastEntryDate = try container.decodeIfPresent(Date.self, forKey: .lastEntryDate)
        self.streakStartedAt = try container.decodeIfPresent(Date.self, forKey: .streakStartedAt)
        self.totalEntries = try container.decode(Int.self, forKey: .totalEntries)
        self.timezone = try container.decode(String.self, forKey: .timezone)
        self.updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    init(uniqueId: String, userId: String, currentStreak: Int, longestStreak: Int, lastEntryDate: Date?, streakStartedAt: Date?, totalEntries: Int, timezone: String, updatedAt: Date) {
        self.uniqueId = uniqueId
        self.userId = userId
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.lastEntryDate = lastEntryDate
        self.streakStartedAt = streakStartedAt
        self.totalEntries = totalEntries
        self.timezone = timezone
        self.updatedAt = updatedAt
    }

    /// Convenience initializer for creating an empty streak
    init(userId: String) {
        self.uniqueId = userId
        self.userId = userId
        self.currentStreak = 0
        self.longestStreak = 0
        self.lastEntryDate = nil
        self.streakStartedAt = nil
        self.totalEntries = 0
        self.timezone = TimeZone.current.identifier
        self.updatedAt = Date()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        try container.encode(currentStreak, forKey: .currentStreak)
        try container.encode(longestStreak, forKey: .longestStreak)
        try container.encodeIfPresent(lastEntryDate, forKey: .lastEntryDate)
        try container.encodeIfPresent(streakStartedAt, forKey: .streakStartedAt)
        try container.encode(totalEntries, forKey: .totalEntries)
        try container.encode(timezone, forKey: .timezone)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    /// Whether the user journaled today
    var journaledToday: Bool {
        guard let lastDate = lastEntryDate else { return false }
        return Calendar.current.isDateInToday(lastDate)
    }

    /// Days until streak breaks (if not journaled today, 0)
    var daysUntilStreakBreaks: Int {
        guard currentStreak > 0 else { return 0 }
        return journaledToday ? 1 : 0
    }

    /// Streak status message
    var statusMessage: String {
        if currentStreak == 0 {
            return "Start your streak today!"
        } else if journaledToday {
            return "You're on a \(currentStreak)-day streak!"
        } else {
            return "Journal today to keep your \(currentStreak)-day streak!"
        }
    }

    /// Empty streak for new users
    static var empty: JournalStreak {
        JournalStreak(
            uniqueId: UUID().uuidString,
            userId: "",
            currentStreak: 0,
            longestStreak: 0,
            lastEntryDate: nil,
            streakStartedAt: nil,
            totalEntries: 0,
            timezone: TimeZone.current.identifier,
            updatedAt: Date()
        )
    }
}

// MARK: - Journal Draft

/// Auto-saved draft of an in-progress journal entry
struct JournalDraft: Identifiable, Codable, Equatable {
    var id: String { uniqueId }
    let uniqueId: String
    let userId: String
    var title: String?
    var content: String
    var moodBefore: Int?
    var promptId: String?
    let lastSavedAt: Date

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case title
        case content
        case moodBefore = "mood_before"
        case promptId = "prompt_id"
        case lastSavedAt = "last_saved_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let userIdValue = try container.decode(String.self, forKey: .userId)
        self.uniqueId = userIdValue
        self.userId = userIdValue
        self.title = try container.decodeIfPresent(String.self, forKey: .title)
        self.content = try container.decode(String.self, forKey: .content)
        self.moodBefore = try container.decodeIfPresent(Int.self, forKey: .moodBefore)
        self.promptId = try container.decodeIfPresent(String.self, forKey: .promptId)
        self.lastSavedAt = try container.decode(Date.self, forKey: .lastSavedAt)
    }

    init(uniqueId: String, userId: String, title: String?, content: String, moodBefore: Int?, promptId: String?, lastSavedAt: Date) {
        self.uniqueId = uniqueId
        self.userId = userId
        self.title = title
        self.content = content
        self.moodBefore = moodBefore
        self.promptId = promptId
        self.lastSavedAt = lastSavedAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(moodBefore, forKey: .moodBefore)
        try container.encodeIfPresent(promptId, forKey: .promptId)
        try container.encode(lastSavedAt, forKey: .lastSavedAt)
    }

    /// Word count of the draft content
    var wordCount: Int {
        content.split(separator: " ").count
    }

    /// Whether the draft has meaningful content
    var hasContent: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Backwards compatibility alias
    var mood: Int? { moodBefore }
}

// MARK: - Journal Daily Usage

/// Tracks daily journal usage for quota enforcement
struct JournalDailyUsage: Identifiable, Codable, Equatable {
    var id: String { "\(userId)-\(date)" }
    let userId: String
    let date: String
    let entriesCreated: Int
    let analysesUsed: Int

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case date
        case entriesCreated = "entries_created"
        case analysesUsed = "analyses_used"
    }
}

// MARK: - Journal Distortion Feedback

/// User feedback on an AI-detected cognitive distortion
struct JournalDistortionFeedback: Identifiable, Codable, Equatable {
    let id: String
    let analysisId: String
    let userId: String
    let distortionType: String
    let userAction: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case analysisId = "analysis_id"
        case userId = "user_id"
        case distortionType = "distortion_type"
        case userAction = "user_action"
        case createdAt = "created_at"
    }

    /// Whether the feedback was positive
    var wasHelpful: Bool {
        userAction == "helpful"
    }
}

// MARK: - Journal Entry with Analysis

/// Combined journal entry with its analysis (for list views)
struct JournalEntryWithAnalysis: Identifiable, Equatable {
    let entry: JournalEntry
    let analysis: JournalAnalysis?
    let prompt: JournalPrompt?

    var id: String { entry.id }

    /// Preview text for list display
    var previewText: String {
        let text = entry.content
        if text.count > 100 {
            return String(text.prefix(100)) + "..."
        }
        return text
    }

    /// Formatted date for display
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: entry.createdAt)
    }

    /// Mood emoji if mood is set
    var moodEmoji: String? {
        guard let mood = entry.moodBefore else { return nil }
        switch mood {
        case 1: return "😢"
        case 2: return "😕"
        case 3: return "😐"
        case 4: return "🙂"
        case 5: return "😊"
        default: return nil
        }
    }
}

// MARK: - Analysis Response (from Edge Function)

/// Response from the analyze-journal Edge Function
struct JournalAnalysisResponse: Codable {
    let analysisId: String?
    let emotionalThemes: [String]?
    let suggestedReframes: [SuggestedReframe]?
    let patternsIdentified: [String]?
    let cognitiveDistortions: [CognitiveDistortionInstance]?
    let supportiveSummary: String?
    let cached: Bool?
    let quotaUsed: Int?
    let quotaLimit: Int?
    let error: String?
    let code: String?
    let message: String?

    /// Convert to JournalAnalysis for storage/display
    func toAnalysis(entryId: String, userId: String) -> JournalAnalysis? {
        guard let analysisId = analysisId else { return nil }
        return JournalAnalysis(
            id: analysisId,
            entryId: entryId,
            userId: userId,
            emotionalThemes: emotionalThemes ?? [],
            suggestedReframes: suggestedReframes ?? [],
            patternsIdentified: patternsIdentified ?? [],
            cognitiveDistortions: cognitiveDistortions ?? [],
            supportiveSummary: supportiveSummary ?? "",
            aiModel: "grok-4-1-fast-reasoning",
            createdAt: Date()
        )
    }

    /// Remaining quota (computed from quotaLimit - quotaUsed)
    var quotaRemaining: Int? {
        guard let limit = quotaLimit, let used = quotaUsed else { return nil }
        if limit < 0 { return nil } // Unlimited
        return max(0, limit - used)
    }
}
