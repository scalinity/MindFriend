import SwiftUI
import GoogleSignIn
import Sentry
import EventKit

@main
struct MindFriendApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var appState = AppState()
    @StateObject private var container = DependencyContainer.shared
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var deepLinkRouter = DeepLinkRouter.shared
    @StateObject private var localizationService = LocalizationService.shared

    /// Selected app theme (persisted to UserDefaults)
    @AppStorage(AppTheme.storageKey) private var selectedTheme: AppTheme = .system

    /// Pending buddy invite code to process after authentication
    @State private var pendingBuddyCode: String?
    @State private var showBuddyAcceptedAlert = false
    @State private var buddyAcceptedMessage = ""
    @State private var showPasswordRecovery = false

    @ViewBuilder
    private var launchContent: some View {
        #if DEBUG
        if SupportSessionUIFixture.isEnabled {
            SupportSessionUIFixtureView()
        } else if ProcessInfo.processInfo.arguments.contains("--auth-ui-test") {
            AuthUITestView()
        } else if ProcessInfo.processInfo.arguments.contains("--subscription-ui-test") {
            SubscriptionCatalogUITestView()
        } else if ProcessInfo.processInfo.arguments.contains("--sleep-ui-test") {
            SleepDashboardUITestView()
        } else if ProcessInfo.processInfo.arguments.contains("--debt-calendar-ui-test") {
            DebtCalendarUITestView()
        } else {
            RootView()
        }
        #else
        RootView()
        #endif
    }

    private var appColorScheme: ColorScheme? {
        #if DEBUG
        if SupportSessionUIFixture.isEnabled {
            return SupportSessionUIFixture.value(after: "--support-appearance") == "dark" ? .dark : .light
        }
        #endif
        return selectedTheme.colorScheme
    }

    var body: some Scene {
        WindowGroup {
            launchContent
                .environmentObject(appState)
                .environmentObject(container)
                .environmentObject(notificationManager)
                .environmentObject(deepLinkRouter)
                .environmentObject(container.ambientThemeService)
                .environmentObject(localizationService)
                .environmentObject(container.achievementService)
                .preferredColorScheme(appColorScheme)
                // Language changes propagate through @Environment(\.locale)
                .environment(\.locale, Locale(identifier: localizationService.currentLanguage))
                .environment(\.layoutDirection, localizationService.isRTL ? .rightToLeft : .leftToRight)
                .task {
                    #if DEBUG
                    // Unit-test hosts must not start live account/service work.
                    if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || SupportSessionUIFixture.isEnabled { return }
                    if ProcessInfo.processInfo.arguments.contains("--auth-ui-test") ||
                       ProcessInfo.processInfo.arguments.contains("--subscription-ui-test") ||
                       ProcessInfo.processInfo.arguments.contains("--sleep-ui-test") ||
                       ProcessInfo.processInfo.arguments.contains("--debt-calendar-ui-test") { return }
                    #endif
                    // A cold-launch notification can arrive before SwiftUI subscribes.
                    if let deepLink = notificationManager.consumePendingDeepLink() {
                        handleNotificationDeepLink(deepLink)
                    }
                    // DEBUG: Log calendar permission status and Info.plist keys at app launch
                    #if DEBUG
                    // Check if calendar Info.plist keys exist in bundle
                    let bundle = Bundle.main
                    let hasFullAccessKey = bundle.object(forInfoDictionaryKey: "NSCalendarsFullAccessUsageDescription") != nil
                    let hasWriteOnlyKey = bundle.object(forInfoDictionaryKey: "NSCalendarsWriteOnlyAccessUsageDescription") != nil
                    let hasLegacyKey = bundle.object(forInfoDictionaryKey: "NSCalendarsUsageDescription") != nil

                    print("🗓️ [APP LAUNCH] Info.plist calendar keys:")
                    print("   - NSCalendarsFullAccessUsageDescription: \(hasFullAccessKey ? "✅ PRESENT" : "❌ MISSING")")
                    print("   - NSCalendarsWriteOnlyAccessUsageDescription: \(hasWriteOnlyKey ? "✅ PRESENT" : "❌ MISSING")")
                    print("   - NSCalendarsUsageDescription (legacy): \(hasLegacyKey ? "✅ PRESENT" : "❌ MISSING")")

                    if !hasFullAccessKey {
                        print("⚠️ CRITICAL: NSCalendarsFullAccessUsageDescription is MISSING from bundle!")
                        print("   iOS will auto-deny calendar access without this key.")
                    }

                    let calendarStatus = EKEventStore.authorizationStatus(for: .event)
                    var statusName: String
                    switch calendarStatus {
                    case .notDetermined: statusName = "notDetermined (0)"
                    case .restricted: statusName = "restricted (1)"
                    case .denied: statusName = "denied (2)"
                    case .fullAccess: statusName = "fullAccess (3)"
                    case .writeOnly: statusName = "writeOnly (4)"
                    @unknown default: statusName = "unknown (\(calendarStatus.rawValue))"
                    }
                    print("🗓️ [APP LAUNCH] Calendar authorization status: \(statusName)")
                    #endif

                    // Configure localization service with Supabase access
                    _ = container.localizationService

                    // Configure notification manager with container for device registration
                    notificationManager.configure(container: container)

                    // Register medication notification categories
                    NotificationCategoryManager.shared.registerCategories()

                    // OPTIMIZATION 2: Parallelize network calls
                    async let sessionTask = container.supabaseAuthService.restoreSession()
                    async let notificationTask: () = notificationManager.checkAuthorizationStatus()

                    // Wait for both to complete in parallel
                    let hasSession = await sessionTask
                    _ = await notificationTask

                    // Signal that the Supabase session is now restored
                    // (HomeView waits for this before making edge function calls)
                    appState.sessionRestored = true

                    // OPTIMIZATION 3: Update from network if needed
                    if hasSession {
                        // Fetch fresh profile (uses cache if valid, otherwise network)
                        if let profile = await container.supabaseAuthService.fetchProfileWithCache() {
                            // Check if user needs onboarding
                            if profile.needsOnboarding {
                                appState.setAuthenticated(user: profile)
                            } else {
                                // Update with verified network data
                                appState.setAuthenticated(user: profile)

                            }

                            if !profile.needsOnboarding {
                                CrashReporter.shared.setUser(id: profile.id.uuidString)
                                Analytics.shared.identify(userId: profile.id.uuidString)
                                Analytics.shared.setUserProperty(.subscriptionTier, value: profile.entitlements?.subscriptionTier ?? "free")
                            }

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
                    }
                }
                .task(id: appState.authenticatedAccountID) {
                    #if DEBUG
                    if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || SupportSessionUIFixture.isEnabled { return }
                    if ProcessInfo.processInfo.arguments.contains("--auth-ui-test") ||
                       ProcessInfo.processInfo.arguments.contains("--subscription-ui-test") ||
                       ProcessInfo.processInfo.arguments.contains("--sleep-ui-test") ||
                       ProcessInfo.processInfo.arguments.contains("--debt-calendar-ui-test") { return }
                    #endif
                    guard let owner = appState.authenticatedAccountID else { return }
                    await container.startAuthenticatedServices(for: owner, appState: appState)
                }
                .onReceive(container.supabaseAuthService.$session) { session in
                    if appState.sessionRestored && session == nil { appState.setUnauthenticated() }
                }
                .onReceive(container.supabaseAuthService.$signOutWarning) { warning in
                    if let warning { appState.showError(.apiError(warning)) }
                }
                .onReceive(container.supabaseAuthService.$requiresPasswordReset) { showPasswordRecovery = $0 }
                .sheet(isPresented: $showPasswordRecovery) {
                    PasswordRecoveryView(authService: container.supabaseAuthService)
                }
                .onOpenURL { url in
                    // Handle Google Sign-In and custom deep links
                    if !GIDSignIn.sharedInstance.handle(url) {
                        handleDeepLink(url)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .notificationDeepLinkReceived)) { notification in
                    if let deepLink = notification.userInfo?["deepLink"] as? NotificationDeepLink {
                        _ = notificationManager.consumePendingDeepLink()
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
                .onChange(of: appState.currentUser?.id) { oldID, newID in
                    if oldID != nil && oldID != newID {
                        deepLinkRouter.clearNavigationState()
                        _ = notificationManager.consumePendingDeepLink()
                    }
                }
                .onChange(of: appState.authState) { oldState, newState in
                    if oldState == .authenticated && newState != .authenticated {
                        deepLinkRouter.clearNavigationState()
                        _ = notificationManager.consumePendingDeepLink()
                    }
                    // Process pending buddy invite after authentication
                    if case .authenticated = newState {
                        processPendingBuddyInvite()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await container.refreshAuthenticatedIntegrations(appState: appState) }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                    Task { await container.refreshAuthenticatedIntegrations(appState: appState) }
                }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "mindfriend" else { return }
        if url.host == "auth", url.path == "/callback" {
            Task { @MainActor in
                do {
                    let profile = try await container.supabaseAuthService.handleAuthCallback(url)
                    if profile.needsOnboarding { appState.setAuthenticated(user: profile) }
                    else { appState.setAuthenticated(user: profile) }
                } catch {
                    appState.showError(.apiError("The sign-in link could not be completed. Request a new link and try again."))
                }
            }
            return
        }

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
        guard let route = deepLinkRouter.route(for: deepLink) else { return }
        if case .buddy(let code) = route {
            handleBuddyInvite(code: code)
        } else {
            deepLinkRouter.handleRoute(route, appState: appState)
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
                OnboardingFlow().id(container.supabaseAuthService.userId)
            case .authenticated:
                AuthenticatedSupportRoot()
                    .ambientBackground(service: ambientService)
                    .privacyLockOverlay(onUnlock: {})
                    .badgeEarnedCelebration()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.authState)
    }
}

/// Account data views are not constructed until their protected local repository is bound and loaded.
private struct AuthenticatedSupportRoot: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var container: DependencyContainer
    @State private var retry = UUID()
    @State private var showHelp = false
    @State private var showFreshJournalChoice = false
    @Environment(\.scenePhase) private var scenePhase

    private struct Scope: Hashable {
        let ownerID: UUID?
        let epoch: UInt64
        let retry: UUID
    }

    var body: some View {
        let scope = Scope(ownerID: appState.currentUser?.id, epoch: appState.accountEpoch, retry: retry)
        Group {
            if let coordinator = container.supportSessionCoordinator,
               coordinator.identity.ownerID == scope.ownerID,
               container.supportSessionAccountEpoch == scope.epoch {
                SupportLoadedShell(coordinator: coordinator)
                    .id(coordinator.identity.epochID)
            } else {
                VStack(spacing: 24) {
                    if let message = container.supportSessionLoadError {
                        ContentUnavailableView("Saved work unavailable", systemImage: "lock.doc",
                                               description: Text(message))
                        Button("Try again") { appState.retryAccountScope(); retry = UUID() }.buttonStyle(.supportPrimary)
                        if container.supportSessionRecovery != nil {
                            Button("Start with an empty journal") { showFreshJournalChoice = true }
                        }
                    } else {
                        ProgressView("Opening your saved work…")
                    }
                    Button("Support and crisis resources") { showHelp = true }
                }
                .padding()
            }
        }
        .task(id: scope) {
            guard let ownerID = scope.ownerID else { return }
            await container.prepareSupportSessionScope(ownerID: ownerID, accountEpoch: scope.epoch)
        }
        .sheet(isPresented: $showHelp) { CrisisResourcesView() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                SyncQueueManager.shared.applicationDidBecomeActive()
                Task { try? await container.supportSync?.refresh() }
            }
        }
        .confirmationDialog("Start with an empty journal?", isPresented: $showFreshJournalChoice, titleVisibility: .visible) {
            Button("Keep recovery files and start empty") {
                guard let ownerID = scope.ownerID else { return }
                Task { await container.startFreshSupportJournal(ownerID: ownerID, accountEpoch: scope.epoch) }
            }
        } message: {
            Text("Unreadable files stay on this device for recovery. They are not added to the empty journal. You can remove them later with a separate choice.")
        }
    }
}

/// Observes the presentation owner directly so an activity opened from any tab reaches its player.
struct SupportLoadedShell: View {
    @ObservedObject var coordinator: SupportSessionCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        MainTabView()
            .environmentObject(coordinator)
            .completionMoments()
            .fullScreenCover(item: Binding(get: { coordinator.activityPresentation },
                                          set: { coordinator.activityPresentation = $0 })) { presentation in
                SupportActivityView(coordinator: coordinator, presentation: presentation)
                    .interactiveDismissDisabled()
                    .completionMoments()
            }
            .transaction { if reduceMotion { $0.disablesAnimations = true; $0.animation = nil } }
    }
}

/// Continues the launch screen: the same canvas with the logo at the same size and centre,
/// so the hand-off from the system launch screen does not jump.
struct SplashView: View {
    var body: some View {
        ZStack {
            SupportTheme.canvas
            Image("LaunchLogo")
                .accessibilityLabel("MindFriend")
            ProgressView()
                .tint(SupportTheme.textSecondary)
                .offset(y: 110)
                .accessibilityLabel("Loading")
        }
        .ignoresSafeArea()
    }
}

#Preview {
    let container = DependencyContainer()
    return RootView()
        .environmentObject(AppState())
        .environmentObject(container)
        .environmentObject(container.achievementService)
        .environmentObject(container.ambientThemeService)
}

private struct PasswordRecoveryView: View {
    @ObservedObject var authService: SupabaseAuthService
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                SecureField("New password", text: $password)
                    .textContentType(.newPassword)
                SecureField("Confirm password", text: $confirmation)
                    .textContentType(.newPassword)
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                Button(isSaving ? "Saving…" : "Save password") {
                    isSaving = true
                    Task { @MainActor in
                        defer { isSaving = false }
                        do {
                            try await authService.completePasswordRecovery(password: password)
                            password = ""
                            confirmation = ""
                            dismiss()
                        } catch {
                            errorMessage = "Password could not be updated. Check your connection or request a new recovery link."
                        }
                    }
                }
                .disabled(isSaving || password.count < 8 || password != confirmation)
            }
            .navigationTitle("Reset password")
            .interactiveDismissDisabled(isSaving)
        }
        .privacySensitive()
    }
}
