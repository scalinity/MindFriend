import SwiftUI
import GoogleSignIn
import Sentry

@main
struct MindFriendApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var appState = AppState()
    @StateObject private var container = DependencyContainer()
    @StateObject private var notificationManager = NotificationManager.shared

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
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "mindfriend" else { return }

        // Parse deep link and navigate
        // Example: mindfriend://quest/123, mindfriend://chat/456
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
        default:
            break
        }
    }

    private func handleNotificationDeepLink(_ deepLink: NotificationDeepLink) {
        switch deepLink {
        case .quest(let id):
            // Navigate to quest with id
            print("[DeepLink] Navigate to quest: \(id)")
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
        case .none:
            break
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
