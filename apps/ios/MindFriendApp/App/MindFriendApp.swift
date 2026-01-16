import SwiftUI
import GoogleSignIn
import Sentry

@main
struct MindFriendApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var appState = AppState()
    @StateObject private var container = DependencyContainer()
    @StateObject private var notificationManager = NotificationManager.shared

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
                .task {
                    // Configure notification manager with container for device registration
                    notificationManager.configure(container: container)

                    // Restore Supabase session
                    let hasSession = await container.supabaseAuthService.restoreSession()

                    // Check notification authorization
                    await notificationManager.checkAuthorizationStatus()

                    // Update auth state based on session status
                    if hasSession {
                        // Try to fetch user profile
                        do {
                            let profile = try await container.supabaseAuthService.fetchProfile()

                            // Check if user needs onboarding
                            if profile.needsOnboarding {
                                appState.requireOnboarding()
                            } else {
                                appState.setAuthenticated(user: profile)
                            }

                            // Set user context for crash reporting and analytics
                            CrashReporter.shared.setUser(
                                id: profile.id,
                                email: profile.email,
                                username: profile.handle
                            )
                            Analytics.shared.identify(userId: profile.id)
                            Analytics.shared.setUserProperty(.subscriptionTier, value: profile.entitlements.tier.rawValue)
                        } catch {
                            // Session invalid, go to sign in
                            appState.setUnauthenticated()
                            error.report(context: ["action": "restore_session"])
                        }
                    } else {
                        appState.setUnauthenticated()
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

        // Parse deep link and navigate
        // Example: mindfriend://quest/123, mindfriend://chat/456, mindfriend://buddy/ABC123
        switch url.host {
        case "quest":
            // Navigate to quest
            break
        case "chat":
            // Navigate to chat
            break
        case "circle":
            // Navigate to circle
            break
        case "mood":
            // Navigate to mood tracking
            break
        case "buddy":
            // Handle buddy invite
            let pathComponents = url.pathComponents.filter { $0 != "/" }
            if let code = pathComponents.first {
                handleBuddyInvite(code: code)
            }
        default:
            break
        }
    }

    private func handleNotificationDeepLink(_ deepLink: NotificationDeepLink) {
        switch deepLink {
        case .quest(let id):
            // Navigate to quest with id
            print("[DeepLink] Navigate to quest: \(id ?? "nil")")
        case .chat(let conversationId):
            // Navigate to chat
            print("[DeepLink] Navigate to chat: \(conversationId)")
        case .circle(let id):
            // Navigate to circle
            print("[DeepLink] Navigate to circle: \(id)")
        case .mood:
            // Navigate to mood tracking
            print("[DeepLink] Navigate to mood")
        case .settings:
            // Navigate to settings
            print("[DeepLink] Navigate to settings")
        case .insights:
            // Navigate to insights/weekly summary
            print("[DeepLink] Navigate to insights")
        case .buddy(let code):
            // Handle buddy invite
            handleBuddyInvite(code: code)
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
            print("[DeepLink] Stored buddy code for after auth: \(code)")
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
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(Color.accentColor)

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
