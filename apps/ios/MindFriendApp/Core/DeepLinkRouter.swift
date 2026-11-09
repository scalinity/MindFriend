import Foundation
import SwiftUI
import Supabase

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
    /// A new identity for every request, including repeated links to the same destination.
    struct Request: Identifiable, Equatable {
        let id: UUID
        let route: DeepLinkRoute
    }

    @Published private(set) var pendingRequest: Request?
    @Published private(set) var requestID = UUID()

    var pendingRoute: DeepLinkRoute? { pendingRequest?.route }

    static let shared = DeepLinkRouter()

    init() {}

    // MARK: - URL Parsing

    /// Parse a URL into a DeepLinkRoute
    func parseURL(_ url: URL) -> DeepLinkRoute? {
        guard url.scheme == "mindfriend" else { return nil }

        let host = url.host ?? ""
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard pathComponents.count <= 1 else { return .unknown }

        switch host {
        // Main tabs
        case "home":
            return .home
        case "chat":
            // SEC-CRIT-005: Validate conversation ID as UUID if provided
            if let conversationId = pathComponents.first {
                guard conversationId.isValidUUID else {
                    Log.general.warning("[DeepLink] Invalid conversation ID format")
                    return .unknown
                }
                return .chat(conversationId: conversationId)
            }
            return .chat(conversationId: nil)
        case "circles", "circle":
            // SEC-CRIT-005: Validate circle ID as UUID if provided
            if let circleId = pathComponents.first {
                guard circleId.isValidUUID else {
                    Log.general.warning("[DeepLink] Invalid circle ID format")
                    return .unknown
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
                    Log.general.warning("[DeepLink] Invalid quest ID format")
                    return .unknown
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
                    Log.general.warning("[DeepLink] Invalid exercise ID format")
                    return .unknown
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
                    Log.general.warning("[DeepLink] Invalid program ID format")
                    return .unknown
                }
                return .program(programId: programId)
            }
            return .programs

        // Wellness
        case "journal":
            return .journal
        case "micro", "micro-moments":
            if let id = pathComponents.first, !id.isValidUUID { return .unknown }
            return .microMoments(templateId: pathComponents.first)
        case "sleep":
            if let id = pathComponents.first, !id.isValidUUID { return .unknown }
            return .sleep(contentId: pathComponents.first)
        case "quote":
            return .quote
        case "assessment":
            // Assessment code (PHQ9, GAD7, WHO5, PSS10) - alphanumeric
            if let code = pathComponents.first {
                let codePattern = "^[A-Za-z0-9]{2,10}$"
                guard code.range(of: codePattern, options: .regularExpression) != nil else {
                    Log.general.warning("[DeepLink] Invalid assessment code format")
                    return .unknown
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
    
    // MARK: - Route Handling

    func handleURL(_ url: URL, appState: AppState) {
        guard let route = parseURL(url) else { return }
        handleRoute(route, appState: appState)
    }

    /// Enqueue only. Authenticated views acknowledge a request after accepting its destination.
    func handleRoute(_ route: DeepLinkRoute, appState: AppState) {
        // Use the same identifier validation for notifications and direct route callers.
        let validatedRoute = validate(route)
        requestID = UUID()
        pendingRequest = Request(id: requestID, route: validatedRoute)
    }

    func requestForPresentation(isAuthenticated: Bool) -> Request? {
        isAuthenticated ? pendingRequest : nil
    }

    /// An older view must never consume a newer request.
    @discardableResult
    func consume(_ request: Request) -> Bool {
        guard pendingRequest?.id == request.id else { return false }
        pendingRequest = nil
        return true
    }

    /// Invalidate in-flight lookups as well as pending destinations on logout or dismissal.
    func clearNavigationState() {
        requestID = UUID()
        pendingRequest = nil
    }

    func dismiss(_ request: Request) {
        guard requestID == request.id else { return }
        clearNavigationState()
    }

    func isPending(_ route: DeepLinkRoute) -> Bool {
        pendingRoute == route
    }

    func route(for notification: NotificationDeepLink) -> DeepLinkRoute? {
        let route: DeepLinkRoute
        switch notification {
        case .quest(let id): route = .quest(questId: id)
        case .chat(let id): route = .chat(conversationId: id)
        case .circle(let id): route = .circles(circleId: id)
        case .mood: route = .mood
        case .settings: route = .settings
        case .insights: route = .insights
        case .buddy(let code): route = .buddy(code: code)
        case .micro(let id): route = .microMoments(templateId: id)
        case .sleep(let id): route = .sleep(contentId: id)
        case .none: return nil
        }
        return validate(route)
    }

    private func validate(_ route: DeepLinkRoute) -> DeepLinkRoute {
        guard let url = route.url, let parsed = parseURL(url) else { return .unknown }
        if case .assessment(let code?) = route {
            return parsed == .assessment(code: code.uppercased()) ? parsed : .unknown
        }
        // An empty supplied identifier must not turn into an identifier-free collection route.
        return parsed == route ? parsed : .unknown
    }

    enum DestinationError: LocalizedError, Equatable {
        case unavailable
        case premium

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "This item is unavailable or you don't have access to it."
            case .premium:
                return "This content requires Premium. Review your plan in your account settings."
            }
        }
    }

    /// A missing or inaccessible row is different from a failed connection.
    static func destinationError(for error: Error) -> DestinationError? {
        if let destinationError = error as? DestinationError { return destinationError }
        if let databaseError = error as? PostgrestError,
           databaseError.code == "PGRST116" || databaseError.code == "42501" {
            return .unavailable
        }
        return nil
    }

    /// Match only within the records returned by the authenticated service lookup.
    static func linkedItem<Item: Identifiable>(id: String, in items: [Item]) throws -> Item where Item.ID == String {
        guard let identifier = UUID(uuidString: id),
              let item = items.first(where: { UUID(uuidString: $0.id) == identifier }) else {
            throw DestinationError.unavailable
        }
        return item
    }

    // MARK: - Tab Mapping

    /// Get the tab for a given route
    func tabForRoute(_ route: DeepLinkRoute) -> MainTab? {
        switch route {
        case .home, .mood, .moodHistory, .quest, .streak,
             .breathing, .journal, .microMoments, .quote, .insights,
             .circles, .sleep, .meditation, .exercise, .exerciseLibrary:
            return .home
        case .chat:
            return .chat
        case .profile, .settings, .achievements:
            return .profile
        case .programs, .therapeuticPrograms, .program:
            return .programs
        case .progress, .assessment:
            return .outcomes
        case .buddy, .unknown:
            return nil
        }
    }
}

// MARK: - Stable shell placement (Today / Chat / Explore / You)

/// Where a deep link lands in the stable four-tab shell (SUPPORT_SESSION_SPEC §4.2).
/// No case depends on activation state. Identifier-bearing routes are still resolved and ownership/membership/
/// premium-checked by the presented destination before anything opens.
enum SupportRoutePlacement: Equatable {
    /// Select the tab root (Today, Chat, You).
    case tabRoot(MainTab)
    /// Select the destination's tab and push it onto that tab's preserved stack.
    case destination(SupportDestination)
    /// Present the existing resolving destination sheet over the given tab (identifier routes, mood check-in, quest).
    case presented(tab: MainTab)
    /// Handled by a separate authenticated app-level flow (buddy invitations).
    case externalFlow
    /// Unknown or invalid link; show the native "isn't supported" error.
    case unavailable
}

extension DeepLinkRoute {
    /// Exhaustive on purpose: adding a `DeepLinkRoute` case without a home must fail to compile.
    var supportPlacement: SupportRoutePlacement {
        switch self {
        case .home:
            return .tabRoot(SupportShellTab.today.mainTab)
        case .quote:
            // No quote content exists; the old link now opens an honest unavailable screen under Practices.
            return .destination(.quote)
        case .chat:
            return .tabRoot(SupportShellTab.chat.mainTab)
        case .profile:
            return .tabRoot(SupportShellTab.you.mainTab)
        case .settings:
            return .destination(.settings)
        case .mood, .quest:
            return .presented(tab: SupportShellTab.today.mainTab)
        case .moodHistory:
            return .destination(.moodHistory)
        case .streak:
            return .destination(.streaks)
        case .progress:
            return .destination(.outcomes)
        case .breathing:
            return .destination(.quickBreathing)
        case .meditation, .exerciseLibrary:
            return .destination(.exerciseLibrary)
        case .exercise, .program:
            return .presented(tab: SupportShellTab.explore.mainTab)
        case .programs:
            return .destination(.programs)
        case .therapeuticPrograms:
            return .destination(.therapeuticPrograms)
        case .journal:
            return .destination(.journal)
        case .microMoments(let id):
            return id == nil ? .destination(.microMoments) : .presented(tab: SupportShellTab.explore.mainTab)
        case .sleep(let id):
            return id == nil ? .destination(.sleep) : .presented(tab: SupportShellTab.explore.mainTab)
        case .circles(let id):
            return id == nil ? .destination(.circles) : .presented(tab: SupportShellTab.explore.mainTab)
        case .assessment(let code):
            return code == nil ? .destination(.outcomes) : .presented(tab: SupportShellTab.you.mainTab)
        case .insights:
            return .destination(.weeklyInsights)
        case .achievements:
            return .destination(.achievements)
        case .buddy:
            return .externalFlow
        case .unknown:
            return .unavailable
        }
    }
}

extension DeepLinkRouter {
    /// Static route → tab mapping for the stable shell. `nil` for routes with no tab (buddy flow, unknown links).
    /// `MainTab.home/.chat/.circles/.profile` are the Today/Chat/Explore/You tags.
    nonisolated static func supportShellTab(for route: DeepLinkRoute) -> MainTab? {
        switch route.supportPlacement {
        case .tabRoot(let tab): return tab
        case .destination(let destination): return destination.tab.mainTab
        case .presented(let tab): return tab
        case .externalFlow, .unavailable: return nil
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
