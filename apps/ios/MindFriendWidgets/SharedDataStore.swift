import Foundation
import WidgetKit

// MARK: - Shared Data Store

/// Manages widget data stored in shared App Group container.
/// Called by main app to update widget data; read by widget extensions.
public final class SharedDataStore: Sendable {
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

    public var lastUpdated: Date? {
        userDefaults?.object(forKey: Keys.lastUpdated) as? Date
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
        userDefaults?.set(mood, forKey: Keys.todayMood)
        if let score = score {
            userDefaults?.set(score, forKey: Keys.todayMoodScore)
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

    // MARK: - Helpers

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
        reloadWidgets()
    }
}
