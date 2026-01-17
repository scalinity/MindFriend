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
    private var saveDebounceTask: Task<Void, Never>?
    private let saveDebounceDelay: UInt64 = 500_000_000 // 500ms in nanoseconds

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

        guard let userId = supabase.auth.currentUser?.id else {
            throw AccessibilityError.invalidPreferences
        }

        let response: AccessibilityPreferences = try await supabase
            .from("accessibility_preferences")
            .select()
            .eq("user_id", value: userId.uuidString)
            .single()
            .execute()
            .value

        preferences = response
        error = nil
    }

    func savePreferences() async throws {
        isLoading = true
        defer { isLoading = false }

        guard let userId = supabase.auth.currentUser?.id else {
            throw AccessibilityError.invalidPreferences
        }

        var prefsToSave = preferences
        prefsToSave.userId = userId
        prefsToSave.updatedAt = Date()

        _ = try await supabase
            .from("accessibility_preferences")
            .upsert(prefsToSave)
            .execute()

        error = nil
    }

    func debouncedSavePreferences() {
        // Cancel previous debounce task
        saveDebounceTask?.cancel()

        // Create new debounce task
        saveDebounceTask = Task {
            try? await Task.sleep(nanoseconds: saveDebounceDelay)
            if !Task.isCancelled {
                do {
                    try await savePreferences()
                } catch {
                    self.error = error
                }
            }
        }
    }

    func updatePreference<T>(_ keyPath: WritableKeyPath<AccessibilityPreferences, T>, to value: T) {
        preferences[keyPath: keyPath] = value
        debouncedSavePreferences()
    }

    func getCaptionCues(for contentType: String, contentId: UUID, language: String) async throws -> [CaptionCue] {
        let captions = try await getCaptions(for: contentType, contentId: contentId)
        return captions.captions ?? []
    }

    func subscribeToPreferenceChanges() async -> AsyncStream<AccessibilityPreferences> {
        return AsyncStream { continuation in
            // Subscribe to preferences table changes via Realtime
            let channel = supabase.channel("preferences:user:\(supabase.auth.currentUser?.id.uuidString ?? "")")

            let subscription = channel
                .onPostgresChange(
                    event: .update,
                    schema: "public",
                    table: "accessibility_preferences"
                ) { payload in
                    // Update published preferences
                    if let data = payload.new as? [String: Any] {
                        // Parse and update preferences
                        print("Preferences updated: \(data)")
                    }
                }

            Task {
                try? await channel.subscribe()
            }
        }
    }

    func getCaptionCuesForTimestamp(_ timestamp: TimeInterval, in captions: [CaptionCue]) -> CaptionCue? {
        return captions.first { cue in
            cue.startTime <= timestamp && timestamp < cue.endTime
        }
    }

    // MARK: - Captions

    func getCaptions(for contentType: String, contentId: UUID) async throws -> AudioCaptions {
        let requestBody: [String: Any] = [
            "contentType": contentType,
            "contentId": contentId.uuidString,
            "language": preferences.preferredLanguage
        ]

        let data = try JSONSerialization.data(withJSONObject: requestBody)
        let response: AudioCaptions = try await supabase.functions
            .invoke(
                "get-captions",
                options: FunctionInvokeOptions(body: data)
            )

        return response
    }

    // MARK: - Localization

    func getLocalizedStrings(forceRefresh: Bool = false) async throws -> LocalizedStringBundle {
        let language = preferences.preferredLanguage
        let region = preferences.preferredRegion
        let cacheKey = "\(language)_\(region ?? "default")"

        if !forceRefresh, let cached = cachedStrings[cacheKey] {
            return cached
        }

        let requestBody: [String: Any] = [
            "language": language,
            "region": region as Any
        ]

        let data = try JSONSerialization.data(withJSONObject: requestBody)
        let bundle: LocalizedStringBundle = try await supabase.functions
            .invoke(
                "get-localized-strings",
                options: FunctionInvokeOptions(body: data)
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

        // Handle pluralization if count is provided
        if let count = count, let plurals = stringValue.plurals {
            let pluralKey = count == 1 ? "one" : "other"
            return plurals[pluralKey] ?? stringValue.value
        }

        return stringValue.value
    }

    // MARK: - Sign Language

    func getSignLanguageVideo(for contentType: String, contentId: UUID) async throws -> SignLanguageVideo? {
        let videos: [SignLanguageVideo] = try await supabase
            .from("sign_language_videos")
            .select()
            .eq("content_type", value: contentType)
            .eq("content_id", value: contentId.uuidString)
            .execute()
            .value

        return videos.first
    }

    // MARK: - Feedback

    func submitFeedback(_ feedback: AccessibilityFeedback) async throws {
        guard !feedback.description.isEmpty else {
            throw AccessibilityError.invalidFeedback("Description is required")
        }

        guard let userId = supabase.auth.currentUser?.id else {
            throw AccessibilityError.invalidFeedback("User not authenticated")
        }

        var feedbackToSubmit = feedback
        // Ensure the feedback is associated with current user (server will validate via RLS)
        _ = try await supabase
            .from("accessibility_feedback")
            .insert([
                "user_id": userId.uuidString,
                "category": feedbackToSubmit.category.rawValue,
                "screen_name": feedbackToSubmit.screenName,
                "element_identifier": feedbackToSubmit.elementIdentifier,
                "issue_type": feedbackToSubmit.issueType.rawValue,
                "description": feedbackToSubmit.description,
                "assistive_tech_used": feedbackToSubmit.assistiveTechUsed.map { $0.rawValue }
            ])
            .execute()
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
