import Foundation
import Supabase
import AuthenticationServices
import GoogleSignIn

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case invalidCredentials
    case missingIdToken
    case emailConfirmationRequired
    case userNotFound
    case accountNotFound
    case sessionExpired
    case handleTaken
    case invalidHandle
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Incorrect email or password. Please try again."
        case .missingIdToken:
            return "Unable to retrieve authentication token"
        case .emailConfirmationRequired:
            return "Please check your email to confirm your account"
        case .userNotFound:
            return "User not found"
        case .accountNotFound:
            return "No account found with this email. Please sign up first."
        case .sessionExpired:
            return "Your session has expired. Please sign in again"
        case .handleTaken:
            return "This handle is already taken. Please choose another."
        case .invalidHandle:
            return "Handle can only contain letters, numbers, and underscores"
        case .unknown(let message):
            return message
        }
    }
}

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

            // If we have a session, try to refresh it to ensure it's valid
            if session != nil {
                do {
                    session = try await supabase.auth.refreshSession()
                    currentUser = session?.user
                    print("[Auth] Session refreshed successfully")
                } catch {
                    print("[Auth] Session refresh failed: \(error)")
                    // Session is invalid, clear it
                    session = nil
                    currentUser = nil
                    return false
                }
            }

            return session != nil
        } catch {
            print("[Auth] No existing session: \(error)")
            return false
        }
    }

    /// Ensure we have a valid session, refreshing if needed
    func ensureValidSession() async throws {
        guard session != nil else {
            throw AuthError.sessionExpired
        }

        do {
            session = try await supabase.auth.refreshSession()
            currentUser = session?.user
            print("[Auth] Session refreshed for API call")
        } catch {
            print("[Auth] Session refresh failed: \(error)")
            session = nil
            currentUser = nil
            throw AuthError.sessionExpired
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
            // Check for specific error types
            let errorString = String(describing: error).lowercased()

            // Email not confirmed
            if errorString.contains("email_not_confirmed") || errorString.contains("email not confirmed") {
                throw AuthError.emailConfirmationRequired
            }

            // Invalid credentials (wrong password or account doesn't exist)
            // Supabase returns same error for both - show helpful message
            if errorString.contains("invalid_credentials") || errorString.contains("invalid login") {
                throw AuthError.invalidCredentials
            }

            // User not found
            if errorString.contains("user_not_found") || errorString.contains("user not found") {
                throw AuthError.accountNotFound
            }

            throw AuthError.unknown(error.localizedDescription)
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

        do {
            let profile: DBProfile = try await supabase
                .from(Tables.profiles)
                .select()
                .eq("id", value: userId)
                .single()
                .execute()
                .value

            return profile.toUserProfile()
        } catch {
            // Profile doesn't exist yet - create it with defaults
            // This handles cases where the database trigger hasn't run yet
            print("[Auth] Profile not found, creating default profile for user: \(userId)")
            let email = currentUser?.email
            let now = Date()

            // Extract display name from user metadata (set during signup)
            let userMetadata = currentUser?.userMetadata
            let displayName = userMetadata?["display_name"]?.stringValue
                ?? userMetadata?["full_name"]?.stringValue
                ?? userMetadata?["name"]?.stringValue

            // Generate a default handle from email if not provided
            let defaultHandle = email?.components(separatedBy: "@").first ?? "user_\(userId.uuidString.prefix(8))"

            let newProfile: [String: AnyEncodable] = [
                "id": AnyEncodable(userId),
                "email": AnyEncodable(email),
                "display_name": AnyEncodable(displayName),
                "handle": AnyEncodable(defaultHandle),
                "timezone": AnyEncodable(TimeZone.current.identifier),
                "created_at": AnyEncodable(ISO8601DateFormatter().string(from: now)),
                "updated_at": AnyEncodable(ISO8601DateFormatter().string(from: now)),
                "daily_quest_time_local": AnyEncodable("09:00"),
                "reminders_enabled": AnyEncodable(true),
                "nudge_after_days_inactive": AnyEncodable(3),
                "share_mood_in_circles": AnyEncodable(true),
                "ai_tone": AnyEncodable("friendly"),
                "privacy_mode": AnyEncodable("standard"),
                "current_streak_days": AnyEncodable(0),
                "longest_streak_days": AnyEncodable(0),
                "total_quests_completed": AnyEncodable(0),
                "total_exercises_completed": AnyEncodable(0),
                "subscription_tier": AnyEncodable("free"),
                "daily_ai_quota": AnyEncodable(10),
                "daily_ai_used": AnyEncodable(0)
            ]

            let createdProfile: DBProfile = try await supabase
                .from(Tables.profiles)
                .insert(newProfile)
                .select()
                .single()
                .execute()
                .value

            return createdProfile.toUserProfile()
        }
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
            // Normalize handle: lowercase, trimmed
            let normalizedHandle = handle.lowercased().trimmingCharacters(in: .whitespaces)

            // Validate handle format (letters, numbers, underscores only)
            let handleRegex = /^[a-z0-9_]{3,30}$/
            guard normalizedHandle.wholeMatch(of: handleRegex) != nil else {
                throw AuthError.invalidHandle
            }

            // Check if handle is available
            let isAvailable = try await isHandleAvailable(normalizedHandle, excludingUserId: userId)
            guard isAvailable else {
                throw AuthError.handleTaken
            }

            updates["handle"] = AnyEncodable(normalizedHandle)
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

    /// Check if a handle is available (not taken by another user)
    func isHandleAvailable(_ handle: String, excludingUserId: UUID? = nil) async throws -> Bool {
        var query = supabase
            .from(Tables.profiles)
            .select("id")
            .eq("handle", value: handle.lowercased())

        if let excludingUserId = excludingUserId {
            query = query.neq("id", value: excludingUserId)
        }

        let results: [DBProfileId] = try await query
            .execute()
            .value

        return results.isEmpty
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
        guard userId != nil else {
            throw AuthError.userNotFound
        }

        // Call delete-account Edge Function
        // This deletes all user data and the auth user
        struct DeleteResponse: Decodable {
            let success: Bool?
            let message: String?
            let error: String?
        }

        do {
            let response: DeleteResponse = try await supabase.functions.invoke(
                "delete-account",
                options: .init()
            )

            if let error = response.error {
                throw AuthError.unknown(error)
            }

            // Clear local state
            session = nil
            currentUser = nil
            CrashReporter.shared.clearUser()
            Analytics.shared.reset()

            print("[Auth] Account deleted successfully")
        } catch {
            print("[Auth] Delete account error: \(error)")
            throw AuthError.unknown("Failed to delete account: \(error.localizedDescription)")
        }
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
