import WatchConnectivity
import Foundation
import Combine
import WidgetKit

enum WatchAppConstants {
    static let appGroupSuite = "group.com.mindfriend.app"
    static var sharedDefaults: UserDefaults { UserDefaults(suiteName: appGroupSuite) ?? .standard }
}

/// Context is replaceable state. Actions and receipts use the durable transfer queue instead.
struct CompanionContext: Codable {
    let ownerID: UUID?
    let snapshot: WidgetSnapshot?
}

@MainActor
public final class WatchConnectivityManager: NSObject, ObservableObject {
    public static let shared = WatchConnectivityManager()
    @Published public private(set) var isReachable = false
    @Published public private(set) var isPaired = false
    @Published public private(set) var isWatchAppInstalled = false
    @Published public private(set) var lastSyncDate: Date?
    @Published public private(set) var currentStreak = 0
    @Published public private(set) var todayMood: String?
    @Published public private(set) var todayMoodScore: Int?
    @Published public private(set) var completedToday = 0
    @Published public private(set) var dailyGoal = 3
    @Published public private(set) var currentQuestId: String?
    @Published public private(set) var currentQuestTitle: String?
    @Published public private(set) var currentQuestDescription: String?
    @Published public private(set) var currentQuestCategory: String?
    @Published public private(set) var currentQuestXpReward: Int?
    @Published public private(set) var currentQuestIsCompleted = false
    @Published public private(set) var actionStatus: String?

    private var session: WCSession?
    private let store = SharedDataStore.shared
    private var pendingContext: CompanionContext?
    var onActionReceived: ((CompanionAction) async -> CompanionActionReceipt?)?
    var onSyncRequested: (() -> Void)?

    override private init() { super.init() }

    public func activate() {
        guard WCSession.isSupported() else { return }
        if session == nil {
            session = WCSession.default
            session?.delegate = self
        }
        if session?.activationState != .activated { session?.activate() }
        #if os(watchOS)
        applySnapshot(store.snapshot())
        #endif
    }

    /// Retain the latest complete state before activation, including explicit sign-out clears.
    func publish(ownerID: UUID?, snapshot: WidgetSnapshot?) {
        pendingContext = CompanionContext(ownerID: ownerID, snapshot: snapshot)
        flushContext()
    }

    private func flushContext() {
        #if os(iOS)
        guard let session, session.activationState == .activated, session.isPaired,
              session.isWatchAppInstalled, let pendingContext,
              let encoded = try? JSONEncoder().encode(pendingContext) else { return }
        do { try session.updateApplicationContext(["companionContext": encoded]) }
        catch { /* Keep the context for the next activation, foreground, or sync request. */ }
        #endif
    }

    private func sendReceipt(_ receipt: CompanionActionReceipt) {
        #if os(iOS)
        guard let session, session.activationState == .activated,
              let data = try? JSONEncoder().encode(receipt) else { return }
        session.transferUserInfo(["companionReceipt": data])
        #endif
    }

    public func sendMoodToPhone(_ mood: String, score: Int) throws {
        #if os(watchOS)
        try enqueue(kind: .mood, score: score)
        #endif
    }

    public func sendQuestCompletedToPhone(questId: String) throws {
        #if os(watchOS)
        _ = try store.queueQuest(questID: questId)
        actionStatus = "Waiting to sync with iPhone"
        flushActions()
        #endif
    }

    public func sendBreathingCompletedToPhone(cycles: Int) throws {
        #if os(watchOS)
        try enqueue(kind: .breathing, cycles: cycles)
        #endif
    }

    #if os(watchOS)
    private func enqueue(kind: CompanionAction.Kind, score: Int? = nil, cycles: Int? = nil) throws {
        guard let owner = store.activeOwnerID else { throw SharedDataStore.StoreError.signInRequired }
        let action = CompanionAction(ownerID: owner, kind: kind, moodScore: score, breathingCycles: cycles)
        try store.storePending(action)
        actionStatus = "Waiting to sync with iPhone"
        flushActions()
    }

    private func flushActions() {
        guard let session, session.activationState == .activated,
              let owner = store.activeOwnerID, let pending = try? store.pendingActions(for: owner) else { return }
        let alreadyQueued = Set(session.outstandingUserInfoTransfers.compactMap {
            ($0.userInfo["companionAction"] as? Data).flatMap { try? JSONDecoder().decode(CompanionAction.self, from: $0).id }
        })
        for action in pending where !alreadyQueued.contains(action.id) {
            guard let data = try? JSONEncoder().encode(action) else { continue }
            session.transferUserInfo(["companionAction": data])
        }
    }

    private func applySnapshot(_ snapshot: WidgetSnapshot?) {
        currentStreak = snapshot?.currentStreak ?? 0
        todayMood = snapshot?.todayMood
        todayMoodScore = snapshot?.todayMoodScore
        completedToday = snapshot?.completedActivities ?? 0
        dailyGoal = snapshot?.goalActivities ?? 3
        currentQuestId = snapshot?.dailyQuest?.id
        currentQuestTitle = snapshot?.dailyQuest?.title
        currentQuestDescription = snapshot?.dailyQuest?.description
        currentQuestCategory = snapshot?.dailyQuest?.category
        currentQuestXpReward = snapshot?.dailyQuest?.xpReward
        currentQuestIsCompleted = snapshot?.dailyQuest?.isCompleted ?? false
        lastSyncDate = snapshot?.updatedAt
        WidgetCenter.shared.reloadAllTimelines()
    }
    #endif

    public func requestSyncFromPhone() {
        #if os(watchOS)
        applySnapshot(store.snapshot())
        flushActions()
        guard let session, session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(["requestSync": true], replyHandler: nil)
        #endif
    }

    private func receive(_ message: [String: Any]) async {
        #if os(iOS)
        if let data = message["companionAction"] as? Data,
           let action = try? JSONDecoder().decode(CompanionAction.self, from: data), action.isValid {
            // Store before invoking services, including while signed out or during account replacement.
            guard (try? store.storePending(action)) != nil else { return }
            if let receipt = await onActionReceived?(action) { sendReceipt(receipt) }
        }
        if message["requestSync"] as? Bool == true { onSyncRequested?() }
        #endif
        #if os(watchOS)
        if let data = message["companionContext"] as? Data,
           let context = try? JSONDecoder().decode(CompanionContext.self, from: data) {
            if store.activeOwnerID != context.ownerID {
                store.reset(to: context.ownerID)
                actionStatus = nil
            }
            if let snapshot = context.snapshot, snapshot.ownerID == context.ownerID {
                _ = try? store.publish(snapshot)
            } else { store.reset(to: context.ownerID) }
            applySnapshot(store.snapshot())
            flushActions()
        }
        if let data = message["companionReceipt"] as? Data,
           let receipt = try? JSONDecoder().decode(CompanionActionReceipt.self, from: data) {
            do {
                try store.acknowledge(receipt)
                if receipt.ownerID == store.activeOwnerID {
                    actionStatus = receipt.status == .applied ? "Synced with iPhone" : "Synced; kept your existing check-in"
                    requestSyncFromPhone()
                }
            } catch { /* An unconfirmed local record remains available to retry. */ }
        }
        #endif
    }

    /// Called after a foreground/background retry confirms an action that originated on the Watch.
    func acknowledgeOnWatch(_ receipt: CompanionActionReceipt) { sendReceipt(receipt) }
}

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            #if os(iOS)
            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
            #endif
            guard activationState == .activated else { return }
            #if os(iOS)
            self.flushContext()
            self.onSyncRequested?()
            #endif
            #if os(watchOS)
            await self.receive(session.receivedApplicationContext)
            self.requestSyncFromPhone()
            #endif
        }
    }

    nonisolated public func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            #if os(iOS)
            self.flushContext()
            self.onSyncRequested?()
            #endif
            #if os(watchOS)
            self.requestSyncFromPhone()
            #endif
        }
    }

    nonisolated public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in await self.receive(applicationContext) }
    }
    nonisolated public func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in await self.receive(message) }
    }
    nonisolated public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in await self.receive(userInfo) }
    }
    #if os(iOS)
    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated public func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated public func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
            self.flushContext()
        }
    }
    #endif
}

#if os(watchOS)
extension WatchConnectivityManager: ConnectivityProviding {}
#endif

#if os(iOS)
/// Owns authenticated companion work. Identity is checked again after every asynchronous boundary.
@MainActor
final class CompanionSyncCoordinator {
    static let shared = CompanionSyncCoordinator()
    private let store = SharedDataStore.shared
    private let watch = WatchConnectivityManager.shared
    private var ownerID: UUID?
    private var generation = UUID()
    private var dataService: SupabaseDataService?
    private var authService: SupabaseAuthService?
    private var refreshTask: Task<Void, Never>?
    private var needsRefresh = false
    private var observers: [NSObjectProtocol] = []

    private init() {
        watch.onActionReceived = { [weak self] action in
            guard let self else { return nil }
            let receipt = await self.submit(action)
            await self.refresh()
            return receipt
        }
        watch.onSyncRequested = { [weak self] in Task { @MainActor in await self?.refresh() } }
        for name in [Notification.Name.wellbeingDebtSourcesDidChange, .NSCalendarDayChanged, .NSSystemTimeZoneDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.refresh() }
            })
        }
        // A widget may enqueue after the app's foreground refresh has already started.
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), nil, { _, _, _, _, _ in
            Task { @MainActor in await CompanionSyncCoordinator.shared.refresh() }
        }, SharedDataStore.actionNotification as CFString, nil, .deliverImmediately)
        watch.activate()
    }

    func reset(to ownerID: UUID?) {
        generation = UUID()
        refreshTask?.cancel()
        refreshTask = nil
        needsRefresh = false
        self.ownerID = ownerID
        dataService = nil
        authService = nil
        store.reset(to: ownerID)
        watch.publish(ownerID: ownerID, snapshot: nil)
    }

    func start(userId: UUID, dataService: SupabaseDataService, authService: SupabaseAuthService) async {
        if ownerID != userId { reset(to: userId) }
        self.dataService = dataService
        self.authService = authService
        watch.activate()
        await refresh()
    }

    private func isCurrent(_ owner: UUID, _ token: UUID) -> Bool {
        generation == token && ownerID == owner && authService?.currentUser?.id == owner && !Task.isCancelled
    }

    private func submit(_ action: CompanionAction) async -> CompanionActionReceipt? {
        guard let owner = ownerID, action.ownerID == owner, let dataService else { return nil }
        let token = generation
        guard isCurrent(owner, token) else { return nil }
        do {
            let receipt = try await dataService.ingestCompanionAction(action)
            guard isCurrent(owner, token), receipt.ownerID == action.ownerID, receipt.eventID == action.id else { return nil }
            try store.acknowledge(receipt)
            return receipt
        } catch { return nil } // The original event remains durable until an exact receipt is obtained.
    }

    func refresh() async {
        guard let owner = ownerID, let dataService, let authService else { return }
        if let refreshTask {
            needsRefresh = true
            await refreshTask.value
            return
        }
        let token = generation
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            repeat {
                self.needsRefresh = false
                guard self.isCurrent(owner, token) else { return }
                if let actions = try? self.store.pendingActions(for: owner) {
                    for action in actions {
                        guard self.isCurrent(owner, token) else { return }
                        if let receipt = await self.submit(action) { self.watch.acknowledgeOnWatch(receipt) }
                    }
                }
                await self.publishSnapshot(owner: owner, token: token, dataService: dataService, authService: authService)
            } while self.needsRefresh && self.isCurrent(owner, token)
        }
        refreshTask = task
        await task.value
        if generation == token { refreshTask = nil }
    }

    private func publishSnapshot(owner: UUID, token: UUID, dataService: SupabaseDataService, authService: SupabaseAuthService) async {
        let now = Date()
        let calendar = Calendar.current
        let day = WidgetSnapshot.dayLabel(for: now, calendar: calendar)
        let from = WidgetSnapshot.dayLabel(for: calendar.date(byAdding: .day, value: -6, to: now) ?? now, calendar: calendar)
        do {
            async let profileResult = authService.fetchProfile()
            async let moodsResult = dataService.getMoods(from: from, to: day)
            async let questResult = dataService.getTodayQuest()
            async let summaryResult = dataService.getCompanionDaySummary(localDate: day, timeZone: calendar.timeZone.identifier)
            let (profile, moods, quest, summary) = try await (profileResult, moodsResult, questResult, summaryResult)
            guard isCurrent(owner, token), profile.id == owner,
                  day == WidgetSnapshot.dayLabel(for: Date()) else { return }
            var snapshot = WidgetSnapshot(ownerID: owner, localDate: day)
            snapshot.currentStreak = profile.stats?.currentStreakDays ?? 0
            snapshot.userName = profile.displayName ?? profile.handle
            let mood = moods.first { $0.localDate == day }
            snapshot.todayMoodScore = mood?.moodScore
            snapshot.todayMood = mood.map { WidgetMoodHelper.mood(for: $0.moodScore) }
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            snapshot.weekMoods = moods.compactMap { entry in
                guard let date = formatter.date(from: entry.localDate) else { return nil }
                return WidgetDailyMood(date: date, mood: WidgetMoodHelper.mood(for: entry.moodScore), score: entry.moodScore)
            }
            if let quest, quest.localDate == day {
                snapshot.dailyQuest = WidgetDailyQuest(id: quest.id, title: quest.template.title,
                    description: quest.template.description, category: quest.template.type.rawValue,
                    xpReward: 0, isCompleted: quest.status == .completed, assignedDate: now)
            }
            snapshot.completedActivities = (mood == nil ? 0 : 1) + (snapshot.dailyQuest?.isCompleted == true ? 1 : 0) + (summary.breathingCount > 0 || summary.todayExerciseCount > 0 ? 1 : 0)
            snapshot.lastBreathingSessionTime = summary.lastBreathingAt
            snapshot.weeklyExercisesCompleted = summary.weeklyExerciseCount
            if try store.publish(snapshot) { watch.publish(ownerID: owner, snapshot: snapshot) }
        } catch { /* Keep a same-day confirmed snapshot; failed fetches never fabricate a replacement. */ }
    }
}
#endif
