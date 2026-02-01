import Foundation
import Supabase

/// Service for generating and managing AI-created wellness content
@MainActor
final class GeneratedContentService: ObservableObject {
    private let supabase: SupabaseClient

    @Published private(set) var isGenerating = false
    @Published private(set) var quotaStatus: ContentQuotaStatus?
    @Published private(set) var error: GeneratedContentError?

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    // MARK: - Content Generation

    /// Generate new AI content
    func generateContent(
        type: GeneratedContentType,
        params: GenerateContentParams = GenerateContentParams()
    ) async throws -> GenerateContentResponse {
        isGenerating = true
        error = nil

        defer { isGenerating = false }

        // === DEBUG LOGGING START ===
        print("[GeneratedContentService] generateContent called for type: \(type.rawValue)")

        // Ensure session is loaded before making function call
        // This forces the SDK to restore session from storage if needed
        let session: Session
        do {
            session = try await supabase.auth.session
            Log.data.debug("[GeneratedContent] Session acquired")
        } catch {
            Log.data.error("[GeneratedContent] Failed to get session")
            self.error = .notAuthenticated
            throw GeneratedContentError.notAuthenticated
        }

        let request = GenerateContentRequest(contentType: type, params: params)
        Log.data.debug("[GeneratedContent] Invoking edge function 'generate-content'")

        do {
            let response: GenerateContentResponse = try await supabase.functions.invoke(
                "generate-content",
                options: FunctionInvokeOptions(body: request)
            )
            print("[GeneratedContentService] Edge function returned successfully")

            // Update quota status from response
            quotaStatus = ContentQuotaStatus(
                used: response.quotaUsed,
                limit: response.quotaLimit,
                isPremium: response.quotaLimit > 3,
                resetsAt: Calendar.current.startOfDay(for: Date().addingTimeInterval(86400))
            )

            if let errorMessage = response.error {
                throw GeneratedContentError.generationFailed(errorMessage)
            }

            return response
        } catch let functionError as FunctionsError {
            print("[GeneratedContentService] ERROR: FunctionsError occurred")
            print("[GeneratedContentService] FunctionsError details: \(functionError)")
            if case .httpError(let code, let data) = functionError {
                print("[GeneratedContentService] HTTP Status Code: \(code)")
                if let bodyString = String(data: data, encoding: .utf8) {
                    print("[GeneratedContentService] Response body: \(bodyString)")
                }
            }
            let contentError = mapFunctionsError(functionError)
            error = contentError
            throw contentError
        } catch let decodingError as DecodingError {
            print("[GeneratedContentService] ERROR: DecodingError occurred")
            switch decodingError {
            case .keyNotFound(let key, let context):
                print("[GeneratedContentService] Missing key: '\(key.stringValue)' in \(context.codingPath.map(\.stringValue))")
            case .typeMismatch(let type, let context):
                print("[GeneratedContentService] Type mismatch: expected \(type) at \(context.codingPath.map(\.stringValue))")
            case .valueNotFound(let type, let context):
                print("[GeneratedContentService] Value not found: \(type) at \(context.codingPath.map(\.stringValue))")
            case .dataCorrupted(let context):
                print("[GeneratedContentService] Data corrupted at \(context.codingPath.map(\.stringValue))")
            @unknown default:
                print("[GeneratedContentService] Unknown decoding error: \(decodingError)")
            }
            throw decodingError
        } catch {
            print("[GeneratedContentService] ERROR: Unknown error: \(error)")
            throw error
        }
    }

    // MARK: - Content Library

    /// Fetch user's generated content library
    func fetchContentLibrary(
        type: GeneratedContentType? = nil,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> [GeneratedContent] {
        var query = supabase
            .from("generated_content")
            .select()

        if let type = type {
            query = query.eq("content_type", value: type.rawValue)
        }

        let content: [GeneratedContent] = try await query
            .order("created_at", ascending: false)
            .range(from: offset, to: offset + limit - 1)
            .execute().value
        return content
    }

    /// Fetch a single content item by ID
    func fetchContent(id: UUID) async throws -> GeneratedContent {
        print("[GeneratedContentService] fetchContent called for id: \(id)")
        let content: GeneratedContent = try await supabase
            .from("generated_content")
            .select()
            .eq("id", value: id.uuidString)
            .single()
            .execute()
            .value

        print("[GeneratedContentService] fetchContent result:")
        print("[GeneratedContentService]   - title: \(content.title)")
        print("[GeneratedContentService]   - audioUrl: \(content.audioUrl ?? "nil")")
        print("[GeneratedContentService]   - status: \(content.status)")
        print("[GeneratedContentService]   - duration: \(content.duration ?? -1)")
        return content
    }

    /// Fetch user's favorite content
    func fetchFavorites() async throws -> [GeneratedContent] {
        let content: [GeneratedContent] = try await supabase
            .from("generated_content")
            .select()
            .eq("is_favorite", value: true)
            .order("created_at", ascending: false)
            .execute()
            .value

        return content
    }

    /// Toggle favorite status for content
    func toggleFavorite(contentId: UUID) async throws -> Bool {
        // First get current state with minimal struct
        struct FavoriteStatus: Codable {
            let isFavorite: Bool

            enum CodingKeys: String, CodingKey {
                case isFavorite = "is_favorite"
            }
        }

        let current: FavoriteStatus = try await supabase
            .from("generated_content")
            .select("is_favorite")
            .eq("id", value: contentId.uuidString)
            .single()
            .execute()
            .value

        let newState = !current.isFavorite

        try await supabase
            .from("generated_content")
            .update(["is_favorite": newState])
            .eq("id", value: contentId.uuidString)
            .execute()

        return newState
    }

    /// Record that content was played
    func recordPlay(contentId: UUID) async throws {
        try await supabase.rpc(
            "increment_play_count",
            params: ["content_id": contentId.uuidString]
        ).execute()
    }

    /// Delete generated content
    func deleteContent(id: UUID) async throws {
        try await supabase
            .from("generated_content")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    // MARK: - Content Series

    /// Fetch user's content series
    func fetchSeries(activeOnly: Bool = true) async throws -> [GeneratedContentSeries] {
        var query = supabase
            .from("gen_content_series")
            .select()

        if activeOnly {
            query = query.eq("is_active", value: true)
        }

        let series: [GeneratedContentSeries] = try await query
            .order("created_at", ascending: false)
            .execute().value
        return series
    }

    /// Fetch content in a series
    func fetchSeriesContent(seriesId: UUID) async throws -> [GeneratedContent] {
        let content: [GeneratedContent] = try await supabase
            .from("generated_content")
            .select()
            .eq("series_id", value: seriesId.uuidString)
            .order("series_order", ascending: true)
            .execute()
            .value

        return content
    }

    // MARK: - Voice Preferences

    /// Fetch available voice options
    func fetchVoiceOptions() async throws -> [VoiceOption] {
        // Return default voices - could be fetched from backend in future
        return DefaultVoice.all
    }
    
    /// Fetch user's voice preference (single, not array)
    func fetchVoicePreference() async throws -> VoicePreference? {
        let preferences = try await fetchVoicePreferences()
        return preferences.first
    }
    
    /// Save voice preference (simplified API for VoicePreferencesView)
    func saveVoicePreference(voiceId: String, speed: Float) async throws {
        try await updateVoicePreference(
            contentType: .meditation, // Default content type
            voiceId: voiceId,
            speed: Double(speed)
        )
    }
    
    /// Preview a voice with sample text
    func previewVoice(voiceId: String, speed: Float) async throws -> URL? {
        // Find the voice to get its preview URL
        guard let voice = DefaultVoice.voice(for: voiceId) else {
            return nil
        }
        
        if let previewUrlString = voice.previewUrl,
           let url = URL(string: previewUrlString) {
            return url
        }
        
        // Could call synthesize-voice edge function for dynamic preview
        return nil
    }

    /// Fetch voice preferences
    func fetchVoicePreferences() async throws -> [VoicePreference] {
        let preferences: [VoicePreference] = try await supabase
            .from("voice_preferences")
            .select()
            .execute()
            .value

        return preferences
    }

    /// Update voice preference for a content type
    func updateVoicePreference(
        contentType: GeneratedContentType,
        voiceId: String,
        speed: Double = 1.0,
        backgroundSound: BackgroundSoundType? = nil,
        backgroundVolume: Double = 0.3
    ) async throws {
        let userId = try await getCurrentUserId()

        struct VoicePreferenceUpdate: Codable {
            let userId: String
            let contentType: String
            let preferredVoiceId: String
            let preferredSpeed: Double
            let backgroundSoundEnabled: Bool
            let backgroundSoundType: String?
            let backgroundSoundVolume: Double

            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case contentType = "content_type"
                case preferredVoiceId = "preferred_voice_id"
                case preferredSpeed = "preferred_speed"
                case backgroundSoundEnabled = "background_sound_enabled"
                case backgroundSoundType = "background_sound_type"
                case backgroundSoundVolume = "background_sound_volume"
            }
        }

        let update = VoicePreferenceUpdate(
            userId: userId.uuidString,
            contentType: contentType.rawValue,
            preferredVoiceId: voiceId,
            preferredSpeed: speed,
            backgroundSoundEnabled: backgroundSound != nil,
            backgroundSoundType: backgroundSound?.rawValue,
            backgroundSoundVolume: backgroundVolume
        )

        try await supabase
            .from("voice_preferences")
            .upsert(update, onConflict: "user_id,content_type")
            .execute()
    }

    // MARK: - Ratings & Feedback

    /// Rate content
    func rateContent(
        contentId: UUID,
        rating: Int,
        helpful: Bool? = nil,
        feedback: String? = nil
    ) async throws -> RateContentResponse {
        // Ensure session is loaded before making function call
        let session: Session
        do {
            session = try await supabase.auth.session
            Log.data.debug("[GeneratedContent] rateContent - Session acquired")
        } catch {
            Log.data.error("[GeneratedContent] rateContent - Failed to get session")
            throw GeneratedContentError.notAuthenticated
        }

        let request = RateContentRequest(
            contentId: contentId.uuidString,
            rating: rating,
            helpful: helpful,
            feedback: feedback
        )

        #if DEBUG
        print("[GeneratedContentService] rateContent - Invoking edge function 'rate-content'...")
        #endif

        let response: RateContentResponse = try await supabase.functions.invoke(
            "rate-content",
            options: FunctionInvokeOptions(body: request)
        )

        #if DEBUG
        print("[GeneratedContentService] rateContent - Success: \(response.message)")
        #endif

        return response
    }

    /// Flag content for review
    func flagContent(
        contentId: UUID,
        reason: ContentFlagReason,
        details: String? = nil
    ) async throws -> FlagContentResponse {
        let request = FlagContentRequest(
            contentId: contentId.uuidString,
            reason: reason,
            details: details
        )

        let response: FlagContentResponse = try await supabase.functions.invoke(
            "flag-content",
            options: FunctionInvokeOptions(body: request)
        )

        return response
    }

    // MARK: - Quota

    /// Fetch current quota status
    func fetchQuotaStatus() async throws -> ContentQuotaStatus {
        let userId = try await getCurrentUserId()

        // Get today's generation count
        let startOfDay = Calendar.current.startOfDay(for: Date())

        struct CountResult: Codable {
            let count: Int
        }

        let result: [CountResult] = try await supabase
            .from("gen_content_requests")
            .select("count", head: false, count: .exact)
            .eq("user_id", value: userId.uuidString)
            .gte("created_at", value: ISO8601DateFormatter().string(from: startOfDay))
            .execute()
            .value

        let used = result.first?.count ?? 0

        // Check premium status from profiles table (subscription_tier column)
        struct ProfileSubscription: Codable {
            let subscriptionTier: String

            enum CodingKeys: String, CodingKey {
                case subscriptionTier = "subscription_tier"
            }
        }

        let profile: ProfileSubscription? = try? await supabase
            .from("profiles")
            .select("subscription_tier")
            .eq("id", value: userId.uuidString)
            .single()
            .execute()
            .value

        // Check for premium tier
        let tier = profile?.subscriptionTier ?? "free"
        let isPremium = tier == "premium"
        let limit = isPremium ? 999 : 3

        print("[GeneratedContentService] fetchQuotaStatus - subscription_tier: '\(tier)', isPremium: \(isPremium), used: \(used)")

        let status = ContentQuotaStatus(
            used: used,
            limit: limit,
            isPremium: isPremium,
            resetsAt: Calendar.current.startOfDay(for: Date().addingTimeInterval(86400))
        )

        quotaStatus = status
        return status
    }

    // MARK: - Helpers

    private func getCurrentUserId() async throws -> UUID {
        // Use async session to properly wait for session restoration
        do {
            let session = try await supabase.auth.session
            return session.user.id
        } catch {
            throw GeneratedContentError.notAuthenticated
        }
    }

    private func mapFunctionsError(_ error: FunctionsError) -> GeneratedContentError {
        switch error {
        case .httpError(let code, _):
            switch code {
            case 401:
                return .notAuthenticated
            case 403:
                return .premiumRequired
            case 429:
                return .quotaExceeded
            case 400:
                return .invalidRequest("Invalid request parameters")
            default:
                return .serverError("Server error: \(code)")
            }
        case .relayError:
            return .networkError
        }
    }
}

// MARK: - Errors

enum GeneratedContentError: LocalizedError {
    case notAuthenticated
    case premiumRequired
    case quotaExceeded
    case invalidRequest(String)
    case generationFailed(String)
    case serverError(String)
    case networkError
    case contentNotFound

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Please sign in to generate content"
        case .premiumRequired:
            return "Premium voice synthesis is a Premium feature. Upgrade to unlock studio-quality AI voices!"
        case .quotaExceeded:
            return "Daily generation limit reached. Upgrade to Premium for unlimited content."
        case .invalidRequest(let message):
            return "Invalid request: \(message)"
        case .generationFailed(let message):
            return "Generation failed: \(message)"
        case .serverError(let message):
            return message
        case .networkError:
            return "Network error. Please check your connection."
        case .contentNotFound:
            return "Content not found"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .premiumRequired, .quotaExceeded:
            return "Upgrade to Premium"
        default:
            return nil
        }
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension GeneratedContentService {
    static var preview: GeneratedContentService {
        GeneratedContentService(supabase: SupabaseClient(
            supabaseURL: URL(string: "https://example.supabase.co")!,
            supabaseKey: "preview-key"
        ))
    }
}

extension GeneratedContent {
    static var preview: GeneratedContent {
        GeneratedContent(
            id: UUID(),
            userId: UUID(),
            contentType: .meditation,
            title: "Peaceful Evening Meditation",
            textContent: "Welcome to this peaceful evening meditation...",
            audioUrl: "https://example.com/audio.mp3",
            voiceId: DefaultVoice.sarah.id,
            duration: 600,
            qualityScore: 0.92,
            status: .completed,
            generationPrompt: "A calming meditation for evening relaxation",
            aiModel: "grok-2",
            processingTimeMs: 15000,
            triggerWarnings: nil,
            averageRating: 4.5,
            ratingCount: 12,
            seriesId: nil,
            seriesOrder: nil,
            isFavorite: false,
            playCount: 5,
            lastPlayedAt: Date().addingTimeInterval(-3600),
            generationContext: nil,
            userRating: nil,
            createdAt: Date().addingTimeInterval(-86400),
            updatedAt: Date().addingTimeInterval(-86400)
        )
    }
}

extension ContentQuotaStatus {
    static var preview: ContentQuotaStatus {
        ContentQuotaStatus(
            used: 1,
            limit: 3,
            isPremium: false,
            resetsAt: Calendar.current.startOfDay(for: Date().addingTimeInterval(86400))
        )
    }

    static var premiumPreview: ContentQuotaStatus {
        ContentQuotaStatus(
            used: 5,
            limit: 999,
            isPremium: true,
            resetsAt: nil
        )
    }
}
#endif
