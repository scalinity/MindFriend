import Foundation
import LocalAuthentication

// MARK: - Protocol

protocol VaultAuthenticating {
    func authenticate(reason: String) async throws -> Bool
    func isBiometricAvailable() -> Bool
    func biometricType() -> LABiometryType
    func canUseBiometrics() -> (available: Bool, error: VaultError?)
}

// MARK: - Implementation

/// Wrapper around LocalAuthentication for vault access control.
/// Supports Face ID, Touch ID, and passcode fallback.
final class VaultAuthService: VaultAuthenticating {

    // MARK: - Public Interface

    /// Authenticates the user with biometrics (Face ID/Touch ID) with passcode fallback
    func authenticate(reason: String) async throws -> Bool {
        let context = LAContext()
        var error: NSError?

        // First check if biometrics are available
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // Try device passcode as fallback
            if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) {
                return try await authenticateWithPasscode(context: context, reason: reason)
            }

            // Handle specific errors
            if let laError = error as? LAError {
                throw mapLAError(laError)
            }
            throw VaultError.authenticationUnavailable
        }

        do {
            // Attempt biometric authentication
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            return success
        } catch let laError as LAError {
            // If biometrics fail, try passcode fallback
            if laError.code == .authenticationFailed || laError.code == .biometryLockout {
                if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) {
                    return try await authenticateWithPasscode(context: LAContext(), reason: reason)
                }
            }
            throw mapLAError(laError)
        }
    }

    /// Checks if biometric authentication (Face ID or Touch ID) is available
    func isBiometricAvailable() -> Bool {
        let context = LAContext()
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    /// Returns the type of biometric authentication available
    func biometricType() -> LABiometryType {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType
    }

    /// Checks if biometrics can be used and returns any error
    func canUseBiometrics() -> (available: Bool, error: VaultError?) {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            return (true, nil)
        }

        if let laError = error as? LAError {
            return (false, mapLAError(laError))
        }

        // Check if at least device authentication is available
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) {
            return (true, nil) // Passcode fallback available
        }

        return (false, .authenticationUnavailable)
    }

    // MARK: - Private Helpers

    /// Authenticates with device passcode as fallback
    private func authenticateWithPasscode(context: LAContext, reason: String) async throws -> Bool {
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
            return success
        } catch let laError as LAError {
            throw mapLAError(laError)
        }
    }

    /// Maps LAError to VaultError for consistent error handling
    private func mapLAError(_ error: LAError) -> VaultError {
        switch error.code {
        case .authenticationFailed:
            return .authenticationFailed
        case .userCancel, .userFallback, .systemCancel, .appCancel:
            return .authenticationCancelled
        case .biometryNotAvailable:
            return .authenticationUnavailable
        case .biometryNotEnrolled:
            return .authenticationUnavailable
        case .biometryLockout:
            return .authenticationFailed
        case .passcodeNotSet:
            return .passcodeNotSet
        default:
            return .authenticationFailed
        }
    }
}
