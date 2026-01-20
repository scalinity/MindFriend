import Foundation
import LocalAuthentication
import Combine
import UIKit

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
        let urlString = SupabaseConfig.projectURL.absoluteString
        guard let url = URL(string: "\(urlString)/functions/v1/privacy-lock-settings") else {
            throw PrivacyLockError.networkError
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        if let token = try? await supabase.auth.session.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PrivacyLockError.networkError
        }

        guard httpResponse.statusCode == 200 else {
            throw PrivacyLockError.serverError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(PrivacyLockSettings.self, from: data)
    }

    func updateSettings(_ newSettings: PrivacyLockSettings) async throws {
        isLoading = true
        defer { isLoading = false }

        let urlString = SupabaseConfig.projectURL.absoluteString
        guard let url = URL(string: "\(urlString)/functions/v1/privacy-lock-settings") else {
            throw PrivacyLockError.networkError
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token = try? await supabase.auth.session.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let updateData: [String: Any] = [
            "app_lock_enabled": newSettings.appLockEnabled,
            "auto_lock_seconds": newSettings.autoLockSeconds,
            "quick_lock_method": newSettings.quickLockMethod.rawValue,
            "triple_tap_enabled": newSettings.tripleTapEnabled
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: updateData)

        let (responseData, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PrivacyLockError.networkError
        }

        guard httpResponse.statusCode == 200 else {
            throw PrivacyLockError.serverError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let savedSettings = try decoder.decode(PrivacyLockSettings.self, from: responseData)

        await MainActor.run {
            self.settings = savedSettings
            self.startAutoLockTimerIfNeeded()
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

    var errorDescription: String? {
        switch self {
        case .networkError:
            return "Network error. Please check your connection."
        case .serverError(let code):
            return "Server error (\(code)). Please try again."
        case .biometricNotAvailable:
            return "Biometric authentication is not available on this device."
        case .authenticationFailed:
            return "Authentication failed. Please try again."
        }
    }
}
