import Foundation
import WidgetKit

/// The app publishes confirmed snapshots; extensions append independent pending action files.
/// Keeping each action in its own file prevents an app acknowledgment from overwriting a new widget tap.
public final class SharedDataStore: Sendable {
    public static let shared = SharedDataStore()
    private nonisolated(unsafe) let userDefaults: UserDefaults?
    private let actionDirectory: URL?
    private let notifyChanges: Bool
    static let actionNotification = "com.mindfriend.companion-actions"

    private enum Keys {
        static let owner = "companion_active_owner_v1"
        static let snapshot = "companion_snapshot_v1"
    }

    public enum StoreError: LocalizedError {
        case unavailable, signInRequired, invalidAction, conflictingAction
        public var errorDescription: String? {
            switch self {
            case .unavailable: return "This action could not be saved. Open MindFriend and try again."
            case .signInRequired: return "Open MindFriend to sign in and refresh your widgets."
            case .invalidAction: return "This action is no longer available. Open MindFriend to refresh."
            case .conflictingAction: return "This action has conflicting saved details. Open MindFriend to continue."
            }
        }
    }

    private convenience init() {
        self.init(userDefaults: UserDefaults(suiteName: "group.com.mindfriend.app"),
                  actionDirectory: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.mindfriend.app")?
                    .appendingPathComponent("CompanionActions", isDirectory: true), notifyChanges: true)
    }

    init(userDefaults: UserDefaults?, actionDirectory: URL?, notifyChanges: Bool = false) {
        self.userDefaults = userDefaults
        self.actionDirectory = actionDirectory
        self.notifyChanges = notifyChanges
    }

    public var activeOwnerID: UUID? {
        userDefaults?.string(forKey: Keys.owner).flatMap(UUID.init(uuidString:))
    }

    /// Clear visible data immediately at identity changes; pending actions retain their original owner.
    public func reset(to ownerID: UUID?) {
        userDefaults?.removeObject(forKey: Keys.snapshot)
        if let ownerID { userDefaults?.set(ownerID.uuidString, forKey: Keys.owner) }
        else { userDefaults?.removeObject(forKey: Keys.owner) }
        // Legacy keys have no reliable account identity and cannot be shown after the upgrade.
        for key in ["widget_current_streak", "widget_today_mood", "widget_today_mood_score", "widget_today_completed",
                    "widget_today_goal", "widget_week_moods", "widget_last_updated", "widget_daily_quote", "widget_daily_quest",
                    "widget_quick_actions", "widget_user_preferences", "widget_user_name", "widget_wellness_score",
                    "widget_wellness_score_trend", "widget_last_breathing_session_time", "widget_daily_affirmation"] {
            userDefaults?.removeObject(forKey: key)
        }
        reloadWidgets()
    }

    public func snapshot(at now: Date = Date(), calendar: Calendar = .current) -> WidgetSnapshot? {
        guard let owner = activeOwnerID, let data = userDefaults?.data(forKey: Keys.snapshot),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data),
              snapshot.ownerID == owner,
              snapshot.localDate == WidgetSnapshot.dayLabel(for: now, calendar: calendar) else { return nil }
        return snapshot
    }

    @discardableResult
    public func publish(_ snapshot: WidgetSnapshot) throws -> Bool {
        guard snapshot.ownerID == activeOwnerID, userDefaults != nil else { return false }
        userDefaults?.set(try JSONEncoder().encode(snapshot), forKey: Keys.snapshot)
        reloadWidgets()
        return true
    }

    public var currentStreak: Int { snapshot()?.currentStreak ?? 0 }
    public var todayMood: String? { snapshot()?.todayMood }
    public var todayMoodScore: Int? { snapshot()?.todayMoodScore }
    public var todayCompletedActivities: Int { snapshot()?.completedActivities ?? 0 }
    public var todayGoalActivities: Int { snapshot()?.goalActivities ?? 3 }
    public var weekMoods: [WidgetDailyMood] { snapshot()?.weekMoods ?? [] }
    public var dailyQuote: WidgetDailyQuote? { snapshot()?.dailyQuote }
    public var dailyQuest: WidgetDailyQuest? { snapshot()?.dailyQuest }
    public var quickActions: [WidgetQuickAction] { snapshot()?.quickActions ?? WidgetQuickAction.defaults }
    public var lastUpdated: Date? { snapshot()?.updatedAt }
    public var userName: String? { snapshot()?.userName }
    public var wellnessScore: Int? { snapshot()?.wellnessScore }
    public var wellnessScoreTrend: Int { snapshot()?.wellnessScoreTrend ?? 0 }
    public var lastBreathingSessionTime: Date? { snapshot()?.lastBreathingSessionTime }
    public var dailyAffirmation: WidgetAffirmation? { snapshot()?.dailyAffirmation }

    @discardableResult
    public func queueMood(score: Int, now: Date = Date(), calendar: Calendar = .current) throws -> CompanionAction {
        guard let snapshot = snapshot(at: now, calendar: calendar) else { throw StoreError.signInRequired }
        let action = CompanionAction(ownerID: snapshot.ownerID, kind: .mood, observedAt: now, calendar: calendar, moodScore: score)
        try storePending(action)
        return action
    }

    @discardableResult
    public func queueQuest(questID: String, now: Date = Date(), calendar: Calendar = .current) throws -> CompanionAction {
        guard let snapshot = snapshot(at: now, calendar: calendar) else { throw StoreError.signInRequired }
        guard let id = UUID(uuidString: questID), snapshot.dailyQuest?.id == questID,
              snapshot.dailyQuest?.isCompleted == false else { throw StoreError.invalidAction }
        let action = CompanionAction(ownerID: snapshot.ownerID, kind: .quest, observedAt: now, calendar: calendar, questID: id)
        try storePending(action)
        return action
    }

    /// Also used when a paired Watch delivers an action for an account that is currently signed out.
    public func storePending(_ action: CompanionAction) throws {
        guard action.isValid else { throw StoreError.invalidAction }
        let url = try actionURL(ownerID: action.ownerID, eventID: action.id)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let existing = try? Data(contentsOf: url) {
            guard try JSONDecoder().decode(CompanionAction.self, from: existing) == action else { throw StoreError.conflictingAction }
            return
        }
        try JSONEncoder().encode(action).write(to: url, options: .atomic)
        reloadWidgets()
        if notifyChanges {
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                CFNotificationName(Self.actionNotification as CFString), nil, nil, true)
        }
    }

    public func pendingActions(for ownerID: UUID) throws -> [CompanionAction] {
        guard let directory = actionDirectory?.appendingPathComponent(ownerID.uuidString, isDirectory: true) else { throw StoreError.unavailable }
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> CompanionAction? in
                guard let action = try? JSONDecoder().decode(CompanionAction.self, from: Data(contentsOf: url)),
                      action.ownerID == ownerID, action.id.uuidString == url.deletingPathExtension().lastPathComponent,
                      action.isValid else { return nil }
                return action
            }
            .sorted { $0.observedAt == $1.observedAt ? $0.id.uuidString < $1.id.uuidString : $0.observedAt < $1.observedAt }
    }

    public func acknowledge(_ receipt: CompanionActionReceipt) throws {
        let url = try actionURL(ownerID: receipt.ownerID, eventID: receipt.eventID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let action = try JSONDecoder().decode(CompanionAction.self, from: Data(contentsOf: url))
        guard action.id == receipt.eventID, action.ownerID == receipt.ownerID else { throw StoreError.invalidAction }
        try FileManager.default.removeItem(at: url)
        reloadWidgets()
    }

    public var pendingMood: CompanionAction? {
        guard let owner = activeOwnerID else { return nil }
        let day = WidgetSnapshot.dayLabel(for: Date())
        return (try? pendingActions(for: owner))?.last { $0.kind == .mood && $0.localDate == day }
    }

    public func isQuestPending(_ questID: String) -> Bool {
        guard let owner = activeOwnerID else { return false }
        return (try? pendingActions(for: owner))?.contains { $0.kind == .quest && $0.questID?.uuidString.lowercased() == questID.lowercased() } == true
    }

    private func actionURL(ownerID: UUID, eventID: UUID) throws -> URL {
        guard let actionDirectory else { throw StoreError.unavailable }
        return actionDirectory.appendingPathComponent(ownerID.uuidString, isDirectory: true)
            .appendingPathComponent(eventID.uuidString).appendingPathExtension("json")
    }

    private func reloadWidgets() { WidgetCenter.shared.reloadAllTimelines() }
    public func reloadSpecificWidget(kind: String) { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
}
