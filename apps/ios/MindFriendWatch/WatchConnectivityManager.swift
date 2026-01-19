import WatchConnectivity
import Foundation
import WidgetKit

// MARK: - Sync Data Types

/// Data that can be synced between iOS and watchOS
public struct WatchSyncData: Codable {
    // User state
    var currentStreak: Int?
    var todayMood: String?
    var todayMoodScore: Int?
    var completedToday: Int?
    var dailyGoal: Int?

    // Quest data
    var questId: String?
    var questTitle: String?
    var questDescription: String?
    var questCategory: String?
    var questXpReward: Int?
    var questIsCompleted: Bool?

    // Timestamps
    var timestamp: TimeInterval?
    var moodTimestamp: TimeInterval?
}

// MARK: - Sync Message Keys

private enum SyncKeys {
    static let syncData = "syncData"
    static let actionType = "actionType"
    static let mood = "mood"
    static let moodScore = "moodScore"
    static let moodTimestamp = "moodTimestamp"
    static let streak = "streak"
    static let questCompleted = "questCompleted"
    static let questId = "questId"
    static let requestSync = "requestSync"
    static let breathingCompleted = "breathingCompleted"
    static let breathingCycles = "breathingCycles"
}

// MARK: - Watch Connectivity Manager

@MainActor
public final class WatchConnectivityManager: NSObject, ObservableObject {
    // MARK: - Singleton

    public static let shared = WatchConnectivityManager()

    // MARK: - Published Properties

    @Published public var isReachable = false
    @Published public var isPaired = false
    @Published public var isWatchAppInstalled = false
    @Published public var lastSyncDate: Date?

    // Synced data
    @Published public var currentStreak: Int = 0
    @Published public var todayMood: String?
    @Published public var todayMoodScore: Int?
    @Published public var completedToday: Int = 0
    @Published public var dailyGoal: Int = 3

    // Quest data
    @Published public var currentQuestId: String?
    @Published public var currentQuestTitle: String?
    @Published public var currentQuestDescription: String?
    @Published public var currentQuestCategory: String?
    @Published public var currentQuestXpReward: Int?
    @Published public var currentQuestIsCompleted: Bool = false

    // MARK: - Private Properties

    private var session: WCSession?

    /// Returns the session if ready for iOS-to-Watch communication
    /// Checks: session exists, activated, paired, watch app installed
    #if os(iOS)
    private var readyiOSSession: WCSession? {
        guard let session = session,
              session.activationState == .activated,
              session.isPaired,
              session.isWatchAppInstalled else {
            return nil
        }
        return session
    }
    #endif

    /// Returns the session if ready for Watch-to-iOS communication
    /// Checks: session exists, activated
    #if os(watchOS)
    private var readyWatchSession: WCSession? {
        guard let session = session,
              session.activationState == .activated else {
            return nil
        }
        return session
    }
    #endif

    // Callbacks for iOS app integration
    public var onMoodReceived: ((String, Int) -> Void)?
    public var onQuestCompleted: ((String) -> Void)?
    public var onBreathingCompleted: ((Int) -> Void)?
    public var onSyncRequested: (() -> Void)?

    // MARK: - Initialization

    override private init() {
        super.init()
    }

    // MARK: - Setup

    /// Call this to start the watch connectivity session
    public func activate() {
        #if os(iOS)
        guard WCSession.isSupported() else {
            print("[WatchConnectivity] WCSession not supported on this device")
            return
        }
        #endif

        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }

    // MARK: - Send Data (iOS to Watch)

    /// Send full sync data to watch
    public func sendSyncData(_ data: WatchSyncData) {
        #if os(iOS)
        guard let session = readyiOSSession else { return }

        var context: [String: Any] = [
            "timestamp": Date().timeIntervalSince1970
        ]

        // Add all available data
        if let streak = data.currentStreak {
            context["streak"] = streak
        }
        if let mood = data.todayMood {
            context["todayMood"] = mood
        }
        if let moodScore = data.todayMoodScore {
            context["todayMoodScore"] = moodScore
        }
        if let completed = data.completedToday {
            context["completedToday"] = completed
        }
        if let goal = data.dailyGoal {
            context["dailyGoal"] = goal
        }

        // Quest data
        if let questId = data.questId {
            context["questId"] = questId
        }
        if let questTitle = data.questTitle {
            context["questTitle"] = questTitle
        }
        if let questDesc = data.questDescription {
            context["questDescription"] = questDesc
        }
        if let questCat = data.questCategory {
            context["questCategory"] = questCat
        }
        if let questXp = data.questXpReward {
            context["questXpReward"] = questXp
        }
        if let questCompleted = data.questIsCompleted {
            context["questIsCompleted"] = questCompleted
        }

        do {
            try session.updateApplicationContext(context)
            print("[WatchConnectivity] Sent sync data to watch")
        } catch {
            print("[WatchConnectivity] Failed to send sync data: \(error)")
        }
        #endif
    }

    /// Send streak update to watch
    public func sendStreak(_ streak: Int) {
        #if os(iOS)
        guard let session = readyiOSSession else { return }

        do {
            try session.updateApplicationContext([
                "streak": streak,
                "timestamp": Date().timeIntervalSince1970
            ])
        } catch {
            print("[WatchConnectivity] Failed to send streak: \(error)")
        }
        #endif
    }

    /// Send daily progress to watch
    public func sendDailyProgress(completed: Int, goal: Int) {
        #if os(iOS)
        guard let session = readyiOSSession else { return }

        do {
            try session.updateApplicationContext([
                "completedToday": completed,
                "dailyGoal": goal,
                "timestamp": Date().timeIntervalSince1970
            ])
        } catch {
            print("[WatchConnectivity] Failed to send daily progress: \(error)")
        }
        #endif
    }

    /// Send mood update to watch (from iOS app)
    public func sendMood(_ mood: String, score: Int) {
        #if os(iOS)
        guard let session = readyiOSSession else { return }

        do {
            try session.updateApplicationContext([
                "todayMood": mood,
                "todayMoodScore": score,
                "moodTimestamp": Date().timeIntervalSince1970,
                "timestamp": Date().timeIntervalSince1970
            ])
        } catch {
            print("[WatchConnectivity] Failed to send mood: \(error)")
        }
        #endif
    }

    /// Send quest data to watch
    public func sendQuest(id: String, title: String, description: String, category: String, xpReward: Int, isCompleted: Bool) {
        #if os(iOS)
        guard let session = readyiOSSession else { return }

        do {
            try session.updateApplicationContext([
                "questId": id,
                "questTitle": title,
                "questDescription": description,
                "questCategory": category,
                "questXpReward": xpReward,
                "questIsCompleted": isCompleted,
                "timestamp": Date().timeIntervalSince1970
            ])
        } catch {
            print("[WatchConnectivity] Failed to send quest: \(error)")
        }
        #endif
    }

    // MARK: - Send Data (Watch to iOS)

    /// Send mood from watch to iOS
    public func sendMoodToPhone(_ mood: String, score: Int) {
        #if os(watchOS)
        guard let session = readyWatchSession else {
            // Store locally and update UserDefaults for complications
            storeMoodLocally(mood, score: score)
            return
        }

        let message: [String: Any] = [
            SyncKeys.actionType: "moodLogged",
            SyncKeys.mood: mood,
            SyncKeys.moodScore: score,
            SyncKeys.moodTimestamp: Date().timeIntervalSince1970
        ]

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { error in
                print("[WatchConnectivity] Failed to send mood: \(error)")
            }
        } else {
            // Use application context for non-reachable state
            do {
                try session.updateApplicationContext(message)
            } catch {
                print("[WatchConnectivity] Failed to send mood via context: \(error)")
            }
        }

        // Also store locally
        storeMoodLocally(mood, score: score)
        #endif
    }

    /// Send quest completion from watch to iOS
    public func sendQuestCompletedToPhone(questId: String) {
        #if os(watchOS)
        guard let session = readyWatchSession else { return }

        let message: [String: Any] = [
            SyncKeys.actionType: "questCompleted",
            SyncKeys.questId: questId
        ]

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { error in
                print("[WatchConnectivity] Failed to send quest completion: \(error)")
            }
        } else {
            do {
                try session.updateApplicationContext(message)
            } catch {
                print("[WatchConnectivity] Failed to send quest completion via context: \(error)")
            }
        }
        #endif
    }

    /// Send breathing exercise completion from watch to iOS
    public func sendBreathingCompletedToPhone(cycles: Int) {
        #if os(watchOS)
        guard let session = readyWatchSession else { return }

        let message: [String: Any] = [
            SyncKeys.actionType: "breathingCompleted",
            SyncKeys.breathingCycles: cycles
        ]

        if session.isReachable {
            session.sendMessage(message, replyHandler: nil) { error in
                print("[WatchConnectivity] Failed to send breathing completion: \(error)")
            }
        }
        #endif
    }

    /// Request sync from iOS app
    public func requestSyncFromPhone() {
        #if os(watchOS)
        guard let session = readyWatchSession, session.isReachable else { return }

        session.sendMessage([SyncKeys.actionType: "requestSync"], replyHandler: nil) { error in
            print("[WatchConnectivity] Failed to request sync: \(error)")
        }
        #endif
    }

    // MARK: - Local Storage (Watch)

    #if os(watchOS)
    private func storeMoodLocally(_ mood: String, score: Int) {
        UserDefaults.standard.set(mood, forKey: "watch_today_mood")
        UserDefaults.standard.set(score, forKey: "watch_today_mood_score")
        UserDefaults.standard.set(Date(), forKey: "watch_mood_date")

        // Reload complications
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func updateLocalDataFromContext(_ context: [String: Any]) {
        if let streak = context["streak"] as? Int {
            self.currentStreak = streak
            UserDefaults.standard.set(streak, forKey: "watch_streak")
        }

        if let mood = context["todayMood"] as? String {
            self.todayMood = mood
            UserDefaults.standard.set(mood, forKey: "watch_today_mood")
        }

        if let moodScore = context["todayMoodScore"] as? Int {
            self.todayMoodScore = moodScore
            UserDefaults.standard.set(moodScore, forKey: "watch_today_mood_score")
        }

        if let completed = context["completedToday"] as? Int {
            self.completedToday = completed
        }

        if let goal = context["dailyGoal"] as? Int {
            self.dailyGoal = goal
        }

        // Quest data
        if let questId = context["questId"] as? String {
            self.currentQuestId = questId
        }
        if let questTitle = context["questTitle"] as? String {
            self.currentQuestTitle = questTitle
        }
        if let questDesc = context["questDescription"] as? String {
            self.currentQuestDescription = questDesc
        }
        if let questCat = context["questCategory"] as? String {
            self.currentQuestCategory = questCat
        }
        if let questXp = context["questXpReward"] as? Int {
            self.currentQuestXpReward = questXp
        }
        if let questCompleted = context["questIsCompleted"] as? Bool {
            self.currentQuestIsCompleted = questCompleted
        }

        self.lastSyncDate = Date()

        // Reload complications
        WidgetCenter.shared.reloadAllTimelines()
    }
    #endif
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.isReachable = session.isReachable

            #if os(iOS)
            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
            #endif

            if activationState == .activated {
                print("[WatchConnectivity] Session activated")
            } else if let error = error {
                print("[WatchConnectivity] Activation failed: \(error)")
            }
        }
    }

    nonisolated public func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            print("[WatchConnectivity] Reachability changed: \(session.isReachable)")
        }
    }

    nonisolated public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            print("[WatchConnectivity] Received application context")

            #if os(watchOS)
            self.updateLocalDataFromContext(applicationContext)
            #endif

            #if os(iOS)
            // Handle data from watch
            if let actionType = applicationContext[SyncKeys.actionType] as? String {
                self.handleWatchAction(actionType, data: applicationContext)
            }
            #endif
        }
    }

    nonisolated public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            print("[WatchConnectivity] Received message: \(message)")

            #if os(iOS)
            if let actionType = message[SyncKeys.actionType] as? String {
                self.handleWatchAction(actionType, data: message)
            }
            #endif
        }
    }

    #if os(iOS)
    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {
        print("[WatchConnectivity] Session became inactive")
    }

    nonisolated public func sessionDidDeactivate(_ session: WCSession) {
        print("[WatchConnectivity] Session deactivated, reactivating...")
        session.activate()
    }

    @MainActor
    private func handleWatchAction(_ actionType: String, data: [String: Any]) {
        switch actionType {
        case "moodLogged":
            if let mood = data[SyncKeys.mood] as? String,
               let score = data[SyncKeys.moodScore] as? Int {
                self.onMoodReceived?(mood, score)
            }

        case "questCompleted":
            if let questId = data[SyncKeys.questId] as? String {
                self.onQuestCompleted?(questId)
            }

        case "breathingCompleted":
            if let cycles = data[SyncKeys.breathingCycles] as? Int {
                self.onBreathingCompleted?(cycles)
            }

        case "requestSync":
            self.onSyncRequested?()

        default:
            break
        }
    }
    #endif

    #if os(watchOS)
    nonisolated public func sessionCompanionAppInstalledDidChange(_ session: WCSession) {
        print("[WatchConnectivity] Companion app installed changed")
    }
    #endif
}
