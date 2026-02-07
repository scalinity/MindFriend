import Foundation
import SwiftUI

// MARK: - UUID Validation

private extension String {
    /// Validates if the string is a valid UUID format
    var isValidUUID: Bool {
        UUID(uuidString: self) != nil
    }
}

// MARK: - Deep Link Route

/// All supported deep link routes in the app
enum DeepLinkRoute: Equatable {
    // Main navigation
    case home
    case chat(conversationId: String? = nil)
    case circles(circleId: String? = nil)
    case profile
    case settings

    // Features
    case mood
    case moodHistory
    case quest(questId: String? = nil)
    case streak
    case progress

    // Exercises
    case breathing
    case meditation
    case exercise(exerciseId: String)
    case exerciseLibrary

    // Programs
    case programs
    case therapeuticPrograms
    case program(programId: String)

    // Wellness features
    case journal
    case microMoments(templateId: String? = nil)
    case sleep(contentId: String? = nil)
    case quote
    case assessment(code: String? = nil)

    // Social
    case buddy(code: String)

    // System
    case insights
    case achievements
    case unknown
}

// MARK: - Deep Link Router

/// Centralized deep link router that parses URLs and manages navigation state
@MainActor
final class DeepLinkRouter: ObservableObject {
    // MARK: - Published Navigation State

    /// The current pending deep link route (cleared after handling)
    @Published var pendingRoute: DeepLinkRoute?

    /// Counter to track route version for race condition prevention
    private var routeVersion: UInt64 = 0

    /// Navigation paths for specific features
    @Published var breathingSheetPresented: Bool = false
    @Published var moodSheetPresented: Bool = false
    @Published var questDetailId: String?
    @Published var exerciseDetailId: String?
    @Published var chatConversationId: String?
    @Published var circleDetailId: String?
    @Published var programDetailId: String?
    @Published var sleepContentId: String?
    @Published var assessmentCode: String?

    // MARK: - Singleton

    static let shared = DeepLinkRouter()

    private init() {}

    // MARK: - URL Parsing

    /// Parse a URL into a DeepLinkRoute
    func parseURL(_ url: URL) -> DeepLinkRoute? {
        guard url.scheme == "mindfriend" else { return nil }

        let host = url.host ?? ""
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        switch host {
        // Main tabs
        case "home":
            return .home
        case "chat":
            // SEC-CRIT-005: Validate conversation ID as UUID if provided
            if let conversationId = pathComponents.first {
                guard conversationId.isValidUUID else {
                    Log.general.warning("[DeepLink] Invalid conversation ID format: \(conversationId)")
                    return .chat(conversationId: nil)
                }
                return .chat(conversationId: conversationId)
            }
            return .chat(conversationId: nil)
        case "circles", "circle":
            // SEC-CRIT-005: Validate circle ID as UUID if provided
            if let circleId = pathComponents.first {
                guard circleId.isValidUUID else {
                    Log.general.warning("[DeepLink] Invalid circle ID format: \(circleId)")
                    return .circles(circleId: nil)
                }
                return .circles(circleId: circleId)
            }
            return .circles(circleId: nil)
        case "profile":
            return .profile
        case "settings":
            return .settings

        // Features
        case "mood":
            if pathComponents.first == "history" {
                return .moodHistory
            }
            return .mood
        case "quest":
            // SEC-CRIT-005: Validate quest ID as UUID if provided
            if let questId = pathComponents.first {
                guard questId.isValidUUID else {
                    Log.general.warning("[DeepLink] Invalid quest ID format: \(questId)")
                    return .quest(questId: nil)
                }
                return .quest(questId: questId)
            }
            return .quest(questId: nil)
        case "streak":
            return .streak
        case "progress":
            return .progress

        // Exercises
        case "breathing", "breathe":
            return .breathing
        case "meditation", "meditate":
            return .meditation
        case "exercise":
            if let exerciseId = pathComponents.first {
                if exerciseId == "meditation" {
                    return .meditation
                }
                // SEC-CRIT-005: Validate exercise ID as UUID
                guard exerciseId.isValidUUID else {
                    Log.general.warning("[DeepLink] Invalid exercise ID format: \(exerciseId)")
                    return .exerciseLibrary
                }
                return .exercise(exerciseId: exerciseId)
            }
            return .exerciseLibrary
        case "exercises":
            return .exerciseLibrary

        // Programs
        case "programs":
            return .programs
        case "therapeutic":
            return .therapeuticPrograms
        case "program":
            if let programId = pathComponents.first {
                // SEC-CRIT-005: Validate program ID as UUID
                guard programId.isValidUUID else {
                    Log.general.warning("[DeepLink] Invalid program ID format: \(programId)")
                    return .programs
                }
                return .program(programId: programId)
            }
            return .programs

        // Wellness
        case "journal":
            return .journal
        case "micro", "micro-moments":
            return .microMoments(templateId: pathComponents.first)
        case "sleep":
            return .sleep(contentId: pathComponents.first)
        case "quote":
            return .quote
        case "assessment":
            // Assessment code (PHQ9, GAD7, WHO5, PSS10) - alphanumeric
            if let code = pathComponents.first {
                let codePattern = "^[A-Za-z0-9]{2,10}$"
                guard code.range(of: codePattern, options: .regularExpression) != nil else {
                    Log.general.warning("[DeepLink] Invalid assessment code format: \(code)")
                    return .assessment(code: nil)
                }
                return .assessment(code: code.uppercased())
            }
            return .assessment(code: nil)

        // Social
        case "buddy":
            if let code = pathComponents.first {
                // Validate buddy code format (alphanumeric, reasonable length)
                let codePattern = "^[A-Za-z0-9]{4,32}$"
                guard code.range(of: codePattern, options: .regularExpression) != nil else {
                    Log.general.warning("[DeepLink] Invalid buddy code format")
                    return .unknown
                }
                return .buddy(code: code)
            }
            return .unknown

        // System
        case "insights":
            return .insights
        case "achievements":
            return .achievements

        default:
            return .unknown
        }
    }
    
    // MARK: - Authentication Requirements
    
    /// Determines if a route requires authentication
    private func routeRequiresAuthentication(_ route: DeepLinkRoute) -> Bool {
        switch route {
        case .home, .breathing, .meditation, .exerciseLibrary, .programs, .therapeuticPrograms, .unknown:
            // Public routes that don't require auth
            return false
        case .chat, .circles, .profile, .settings, .mood, .moodHistory, .quest,
             .streak, .progress, .exercise, .program, .journal, .microMoments,
             .sleep, .quote, .buddy, .insights, .achievements, .assessment:
            // Private routes that require authentication
            return true
        }
    }

    // MARK: - Route Handling

    /// Handle a deep link URL
    func handleURL(_ url: URL, appState: AppState) {
        guard let route = parseURL(url) else { return }
        handleRoute(route, appState: appState)
    }

    /// Handle a parsed deep link route
    func handleRoute(_ route: DeepLinkRoute, appState: AppState) {
        Log.general.info("[DeepLink] Handling route: \(String(describing: route))")
        
        // SEC-CRIT-005: Validate authentication for sensitive routes
        let requiresAuth = routeRequiresAuthentication(route)
        if requiresAuth && appState.authState != .authenticated {
            Log.general.warning("[DeepLink] Blocked unauthenticated access to: \(String(describing: route))")
            // Store route to handle after authentication
            pendingRoute = route
            return
        }

        // Store pending route for views that need to respond
        pendingRoute = route

        switch route {
        // Main navigation - update tab
        case .home:
            appState.selectedTab = .home

        case .chat(let conversationId):
            appState.selectedTab = .chat
            chatConversationId = conversationId

        case .circles(let circleId):
            appState.selectedTab = .home
            circleDetailId = circleId

        case .profile:
            appState.selectedTab = .profile

        case .settings:
            appState.selectedTab = .profile
            // Settings is within profile tab

        // Mood features
        case .mood:
            appState.selectedTab = .home
            moodSheetPresented = true

        case .moodHistory:
            appState.selectedTab = .home
            // Navigate to mood history view

        // Quest
        case .quest(let questId):
            appState.selectedTab = .home
            questDetailId = questId

        case .streak:
            appState.selectedTab = .home
            // Show streak view or navigate to progress

        case .progress:
            appState.selectedTab = .home
            // Navigate to progress view

        // Exercises
        case .breathing:
            appState.selectedTab = .home
            breathingSheetPresented = true

        case .meditation:
            appState.selectedTab = .programs
            // Navigate to meditation exercises

        case .exercise(let exerciseId):
            appState.selectedTab = .programs
            exerciseDetailId = exerciseId

        case .exerciseLibrary:
            appState.selectedTab = .programs

        // Programs
        case .programs:
            appState.selectedTab = .programs

        case .therapeuticPrograms:
            appState.selectedTab = .programs
            // Navigate to therapeutic programs section

        case .program(let programId):
            appState.selectedTab = .programs
            programDetailId = programId

        // Wellness
        case .journal:
            appState.selectedTab = .home
            // Navigate to journal feature

        case .microMoments(let templateId):
            appState.selectedTab = .home
            Log.general.info("[DeepLink] Navigate to micro-moments: \(templateId ?? "hub")")

        case .sleep(let contentId):
            appState.selectedTab = .home
            sleepContentId = contentId

        case .quote:
            // Quote is informational - could show a quote detail or just go home
            appState.selectedTab = .home

        case .assessment(let code):
            // Navigate to wellness tab and trigger assessment flow
            appState.selectedTab = .home
            assessmentCode = code
            Log.general.info("[DeepLink] Navigate to assessment: \(code ?? "selection")")

        // Social
        case .buddy:
            // Buddy invite handling is special - done at app level
            break

        // System
        case .insights:
            appState.selectedTab = .home
            // Navigate to insights/weekly summary

        case .achievements:
            appState.selectedTab = .profile
            // Navigate to achievements view

        case .unknown:
            Log.general.warning("[DeepLink] Unknown route")
        }

        // Clear pending route after a delay to allow views to consume it
        // Track version to prevent race condition if a new route arrives during delay
        routeVersion &+= 1
        let capturedVersion = routeVersion
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            // Only clear if no new route has arrived
            if routeVersion == capturedVersion {
                pendingRoute = nil
            }
        }
    }

    // MARK: - Sheet State Management

    /// Clear all sheet/detail states
    func clearNavigationState() {
        breathingSheetPresented = false
        moodSheetPresented = false
        questDetailId = nil
        exerciseDetailId = nil
        chatConversationId = nil
        circleDetailId = nil
        programDetailId = nil
        sleepContentId = nil
        assessmentCode = nil
        pendingRoute = nil
    }

    /// Check if a route matches the current pending route
    func isPending(_ route: DeepLinkRoute) -> Bool {
        pendingRoute == route
    }

    // MARK: - Tab Mapping

    /// Get the tab for a given route
    func tabForRoute(_ route: DeepLinkRoute) -> MainTab? {
        switch route {
        case .home, .mood, .moodHistory, .quest, .streak, .progress,
             .breathing, .journal, .microMoments, .quote, .insights, .assessment,
             .circles, .sleep:
            return .home
        case .chat:
            return .chat
        case .profile, .settings, .achievements:
            return .profile
        case .programs, .therapeuticPrograms, .program, .meditation, .exercise, .exerciseLibrary:
            return .programs
        case .buddy, .unknown:
            return nil
        }
    }
}

// MARK: - URL Generation

extension DeepLinkRoute {
    /// Generate a URL for this route
    var url: URL? {
        var components = URLComponents()
        components.scheme = "mindfriend"

        switch self {
        case .home:
            components.host = "home"
        case .chat(let conversationId):
            components.host = "chat"
            if let id = conversationId {
                components.path = "/\(id)"
            }
        case .circles(let circleId):
            components.host = "circles"
            if let id = circleId {
                components.path = "/\(id)"
            }
        case .profile:
            components.host = "profile"
        case .settings:
            components.host = "settings"
        case .mood:
            components.host = "mood"
        case .moodHistory:
            components.host = "mood"
            components.path = "/history"
        case .quest(let questId):
            components.host = "quest"
            if let id = questId {
                components.path = "/\(id)"
            }
        case .streak:
            components.host = "streak"
        case .progress:
            components.host = "progress"
        case .breathing:
            components.host = "breathing"
        case .meditation:
            components.host = "meditation"
        case .exercise(let exerciseId):
            components.host = "exercise"
            components.path = "/\(exerciseId)"
        case .exerciseLibrary:
            components.host = "exercises"
        case .programs:
            components.host = "programs"
        case .therapeuticPrograms:
            components.host = "therapeutic"
        case .program(let programId):
            components.host = "program"
            components.path = "/\(programId)"
        case .journal:
            components.host = "journal"
        case .microMoments(let templateId):
            components.host = "micro"
            if let id = templateId {
                components.path = "/\(id)"
            }
        case .sleep(let contentId):
            components.host = "sleep"
            if let id = contentId {
                components.path = "/\(id)"
            }
        case .quote:
            components.host = "quote"
        case .assessment(let code):
            components.host = "assessment"
            if let code = code {
                components.path = "/\(code)"
            }
        case .buddy(let code):
            components.host = "buddy"
            components.path = "/\(code)"
        case .insights:
            components.host = "insights"
        case .achievements:
            components.host = "achievements"
        case .unknown:
            return nil
        }

        return components.url
    }
}
