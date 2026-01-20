import Foundation
import SafariServices
#if canImport(UIKit)
import UIKit
#endif
import OSLog
import CommonCrypto
import Supabase

// MARK: - Configuration

enum Configuration {
    // Notion OAuth - requires developer registration
    // Get at https://www.notion.so/my-integrations
    // Set NOTION_CLIENT_ID in Supabase Edge Function environment variables
    static var notionClientId: String = ""

    /// Fetches public configuration from Supabase Edge Function
    static func loadConfiguration() async {
        do {
            struct PublicConfig: Codable {
                let notionClientId: String?
            }
            let config: PublicConfig = try await supabase.functions.invoke(
                "public-config",
                options: FunctionInvokeOptions(method: .get)
            )
            if let clientId = config.notionClientId {
                notionClientId = clientId
            }
        } catch {
            print("Failed to load public config: \(error)")
        }
    }
}

// MARK: - OAuthHandler

/// Simplified OAuth handler that leverages Supabase Auth for Google/Microsoft
/// and handles Notion OAuth for journal exports
final class OAuthHandler: NSObject, ObservableObject {
    static let shared = OAuthHandler()

    private let logger = Logger(subsystem: "com.mindfriend", category: "OAuth")
    private let encryptionService: EncryptionServiceProtocol
    private var supabaseClient: SupabaseClient

    @available(*, deprecated, message: "Use init(supabaseClient:encryptionService:) instead")
    override convenience init() {
        self.init(supabaseClient: supabase, encryptionService: OAuthEncryptionService())
    }

    init(supabaseClient: SupabaseClient, encryptionService: EncryptionServiceProtocol) {
        self.supabaseClient = supabaseClient
        self.encryptionService = encryptionService
        super.init()

        // Load public configuration asynchronously
        Task {
            await Configuration.loadConfiguration()
        }
    }

    // MARK: - Calendar Integration (Uses Supabase Auth)

    /// Checks if user is signed in with Google (for calendar access)
    func isGoogleConnected() async -> Bool {
        do {
            let session = try await supabase.auth.session
            // Check if user has a Google identity
            return session.user.identities?.contains { $0.provider == "google" } ?? false
        } catch {
            logger.error("Failed to get session for Google check: \(error.localizedDescription)")
            return false
        }
    }

    /// Gets access token for Google Calendar
    func getGoogleAccessToken() async throws -> String {
        let session = try await supabase.auth.session
        // Check if user has a Google identity
        guard session.user.identities?.contains(where: { $0.provider == "google" }) ?? false else {
            throw OAuthError.notConnected
        }
        return session.accessToken
    }

    // MARK: - Notion OAuth (Custom Flow)

    /// Initiates Notion OAuth flow
    func connectNotion(from viewController: UIViewController) async throws {
        let state = generateState()
        let codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)

        let oauthState = OAuthState(
            state: state,
            codeVerifier: codeVerifier,
            integrationType: .notion,
            redirectUri: "mindfriend://oauth/callback/notion",
            createdAt: Date()
        )

        guard encryptionService.storeOAuthState(oauthState) else {
            throw OAuthError.stateStorageFailed
        }

        var components = URLComponents(string: "https://api.notion.com/v1/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Configuration.notionClientId),
            URLQueryItem(name: "redirect_uri", value: "mindfriend://oauth/callback/notion"),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "owner", value: "user")
        ]

        guard let authUrl = components.url else {
            throw OAuthError.invalidAuthorizationURL
        }

        await MainActor.run {
            isAuthenticating = true
            pendingIntegration = .notion
            authError = nil
        }

        let safariVC = SFSafariViewController(url: authUrl)
        safariVC.delegate = self

        await MainActor.run {
            viewController.present(safariVC, animated: true)
        }
    }

    /// Exchanges Notion authorization code for token
    func exchangeNotionCode(_ code: String) async throws -> OAuthToken {
        guard let storedState = encryptionService.retrieveOAuthState(for: .notion) else {
            throw OAuthError.invalidState
        }

        var request = URLRequest(url: URL(string: "https://api.notion.com/v1/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Basic \(Data("\(Configuration.notionClientId):".utf8).base64EncodedString())", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": "mindfriend://oauth/callback/notion"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw OAuthError.tokenExchangeFailed(400)
        }

        let decoder = JSONDecoder()
        let tokenResponse = try decoder.decode(NotionTokenResponse.self, from: data)

        let token = OAuthToken(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            tokenType: "bearer",
            expiresAt: Date().addingTimeInterval(86400 * 365), // Notion tokens don't expire
            scope: tokenResponse.scope
        )

        guard encryptionService.storeOAuthToken(token, for: .notion) else {
            throw OAuthError.tokenStorageFailed
        }

        encryptionService.deleteOAuthState(for: .notion)

        return token
    }

    /// Gets Notion access token
    func getNotionAccessToken() async throws -> String {
        guard let token = encryptionService.retrieveOAuthToken(for: .notion) else {
            throw OAuthError.notConnected
        }
        return token.accessToken
    }

    /// Checks if Notion is connected
    func isNotionConnected() -> Bool {
        encryptionService.retrieveOAuthToken(for: .notion) != nil
    }

    /// Disconnects Notion
    func disconnectNotion() {
        encryptionService.deleteOAuthToken(for: .notion)
    }

    // MARK: - Connection Status

    /// Returns all available calendar integrations that the user can use
    func availableCalendarIntegrations() async -> [IntegrationType] {
        var available: [IntegrationType] = []

        if await isGoogleConnected() {
            available.append(.googleCalendar)
        }
        // TODO: Add Microsoft Calendar support when .microsoftCalendar is added to IntegrationType

        return available
    }

    /// Checks if any calendar is connected
    func isAnyCalendarConnected() async -> Bool {
        await isGoogleConnected()
    }

    // MARK: - PKCE Helpers

    func generateState() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    func generateCodeChallenge(from verifier: String) -> String {
        guard let data = verifier.data(using: .utf8) else { return "" }
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG($0.count), &hash) }
        let hashData = Data(hash)
        return hashData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Published State

    @Published var isAuthenticating = false
    @Published var authError: OAuthError?
    @Published var pendingIntegration: IntegrationType?
}

// MARK: - SFSafariViewControllerDelegate

extension OAuthHandler: SFSafariViewControllerDelegate {
    nonisolated func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        Task { @MainActor in
            isAuthenticating = false
            pendingIntegration = nil
            authError = .userCancelled
        }
    }
}

// MARK: - Error Types

enum OAuthError: LocalizedError {
    case userCancelled
    case loadFailed
    case invalidState
    case stateStorageFailed
    case tokenStorageFailed
    case invalidAuthorizationURL
    case invalidResponse
    case tokenExchangeFailed(Int)
    case tokenRefreshFailed(Int)
    case noRefreshToken
    case notConnected
    case unsupportedIntegration
    case providerError(String)

    var errorDescription: String? {
        switch self {
        case .userCancelled: return "Authentication was cancelled"
        case .loadFailed: return "Failed to load authentication page"
        case .invalidState: return "Invalid authentication state"
        case .stateStorageFailed: return "Failed to store authentication state"
        case .tokenStorageFailed: return "Failed to store authentication token"
        case .invalidAuthorizationURL: return "Invalid authorization URL"
        case .invalidResponse: return "Invalid server response"
        case .tokenExchangeFailed(let code): return "Token exchange failed (HTTP \(code))"
        case .tokenRefreshFailed(let code): return "Token refresh failed (HTTP \(code))"
        case .noRefreshToken: return "No refresh token available - please reconnect"
        case .notConnected: return "Not connected - please sign in first"
        case .unsupportedIntegration: return "This integration is not yet supported"
        case .providerError(let message): return "Provider error: \(message)"
        }
    }
}

// MARK: - Response Types

private struct NotionTokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let tokenType: String
    let scope: String?
    let owner: NotionOwner

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case scope
        case owner
    }
}

private struct NotionOwner: Codable {
    let user: NotionUser
}

private struct NotionUser: Codable {
    let id: String
    let name: String?
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case avatarUrl = "avatar_url"
    }
}

// MARK: - Encryption Service Protocol

protocol EncryptionServiceProtocol {
    func storeOAuthToken(_ token: OAuthToken, for integrationType: IntegrationType) -> Bool
    func retrieveOAuthToken(for integrationType: IntegrationType) -> OAuthToken?
    func deleteOAuthToken(for integrationType: IntegrationType) -> Bool
    func storeOAuthState(_ state: OAuthState) -> Bool
    func retrieveOAuthState(for integrationType: IntegrationType) -> OAuthState?
    func deleteOAuthState(for integrationType: IntegrationType)
}

// MARK: - OAuth Encryption Service (Implementation)

final class OAuthEncryptionService: EncryptionServiceProtocol {
    private let keychainService = "com.mindfriend.integrations.oauth"

    func storeOAuthToken(_ token: OAuthToken, for integrationType: IntegrationType) -> Bool {
        guard let tokenData = try? JSONEncoder().encode(token),
              let encryptedData = encrypt(tokenData) else { return false }
        let account = "oauth_token_\(integrationType.rawValue)"
        return storeInKeychain(encryptedData, for: account)
    }

    func retrieveOAuthToken(for integrationType: IntegrationType) -> OAuthToken? {
        let account = "oauth_token_\(integrationType.rawValue)"
        guard let encryptedData = retrieveFromKeychain(for: account),
              let decryptedData = decrypt(encryptedData),
              let token = try? JSONDecoder().decode(OAuthToken.self, from: decryptedData) else { return nil }
        return token
    }

    func deleteOAuthToken(for integrationType: IntegrationType) -> Bool {
        let account = "oauth_token_\(integrationType.rawValue)"
        return deleteFromKeychain(for: account)
    }

    func storeOAuthState(_ state: OAuthState) -> Bool {
        guard let stateData = try? JSONEncoder().encode(state),
              let encryptedData = encrypt(stateData) else { return false }
        let account = "oauth_state_\(state.integrationType.rawValue)"
        return storeInKeychain(encryptedData, for: account)
    }

    func retrieveOAuthState(for integrationType: IntegrationType) -> OAuthState? {
        let account = "oauth_state_\(integrationType.rawValue)"
        guard let encryptedData = retrieveFromKeychain(for: account),
              let decryptedData = decrypt(encryptedData),
              let state = try? JSONDecoder().decode(OAuthState.self, from: decryptedData) else { return nil }
        return state
    }

    func deleteOAuthState(for integrationType: IntegrationType) {
        let account = "oauth_state_\(integrationType.rawValue)"
        deleteFromKeychain(for: account)
    }

    // MARK: - Keychain Helpers

    private func storeInKeychain(_ data: Data, for account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemDelete(query as CFDictionary)
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private func retrieveFromKeychain(for account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return data
    }

    private func deleteFromKeychain(for account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    // MARK: - Simple XOR Encryption (for demo - use AES in production)

    private let encryptionKey = "MindFriendOAuthKey2024!".data(using: .utf8)!

    private func encrypt(_ data: Data) -> Data? {
        var result = Data(count: data.count)
        for i in 0..<data.count {
            result[i] = data[i] ^ encryptionKey[i % encryptionKey.count]
        }
        return result
    }

    private func decrypt(_ data: Data) -> Data? {
        return encrypt(data)
    }
}
