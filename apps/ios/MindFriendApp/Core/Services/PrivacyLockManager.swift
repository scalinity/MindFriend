import Foundation
import LocalAuthentication
import Combine
import UIKit
import Auth

@MainActor
final class PrivacyLockManager: ObservableObject {
    static let shared = PrivacyLockManager()

    @Published private(set) var isLocked = false
    @Published private(set) var settings: PrivacyLockSettings = .default
    @Published private(set) var isLoading = false
    @Published private(set) var biometricType: BiometricType = .none

    private var autoLockTimer: Timer?
    private var lastActivityDate: Date = Date()
    private var cancellables = Set<AnyCancellable>()

    enum BiometricType {
        case none
        case touchID
        case faceID

        var displayName: String {
            switch self {
            case .none: return "Passcode"
            case .touchID: return "Touch ID"
            case .faceID: return "Face ID"
            }
        }

        var iconName: String {
            switch self {
            case .none: return "lock.fill"
            case .touchID: return "touchid"
            case .faceID: return "faceid"
            }
        }
    }

    private init() {
        setupBiometricDetection()
        setupActivityTracking()
        setupAppLifecycleObservers()
    }

    private func setupBiometricDetection() {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            switch context.biometryType {
            case .faceID:
                biometricType = .faceID
            case .touchID:
                biometricType = .touchID
            case .opticID:
                biometricType = .faceID
            case .none:
                biometricType = .none
            @unknown default:
                biometricType = .none
            }
        } else {
            biometricType = .none
        }
    }

    private func setupActivityTracking() {
        NotificationCenter.default.publisher(for: UIApplication.keyboardWillShowNotification)
            .sink { [weak self] _ in self?.resetAutoLockTimer() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.keyboardWillHideNotification)
            .sink { [weak self] _ in self?.resetAutoLockTimer() }
            .store(in: &cancellables)
    }

    private func setupAppLifecycleObservers() {
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                self?.handleAppBackgrounding()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.handleAppForegrounding()
                }
            }
            .store(in: &cancellables)
    }

    func loadSettings() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let fetchedSettings = try await fetchSettingsFromServer()
            await MainActor.run {
                self.settings = fetchedSettings
            }
        } catch {
            Log.privacy.error("Failed to load privacy lock settings: \(error)")
            settings = .default
        }
    }

    private func fetchSettingsFromServer() async throws -> PrivacyLockSettings {
        // Log current session state before refresh
        let currentSession = try? await supabase.auth.session
        Log.privacy.debug("[PrivacyLock] Current session exists: \(currentSession != nil)")
        if let current = currentSession {
            Log.privacy.debug("[PrivacyLock] Current token length: \(current.accessToken.count)")
            Log.privacy.debug("[PrivacyLock] Current user ID: \(current.user.id)")
            let expiry = Date(timeIntervalSince1970: current.expiresAt)
            Log.privacy.debug("[PrivacyLock] Token expires at: \(expiry.description)")
            Log.privacy.debug("[PrivacyLock] Token expired: \(expiry < Date())")
        }

        // Refresh the session to ensure we have a valid token
        let session: Session
        do {
            session = try await supabase.auth.refreshSession()
            Log.privacy.debug("[PrivacyLock] Session refreshed successfully")
            Log.privacy.debug("[PrivacyLock] Refreshed token length: \(session.accessToken.count)")
            Log.privacy.debug("[PrivacyLock] Refreshed user ID: \(session.user.id)")
            let newExpiry = Date(timeIntervalSince1970: session.expiresAt)
            Log.privacy.debug("[PrivacyLock] New token expires at: \(newExpiry.description)")
        } catch {
            Log.privacy.error("[PrivacyLock] Failed to refresh session: \(error)")
            Log.privacy.error("[PrivacyLock] Refresh error type: \(type(of: error))")
            throw PrivacyLockError.authenticationFailed
        }

        // Log the request details
        let tokenPrefix = String(session.accessToken.prefix(20))
        Log.privacy.debug("[PrivacyLock] Making GET request to privacy-lock-settings")
        Log.privacy.debug("[PrivacyLock] Token prefix: \(tokenPrefix)...")

        do {
            let response: PrivacyLockSettings = try await supabase.functions.invoke(
                "privacy-lock-settings",
                options: .init(
                    method: .get,
                    headers: ["Authorization": "Bearer \(session.accessToken)"]
                )
            )
            Log.privacy.debug("[PrivacyLock] Fetch succeeded, appLockEnabled: \(response.appLockEnabled)")
            return response
        } catch let error as DecodingError {
            Log.privacy.error("[PrivacyLock] Decoding failed: \(error)")
            throw PrivacyLockError.decodingError(error.localizedDescription)
        } catch {
            Log.privacy.error("[PrivacyLock] Fetch failed: \(error)")
            Log.privacy.error("[PrivacyLock] Error type: \(type(of: error))")
            Log.privacy.error("[PrivacyLock] Error description: \(String(describing: error))")

            // Try to extract and decode response data from error
            let errorString = String(describing: error)
            Log.privacy.error("[PrivacyLock] Full error string: \(errorString)")

            // Try to extract the data bytes and decode as UTF-8
            if let dataRange = errorString.range(of: "data: "),
               let bytesStart = errorString.range(of: " bytes", range: dataRange.upperBound..<errorString.endIndex) {
                let bytesInfo = errorString[dataRange.upperBound..<bytesStart.lowerBound]
                Log.privacy.error("[PrivacyLock] Response size: \(bytesInfo) bytes")
            }

            // The Supabase SDK includes response data in the error - try to extract it
            let mirror = Mirror(reflecting: error)
            for child in mirror.children {
                Log.privacy.error("[PrivacyLock] Error child: \(child.label ?? "nil") = \(child.value)")
                if let data = child.value as? Data, let str = String(data: data, encoding: .utf8) {
                    Log.privacy.error("[PrivacyLock] Response body: \(str)")
                }
            }

            if errorString.contains("401") {
                throw PrivacyLockError.authenticationFailed
            }
            throw PrivacyLockError.networkError
        }
    }

    private struct UpdateSettingsRequest: Encodable {
        let app_lock_enabled: Bool
        let auto_lock_seconds: Int
        let quick_lock_method: String
        let triple_tap_enabled: Bool
    }

    func updateSettings(_ newSettings: PrivacyLockSettings) async throws {
        isLoading = true
        defer { isLoading = false }

        Log.privacy.debug("[PrivacyLock] updateSettings called with appLockEnabled: \(newSettings.appLockEnabled)")

        // Refresh the session to ensure we have a valid token
        let session: Session
        do {
            session = try await supabase.auth.refreshSession()
            Log.privacy.debug("[PrivacyLock] Session refreshed for update")
            Log.privacy.debug("[PrivacyLock] Update token length: \(session.accessToken.count)")
            Log.privacy.debug("[PrivacyLock] Update user ID: \(session.user.id)")
        } catch {
            Log.privacy.error("[PrivacyLock] Failed to refresh session for update: \(error)")
            throw PrivacyLockError.authenticationFailed
        }

        let requestBody = UpdateSettingsRequest(
            app_lock_enabled: newSettings.appLockEnabled,
            auto_lock_seconds: newSettings.autoLockSeconds,
            quick_lock_method: newSettings.quickLockMethod.rawValue,
            triple_tap_enabled: newSettings.tripleTapEnabled
        )

        Log.privacy.debug("[PrivacyLock] Request body: app_lock_enabled=\(requestBody.app_lock_enabled), auto_lock_seconds=\(requestBody.auto_lock_seconds), quick_lock_method=\(requestBody.quick_lock_method)")
        Log.privacy.debug("[PrivacyLock] Making PUT request to privacy-lock-settings")

        do {
            let savedSettings: PrivacyLockSettings = try await supabase.functions.invoke(
                "privacy-lock-settings",
                options: .init(
                    method: .put,
                    headers: ["Authorization": "Bearer \(session.accessToken)"],
                    body: requestBody
                )
            )

            Log.privacy.debug("[PrivacyLock] Update succeeded, returned appLockEnabled: \(savedSettings.appLockEnabled)")

            await MainActor.run {
                self.settings = savedSettings
                self.startAutoLockTimerIfNeeded()
            }
        } catch let error as DecodingError {
            Log.privacy.error("[PrivacyLock] Update decoding failed: \(error)")
            throw PrivacyLockError.decodingError(error.localizedDescription)
        } catch {
            Log.privacy.error("[PrivacyLock] Update failed: \(error)")
            Log.privacy.error("[PrivacyLock] Update error type: \(type(of: error))")
            Log.privacy.error("[PrivacyLock] Update error description: \(String(describing: error))")

            // Try to extract response body from error
            let errorString = String(describing: error)
            if let dataRange = errorString.range(of: "data: ") {
                let dataInfo = errorString[dataRange.upperBound...]
                Log.privacy.error("[PrivacyLock] Update response data info: \(dataInfo.prefix(100))")
            }

            if errorString.contains("401") {
                throw PrivacyLockError.authenticationFailed
            } else if errorString.contains("400") {
                throw PrivacyLockError.validationError
            } else if errorString.contains("500") {
                throw PrivacyLockError.serverError(500)
            }
            throw PrivacyLockError.networkError
        }
    }

    func lockApp() async {
        guard settings.appLockEnabled else { return }

        await MainActor.run {
            isLocked = true
            resetAutoLockTimer()
        }

        Analytics.shared.track(.privacyLockEngaged, properties: [
            "method": settings.quickLockMethod.rawValue
        ])
    }

    func unlockApp() async -> Bool {
        let authenticated = await authenticateWithBiometrics()

        if authenticated {
            await MainActor.run {
                isLocked = false
                lastActivityDate = Date()
                startAutoLockTimerIfNeeded()
            }

            Analytics.shared.track(.privacyLockDisengaged)
        }

        return authenticated
    }

    private func authenticateWithBiometrics() async -> Bool {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) {
                return await authenticateWithPasscode(context: context)
            }
            return false
        }

        let reason = "Unlock MindFriend"

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            return success
        } catch {
            Log.privacy.error("Biometric authentication failed: \(error)")
            return false
        }
    }

    private func authenticateWithPasscode(context: LAContext) async -> Bool {
        let reason = "Unlock MindFriend"

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
            return success
        } catch {
            Log.privacy.error("Passcode authentication failed: \(error)")
            return false
        }
    }

    private func handleAppBackgrounding() {
        guard settings.appLockEnabled else { return }
        Task { @MainActor in
            isLocked = true
        }
        stopAutoLockTimer()
    }

    private func handleAppForegrounding() async {
        guard settings.appLockEnabled else { return }

        if isLocked {
            let _ = await unlockApp()
        } else {
            startAutoLockTimerIfNeeded()
        }
    }

    private func startAutoLockTimerIfNeeded() {
        guard settings.appLockEnabled && settings.autoLockSeconds > 0 else {
            stopAutoLockTimer()
            return
        }

        stopAutoLockTimer()

        autoLockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAutoLock()
            }
        }
    }

    private func stopAutoLockTimer() {
        autoLockTimer?.invalidate()
        autoLockTimer = nil
    }

    private func checkAutoLock() {
        guard settings.appLockEnabled && settings.autoLockSeconds > 0 && !isLocked else { return }

        let elapsed = Date().timeIntervalSince(lastActivityDate)
        let timeout = TimeInterval(settings.autoLockSeconds)

        if elapsed >= timeout {
            Task { @MainActor in
                isLocked = true
            }
            stopAutoLockTimer()

            Analytics.shared.track(.privacyAutoLockTriggered, properties: [
                "timeout_seconds": settings.autoLockSeconds
            ])
        }
    }

    private func resetAutoLockTimer() {
        guard settings.appLockEnabled && settings.autoLockSeconds > 0 else { return }
        lastActivityDate = Date()
    }

    func quickLock() async {
        await lockApp()
    }

    var canEnableBiometrics: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) ||
               context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }
}

enum PrivacyLockError: LocalizedError {
    case networkError
    case serverError(Int)
    case biometricNotAvailable
    case authenticationFailed
    case validationError
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .networkError:
            return "Network error. Please check your connection."
        case .serverError(let code):
            return "Server error (\(code)). Please try again."
        case .biometricNotAvailable:
            return "Biometric authentication is not available on this device."
        case .authenticationFailed:
            return "Authentication failed. Please sign in again."
        case .validationError:
            return "Invalid settings. Please check your selections."
        case .decodingError(let detail):
            return "Data error: \(detail)"
        }
    }
}
