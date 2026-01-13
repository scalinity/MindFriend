import Foundation
import AuthenticationServices

/// Handles authentication with Apple Sign-In
@MainActor
final class AuthService: ObservableObject {
    private let apiClient: APIClient
    private let keychainManager: KeychainManager

    @Published private(set) var isSigningIn = false
    @Published private(set) var error: Error?

    init(apiClient: APIClient, keychainManager: KeychainManager) {
        self.apiClient = apiClient
        self.keychainManager = keychainManager
    }

    // MARK: - Apple Sign-In

    func signInWithApple(
        identityToken: Data,
        authorizationCode: Data,
        fullName: PersonNameComponents?,
        email: String?
    ) async throws -> UserProfile {
        guard let tokenString = String(data: identityToken, encoding: .utf8),
              let codeString = String(data: authorizationCode, encoding: .utf8) else {
            throw AuthError.invalidCredentials
        }

        isSigningIn = true
        defer { isSigningIn = false }

        let fullNameString = [fullName?.givenName, fullName?.familyName]
            .compactMap { $0 }
            .joined(separator: " ")

        let request = AppleSignInRequest(
            identityToken: tokenString,
            authorizationCode: codeString,
            fullName: fullNameString.isEmpty ? nil : fullNameString,
            email: email
        )

        let response: AuthResponse = try await apiClient.request(.appleSignIn(request))

        // Save tokens
        await keychainManager.saveTokens(response.tokens)

        return response.user
    }

    // MARK: - Google Sign-In

    func signInWithGoogle(
        idToken: String,
        email: String?,
        fullName: String?
    ) async throws -> UserProfile {
        isSigningIn = true
        defer { isSigningIn = false }

        let request = GoogleSignInRequest(
            idToken: idToken,
            email: email,
            fullName: fullName
        )

        let response: AuthResponse = try await apiClient.request(.googleSignIn(request))

        // Save tokens
        await keychainManager.saveTokens(response.tokens)

        return response.user
    }
}

// MARK: - Auth Response

struct AuthResponse: Decodable {
    let user: UserProfile
    let tokens: AuthTokens
    let isNewUser: Bool
}

// MARK: - Auth Error

enum AuthError: Error, LocalizedError {
    case invalidCredentials
    case cancelled
    case failed(Error)
    case googleSignInFailed(String)
    case missingIdToken
    case emailConfirmationRequired
    case invalidEmail
    case weakPassword
    case emailAlreadyInUse

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid sign-in credentials"
        case .cancelled:
            return "Sign-in was cancelled"
        case .failed(let error):
            return error.localizedDescription
        case .googleSignInFailed(let message):
            return "Google Sign-In failed: \(message)"
        case .missingIdToken:
            return "Could not retrieve Google ID token"
        case .emailConfirmationRequired:
            return "Please check your email to confirm your account"
        case .invalidEmail:
            return "Please enter a valid email address"
        case .weakPassword:
            return "Password must be at least 6 characters"
        case .emailAlreadyInUse:
            return "An account with this email already exists"
        }
    }
}
