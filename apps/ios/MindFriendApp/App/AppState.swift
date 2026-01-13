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

    // MARK: - Entitlements
    @Published var entitlements: Entitlements = .free

    // MARK: - Today's Data
    @Published var todayQuest: Quest?
    @Published var todayMood: MoodEntry?
    @Published var currentStreak: Int = 0

    // MARK: - Navigation
    @Published var selectedTab: MainTab = .home
    @Published var showPaywall: Bool = false
    @Published var showCrisisResources: Bool = false

    // MARK: - Error Handling
    @Published var globalError: AppError?
    @Published var showError: Bool = false

    // MARK: - Methods

    func setAuthenticated(user: UserProfile) {
        self.currentUser = user
        self.entitlements = user.entitlements
        self.authState = .authenticated
    }

    func setUnauthenticated() {
        self.currentUser = nil
        self.entitlements = .free
        self.todayQuest = nil
        self.todayMood = nil
        self.currentStreak = 0
        self.authState = .unauthenticated
    }

    func requireOnboarding() {
        self.authState = .onboarding
    }

    func completeOnboarding() {
        self.authState = .authenticated
    }

    func showError(_ error: AppError) {
        self.globalError = error
        self.showError = true
    }

    func updateEntitlements(_ entitlements: Entitlements) {
        self.entitlements = entitlements
        self.currentUser?.entitlements = entitlements
    }
}

// MARK: - Main Tab

enum MainTab: String, CaseIterable {
    case home
    case chat
    case circles
    case profile

    var title: String {
        switch self {
        case .home: return "Home"
        case .chat: return "Chat"
        case .circles: return "Circles"
        case .profile: return "Profile"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .circles: return "person.3.fill"
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
