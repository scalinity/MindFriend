import Foundation
import Supabase
import SwiftUI

// Import all personalization models
// Note: PersonalizationModels.swift defines all these types
// The compiler needs them in scope for type checking

/// Service for smart personalization: preferences, recommendations, insights, and schedule suggestions
///
/// This service provides complete personalization functionality including:
/// - User preference profile management
/// - Learned preference tracking from engagement
/// - Usage pattern analysis for optimal timing
/// - Content recommendations based on user context
/// - Personalized insights generation
/// - Schedule suggestions for activities
/// - Real-time engagement tracking
@MainActor
final class PersonalizationService: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var preferenceProfile: UserPreferenceProfile?
    @Published private(set) var learnedPreferences: [DBLearnedPreference] = []
    @Published private(set) var usagePatterns: [DBUsagePattern] = []
    @Published private(set) var insights: [DBPersonalizedInsight] = []
    @Published private(set) var scheduleSuggestions: [DBScheduleSuggestion] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    // MARK: - Private Properties

    private let supabase: SupabaseClient
    private let authService: SupabaseAuthService

    /// Cached auth headers to avoid concurrent refreshSession() calls
    /// which can invalidate each other's tokens (OAuth refresh tokens are single-use)
    private var cachedAuthHeaders: [String: String]?

    // MARK: - Initialization

    init(supabase: SupabaseClient, authService: SupabaseAuthService) {
        self.supabase = supabase
        self.authService = authService
    }

    // MARK: - Auth Helpers

    private func authHeadersForFunctions() async throws -> [String: String] {
        // Use cached headers if available (set by refreshAuthOnce before concurrent calls)
        if let cached = cachedAuthHeaders {
            return cached
        }

        // Refresh session and get fresh token directly from the refresh call
        let session: Session
        do {
            session = try await supabase.auth.refreshSession()
            #if DEBUG
            print("🔐 PersonalizationService: Session refreshed, token length: \(session.accessToken.count)")
            #endif
        } catch {
            print("❌ PersonalizationService: Session refresh failed: \(error)")
            throw AuthError.sessionExpired
        }

        return ["Authorization": "Bearer \(session.accessToken)"]
    }

    /// Refresh session once and cache headers for concurrent use.
    /// Call this before fanning out multiple async tasks to avoid
    /// concurrent refreshSession() calls invalidating each other's tokens.
    private func refreshAuthOnce() async throws {
        let session: Session
        do {
            session = try await supabase.auth.refreshSession()
        } catch {
            throw AuthError.sessionExpired
        }
        cachedAuthHeaders = ["Authorization": "Bearer \(session.accessToken)"]
    }

    /// Ensures valid session and returns user ID, or throws if not authenticated
    private func ensureValidSessionAndUserId() async throws -> UUID {
        // Refresh session directly - this is more reliable than using authService
        let session: Session
        do {
            session = try await supabase.auth.refreshSession()
        } catch {
            throw AuthError.sessionExpired
        }

        return session.user.id
    }

    private func logFunctionsError(_ error: FunctionsError, context: String) {
        switch error {
        case .relayError:
            print("❌ PersonalizationService[\(context)]: Relay error invoking Edge Function")
        case .httpError(let code, let data):
            print("❌ PersonalizationService[\(context)]: HTTP \(code)")
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("❌ PersonalizationService[\(context)]: Error JSON: \(errorJson)")
            } else if let errorString = String(data: data, encoding: .utf8) {
                print("❌ PersonalizationService[\(context)]: Error raw: \(errorString)")
            }
        }
    }

    private func invokeFunction<T: Decodable>(
        _ name: String
    ) async throws -> T {
        let headers = try await authHeadersForFunctions()

        do {
            return try await supabase.functions.invoke(
                name,
                options: .init(headers: headers)
            )
        } catch let error as FunctionsError {
            logFunctionsError(error, context: name)
            if case .httpError(let code, _) = error, code == 401 {
                throw AuthError.sessionExpired
            }
            throw error
        }
    }

    private func invokeFunction<T: Decodable, Body: Encodable>(
        _ name: String,
        body: Body
    ) async throws -> T {
        let headers = try await authHeadersForFunctions()

        do {
            return try await supabase.functions.invoke(
                name,
                options: .init(headers: headers, body: body)
            )
        } catch let error as FunctionsError {
            logFunctionsError(error, context: name)
            if case .httpError(let code, _) = error, code == 401 {
                throw AuthError.sessionExpired
            }
            throw error
        }
    }

    // MARK: - Load All Data

    /// Load all personalization data
    func loadData() async {
        isLoading = true
        error = nil

        // Refresh session once before fanning out concurrent tasks.
        // This prevents 5 concurrent refreshSession() calls from
        // invalidating each other's single-use OAuth refresh tokens.
        do {
            try await refreshAuthOnce()
        } catch {
            self.error = "Authentication failed"
            isLoading = false
            return
        }

        async let profileTask: Void = loadPreferenceProfile()
        async let learnedTask: Void = loadLearnedPreferences()
        async let patternsTask: Void = loadUsagePatterns()
        async let insightsTask: Void = loadInsights()
        async let suggestionsTask: Void = loadScheduleSuggestions()

        // Await all tasks and collect results
        _ = await profileTask
        _ = await learnedTask
        _ = await patternsTask
        _ = await insightsTask
        _ = await suggestionsTask

        // Clear cached headers after concurrent tasks complete
        cachedAuthHeaders = nil
        isLoading = false
    }

    // MARK: - Preference Profile

    /// Load user's preference profile, creating default if needed
    func loadPreferenceProfile() async {
        let userId: UUID
        do {
            userId = try await ensureValidSessionAndUserId()
        } catch {
            self.error = "Session expired"
            return
        }

        do {
            let profiles: [DBUserPreferenceProfile] = try await supabase
                .from("user_preference_profiles")
                .select()
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value

            if let profile = profiles.first {
                self.preferenceProfile = UserPreferenceProfile(from: profile)
                self.error = nil
            } else {
                // Create default profile
                try await createDefaultProfile(userId: userId.uuidString)
            }
        } catch {
            self.error = "Failed to load preferences"
        }
    }

    private func createDefaultProfile(userId: String) async throws {
        let defaultData = UserPreferenceProfile.createDefault(userId: userId)
        let data = try JSONSerialization.data(withJSONObject: [defaultData])

        try await supabase
            .from("user_preference_profiles")
            .insert(data)
            .execute()

        // Reload to get the created profile
        await loadPreferenceProfile()
    }

    /// Update preference profile
    func updatePreferenceProfile(_ profile: UserPreferenceProfile) async throws {
        let payload = profile.toUpdatePayload()
        let data = try JSONSerialization.data(withJSONObject: payload)

        try await supabase
            .from("user_preference_profiles")
            .update(data)
            .eq("id", value: profile.id)
            .execute()

        self.preferenceProfile = profile
    }

    /// Update session length preference
    func updateSessionLengthPreference(_ length: SessionLength) async throws {
        guard var profile = preferenceProfile else { return }
        profile.preferredSessionLength = length
        try await updatePreferenceProfile(profile)
    }

    /// Update content type preferences
    func updateContentTypePreferences(_ types: [PersonalizationContentType]) async throws {
        guard var profile = preferenceProfile else { return }
        profile.preferredContentTypes = types
        try await updatePreferenceProfile(profile)
    }

    /// Update category preferences
    func updateCategoryPreferences(_ categories: [String]) async throws {
        guard var profile = preferenceProfile else { return }
        profile.preferredCategories = categories
        try await updatePreferenceProfile(profile)
    }

    /// Update smart feature toggles
    func updateFeatureToggle(moodBased: Bool? = nil, insights: Bool? = nil, scheduling: Bool? = nil, difficulty: Bool? = nil) async throws {
        guard var profile = preferenceProfile else { return }
        if let moodBased { profile.moodBasedRecommendations = moodBased }
        if let insights { profile.personalizedInsights = insights }
        if let scheduling { profile.smartScheduling = scheduling }
        if let difficulty { profile.adaptiveDifficulty = difficulty }
        try await updatePreferenceProfile(profile)
    }

    // MARK: - Learned Preferences

    /// Load user's learned preferences
    func loadLearnedPreferences() async {
        let userId: UUID
        do {
            userId = try await ensureValidSessionAndUserId()
        } catch {
            self.error = "Session expired"
            return
        }

        do {
            let preferences: [DBLearnedPreference] = try await supabase
                .from("learned_preferences")
                .select()
                .eq("user_id", value: userId.uuidString)
                .order("preference_score", ascending: false)
                .execute()
                .value

            self.learnedPreferences = preferences
            self.error = nil
        } catch {
            self.error = "Failed to load preferences"
        }
    }

    /// Get top preferences by type
    func getTopPreferences(type: String, limit: Int = 3) -> [DBLearnedPreference] {
        return learnedPreferences
            .filter { $0.preferenceType == type && $0.confidenceScore >= 0.3 }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Usage Patterns

    /// Load user's usage patterns
    func loadUsagePatterns() async {
        let userId: UUID
        do {
            userId = try await ensureValidSessionAndUserId()
        } catch {
            self.error = "Session expired"
            return
        }

        do {
            let patterns: [DBUsagePattern] = try await supabase
                .from("usage_patterns")
                .select()
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value

            self.usagePatterns = patterns
            self.error = nil
        } catch {
            self.error = "Failed to load usage patterns"
        }
    }

    /// Get best times to practice
    func getBestTimes() -> [PatternDataWrapper.TimeSlot] {
        guard let pattern = usagePatterns.first(where: { $0.patternType == "daily_time" }) else {
            return []
        }
        return pattern.patternData.slots?.sorted { $0.score > $1.score } ?? []
    }

    /// Get best days to practice
    func getBestDays() -> [PatternDataWrapper.DaySlot] {
        guard let pattern = usagePatterns.first(where: { $0.patternType == "weekly_day" }) else {
            return []
        }
        return pattern.patternData.days?.sorted { $0.score > $1.score } ?? []
    }

    // MARK: - Content Engagement Tracking

    /// Track user engagement with content
    func trackEngagement(
        contentType: String,
        contentId: String,
        eventType: EngagementEventType,
        durationSeconds: Int? = nil,
        completionPercentage: Double? = nil,
        rating: Int? = nil,
        skipReason: String? = nil,
        contentAttributes: [String: String] = [:]
    ) async throws {
        struct EngagementPayload: Encodable {
            let contentType: String
            let contentId: String
            let eventType: String
            let durationSeconds: Int?
            let completionPercentage: Double?
            let rating: Int?
            let skipReason: String?
            let contentAttributes: [String: String]
        }

        let payload = EngagementPayload(
            contentType: contentType,
            contentId: contentId,
            eventType: eventType.rawValue,
            durationSeconds: durationSeconds,
            completionPercentage: completionPercentage,
            rating: rating,
            skipReason: skipReason,
            contentAttributes: contentAttributes
        )

        struct EmptyResponse: Decodable {}
        let _: EmptyResponse = try await invokeFunction("update-preferences", body: payload)
    }

    enum EngagementEventType: String {
        case start
        case complete
        case skip
        case rate
    }

    // MARK: - Recommendations

    /// Get personalized content recommendations
    func getRecommendations(
        contentType: String,
        context: RecommendationContext? = nil,
        limit: Int = 10
    ) async throws -> [ContentRecommendation] {
        // Ensure user is authenticated
        guard let userId = authService.userId else {
            throw AuthError.sessionExpired
        }

        print("🔍 PersonalizationService: Getting recommendations for user \(userId)")

        struct RecommendationContextPayload: Encodable {
            let currentMood: String?
            let timeOfDay: String?
            let recentActivity: String?
            let anxietyLevel: AnxietyLevel?
            let energyLevel: EnergyLevel?
        }

        struct RecommendationRequestPayload: Encodable {
            let contentType: String
            let context: RecommendationContextPayload
            let limit: Int
        }

        let payload = RecommendationRequestPayload(
            contentType: contentType,
            context: RecommendationContextPayload(
                currentMood: context?.currentMood,
                timeOfDay: context?.timeOfDay,
                recentActivity: context?.recentActivity,
                anxietyLevel: context?.anxietyLevel,
                energyLevel: context?.energyLevel
            ),
            limit: limit
        )

        let result: RecommendationResponse = try await invokeFunction(
            "get-recommendations",
            body: payload
        )
        print("✅ PersonalizationService: Got \(result.recommendations.count) recommendations")
        return result.recommendations
    }

    /// Log when user clicks a recommendation
    func logRecommendationClick(contentId: String) async throws {
        let userId = try await ensureValidSessionAndUserId()

        try await supabase
            .from("recommendation_logs")
            .update(["was_clicked": true])
            .eq("user_id", value: userId.uuidString)
            .eq("content_id", value: contentId)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
    }

    // MARK: - Insights

    /// Load user's personalized insights
    func loadInsights() async {
        let userId: UUID
        do {
            userId = try await ensureValidSessionAndUserId()
        } catch {
            self.error = "Session expired"
            return
        }

        let now = ISO8601DateFormatter().string(from: Date())

        do {
            let insights: [DBPersonalizedInsight] = try await supabase
                .from("personalized_insights")
                .select()
                .eq("user_id", value: userId.uuidString)
                .eq("was_dismissed", value: false)
                .lte("valid_from", value: now)
                .gte("valid_until", value: now)
                .order("created_at", ascending: false)
                .limit(10)
                .execute()
                .value

            self.insights = insights
            self.error = nil
        } catch {
            self.error = "Failed to load insights"
        }
    }

    /// Generate new insights via edge function
    func generateInsights() async throws {
        struct EmptyResponse: Decodable {}
        let _: EmptyResponse = try await invokeFunction("generate-insights")
        await loadInsights()
    }

    /// Mark insight as shown
    func markInsightAsShown(_ insight: DBPersonalizedInsight) async throws {
        try await supabase
            .from("personalized_insights")
            .update(["was_shown": true])
            .eq("id", value: insight.id)
            .execute()

        if let index = insights.firstIndex(where: { $0.id == insight.id }) {
            insights[index].wasShown = true
        }
    }

    /// Dismiss an insight
    func dismissInsight(_ insight: DBPersonalizedInsight) async throws {
        try await supabase
            .from("personalized_insights")
            .update(["was_dismissed": true])
            .eq("id", value: insight.id)
            .execute()

        insights.removeAll { $0.id == insight.id }
    }

    /// Record action taken on insight
    func actOnInsight(_ insight: DBPersonalizedInsight) async throws {
        try await supabase
            .from("personalized_insights")
            .update(["was_acted_upon": true])
            .eq("id", value: insight.id)
            .execute()

        if let index = insights.firstIndex(where: { $0.id == insight.id }) {
            insights[index].wasActedUpon = true
        }
    }

    // MARK: - Schedule Suggestions

    /// Load schedule suggestions
    func loadScheduleSuggestions() async {
        let userId: UUID
        do {
            userId = try await ensureValidSessionAndUserId()
        } catch {
            self.error = "Session expired"
            return
        }

        do {
            let suggestions: [DBScheduleSuggestion] = try await supabase
                .from("schedule_suggestions")
                .select()
                .eq("user_id", value: userId.uuidString)
                .eq("status", value: "suggested")
                .order("confidence_score", ascending: false)
                .limit(5)
                .execute()
                .value

            self.scheduleSuggestions = suggestions
            self.error = nil
        } catch {
            self.error = "Failed to load schedule suggestions"
        }
    }

    /// Accept a schedule suggestion
    func acceptScheduleSuggestion(_ suggestion: DBScheduleSuggestion) async throws {
        try await supabase
            .from("schedule_suggestions")
            .update([
                "status": "accepted",
                "user_response_at": ISO8601DateFormatter().string(from: Date())
            ])
            .eq("id", value: suggestion.id)
            .execute()

        // Update preferred times based on suggestion
        if var profile = preferenceProfile {
            var times = profile.preferredTimes
            let isWeekend = suggestion.suggestedDays.allSatisfy { $0 == 0 || $0 == 6 }

            if isWeekend {
                if !times.weekend.contains(suggestion.suggestedTime) {
                    times.weekend.append(suggestion.suggestedTime)
                }
            } else {
                if !times.weekday.contains(suggestion.suggestedTime) {
                    times.weekday.append(suggestion.suggestedTime)
                }
            }

            profile.preferredTimes = times
            try await updatePreferenceProfile(profile)
        }

        scheduleSuggestions.removeAll { $0.id == suggestion.id }
    }

    /// Reject a schedule suggestion
    func rejectScheduleSuggestion(_ suggestion: DBScheduleSuggestion) async throws {
        try await supabase
            .from("schedule_suggestions")
            .update([
                "status": "rejected",
                "user_response_at": ISO8601DateFormatter().string(from: Date())
            ])
            .eq("id", value: suggestion.id)
            .execute()

        scheduleSuggestions.removeAll { $0.id == suggestion.id }
    }
}
