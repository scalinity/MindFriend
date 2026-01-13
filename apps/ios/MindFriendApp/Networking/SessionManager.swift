import Foundation

/// Manages user session and token refresh
@MainActor
final class SessionManager: ObservableObject {
    private let apiClient: APIClient
    private let keychainManager: KeychainManager

    @Published private(set) var isRestoring = true
    @Published private(set) var hasValidSession = false

    private var refreshTask: Task<Void, Error>?

    init(apiClient: APIClient, keychainManager: KeychainManager) {
        self.apiClient = apiClient
        self.keychainManager = keychainManager
    }

    // MARK: - Token Access

    func getAccessToken() async -> String? {
        await keychainManager.getAccessToken()
    }

    // MARK: - Session Management

    func restoreSession() async {
        defer { isRestoring = false }

        let hasTokens = await keychainManager.hasValidTokens()
        guard hasTokens else {
            hasValidSession = false
            return
        }

        // If access token is expired, try to refresh
        let isExpired = await keychainManager.isAccessTokenExpired()
        if isExpired {
            do {
                try await refreshAccessToken()
                hasValidSession = true
            } catch {
                // Refresh failed, clear tokens
                await keychainManager.clearTokens()
                hasValidSession = false
            }
        } else {
            hasValidSession = true
        }
    }

    func saveTokens(_ tokens: AuthTokens) async {
        await keychainManager.saveTokens(tokens)
        hasValidSession = true
    }

    func clearSession() async {
        await keychainManager.clearTokens()
        hasValidSession = false
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: - Token Refresh

    func refreshAccessToken() async throws {
        // Coalesce multiple refresh requests
        if let existingTask = refreshTask {
            return try await existingTask.value
        }

        let task = Task { @MainActor [keychainManager, apiClient] in
            defer { self.refreshTask = nil }

            guard let refreshToken = await keychainManager.getRefreshToken() else {
                throw APIError.unauthorized
            }

            let request = RefreshTokenRequest(refreshToken: refreshToken)
            let tokens: AuthTokens = try await apiClient.request(.refreshToken(request))
            await keychainManager.saveTokens(tokens)
        }

        refreshTask = task
        try await task.value
    }

    // MARK: - Logout

    func logout() async {
        do {
            try await apiClient.requestVoid(.logout)
        } catch {
            // Ignore logout errors
        }

        await clearSession()
    }
}
