import Foundation
import WidgetKit

/// Shared data store for widget and app communication via App Group
/// Uses UserDefaults with a shared App Group suite for cross-process data sharing
public final class SharedDataStore: Sendable {
    public static let shared = SharedDataStore()

    private let suiteName = "group.com.mindfriend.app"
    private let userDefaults: UserDefaults?

    private init() {
        self.userDefaults = UserDefaults(suiteName: suiteName)
    }

    // MARK: - Widget Data Keys

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
        static let userName = "widget_user_name"
    }

    // MARK: - Read Methods

    public var currentStreak: Int {
        userDefaults?.integer(forKey: Keys.currentStreak) ?? 0
    }

    public var todayMood: String? {
        userDefaults?.string(forKey: Keys.todayMood)
    }

    public var todayMoodScore: Int? {
        let score = userDefaults?.integer(forKey: Keys.todayMoodScore) ?? 0
        return score == 0 ? nil : score
    }

    public var todayCompletedActivities: Int {
        userDefaults?.integer(forKey: Keys.todayCompletedActivities) ?? 0
    }

    public var todayGoalActivities: Int {
        let goal = userDefaults?.integer(forKey: Keys.todayGoalActivities) ?? 0
        return goal > 0 ? goal : 3 // Default to 3 activities
    }

    public var weekMoods: [WidgetDailyMood] {
        guard let data = userDefaults?.data(forKey: Keys.weekMoods),
              let moods = try? JSONDecoder().decode([WidgetDailyMood].self, from: data) else {
            return []
        }
        return moods
    }

    public var dailyQuote: WidgetDailyQuote? {
        guard let data = userDefaults?.data(forKey: Keys.dailyQuote),
              let quote = try? JSONDecoder().decode(WidgetDailyQuote.self, from: data) else {
            return nil
        }
        return quote
    }

    public var quickActions: [WidgetQuickAction] {
        guard let data = userDefaults?.data(forKey: Keys.quickActions),
              let actions = try? JSONDecoder().decode([WidgetQuickAction].self, from: data) else {
            return WidgetQuickAction.defaults
        }
        return actions
    }

    public var lastUpdated: Date? {
        userDefaults?.object(forKey: Keys.lastUpdated) as? Date
    }

    public var userName: String? {
        userDefaults?.string(forKey: Keys.userName)
    }

    // MARK: - Write Methods (Called from main app)

    public func updateStreak(_ streak: Int) {
        userDefaults?.set(streak, forKey: Keys.currentStreak)
        updateTimestamp()
        reloadWidgets()
    }

    public func updateTodayMood(_ mood: String?, score: Int?) {
        userDefaults?.set(mood, forKey: Keys.todayMood)
        if let score = score {
            userDefaults?.set(score, forKey: Keys.todayMoodScore)
        } else {
            userDefaults?.removeObject(forKey: Keys.todayMoodScore)
        }
        updateTimestamp()
        reloadWidgets()
    }

    public func updateTodayProgress(completed: Int, goal: Int) {
        userDefaults?.set(completed, forKey: Keys.todayCompletedActivities)
        userDefaults?.set(goal, forKey: Keys.todayGoalActivities)
        updateTimestamp()
        reloadWidgets()
    }

    public func updateWeekMoods(_ moods: [WidgetDailyMood]) {
        if let data = try? JSONEncoder().encode(moods) {
            userDefaults?.set(data, forKey: Keys.weekMoods)
            updateTimestamp()
            reloadWidgets()
        }
    }

    public func updateDailyQuote(_ quote: WidgetDailyQuote) {
        if let data = try? JSONEncoder().encode(quote) {
            userDefaults?.set(data, forKey: Keys.dailyQuote)
            updateTimestamp()
            reloadWidgets()
        }
    }

    public func updateQuickActions(_ actions: [WidgetQuickAction]) {
        if let data = try? JSONEncoder().encode(actions) {
            userDefaults?.set(data, forKey: Keys.quickActions)
            reloadWidgets()
        }
    }

    public func updateUserName(_ name: String?) {
        userDefaults?.set(name, forKey: Keys.userName)
        reloadWidgets()
    }

    /// Sync all widget data from app state
    public func syncFromAppState(
        streak: Int,
        todayMood: String?,
        todayMoodScore: Int?,
        completedActivities: Int,
        goalActivities: Int,
        userName: String?
    ) {
        userDefaults?.set(streak, forKey: Keys.currentStreak)
        userDefaults?.set(todayMood, forKey: Keys.todayMood)
        if let score = todayMoodScore {
            userDefaults?.set(score, forKey: Keys.todayMoodScore)
        }
        userDefaults?.set(completedActivities, forKey: Keys.todayCompletedActivities)
        userDefaults?.set(goalActivities, forKey: Keys.todayGoalActivities)
        userDefaults?.set(userName, forKey: Keys.userName)
        updateTimestamp()
        reloadWidgets()
    }

    // MARK: - Helpers

    private func updateTimestamp() {
        userDefaults?.set(Date(), forKey: Keys.lastUpdated)
    }

    private func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    public func reloadSpecificWidget(kind: String) {
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }
}
