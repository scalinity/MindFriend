import Foundation
import Supabase
import AuthenticationServices
import GoogleSignIn

/// Handles authentication with Supabase (Apple Sign-In, Google Sign-In)
@MainActor
final class SupabaseAuthService: ObservableObject {
    @Published private(set) var isSigningIn = false
    @Published private(set) var currentUser: User?
    @Published private(set) var session: Session?

    init() {
        // Listen for auth state changes
        Task {
            for await (event, session) in supabase.auth.authStateChanges {
                self.session = session
                self.currentUser = session?.user

                switch event {
                case .initialSession:
                    print("[Auth] Initial session loaded")
                case .signedIn:
                    print("[Auth] User signed in: \(session?.user.id.uuidString ?? "unknown")")
                    Analytics.shared.track(.signInCompleted, properties: ["provider": "supabase"])
                case .signedOut:
                    print("[Auth] User signed out")
                    Analytics.shared.track(.signOut)
                    CrashReporter.shared.clearUser()
                case .tokenRefreshed:
                    print("[Auth] Token refreshed")
                case .userUpdated:
                    print("[Auth] User updated")
                case .passwordRecovery:
                    break
                @unknown default:
                    break
                }
            }
        }
    }

    // MARK: - Session Management

    var isAuthenticated: Bool {
        session != nil
    }

    var userId: UUID? {
        session?.user.id
    }

    /// Restore existing session on app launch
    func restoreSession() async -> Bool {
        do {
            session = try await supabase.auth.session
            currentUser = session?.user
            return session != nil
        } catch {
            print("[Auth] No existing session: \(error)")
            return false
        }
    }

    // MARK: - Apple Sign-In

    func signInWithApple(
        identityToken: Data,
        authorizationCode: Data,
        fullName: PersonNameComponents?,
        email: String?
    ) async throws -> UserProfile {
        guard let tokenString = String(data: identityToken, encoding: .utf8) else {
            throw AuthError.invalidCredentials
        }

        isSigningIn = true
        defer { isSigningIn = false }

        do {
            // Sign in with Supabase using Apple ID token
            let session = try await supabase.auth.signInWithIdToken(
                credentials: .init(
                    provider: .apple,
                    idToken: tokenString
                )
            )

            self.session = session
            self.currentUser = session.user

            // Update profile with name if provided
            if let fullName = fullName {
                let displayName = [fullName.givenName, fullName.familyName]
                    .compactMap { $0 }
                    .joined(separator: " ")

                if !displayName.isEmpty {
                    try await updateProfile(displayName: displayName)
                }
            }

            // Fetch and return full profile
            let profile = try await fetchProfile()

            // Set user context for crash reporting
            CrashReporter.shared.setUser(
                id: session.user.id.uuidString,
                email: session.user.email,
                username: profile.handle
            )
            Analytics.shared.identify(userId: session.user.id.uuidString)

            return profile

        } catch {
            Analytics.shared.trackSignIn(provider: "apple", success: false, error: error)
            throw error
        }
    }

    // MARK: - Google Sign-In

    func signInWithGoogle(idToken: String, accessToken: String) async throws -> UserProfile {
        isSigningIn = true
        defer { isSigningIn = false }

        do {
            let session = try await supabase.auth.signInWithIdToken(
                credentials: .init(
                    provider: .google,
                    idToken: idToken,
                    accessToken: accessToken
                )
            )

            self.session = session
            self.currentUser = session.user

            // Fetch and return full profile
            let profile = try await fetchProfile()

            // Set user context
            CrashReporter.shared.setUser(
                id: session.user.id.uuidString,
                email: session.user.email,
                username: profile.handle
            )
            Analytics.shared.identify(userId: session.user.id.uuidString)

            return profile

        } catch {
            Analytics.shared.trackSignIn(provider: "google", success: false, error: error)
            throw error
        }
    }

    // MARK: - Email/Password Sign Up

    func signUp(email: String, password: String, displayName: String?) async throws -> UserProfile {
        isSigningIn = true
        defer { isSigningIn = false }

        do {
            let response = try await supabase.auth.signUp(
                email: email,
                password: password,
                data: displayName.map { ["display_name": .string($0)] } ?? [:]
            )

            guard let session = response.session else {
                // Email confirmation required
                throw AuthError.emailConfirmationRequired
            }

            self.session = session
            self.currentUser = session.user

            let profile = try await fetchProfile()

            CrashReporter.shared.setUser(
                id: session.user.id.uuidString,
                email: session.user.email,
                username: profile.handle
            )
            Analytics.shared.identify(userId: session.user.id.uuidString)
            Analytics.shared.trackSignIn(provider: "email", success: true, error: nil)

            return profile

        } catch {
            Analytics.shared.trackSignIn(provider: "email", success: false, error: error)
            throw error
        }
    }

    // MARK: - Email/Password Sign In

    func signIn(email: String, password: String) async throws -> UserProfile {
        isSigningIn = true
        defer { isSigningIn = false }

        do {
            let session = try await supabase.auth.signIn(
                email: email,
                password: password
            )

            self.session = session
            self.currentUser = session.user

            let profile = try await fetchProfile()

            CrashReporter.shared.setUser(
                id: session.user.id.uuidString,
                email: session.user.email,
                username: profile.handle
            )
            Analytics.shared.identify(userId: session.user.id.uuidString)
            Analytics.shared.trackSignIn(provider: "email", success: true, error: nil)

            return profile

        } catch {
            Analytics.shared.trackSignIn(provider: "email", success: false, error: error)
            throw error
        }
    }

    // MARK: - Password Reset

    func resetPassword(email: String) async throws {
        try await supabase.auth.resetPasswordForEmail(email)
    }

    // MARK: - Sign Out

    func signOut() async throws {
        try await supabase.auth.signOut()
        session = nil
        currentUser = nil
        CrashReporter.shared.clearUser()
        Analytics.shared.reset()
    }

    // MARK: - Profile Management

    func fetchProfile() async throws -> UserProfile {
        guard let userId = userId else {
            throw AuthError.invalidCredentials
        }

        let profile: DBProfile = try await supabase
            .from(Tables.profiles)
            .select()
            .eq("id", value: userId)
            .single()
            .execute()
            .value

        return profile.toUserProfile()
    }

    func updateProfile(displayName: String? = nil, handle: String? = nil, timezone: String? = nil) async throws {
        guard let userId = userId else { return }

        var updates: [String: AnyEncodable] = [
            "updated_at": AnyEncodable(ISO8601DateFormatter().string(from: Date()))
        ]

        if let displayName = displayName {
            updates["display_name"] = AnyEncodable(displayName)
        }
        if let handle = handle {
            updates["handle"] = AnyEncodable(handle)
        }
        if let timezone = timezone {
            updates["timezone"] = AnyEncodable(timezone)
        }

        try await supabase
            .from(Tables.profiles)
            .update(updates)
            .eq("id", value: userId)
            .execute()
    }

    func updateSettings(_ settings: UserSettings) async throws {
        guard let userId = userId else { return }

        let updates: [String: AnyEncodable] = [
            "daily_quest_time_local": AnyEncodable(settings.dailyQuestTimeLocal),
            "quiet_hours_start_local": AnyEncodable(settings.quietHoursStartLocal),
            "quiet_hours_end_local": AnyEncodable(settings.quietHoursEndLocal),
            "reminders_enabled": AnyEncodable(settings.remindersEnabled),
            "nudge_after_days_inactive": AnyEncodable(settings.nudgeAfterDaysInactive),
            "share_mood_in_circles": AnyEncodable(settings.shareMoodInCircles),
            "ai_tone": AnyEncodable(settings.aiTone.rawValue),
            "privacy_mode": AnyEncodable(settings.privacyMode.rawValue),
            "updated_at": AnyEncodable(ISO8601DateFormatter().string(from: Date()))
        ]

        try await supabase
            .from(Tables.profiles)
            .update(updates)
            .eq("id", value: userId)
            .execute()
    }

    // MARK: - Account Management

    func deleteAccount() async throws {
        // Note: This soft-deletes by calling a Supabase Edge Function
        // The Edge Function should handle proper data deletion
        guard userId != nil else { return }

        // For now, just sign out - implement Edge Function for full deletion
        try await signOut()
    }
}

// MARK: - Helper for encoding dynamic values

struct AnyEncodable: Encodable {
    private let value: any Encodable

    init(_ value: any Encodable) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}
