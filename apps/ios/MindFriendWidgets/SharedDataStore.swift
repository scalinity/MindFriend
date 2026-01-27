import Foundation
import WidgetKit

// MARK: - Shared Data Store

/// Manages widget data stored in shared App Group container.
/// Called by main app to update widget data; read by widget extensions.
/// Note: Not Sendable because UserDefaults is not thread-safe. Access from main thread recommended.
public final class SharedDataStore {
    // MARK: - Singleton

    public static let shared = SharedDataStore()

    // MARK: - Properties

    private let suiteName = "group.com.mindfriend.app"
    private let userDefaults: UserDefaults?

    private init() {
        self.userDefaults = UserDefaults(suiteName: suiteName)
    }

    // MARK: - Keys

    private enum Keys {
        static let currentStreak = "widget_current_streak"
        static let todayMood = "widget_today_mood"
        static let todayMoodScore = "widget_today_mood_score"
        static let todayCompletedActivities = "widget_today_completed"
        static let todayGoalActivities = "widget_today_goal"
        static let weekMoods = "widget_week_moods"
        static let lastUpdated = "widget_last_updated"
        static let dailyQuote = "widget_daily_quote"
        static let quickActions = "widget_quick_actions"
        static let userPreferences = "widget_user_preferences"
        static let dailyQuest = "widget_daily_quest"
        // Ambient Wellness Presence keys
        static let wellnessScore = "widget_wellness_score"
        static let wellnessScoreTrend = "widget_wellness_score_trend"
        static let lastBreathingSessionTime = "widget_last_breathing_session_time"
        static let dailyAffirmation = "widget_daily_affirmation"
    }

    // MARK: - Read Methods

    public var currentStreak: Int {
        userDefaults?.integer(forKey: Keys.currentStreak) ?? 0
    }

    public var todayMood: String? {
        userDefaults?.string(forKey: Keys.todayMood)
    }

    public var todayMoodScore: Int? {
        guard let score = userDefaults?.integer(forKey: Keys.todayMoodScore),
              score > 0
        else {
            return nil
        }
        return score
    }

    public var todayCompletedActivities: Int {
        userDefaults?.integer(forKey: Keys.todayCompletedActivities) ?? 0
    }

    public var todayGoalActivities: Int {
        userDefaults?.integer(forKey: Keys.todayGoalActivities) ?? 3
    }

    public var weekMoods: [WidgetDailyMood] {
        guard let data = userDefaults?.data(forKey: Keys.weekMoods),
              let moods = try? JSONDecoder().decode([WidgetDailyMood].self, from: data)
        else {
            return []
        }
        return moods
    }

    public var dailyQuote: WidgetDailyQuote? {
        guard let data = userDefaults?.data(forKey: Keys.dailyQuote),
              let quote = try? JSONDecoder().decode(WidgetDailyQuote.self, from: data)
        else {
            return nil
        }
        return quote
    }

    public var quickActions: [WidgetQuickAction] {
        guard let data = userDefaults?.data(forKey: Keys.quickActions),
              let actions = try? JSONDecoder().decode([WidgetQuickAction].self, from: data)
        else {
            return WidgetQuickAction.defaults
        }
        return actions
    }

    public var dailyQuest: WidgetDailyQuest? {
        guard let data = userDefaults?.data(forKey: Keys.dailyQuest),
              let quest = try? JSONDecoder().decode(WidgetDailyQuest.self, from: data)
        else {
            return nil
        }
        // Only return quest if it's from today
        return quest.isToday ? quest : nil
    }

    public var lastUpdated: Date? {
        userDefaults?.object(forKey: Keys.lastUpdated) as? Date
    }

    /// Current wellness score (0-100)
    public var wellnessScore: Int? {
        guard let score = userDefaults?.integer(forKey: Keys.wellnessScore),
              score > 0
        else {
            return nil
        }
        return score
    }

    /// Wellness score trend: positive means improving, negative means declining
    public var wellnessScoreTrend: Int {
        userDefaults?.integer(forKey: Keys.wellnessScoreTrend) ?? 0
    }

    /// Last breathing exercise session timestamp
    public var lastBreathingSessionTime: Date? {
        userDefaults?.object(forKey: Keys.lastBreathingSessionTime) as? Date
    }

    /// Daily affirmation for widget display
    public var dailyAffirmation: WidgetAffirmation? {
        guard let data = userDefaults?.data(forKey: Keys.dailyAffirmation),
              let affirmation = try? JSONDecoder().decode(WidgetAffirmation.self, from: data)
        else {
            return nil
        }
        return affirmation
    }

    // MARK: - Write Methods

    /// Update current streak (called from main app when quest completed)
    public func updateStreak(_ streak: Int) {
        userDefaults?.set(streak, forKey: Keys.currentStreak)
        updateTimestamp()
        reloadWidgets()
    }

    /// Update today's mood (called from main app or widget intent)
    public func updateTodayMood(_ mood: String?, score: Int?) {
        // Validate mood string - only allow alphanumeric, spaces, and common punctuation
        let sanitizedMood = mood.map { sanitizeString($0, maxLength: 100) }
        userDefaults?.set(sanitizedMood, forKey: Keys.todayMood)
        if let score = score {
            // Clamp score to valid range
            userDefaults?.set(max(0, min(10, score)), forKey: Keys.todayMoodScore)
        } else {
            userDefaults?.removeObject(forKey: Keys.todayMoodScore)
        }
        updateTimestamp()
        reloadWidgets()
    }

    /// Update today's activity progress
    public func updateTodayProgress(completed: Int, goal: Int) {
        userDefaults?.set(completed, forKey: Keys.todayCompletedActivities)
        userDefaults?.set(goal, forKey: Keys.todayGoalActivities)
        updateTimestamp()
        reloadWidgets()
    }

    /// Update week mood history
    public func updateWeekMoods(_ moods: [WidgetDailyMood]) {
        if let data = try? JSONEncoder().encode(moods) {
            userDefaults?.set(data, forKey: Keys.weekMoods)
            updateTimestamp()
            reloadWidgets()
        }
    }

    /// Update daily quote
    public func updateDailyQuote(_ quote: WidgetDailyQuote) {
        if let data = try? JSONEncoder().encode(quote) {
            userDefaults?.set(data, forKey: Keys.dailyQuote)
            updateTimestamp()
            reloadWidgets()
        }
    }

    /// Update quick actions
    public func updateQuickActions(_ actions: [WidgetQuickAction]) {
        if let data = try? JSONEncoder().encode(actions) {
            userDefaults?.set(data, forKey: Keys.quickActions)
            reloadWidgets()
        }
    }

    /// Update daily quest
    public func updateDailyQuest(_ quest: WidgetDailyQuest) {
        if let data = try? JSONEncoder().encode(quest) {
            userDefaults?.set(data, forKey: Keys.dailyQuest)
            updateTimestamp()
            reloadWidgets()
        }
    }

    /// Mark daily quest as completed
    public func markQuestCompleted(questId: String) {
        guard let existingQuest = dailyQuest, existingQuest.id == questId else { return }
        let completedQuest = WidgetDailyQuest(
            id: existingQuest.id,
            title: existingQuest.title,
            description: existingQuest.description,
            category: existingQuest.category,
            xpReward: existingQuest.xpReward,
            isCompleted: true,
            assignedDate: existingQuest.assignedDate
        )
        updateDailyQuest(completedQuest)
    }

    /// Update wellness score and trend
    public func updateWellnessScore(_ score: Int, trend: Int) {
        userDefaults?.set(max(0, min(100, score)), forKey: Keys.wellnessScore)
        userDefaults?.set(trend, forKey: Keys.wellnessScoreTrend)
        updateTimestamp()
        reloadWidgets()
    }

    /// Update last breathing session time
    public func updateLastBreathingSession(_ date: Date = Date()) {
        userDefaults?.set(date, forKey: Keys.lastBreathingSessionTime)
        updateTimestamp()
        reloadWidgets()
    }

    /// Update daily affirmation with input validation
    public func updateDailyAffirmation(_ affirmation: WidgetAffirmation) {
        // Create sanitized version to prevent injection
        let sanitizedAffirmation = WidgetAffirmation(
            text: sanitizeString(affirmation.text, maxLength: 500),
            category: sanitizeString(affirmation.category, maxLength: 50),
            date: affirmation.date
        )

        do {
            let data = try JSONEncoder().encode(sanitizedAffirmation)
            userDefaults?.set(data, forKey: Keys.dailyAffirmation)
            updateTimestamp()
            reloadWidgets()
        } catch {
            // Log encoding error but don't crash
            #if DEBUG
            print("Failed to encode affirmation: \(error)")
            #endif
        }
    }

    // MARK: - Helpers

    /// Sanitize string input to prevent injection attacks
    /// - Parameters:
    ///   - input: Raw string input
    ///   - maxLength: Maximum allowed length
    /// - Returns: Sanitized string with only safe characters
    private func sanitizeString(_ input: String, maxLength: Int) -> String {
        // Allow alphanumeric, spaces, and common punctuation
        let allowedCharacters = CharacterSet.alphanumerics
            .union(.whitespaces)
            .union(CharacterSet(charactersIn: ".,!?'-"))

        let sanitized = input
            .unicodeScalars
            .filter { allowedCharacters.contains($0) }
            .map { Character($0) }

        return String(sanitized.prefix(maxLength))
    }

    private func updateTimestamp() {
        userDefaults?.set(Date(), forKey: Keys.lastUpdated)
    }

    private func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Reload specific widget by kind
    public func reloadWidget(kind: String) {
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }

    /// Clear all widget data (called on user sign-out)
    public func clearAllData() {
        userDefaults?.removeObject(forKey: Keys.currentStreak)
        userDefaults?.removeObject(forKey: Keys.todayMood)
        userDefaults?.removeObject(forKey: Keys.todayMoodScore)
        userDefaults?.removeObject(forKey: Keys.todayCompletedActivities)
        userDefaults?.removeObject(forKey: Keys.todayGoalActivities)
        userDefaults?.removeObject(forKey: Keys.weekMoods)
        userDefaults?.removeObject(forKey: Keys.lastUpdated)
        userDefaults?.removeObject(forKey: Keys.dailyQuote)
        userDefaults?.removeObject(forKey: Keys.quickActions)
        userDefaults?.removeObject(forKey: Keys.userPreferences)
        userDefaults?.removeObject(forKey: Keys.dailyQuest)
        // Clear ambient wellness keys
        userDefaults?.removeObject(forKey: Keys.wellnessScore)
        userDefaults?.removeObject(forKey: Keys.wellnessScoreTrend)
        userDefaults?.removeObject(forKey: Keys.lastBreathingSessionTime)
        userDefaults?.removeObject(forKey: Keys.dailyAffirmation)
        reloadWidgets()
    }
}
