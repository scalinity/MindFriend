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

    /// Whether the initial auth check has completed
    @Published var hasCompletedInitialAuth: Bool = false

    /// Whether we're using cached data (before network verification)
    @Published var isUsingCachedData: Bool = false

    // MARK: - Entitlements
    @Published var entitlements: Entitlements = .free

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

    func setAuthenticated(user: UserProfile) {
        self.currentUser = user
        self.authState = .authenticated
        self.hasCompletedInitialAuth = true
        self.isUsingCachedData = false
    }

    /// Set authenticated state with cached data (before network verification)
    func setAuthenticatedFromCache(user: UserProfile) {
        self.currentUser = user
        self.authState = .authenticated
        self.isUsingCachedData = true
        // Don't set hasCompletedInitialAuth - that's for after network verification
    }

    func setUnauthenticated() {
        self.currentUser = nil
        self.entitlements = .free
        self.todayQuest = nil
        self.todayMood = nil
        self.todayActionPlan = nil
        self.todayActionPlanItems = []
        self.currentStreak = 0
        self.authState = .unauthenticated
        self.hasCompletedInitialAuth = true
        self.isUsingCachedData = false
    }

    func requireOnboarding() {
        self.authState = .onboarding
    }

    func completeOnboarding(user: UserProfile) {
        self.currentUser = user
        self.authState = .authenticated
    }

    func showError(_ error: AppError) {
        self.globalError = error
        self.showError = true
    }

    func updateEntitlements(_ entitlements: Entitlements) {
        self.entitlements = entitlements
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

    // MARK: - Celebration Methods

    private let maxPendingCelebrations = 10

    func addCelebrations(_ celebrations: [CelebrationEvent]) {
        // Filter out any that were already shown (have shownAt)
        let newCelebrations = celebrations.filter { $0.shownAt == nil }
        // Limit queue size to prevent memory issues or overwhelming UX
        let spaceAvailable = maxPendingCelebrations - pendingCelebrations.count
        let toAdd = Array(newCelebrations.prefix(max(0, spaceAvailable)))
        self.pendingCelebrations.append(contentsOf: toAdd)
    }

    func removeCelebration(id: UUID) {
        self.pendingCelebrations.removeAll { $0.id == id }
    }

    // MARK: - Widget Sync

    /// Process pending quest completions made from widgets
    /// Called when app becomes active to sync widget actions to backend
    /// TODO: SharedDataStore not added to Xcode project target
    func processPendingWidgetSyncs(container: DependencyContainer) async {
        // Temporarily disabled - SharedDataStore exists but not in build target
        // let pendingCompletions = SharedDataStore.shared.pendingQuestCompletions
        // guard !pendingCompletions.isEmpty else { return }
        //
        // for questId in pendingCompletions {
        //     do {
        //         // Sync quest completion to backend (widget completions don't include reflection/rating)
        //         try await container.supabaseDataService.completeQuest(id: questId, reflectionNote: nil, rating: nil)
        //         SharedDataStore.shared.clearPendingQuestCompletion(questId: questId)
        //         Log.general.info("[WidgetSync] Synced quest completion: \(questId)")
        //     } catch {
        //         // Keep in pending queue if sync fails - will retry next time
        //         Log.general.error("[WidgetSync] Failed to sync quest completion: \(questId), error: \(error)")
        //     }
        // }
    }
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
        case .home: return "Home"
        case .programs: return "Programs"
        case .chat: return "Chat"
        case .outcomes: return "Progress"
        case .circles: return "Circles"
        case .mentorship: return "Mentorship"
        case .sleep: return "Sleep"
        case .personalization: return "For You"
        case .profile: return "Profile"
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
