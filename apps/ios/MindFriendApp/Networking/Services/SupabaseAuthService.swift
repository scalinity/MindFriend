import Foundation
import Supabase
import AuthenticationServices
import GoogleSignIn
import OSLog

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

    // MARK: - Caching Keys
    private enum CacheKeys {
        static let cachedProfile = "com.mindfriend.cachedProfile"
        static let cachedAuthState = "com.mindfriend.cachedAuthState"
        static let lastProfileFetch = "com.mindfriend.lastProfileFetch"
    }

    /// Minimum time before token expiry to trigger refresh (5 minutes)
    private let tokenRefreshThreshold: TimeInterval = 5 * 60

    /// Profile cache validity duration (1 hour)
    private let profileCacheValidityDuration: TimeInterval = 60 * 60

    init() {
        // Listen for auth state changes
        Task {
            for await (event, session) in supabase.auth.authStateChanges {
                self.session = session
                self.currentUser = session?.user

                switch event {
                case .initialSession:
                    Log.auth.debug("Initial session loaded")
                case .signedIn:
                    Log.auth.userAction("User signed in", userId: session?.user.id.uuidString ?? "unknown")
                    Analytics.shared.track(.signInCompleted, properties: ["provider": "supabase"])
                case .signedOut:
                    Log.auth.info("User signed out")
                    Analytics.shared.track(.signOut)
                    CrashReporter.shared.clearUser()
                case .tokenRefreshed:
                    Log.auth.debug("Token refreshed")
                case .userUpdated:
                    Log.auth.debug("User updated")
                case .passwordRecovery:
                    break
                case .mfaChallengeVerified:
                    Log.auth.debug("MFA challenge verified")
                case .userDeleted:
                    Log.auth.info("User deleted")
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

    /// Restore existing session on app launch (optimized - skips network refresh if token still valid)
    func restoreSession() async -> Bool {
        do {
            session = try await supabase.auth.session
            currentUser = session?.user

            guard let currentSession = session else {
                Log.auth.debug("No existing session found")
                clearCachedAuthState()
                return false
            }

            // Check if token needs refreshing (only if expiring within threshold)
            let needsRefresh = isTokenExpiringSoon(currentSession)

            if needsRefresh {
                Log.auth.debug("Token expiring soon, refreshing...")
                do {
                    session = try await supabase.auth.refreshSession()
                    currentUser = session?.user
                    Log.auth.debug("Session refreshed successfully")
                } catch {
                    Log.auth.warning("Session refresh failed: \(error.localizedDescription)")
                    // Token might still work for a bit, don't clear immediately
                    // Only clear if it's actually expired
                    if isTokenExpired(currentSession) {
                        session = nil
                        currentUser = nil
                        clearCachedAuthState()
                        return false
                    }
                    // Keep using the old session for now
                    Log.auth.debug("Using existing session despite refresh failure")
                }
            } else {
                Log.auth.debug("Token still valid, skipping refresh")
            }

            // Cache that we have a valid session
            saveCachedAuthState(isAuthenticated: true)
            return true
        } catch {
            Log.auth.debug("No existing session: \(error.localizedDescription)")
            clearCachedAuthState()
            return false
        }
    }

    /// Check if token is expiring within the threshold
    private func isTokenExpiringSoon(_ session: Session) -> Bool {
        let expiresAt = Date(timeIntervalSince1970: TimeInterval(session.expiresAt ?? 0))
        let timeUntilExpiry = expiresAt.timeIntervalSinceNow
        return timeUntilExpiry < tokenRefreshThreshold
    }

    /// Check if token has actually expired
    private func isTokenExpired(_ session: Session) -> Bool {
        let expiresAt = Date(timeIntervalSince1970: TimeInterval(session.expiresAt ?? 0))
        return expiresAt < Date()
    }

    /// Ensure we have a valid session, refreshing if needed
    func ensureValidSession() async throws {
        guard session != nil else {
            throw AuthError.sessionExpired
        }

        do {
            session = try await supabase.auth.refreshSession()
            currentUser = session?.user
            Log.auth.debug("Session refreshed for API call")
        } catch {
            Log.auth.warning("Session refresh failed: \(error.localizedDescription)")
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
        clearCachedAuthState()
        clearCachedProfile()
        CrashReporter.shared.clearUser()
        Analytics.shared.reset()
    }

    // MARK: - Auth State Caching

    /// Save cached auth state to UserDefaults
    private func saveCachedAuthState(isAuthenticated: Bool) {
        UserDefaults.standard.set(isAuthenticated, forKey: CacheKeys.cachedAuthState)
    }

    /// Clear cached auth state
    private func clearCachedAuthState() {
        UserDefaults.standard.removeObject(forKey: CacheKeys.cachedAuthState)
    }

    /// Get cached auth state (for instant UI on launch)
    func getCachedAuthState() -> Bool {
        UserDefaults.standard.bool(forKey: CacheKeys.cachedAuthState)
    }

    // MARK: - Profile Caching

    /// Save profile to cache
    private func cacheProfile(_ profile: UserProfile) {
        do {
            let data = try JSONEncoder().encode(profile)
            UserDefaults.standard.set(data, forKey: CacheKeys.cachedProfile)
            UserDefaults.standard.set(Date(), forKey: CacheKeys.lastProfileFetch)
            Log.auth.debug("Profile cached successfully")
        } catch {
            Log.auth.warning("Failed to cache profile: \(error.localizedDescription)")
        }
    }

    /// Clear cached profile
    func clearCachedProfile() {
        UserDefaults.standard.removeObject(forKey: CacheKeys.cachedProfile)
        UserDefaults.standard.removeObject(forKey: CacheKeys.lastProfileFetch)
    }

    /// Get cached profile (returns nil if cache is invalid or expired)
    func getCachedProfile() -> UserProfile? {
        guard let data = UserDefaults.standard.data(forKey: CacheKeys.cachedProfile),
              let lastFetch = UserDefaults.standard.object(forKey: CacheKeys.lastProfileFetch) as? Date else {
            return nil
        }

        // Check if cache is still valid
        let cacheAge = Date().timeIntervalSince(lastFetch)
        guard cacheAge < profileCacheValidityDuration else {
            Log.auth.debug("Profile cache expired (age: \(Int(cacheAge))s)")
            return nil
        }

        do {
            let profile = try JSONDecoder().decode(UserProfile.self, from: data)
            Log.auth.debug("Loaded profile from cache (age: \(Int(cacheAge))s)")
            return profile
        } catch {
            Log.auth.warning("Failed to decode cached profile: \(error.localizedDescription)")
            clearCachedProfile()
            return nil
        }
    }

    /// Check if we have a valid cached profile
    func hasCachedProfile() -> Bool {
        getCachedProfile() != nil
    }

    // MARK: - Profile Management

    func fetchProfile() async throws -> UserProfile {
        guard let userId = userId else {
            throw AuthError.invalidCredentials
        }

        // Query all three tables in parallel for efficiency
        async let profileTask: DBProfileRow = supabase
            .from(Tables.profiles)
            .select()
            .eq("id", value: userId)
            .single()
            .execute()
            .value

        async let settingsTask: DBUserSettingsRow = supabase
            .from(Tables.userSettings)
            .select()
            .eq("user_id", value: userId)
            .single()
            .execute()
            .value

        async let statsTask: DBUserStatsRow = supabase
            .from(Tables.userStats)
            .select()
            .eq("user_id", value: userId)
            .single()
            .execute()
            .value

        do {
            let (profile, settings, stats) = try await (profileTask, settingsTask, statsTask)
            let userProfile = profile.toUserProfile(settings: settings, stats: stats)
            // Cache the profile for faster startup next time
            cacheProfile(userProfile)
            return userProfile
        } catch {
            // If any table is missing data, the DB trigger may not have run yet.
            // Log the error but don't try to create rows here - let the trigger handle it.
            Log.auth.warning("Failed to fetch profile data: \(error.localizedDescription)")
            throw AuthError.userNotFound
        }
    }

    /// Fetch profile with cache fallback - returns cached immediately, refreshes in background
    func fetchProfileWithCache() async -> UserProfile? {
        // First, try to get cached profile for instant return
        if let cached = getCachedProfile() {
            // Refresh in background (don't await)
            Task {
                do {
                    _ = try await fetchProfile()
                    Log.auth.debug("Profile refreshed in background")
                } catch {
                    Log.auth.warning("Background profile refresh failed: \(error.localizedDescription)")
                }
            }
            return cached
        }

        // No cache, must fetch from network
        do {
            return try await fetchProfile()
        } catch {
            Log.auth.warning("Profile fetch failed: \(error.localizedDescription)")
            return nil
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
    /// Uses SECURITY DEFINER RPC to avoid exposing profile data
    func isHandleAvailable(_ handle: String, excludingUserId: UUID? = nil) async throws -> Bool {
        // Build params - exclude_user_id is optional
        var params: [String: AnyEncodable] = [
            "p_handle": AnyEncodable(handle)
        ]
        if let excludingUserId = excludingUserId {
            params["p_exclude_user_id"] = AnyEncodable(excludingUserId)
        }

        let result: Bool = try await supabase
            .rpc("is_handle_available", params: params)
            .execute()
            .value

        return result
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
            .from(Tables.userSettings)
            .update(updates)
            .eq("user_id", value: userId)
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

            Log.auth.info("Account deleted successfully")
        } catch {
            Log.auth.error("Delete account error: \(error.localizedDescription)")
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
