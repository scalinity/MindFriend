import Foundation
import Supabase

@MainActor
protocol CoachServiceProtocol {
    func getSettings() async throws -> CoachSettings
    func updateSettings(_ settings: CoachSettings) async throws
    func recordInteraction(encounterId: UUID?, distortionCode: String, action: CoachInteraction.Action, confidence: Double?) async throws
    func getMyPatterns() async throws -> PatternAnalytics
    func getWeeklySummary() async throws -> WeeklyPatternSummary?
    func getDistortionLibrary() async throws -> [CognitiveDistortionDefinition]
    func getDistortion(code: String) async throws -> CognitiveDistortionDefinition?
    func getEncounters(limit: Int) async throws -> [DistortionEncounter]
}

@MainActor
class CoachService: ObservableObject, CoachServiceProtocol {
    private let supabase: SupabaseClient

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    // MARK: - Settings

    func getSettings() async throws -> CoachSettings {
        let session = try await supabase.auth.session
        let user = session.user
        
        let response: CoachSettings = try await supabase
            .from("coach_settings")
            .select()
            .eq("user_id", value: user.id.uuidString)
            .single()
            .execute()
            .value
        
        return response
    }

    func updateSettings(_ settings: CoachSettings) async throws {
        let session = try await supabase.auth.session
        let user = session.user
        
        _ = try await supabase
            .from("coach_settings")
            .update(settings)
            .eq("user_id", value: user.id.uuidString)
            .execute()
    }

    // MARK: - Interactions

    func recordInteraction(
        encounterId: UUID?,
        distortionCode: String,
        action: CoachInteraction.Action,
        confidence: Double? = nil
    ) async throws {
        let session = try await supabase.auth.session
        let user = session.user
        
        let interaction = CoachInteraction(
            id: UUID(),
            userId: user.id,
            encounterId: encounterId,
            distortionCode: distortionCode,
            action: action,
            confidence: confidence,
            occurredAt: Date()
        )
        
        _ = try await supabase
            .from("coach_interactions")
            .insert([interaction])
            .execute()

        // Update encounter with user action
        if let encounterId = encounterId {
            let userAction = action.rawValue
            let reframeAccepted = action == .helpful
            
            struct UpdateData: Encodable {
                let user_action: String
                let reframe_accepted: Bool
            }
            
            let updateData = UpdateData(user_action: userAction, reframe_accepted: reframeAccepted)
            
            try await supabase
                .from("distortion_encounters")
                .update(updateData)
                .eq("id", value: encounterId.uuidString)
                .execute()
        }
    }

    // MARK: - Pattern Analytics

    func getMyPatterns() async throws -> PatternAnalytics {
        let session = try await supabase.auth.session
        let user = session.user
        
        let _ = JSONEncoder()
        let body: [String: String] = ["userId": user.id.uuidString]
        
        let result: PatternAnalytics = try await supabase.functions.invoke(
            "my-patterns",
            options: FunctionInvokeOptions(body: body)
        )

        return result
    }

    func getWeeklySummary() async throws -> WeeklyPatternSummary? {
        let session = try await supabase.auth.session
        let user = session.user
        
        let response: [WeeklyPatternSummary]? = try await supabase
            .from("weekly_pattern_summaries")
            .select()
            .eq("user_id", value: user.id.uuidString)
            .order("week_start", ascending: false)
            .limit(1)
            .execute()
            .value
        
        return response?.first
    }

    // MARK: - Distortion Library

    func getDistortionLibrary() async throws -> [CognitiveDistortionDefinition] {
        let response: [CognitiveDistortionDefinition] = try await supabase
            .from("cognitive_distortions")
            .select()
            .order("display_order", ascending: true)
            .execute()
            .value
        
        return response
    }

    func getDistortion(code: String) async throws -> CognitiveDistortionDefinition? {
        let response: [CognitiveDistortionDefinition] = try await supabase
            .from("cognitive_distortions")
            .select()
            .eq("code", value: code)
            .limit(1)
            .execute()
            .value
        
        return response.first
    }

    // MARK: - Encounters

    func getEncounters(limit: Int) async throws -> [DistortionEncounter] {
        let session = try await supabase.auth.session
        let user = session.user
        
        let response: [DistortionEncounter] = try await supabase
            .from("distortion_encounters")
            .select()
            .eq("user_id", value: user.id.uuidString)
            .order("occurred_at", ascending: false)
            .limit(limit)
            .execute()
            .value
        
        return response
    }
}

// MARK: - Error

enum CoachError: LocalizedError {
    case notAuthenticated
    case networkError
    case decodingError

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to use this feature."
        case .networkError:
            return "Unable to connect. Please check your internet connection."
        case .decodingError:
            return "Unable to process data. Please try again."
        }
    }
}
