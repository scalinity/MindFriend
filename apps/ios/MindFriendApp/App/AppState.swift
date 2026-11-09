import SwiftUI
import Combine

/// Authentication state of the app
enum AuthState: Equatable {
    case unknown
    case unauthenticated
    case onboarding
    case authenticated
}

/// Global app state observable
@MainActor
final class AppState: ObservableObject {
    // MARK: - Auth State
    @Published var authState: AuthState = .unknown
    @Published var currentUser: UserProfile?
    @Published private(set) var accountEpoch: UInt64 = 0

    /// Whether the initial auth check has completed
    @Published var hasCompletedInitialAuth: Bool = false

    /// Whether we're using cached data (before network verification)
    @Published var isUsingCachedData: Bool = false

    /// Whether the Supabase session has been restored (safe to make edge function calls)
    @Published var sessionRestored: Bool = false

    var authenticatedAccountID: UUID? {
        guard authState == .authenticated, sessionRestored, !isUsingCachedData else { return nil }
        return currentUser?.id
    }

    // MARK: - Entitlements
    @Published private(set) var entitlementSnapshot: EntitlementSnapshot?
    var entitlements: Entitlements { entitlementSnapshot?.legacy ?? .free }

    // MARK: - Today's Data
    @Published var todayQuest: Quest?
    @Published var todayMood: MoodEntry?
    @Published var todayActionPlan: ActionPlan?
    @Published var todayActionPlanItems: [ActionPlanItem] = []
    @Published var currentStreak: Int = 0

    // MARK: - Navigation
    @Published var selectedTab: MainTab = .home
    @Published var showPaywall: Bool = false
    @Published var showCrisisResources: Bool = false
    @Published var shouldOpenNewChat: Bool = false  // Triggers new chat from SOS or other flows

    // MARK: - Level Up Celebration
    @Published var showLevelUp: Bool = false
    @Published var levelUpLevel: Int = 0
    @Published var levelUpTitle: String = ""

    // MARK: - Re-engagement
    @Published var showWelcomeBack: Bool = false
    @Published var absenceSummary: AbsenceSummary?

    // MARK: - Celebrations
    @Published var pendingCelebrations: [CelebrationEvent] = []

    // MARK: - Error Handling
    @Published var globalError: AppError?
    @Published var showError: Bool = false

    // MARK: - Methods

    /// Retry account-bound storage with a fresh lifecycle after a partial startup failure.
    func retryAccountScope() { accountEpoch &+= 1 }

    func setAuthenticated(user: UserProfile) {
        if currentUser?.id != user.id { accountEpoch &+= 1; entitlementSnapshot = nil; pendingCelebrations = [] }
        self.currentUser = user
        refreshProfileEntitlements(user, cached: false)
        self.authState = user.needsOnboarding ? .onboarding : .authenticated
        self.hasCompletedInitialAuth = true
        self.isUsingCachedData = false
        self.sessionRestored = true
    }

    /// Set authenticated state with cached data (before network verification)
    func setAuthenticatedFromCache(user: UserProfile) {
        if currentUser?.id != user.id { accountEpoch &+= 1; entitlementSnapshot = nil; pendingCelebrations = [] }
        self.currentUser = user
        refreshProfileEntitlements(user, cached: true)
        self.authState = user.needsOnboarding ? .onboarding : .authenticated
        self.isUsingCachedData = true
        // Don't set hasCompletedInitialAuth - that's for after network verification
    }

    func setUnauthenticated() {
        if currentUser != nil { accountEpoch &+= 1 }
        self.currentUser = nil
        self.entitlementSnapshot = nil
        self.pendingCelebrations = []
        self.todayQuest = nil
        self.todayMood = nil
        self.todayActionPlan = nil
        self.todayActionPlanItems = []
        self.currentStreak = 0
        self.authState = .unauthenticated
        self.hasCompletedInitialAuth = true
        self.isUsingCachedData = false
        self.sessionRestored = false
    }

    func requireOnboarding() {
        self.authState = .onboarding
    }

    func completeOnboarding(user: UserProfile) {
        setAuthenticated(user: user)
    }

    func showError(_ error: AppError) {
        self.globalError = error
        self.showError = true
    }

    func refreshProfileEntitlements(_ profile: UserProfile, cached: Bool = false) {
        guard currentUser?.id == profile.id else { return }
        let values = profile.entitlements
        let expired = values?.premiumExpiresAt.map { $0 <= Date() } ?? false
        let tier: Tier = !expired && ["premium", "sponsored"].contains(values?.subscriptionTier ?? "") ? .premium : .free
        mergeEntitlements(ownerID: profile.id, tier: tier, usage: values?.dailyAiUsed,
                          quota: values?.dailyAiQuota, period: values?.quotaPeriodStartedAt,
                          verifiedAt: values?.verifiedAt, source: cached ? .cachedProfile : .serverProfile)
    }

    func updateEntitlements(_ values: Entitlements) {
        guard let ownerID = currentUser?.id else { return }
        // Legacy constants describe tier only, and never provide quota evidence.
        mergeEntitlements(ownerID: ownerID, tier: values.tier,
                          usage: values.verifiedAt == nil ? nil : values.dailyAiUsed,
                          quota: values.verifiedAt == nil ? nil : values.dailyAiQuota,
                          period: values.quotaPeriodStartedAt, verifiedAt: values.verifiedAt,
                          source: .serverBilling)
    }

    /// A chat receipt reports usage for the server day it was counted in. A receipt can
    /// arrive after that day ends, or be replayed later, so only the server's day moves the
    /// quota period, and only when the receipt carries usage.
    func recordChatQuota(ownerID: UUID, used: Int?, limit: Int?, countedOn day: String?) {
        guard currentUser?.id == ownerID else { return }
        let period = used == nil ? nil : EntitlementSnapshot.serverDay(reported: day)
        mergeEntitlements(ownerID: ownerID, tier: entitlements.tier, usage: used, quota: limit,
                          period: period, verifiedAt: Date(), source: .chatReceipt)
    }

    /// The server's count shows no free messages left until its next reset.
    var isOutOfFreeMessages: Bool {
        entitlements.tier != .premium && entitlementSnapshot?.remaining == 0
    }

    private func mergeEntitlements(ownerID: UUID, tier: Tier, usage: Int?, quota: Int?,
                                   period: Date?, verifiedAt: Date?, source: EntitlementSnapshot.Source) {
        guard currentUser?.id == ownerID else { return }
        var snapshot = entitlementSnapshot ?? EntitlementSnapshot(
            ownerID: ownerID, tier: tier, source: source, verifiedAt: nil,
            usage: nil, quota: nil, quotaPeriodStartedAt: nil)
        snapshot.merge(tier: tier, usage: usage, quota: quota, period: period, verifiedAt: verifiedAt, source: source)
        entitlementSnapshot = snapshot
    }

    func showLevelUpCelebration(level: Int, title: String) {
        self.levelUpLevel = level
        self.levelUpTitle = title
        self.showLevelUp = true
    }

    func dismissLevelUp() {
        self.showLevelUp = false
    }

    func showWelcomeBackModal(summary: AbsenceSummary) {
        self.absenceSummary = summary
        self.showWelcomeBack = true
    }

    func dismissWelcomeBack() {
        self.showWelcomeBack = false
        // Keep absenceSummary for AI context until next session
    }

    // MARK: - Simple Celebration Toast
    @Published var celebrationTitle: String = ""
    @Published var celebrationSubtitle: String = ""
    @Published var celebrationIcon: String = ""
    @Published var showSimpleCelebration: Bool = false

    func showCelebration(title: String, subtitle: String, icon: String) {
        self.celebrationTitle = title
        self.celebrationSubtitle = subtitle
        self.celebrationIcon = icon
        self.showSimpleCelebration = true
    }

    // MARK: - Completion moments

    @Published var completionMoment: CompletionMoment?

    /// One calm acknowledgement after a durable save. Standard moments add the spec's single
    /// soft confirmation haptic; soft moments (a mood check-in) have none.
    func celebrateCompletion(_ title: String, soft: Bool = false) {
        completionMoment = CompletionMoment(title: title, soft: soft)
        if !soft { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        AccessibilityNotification.Announcement(title).post()
    }

    // MARK: - Celebration Methods

    private let maxPendingCelebrations = 10

    func addCelebrations(_ celebrations: [CelebrationEvent]) {
        // Filter out any that were already shown (have shownAt). Streak milestones stay on the
        // server but are not shown. A response requested by an earlier account is dropped.
        guard let owner = currentUser?.id else { return }
        let newCelebrations = celebrations.filter {
            $0.userId == owner && $0.shownAt == nil && $0.celebrationType != .streakMilestone
        }
        // Limit queue size to prevent memory issues or overwhelming UX
        let spaceAvailable = maxPendingCelebrations - pendingCelebrations.count
        let toAdd = Array(newCelebrations.prefix(max(0, spaceAvailable)))
        self.pendingCelebrations.append(contentsOf: toAdd)
    }

    func removeCelebration(id: UUID) {
        self.pendingCelebrations.removeAll { $0.id == id }
    }

    // MARK: - Widget Sync

    /// Reconcile owner-tagged companion actions and refresh their snapshots.
    func processPendingWidgetSyncs(container: DependencyContainer) async {
        guard let owner = authenticatedAccountID, container.supabaseAuthService.currentUser?.id == owner else { return }
        await CompanionSyncCoordinator.shared.refresh()
    }
}

struct CompletionMoment: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let soft: Bool
}

// MARK: - Main Tab

enum MainTab: String, CaseIterable {
    case home
    case programs
    case chat
    case outcomes
    case circles
    case mentorship
    case sleep
    case personalization
    case profile

    var title: String {
        switch self {
        case .home: return String(localized: "Home")
        case .programs: return String(localized: "Programs")
        case .chat: return String(localized: "Chat")
        case .outcomes: return String(localized: "Progress")
        case .circles: return String(localized: "Circles")
        case .mentorship: return String(localized: "Mentorship")
        case .sleep: return String(localized: "Sleep")
        case .personalization: return String(localized: "For You")
        case .profile: return String(localized: "Profile")
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .programs: return "book.fill"
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .outcomes: return "chart.line.uptrend.xyaxis"
        case .circles: return "person.3.fill"
        case .mentorship: return "star.fill"
        case .sleep: return "moon.fill"
        case .personalization: return "sparkles"
        case .profile: return "person.fill"
        }
    }
}

// MARK: - App Error

struct AppError: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    let isRecoverable: Bool

    static func == (lhs: AppError, rhs: AppError) -> Bool {
        lhs.id == rhs.id
    }

    static let networkError = AppError(
        title: "Connection Error",
        message: "Unable to connect to the server. Please check your internet connection.",
        isRecoverable: true
    )

    static let sessionExpired = AppError(
        title: "Session Expired",
        message: "Your session has expired. Please sign in again.",
        isRecoverable: false
    )

    static func apiError(_ message: String) -> AppError {
        AppError(title: "Error", message: message, isRecoverable: true)
    }
}
