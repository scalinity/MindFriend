// Spec 14: Accessibility Service
// Manages user accessibility preferences and fetches accessibility content

import Foundation
import Supabase

@MainActor
final class AccessibilityService: ObservableObject {
    // MARK: - Published State
    @Published private(set) var preferences: AccessibilityPreferences = .default
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?

    // MARK: - Private Properties
    private let supabase: SupabaseClient
    private var cachedStrings: [String: LocalizedStringBundle] = [:]
    private var systemSettingsObservers: [NSObjectProtocol] = []

    // MARK: - Init
    init(supabase: SupabaseClient) {
        self.supabase = supabase
        observeSystemSettings()
    }

    deinit {
        systemSettingsObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Preferences Management

    func loadPreferences() async throws {
        isLoading = true
        defer { isLoading = false }

        // TODO: Implement with correct Supabase Swift SDK API
        // For now, use default preferences
        preferences = .default
        error = nil
    }

    func savePreferences() async throws {
        isLoading = true
        defer { isLoading = false }

        // TODO: Implement with correct Supabase Swift SDK API
        error = nil
    }

    func updatePreference<T>(_ keyPath: WritableKeyPath<AccessibilityPreferences, T>, to value: T) {
        preferences[keyPath: keyPath] = value

        Task {
            do {
                try await savePreferences()
            } catch {
                self.error = error
            }
        }
    }

    // MARK: - Captions

    func getCaptions(for contentType: String, contentId: UUID) async throws -> AudioCaptions {
        // TODO: Implement Edge Function call
        throw AccessibilityError.captionsNotAvailable
    }

    // MARK: - Localization

    func getLocalizedStrings(forceRefresh: Bool = false) async throws -> LocalizedStringBundle {
        let language = preferences.preferredLanguage
        let region = preferences.preferredRegion
        let cacheKey = "\(language)_\(region ?? "default")"

        if !forceRefresh, let cached = cachedStrings[cacheKey] {
            return cached
        }

        // TODO: Implement Edge Function call
        let bundle = LocalizedStringBundle(
            language: language,
            region: region,
            strings: [:],
            updatedAt: Date()
        )
        cachedStrings[cacheKey] = bundle
        return bundle
    }

    func localizedString(_ key: String, count: Int? = nil) -> String {
        let language = preferences.preferredLanguage
        let region = preferences.preferredRegion
        let cacheKey = "\(language)_\(region ?? "default")"

        guard let bundle = cachedStrings[cacheKey],
              let stringValue = bundle.strings[key] else {
            return key
        }

        return stringValue.value
    }

    // MARK: - Sign Language

    func getSignLanguageVideo(for contentType: String, contentId: UUID) async throws -> SignLanguageVideo? {
        // TODO: Implement with correct PostgREST API
        return nil
    }

    // MARK: - Feedback

    func submitFeedback(_ feedback: AccessibilityFeedback) async throws {
        guard !feedback.description.isEmpty else {
            throw AccessibilityError.invalidFeedback("Description is required")
        }

        guard let userId = supabase.auth.currentUser?.id.uuidString else {
            throw AccessibilityError.invalidFeedback("User not authenticated")
        }

        // TODO: Implement database insert
    }

    // MARK: - System Settings Observer

    private func observeSystemSettings() {
        // SwiftUI environments handle reduce motion and transparency automatically
        // through @Environment(\.accessibilityReduceMotion) and similar
    }

    // MARK: - Computed Properties

    var shouldReduceMotion: Bool {
        preferences.reduceMotionEnabled
    }

    var effectiveFontScale: CGFloat {
        preferences.preferredFontSize.scaleFactor
    }

    var effectiveAnimationDuration: Double {
        shouldReduceMotion ? 0.0 : preferences.animationSpeed
    }
}

// MARK: - AccessibilityError

enum AccessibilityError: LocalizedError {
    case invalidFeedback(String)
    case captionsNotAvailable
    case localizationFailed
    case invalidPreferences

    var errorDescription: String? {
        switch self {
        case .invalidFeedback(let message):
            return message
        case .captionsNotAvailable:
            return "Captions are not available for this content"
        case .localizationFailed:
            return "Failed to load localization strings"
        case .invalidPreferences:
            return "Invalid accessibility preferences"
        }
    }
}
