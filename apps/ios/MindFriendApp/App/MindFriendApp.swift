import SwiftUI
import GoogleSignIn
import Sentry

@main
struct MindFriendApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var appState = AppState()
    @StateObject private var container = DependencyContainer()
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var deepLinkRouter = DeepLinkRouter.shared
    @StateObject private var localizationService = LocalizationService.shared

    /// Selected app theme (persisted to UserDefaults)
    @AppStorage(AppTheme.storageKey) private var selectedTheme: AppTheme = .system

    /// Pending buddy invite code to process after authentication
    @State private var pendingBuddyCode: String?
    @State private var showBuddyAcceptedAlert = false
    @State private var buddyAcceptedMessage = ""

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(container)
                .environmentObject(notificationManager)
                .environmentObject(deepLinkRouter)
                .environmentObject(container.ambientThemeService)
                .environmentObject(localizationService)
                .preferredColorScheme(selectedTheme.colorScheme)
                // Force view refresh when language changes
                .id(localizationService.refreshTrigger)
                .environment(\.layoutDirection, localizationService.isRTL ? .rightToLeft : .leftToRight)
                .task {
                    // Configure localization service with Supabase access
                    _ = container.localizationService
                    
                    // Configure notification manager with container for device registration
                    notificationManager.configure(container: container)

                    // Register medication notification categories
                    NotificationCategoryManager.shared.registerCategories()

                    // OPTIMIZATION 1: Load cached auth state immediately to skip splash
                    if let cachedProfile = container.supabaseAuthService.getCachedProfile() {
                        if cachedProfile.needsOnboarding {
                            appState.requireOnboarding()
                        } else {
                            // Show UI immediately with cached data
                            appState.setAuthenticatedFromCache(user: cachedProfile)

                            // Set user context for crash reporting (from cache)
                            CrashReporter.shared.setUser(
                                id: cachedProfile.id.uuidString,
                                email: cachedProfile.email,
                                username: cachedProfile.handle
                            )
                            Analytics.shared.identify(userId: cachedProfile.id.uuidString)
                        }
                    }

                    // OPTIMIZATION 2: Parallelize network calls
                    async let sessionTask = container.supabaseAuthService.restoreSession()
                    async let notificationTask: () = notificationManager.checkAuthorizationStatus()

                    // Wait for both to complete in parallel
                    let hasSession = await sessionTask
                    _ = await notificationTask

                    // OPTIMIZATION 3: Update from network if needed
                    if hasSession {
                        // Fetch fresh profile (uses cache if valid, otherwise network)
                        if let profile = await container.supabaseAuthService.fetchProfileWithCache() {
                            // Check if user needs onboarding
                            if profile.needsOnboarding {
                                appState.requireOnboarding()
                            } else {
                                // Update with verified network data
                                appState.setAuthenticated(user: profile)

                                // Request notification permission after authentication
                                if !notificationManager.isAuthorized {
                                    _ = await notificationManager.requestAuthorization()
                                }

                                // Start ambient theme service
                                await container.ambientThemeService.start()

                                // Sync any widget actions made while app was inactive
                                await appState.processPendingWidgetSyncs(container: container)
                            }

                            // Set user context for crash reporting and analytics
                            CrashReporter.shared.setUser(
                                id: profile.id.uuidString,
                                email: profile.email,
                                username: profile.handle
                            )
                            Analytics.shared.identify(userId: profile.id.uuidString)
                            Analytics.shared.setUserProperty(.subscriptionTier, value: profile.entitlements?.subscriptionTier ?? "free")
                        } else {
                            // Could not fetch profile, session may be invalid
                            if !appState.isUsingCachedData {
                                // Only sign out if we weren't already showing cached data
                                appState.setUnauthenticated()
                            }
                            // If using cached data, keep showing it - user can use app offline
                        }
                    } else {
                        // No session - if we showed cached data, clear it now
                        appState.setUnauthenticated()
                        container.supabaseAuthService.clearCachedProfile()
                    }
                }
                .onOpenURL { url in
                    // Handle Google Sign-In and custom deep links
                    if !GIDSignIn.sharedInstance.handle(url) {
                        handleDeepLink(url)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .notificationDeepLinkReceived)) { notification in
                    if let deepLink = notification.userInfo?["deepLink"] as? NotificationDeepLink {
                        handleNotificationDeepLink(deepLink)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .deepLinkReceived)) { notification in
                    if let url = notification.userInfo?["url"] as? URL {
                        handleDeepLink(url)
                    }
                }
                .alert("Welcome, Buddy!", isPresented: $showBuddyAcceptedAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(buddyAcceptedMessage)
                }
                .onChange(of: appState.authState) { _, newState in
                    // Process pending buddy invite after authentication
                    if case .authenticated = newState {
                        processPendingBuddyInvite()
                    }
                }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "mindfriend" else { return }

        // Parse the deep link using the router
        guard let route = deepLinkRouter.parseURL(url) else { return }

        // Handle buddy invites specially (requires authentication check)
        if case .buddy(let code) = route {
            handleBuddyInvite(code: code)
            return
        }

        // Let the router handle all other navigation
        deepLinkRouter.handleRoute(route, appState: appState)
    }

    private func handleNotificationDeepLink(_ deepLink: NotificationDeepLink) {
        switch deepLink {
        case .quest(let id):
            // Navigate to quest with id
            Log.general.info("[DeepLink] Navigate to quest: \(id ?? "nil")")
        case .chat(let conversationId):
            // Navigate to chat
            Log.general.info("[DeepLink] Navigate to chat: \(conversationId)")
        case .circle(let id):
            // Navigate to circle
            Log.general.info("[DeepLink] Navigate to circle: \(id)")
        case .mood:
            // Navigate to mood tracking
            Log.general.info("[DeepLink] Navigate to mood")
        case .settings:
            // Navigate to settings
            Log.general.info("[DeepLink] Navigate to settings")
        case .insights:
            // Navigate to insights/weekly summary
            Log.general.info("[DeepLink] Navigate to insights")
        case .buddy(let code):
            // Handle buddy invite
            handleBuddyInvite(code: code)
        case .micro(let templateId):
            // Navigate to micro-moments
            appState.selectedTab = .home
            Log.general.info("[DeepLink] Navigate to micro-moments: \(templateId ?? "hub")")
        case .sleep(let contentId):
            // Navigate to sleep tab
            appState.selectedTab = .sleep
            Log.general.info("[DeepLink] Navigate to sleep: \(contentId ?? "home")")
        case .none:
            break
        }
    }

    // MARK: - Buddy Invite Handling

    private func handleBuddyInvite(code: String) {
        // Check if user is authenticated
        guard case .authenticated = appState.authState else {
            // Store the code to process after authentication
            pendingBuddyCode = code
            Log.general.info("[DeepLink] Stored buddy code for after auth: \(code)")
            return
        }

        // Accept the buddy invite
        Task {
            await acceptBuddyInvite(code: code)
        }
    }

    private func acceptBuddyInvite(code: String) async {
        do {
            let relationship = try await container.supabaseDataService.acceptBuddyInvite(code: code)

            await MainActor.run {
                // Show success message
                if let inviterName = relationship.inviter?.displayName {
                    buddyAcceptedMessage = "You're now wellness buddies with \(inviterName)! You can see each other's streaks and send encouragement."
                } else {
                    buddyAcceptedMessage = "You're now connected with your wellness buddy! You can see each other's streaks and send encouragement."
                }
                showBuddyAcceptedAlert = true
            }

            Analytics.shared.track(.buddyInviteAccepted, properties: [
                "invite_code": code,
                "relationship_id": relationship.id
            ])
        } catch {
            await MainActor.run {
                buddyAcceptedMessage = "Could not accept buddy invite. The invite may have expired or already been used."
                showBuddyAcceptedAlert = true
            }
            error.report(context: ["action": "accept_buddy_invite", "code": code])
        }
    }

    /// Process any pending buddy invite after user authenticates
    func processPendingBuddyInvite() {
        guard let code = pendingBuddyCode else { return }
        pendingBuddyCode = nil

        Task {
            await acceptBuddyInvite(code: code)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var container: DependencyContainer
    @EnvironmentObject var ambientService: AmbientThemeService

    var body: some View {
        Group {
            switch appState.authState {
            case .unknown:
                SplashView()
            case .unauthenticated:
                SignInView()
            case .onboarding:
                OnboardingFlow()
            case .authenticated:
                MainTabView()
                    .ambientBackground(service: ambientService)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.authState)
    }
}

struct SplashView: View {
    var body: some View {
        ZStack {
            Color.accentColor.opacity(0.1)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)

                Text("MindFriend")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                ProgressView()
                    .padding(.top, 20)
            }
        }
    }
}

#Preview {
    RootView()
        .environmentObject(AppState())
        .environmentObject(DependencyContainer())
}
