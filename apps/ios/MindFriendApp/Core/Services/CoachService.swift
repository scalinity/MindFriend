import Foundation
import Supabase

@MainActor
class CoachService: ObservableObject {
    private let supabase: SupabaseClient

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    // MARK: - Settings

    func getSettings() async throws -> CoachSettings {
        guard let session = try? await supabase.auth.session, let user = session.user else {
            throw CoachError.notAuthenticated
        }

        let response: CoachSettings = try await supabase
            .from("user_coach_settings")
            .select()
            .eq("user_id", value: user.id.uuidString)
            .single()
            .execute()
            .value

        return response
    }

    func updateSettings(_ settings: CoachSettings) async throws {
        guard let session = try? await supabase.auth.session, let user = session.user else {
            throw CoachError.notAuthenticated
        }

        _ = try await supabase
            .from("user_coach_settings")
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
        guard let session = try? await supabase.auth.session, let user = session.user else {
            throw CoachError.notAuthenticated
        }

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
            var updateData: [String: Any] = [
                "user_action": action.rawValue
            ]

            if action == .helpful {
                updateData["reframe_accepted"] = true
            }

            try await supabase
                .from("distortion_encounters")
                .update(updateData)
                .eq("id", value: encounterId.uuidString)
                .execute()
        }
    }

    // MARK: - Pattern Analytics

    func getMyPatterns() async throws -> PatternAnalytics {
        guard let session = try? await supabase.auth.session, let user = session.user else {
            throw CoachError.notAuthenticated
        }

        let invokeResponse = try await supabase.functions
            .invoke(
                "get-patterns",
                options: FunctionInvokeOptions(body: ["userId": user.id.uuidString])
            )

        let response = try invokeResponse.decoded(as: PatternAnalytics.self)
        return response
    }

    func getWeeklySummary() async throws -> WeeklyPatternSummary? {
        guard let session = try? await supabase.auth.session, let user = session.user else {
            throw CoachError.notAuthenticated
        }

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

    func getDistortionLibrary() async throws -> [CognitiveDistortion] {
        let response: [CognitiveDistortion] = try await supabase
            .from("cognitive_distortions")
            .select()
            .order("display_order", ascending: true)
            .execute()
            .value

        return response
    }

    func getDistortion(code: String) async throws -> CognitiveDistortion? {
        let response: [CognitiveDistortion] = try await supabase
            .from("cognitive_distortions")
            .select()
            .eq("code", value: code)
            .execute()
            .value

        return response.first
    }

    // MARK: - Encounters

    func getEncounters(limit: Int) async throws -> [DistortionEncounter] {
        guard let session = try? await supabase.auth.session, let user = session.user else {
            throw CoachError.notAuthenticated
        }

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
