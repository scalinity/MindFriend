import Foundation
import Supabase
import AuthenticationServices
import GoogleSignIn
import OSLog
import SwiftUI
import Combine

/// Only a locally requested recovery with the same PKCE verifier can open reset mode.
struct PasswordRecoveryIntent: Codable {
    let email: String
    let verifier: Data
    let requestedAt: Date
    var verifiedUserId: UUID?

    func matches(email: String?, verifier: Data?, now: Date = Date()) -> Bool {
        guard verifiedUserId == nil, let email, let verifier,
              now >= requestedAt, now.timeIntervalSince(requestedAt) < 3600 else { return false }
        return self.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            == email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            && self.verifier == verifier
    }
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case invalidCredentials
    case missingIdToken
    case emailConfirmationRequired
    case userNotFound
    case accountNotFound
    case sessionExpired
    case sessionUnavailable
    case profileUnavailable
    case handleTaken
    case invalidHandle
    case signOutFailed(String)
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
        case .sessionUnavailable:
            return "Unable to keep you signed in. Please try signing in again."
        case .profileUnavailable:
            return "We couldn't load your profile. Check your connection and try again."
        case .handleTaken:
            return "This handle is already taken. Please choose another."
        case .invalidHandle:
            return "Handle can only contain letters, numbers, and underscores"
        case .signOutFailed(let message):
            return "Failed to sign out: \(message)"
        case .unknown(let message):
            return message
        }
    }
}

/// Handles authentication with Supabase (Apple Sign-In, Google Sign-In)
@MainActor
final class SupabaseAuthService: ObservableObject {
    @Published private(set) var isSigningIn = false
    @Published private(set) var isLoading = false
    @Published var requiresPasswordReset = false
    @Published private(set) var currentUser: User?
    @Published private(set) var session: Session?
    @Published private(set) var signOutWarning: String?

    // MARK: - Dependencies
    private let secureStorage: SecureStorage
    // ✅ ARCHITECTURE FIX: Remove PathwayCacheService dependency (breaks circular reference)
    // Use closure injection instead
    private var onLogoutHandler: (() -> Void)?
    private var onAccountChangeHandler: ((UUID?) -> Void)?
    private var beforeSignOutHandler: ((UUID) async -> Void)?
    private let authStorage = AuthClient.Configuration.defaultLocalStorage
    private let recoveryIntentKey = "com.mindfriend.passwordRecoveryIntent"
    private var logoutCleanupTask: Task<Void, Never>?
    private var signOutTask: Task<Void, Error>?
    private var handledSignOutEvents = 0

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

    /// Authentication headers for Edge Function calls
    /// Returns headers with Bearer token if session exists, empty otherwise
    var authHeaders: [String: String] {
        guard let accessToken = session?.accessToken else {
            return [:]
        }
        return ["Authorization": "Bearer \(accessToken)"]
    }

    init(
        secureStorage: SecureStorage = SecureStorage()
    ) {
        self.secureStorage = secureStorage
        // Listen for auth state changes
        Task {
            await setupAuthStateListener()
        }
    }

    // ✅ ARCHITECTURE FIX: Set logout handler (called by DependencyContainer)
    func setLogoutHandler(_ handler: @escaping () -> Void) {
        self.onLogoutHandler = handler
    }

    func setAccountChangeHandler(_ handler: @escaping (UUID?) -> Void) {
        onAccountChangeHandler = handler
    }

    func setBeforeSignOutHandler(_ handler: @escaping (UUID) async -> Void) {
        beforeSignOutHandler = handler
    }

    private func waitForLogout() async {
        _ = try? await signOutTask?.value
        await logoutCleanupTask?.value
    }

    // MARK: - Auth State Listener

    /// Listen for auth state changes from Supabase
    private func setupAuthStateListener() async {
        for await (event, session) in supabase.auth.authStateChanges {
            if event == .signedOut, handledSignOutEvents > 0 {
                handledSignOutEvents -= 1
                continue
            }
            let departingUserId = self.currentUser?.id.uuidString ?? self.session?.user.id.uuidString
            if event == .signedOut || event == .userDeleted {
                clearLocalAuthState(userId: departingUserId)
                continue
            }
            await logoutCleanupTask?.value
            if let session {
                do {
                    try applyValidatedSession(session)
                } catch {
                    Log.auth.warning("Auth event session is unavailable to the SDK")
                    continue
                }
            } else {
                if currentUser != nil { onAccountChangeHandler?(nil) }
                self.session = nil
                self.currentUser = nil
            }

            switch event {
            case .initialSession:
                restoreVerifiedRecovery(for: session?.user.id)
                Log.auth.debug("Initial session loaded")
            case .signedIn:
                restoreVerifiedRecovery(for: session?.user.id)
                Log.auth.userAction("User signed in", userId: session?.user.id.uuidString ?? "unknown")
                Analytics.shared.track(.signInCompleted, properties: ["provider": "supabase"])
            case .signedOut:
                break // Handled before overwriting the departing user.
            case .tokenRefreshed:
                Log.auth.debug("Token refreshed")
            case .userUpdated:
                Log.auth.debug("User updated")
            case .passwordRecovery:
                requiresPasswordReset = true
            case .mfaChallengeVerified:
                Log.auth.debug("MFA challenge verified")
            case .userDeleted:
                Log.auth.info("User deleted")
            @unknown default:
                break
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
        await waitForLogout()
        do {
            let currentSession = try await supabase.auth.session
            try applyValidatedSession(currentSession)

            // Check if token needs refreshing (only if expiring within threshold)
            let needsRefresh = isTokenExpiringSoon(currentSession)

            if needsRefresh {
                Log.auth.debug("Token expiring soon, refreshing...")
                do {
                    _ = try await supabase.auth.refreshSession()
                    try applyValidatedSession(currentSession)
                    Log.auth.debug("Session refreshed successfully")
                } catch {
                    Log.auth.warning("Session refresh failed: \(error.localizedDescription)")
                    // Token might still work for a bit, don't clear immediately
                    // Only clear if it's actually expired
                    if isTokenExpired(currentSession) {
                        onAccountChangeHandler?(nil)
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

            // Refresh can return successfully even when storing its session failed.
            try applyValidatedSession(currentSession)
            // Cache that we have a valid session
            saveCachedAuthState(isAuthenticated: true)
            return true
        } catch {
            Log.auth.debug("No existing session: \(error.localizedDescription)")
            if currentUser != nil { onAccountChangeHandler?(nil) }
            session = nil
            currentUser = nil
            clearCachedAuthState()
            return false
        }
    }

    /// Validate what the SDK will read for requests, rather than a sign-in response alone.
    /// A newer token for the same user is valid after automatic refresh.
    nonisolated static func validatedSession(_ storedSession: Session?, expectedUserId: UUID) throws -> Session {
        guard let storedSession,
              storedSession.user.id == expectedUserId,
              !storedSession.accessToken.isEmpty,
              !storedSession.isExpired else { throw AuthError.sessionUnavailable }
        return storedSession
    }

    private func applyValidatedSession(_ candidate: Session) throws {
        // A delayed event for another account must not clear a newer session.
        guard let stored = supabase.auth.currentSession else {
            if currentUser != nil { onAccountChangeHandler?(nil) }
            session = nil
            currentUser = nil
            clearCachedAuthState()
            throw AuthError.sessionUnavailable
        }
        let validated = try Self.validatedSession(stored, expectedUserId: candidate.user.id)
        if currentUser?.id != validated.user.id {
            onAccountChangeHandler?(validated.user.id)
        }
        session = validated
        currentUser = validated.user
    }

    /// Check if token is expiring within the threshold
    private func isTokenExpiringSoon(_ session: Session) -> Bool {
        let expiresAt = Date(timeIntervalSince1970: TimeInterval(session.expiresAt))
        let timeUntilExpiry = expiresAt.timeIntervalSinceNow
        return timeUntilExpiry < tokenRefreshThreshold
    }

    /// Check if token has actually expired
    private func isTokenExpired(_ session: Session) -> Bool {
        let expiresAt = Date(timeIntervalSince1970: TimeInterval(session.expiresAt))
        return expiresAt < Date()
    }

    /// Refresh near expiry; a network failure must not erase a returning session.
    func ensureValidSession() async throws {
        guard let currentSession = session else { throw AuthError.sessionExpired }
        guard isTokenExpiringSoon(currentSession) else {
            try applyValidatedSession(currentSession)
            return
        }
        do {
            _ = try await supabase.auth.refreshSession()
            try applyValidatedSession(currentSession)
        } catch {
            // The SDK emits signedOut for an invalid refresh token. Transport failures
            // propagate to the caller while keeping the recoverable local session.
            Log.auth.warning("Session refresh unavailable")
            throw error
        }
    }

    func handleAuthCallback(_ url: URL) async throws -> UserProfile {
        await waitForLogout()
        guard url.scheme == SupabaseConfig.redirectURL.scheme,
              url.host == SupabaseConfig.redirectURL.host,
              url.path == SupabaseConfig.redirectURL.path else { throw AuthError.invalidCredentials }
        let intent = loadRecoveryIntent()
        // The SDK removes this verifier after a successful PKCE exchange.
        let verifier = try authStorage.retrieve(key: pkceVerifierKey)
        let restored = try await supabase.auth.session(from: url)
        try applyValidatedSession(restored)
        if var intent, intent.matches(email: restored.user.email, verifier: verifier) {
            intent.verifiedUserId = restored.user.id
            try authStorage.store(key: recoveryIntentKey, value: JSONEncoder().encode(intent))
            requiresPasswordReset = true
        }
        return try await fetchProfile()
    }

    func completePasswordRecovery(password: String) async throws {
        guard requiresPasswordReset, let session,
              loadRecoveryIntent()?.verifiedUserId == session.user.id else { throw AuthError.sessionExpired }
        _ = try await supabase.auth.update(user: .init(password: password))
        try authStorage.remove(key: recoveryIntentKey)
        requiresPasswordReset = false
    }

    private var pkceVerifierKey: String {
        // Supabase 2.55.4's default storage key; the shared client uses default auth storage.
        "sb-\(SupabaseConfig.projectURL.host!.split(separator: ".")[0])-auth-token-code-verifier"
    }

    private func loadRecoveryIntent() -> PasswordRecoveryIntent? {
        guard let data = try? authStorage.retrieve(key: recoveryIntentKey) else { return nil }
        return try? JSONDecoder().decode(PasswordRecoveryIntent.self, from: data)
    }

    private func restoreVerifiedRecovery(for userId: UUID?) {
        let verifiedUserId = loadRecoveryIntent()?.verifiedUserId
        requiresPasswordReset = userId != nil && verifiedUserId == userId
    }

    // MARK: - Apple Sign-In

    func signInWithApple(
        identityToken: Data,
        authorizationCode: Data,
        fullName: PersonNameComponents?,
        email: String?
    ) async throws -> UserProfile {
        await waitForLogout()
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

            try applyValidatedSession(session)

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
        await waitForLogout()
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

            try applyValidatedSession(session)

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
        await waitForLogout()
        guard !isSigningIn else { throw AuthError.unknown("An authentication request is already in progress.") }
        isSigningIn = true
        defer { isSigningIn = false }

        do {
            let response = try await supabase.auth.signUp(
                email: email,
                password: password,
                data: displayName.map { ["display_name": .string($0)] } ?? [:],
                redirectTo: SupabaseConfig.redirectURL
            )

            guard let session = response.session else {
                // Email confirmation required
                throw AuthError.emailConfirmationRequired
            }

            try applyValidatedSession(session)

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
        await waitForLogout()
        isSigningIn = true
        defer { isSigningIn = false }

        do {
            let session: Session
            do {
                session = try await supabase.auth.signIn(email: email, password: password)
            } catch {
                // These account errors apply only to authentication, not profile loading.
                let errorString = String(describing: error).lowercased()
                if errorString.contains("email_not_confirmed") || errorString.contains("email not confirmed") {
                    throw AuthError.emailConfirmationRequired
                }
                if errorString.contains("invalid_credentials") || errorString.contains("invalid login") {
                    throw AuthError.invalidCredentials
                }
                if errorString.contains("user_not_found") || errorString.contains("user not found") {
                    throw AuthError.accountNotFound
                }
                throw AuthError.unknown(error.localizedDescription)
            }

            try applyValidatedSession(session)

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
        await waitForLogout()
        guard !isSigningIn else { throw AuthError.unknown("An authentication request is already in progress.") }
        isSigningIn = true
        defer { isSigningIn = false }
        try await supabase.auth.resetPasswordForEmail(email, redirectTo: SupabaseConfig.redirectURL)
        guard let verifier = try authStorage.retrieve(key: pkceVerifierKey) else {
            throw AuthError.unknown("Unable to save password recovery. Please request a new link.")
        }
        let intent = PasswordRecoveryIntent(email: email, verifier: verifier, requestedAt: Date())
        try authStorage.store(key: recoveryIntentKey, value: JSONEncoder().encode(intent))
    }

    // MARK: - Sign Out

    func signOut() async throws {
        if let signOutTask { return try await signOutTask.value }
        let task = Task { try await performSignOut() }
        signOutTask = task
        defer { signOutTask = nil }
        try await task.value
    }

    private func performSignOut() async throws {
        isLoading = true
        defer { isLoading = false }
        signOutWarning = nil
        let departingOwner = currentUser?.id ?? session?.user.id
        let userIdForCleanup = departingOwner?.uuidString
        if let departingOwner { await beforeSignOutHandler?(departingOwner) }
        // Consume exactly the event produced by this explicit operation. Cleanup below
        // is awaited even if remote revocation fails after the SDK removes its session.
        if supabase.auth.currentSession != nil { handledSignOutEvents += 1 }
        let remoteFailed = try await Self.finishLogout(
            revokeRemote: { try await supabase.auth.signOut() },
            removeLocalCredentials: { try self.removeLocalSDKSession() },
            cleanup: {
                clearLocalAuthState(userId: userIdForCleanup)
                await logoutCleanupTask?.value
            }
        )
        if remoteFailed {
            signOutWarning = "Signed out on this device. The server could not confirm sign-out on other devices."
            Log.auth.warning("Local sign-out completed; remote revocation was unavailable")
        }
    }

    /// Keep remote revocation failure separate from the local logout guarantee.
    static func finishLogout(
        revokeRemote: () async throws -> Void,
        removeLocalCredentials: () throws -> Void,
        cleanup: () async -> Void
    ) async throws -> Bool {
        var remoteFailed = false
        do { try await revokeRemote() } catch { remoteFailed = true }
        try removeLocalCredentials()
        await cleanup()
        return remoteFailed
    }

    private func removeLocalSDKSession() throws {
        // The SDK logs storage-delete failures rather than throwing them. Remove and
        // verify its configured default keys before presenting a successful logout.
        let project = SupabaseConfig.projectURL.host!.split(separator: ".")[0]
        try authStorage.remove(key: "sb-\(project)-auth-token")
        try authStorage.remove(key: "supabase.session")
        try authStorage.remove(key: pkceVerifierKey)
        guard supabase.auth.currentSession == nil else {
            throw AuthError.signOutFailed("Unable to remove this device's saved session. Please try again.")
        }
    }

    private func clearLocalAuthState(userId: String?) {
        if userId == nil, currentUser == nil, session == nil, logoutCleanupTask != nil { return }
        onAccountChangeHandler?(nil)
        session = nil
        currentUser = nil
        requiresPasswordReset = false
        clearCachedAuthState()
        clearCachedProfile()
        CrashReporter.shared.clearUser()
        Analytics.shared.track(.signOut)
        Analytics.shared.reset()
        // Clear process caches synchronously, before another account can sign in.
        onLogoutHandler?()
        try? authStorage.remove(key: recoveryIntentKey)
        // The legacy key also protects persisted pathway journals. Logout may evict
        // plaintext/key caches, but must not destroy the only key for retained data.
        secureStorage.clearCachedKey()
        let previousCleanup = logoutCleanupTask
        logoutCleanupTask = Task { @MainActor in
            await previousCleanup?.value
            await clearOfflineDataOnLogout(userId: userId)
            await supabase.removeAllChannels()
        }
    }

    // TD-HIGH-005: Enabled offline data cleanup on logout
    /// Clear all offline data when user logs out
    private func clearOfflineDataOnLogout(userId: String?) async {
        // Clear download manager state (cancel downloads, clear tasks)
        await DownloadManager.shared.clearOnLogout()
        
        // Clear sync queue manager state (pending sync items)
        await SyncQueueManager.shared.clearOnLogout()
        
        // Clear offline cache (user-specific cached data)
        await OfflineCacheService.shared.clearOnLogout()
        
        // Clear offline storage manager and delete user files
        if let userId = userId {
            try? await OfflineStorageManager.shared.deleteUserData(userId: userId)
        }
        await OfflineStorageManager.shared.clearCurrentUser()
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
            guard let userId, profile.id == userId else { return nil }
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
        // The SDK can otherwise silently fall back to the anonymous key.
        guard let currentSession = session else { throw AuthError.sessionExpired }
        if currentSession.isExpired {
            _ = try await supabase.auth.session
        }
        try applyValidatedSession(currentSession)
        let userId = currentSession.user.id

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

        // A sponsorship refresh outage must not turn valid profile data into
        // a failed login. Paid operations still validate entitlement on server.
        async let sponsorshipTask: Bool? = try? await supabase
            .rpc("refresh_sponsored_entitlement", params: ["p_user_id": userId])
            .execute().value

        do {
            let (profile, settings, stats) = try await (profileTask, settingsTask, statsTask)
            let hasSponsoredAccess = await sponsorshipTask ?? false
            guard self.userId == userId else { throw AuthError.sessionExpired }
            _ = try Self.validatedSession(supabase.auth.currentSession, expectedUserId: userId)
            let userProfile = profile.toUserProfile(settings: settings, stats: stats, hasSponsoredAccess: hasSponsoredAccess)
            // Cache the profile for faster startup next time
            cacheProfile(userProfile)
            return userProfile
        } catch {
            Log.auth.warning("Profile load failed (\(String(reflecting: type(of: error))))")
            if let authError = error as? AuthError { throw authError }
            // Missing rows, permissions, transport and decoding failures do not
            // establish that the account is absent.
            throw AuthError.profileUnavailable
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

    nonisolated static func normalizedHandle(_ handle: String) throws -> String {
        let normalizedHandle = handle.lowercased().trimmingCharacters(in: .whitespaces)
        let handleRegex = /^[a-z0-9_]{3,30}$/
        guard normalizedHandle.wholeMatch(of: handleRegex) != nil else {
            throw AuthError.invalidHandle
        }
        return normalizedHandle
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
            let normalizedHandle = try Self.normalizedHandle(handle)

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
        guard let departingOwner = userId else {
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
            guard response.success == true else {
                throw AuthError.unknown("The server did not confirm account deletion.")
            }

            // Server deletion is confirmed. Remove only keys and drafts owned by this
            // account; the shared legacy journal key may still protect another account.
            let ownerKey = departingOwner.uuidString.lowercased()
            var retainedKeyError: Error?
            for key in ["pathway.\(ownerKey)", "voice-transcript.\(ownerKey)"] {
                do { try SecureStorage(keyIdentifier: key).deleteEncryptionKey() }
                catch { retainedKeyError = error }
            }
            UserDefaults.standard.removeObject(forKey: "voice-transcript.\(ownerKey)")
            try await signOut()
            signOutWarning = nil
            if retainedKeyError != nil {
                throw AuthError.unknown("Your account was deleted and signed out, but a local encryption key could not be removed.")
            }

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
