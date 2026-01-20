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
        guard let userId = try await supabase.auth.session.user.id else {
            throw CoachError.notAuthenticated
        }

        let response = try await supabase
            .from("coach_settings")
            .select()
            .eq("user_id", value: userId)
            .maybeSingle()
            .execute()

        if let data = response.data, !data.isEmpty {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(CoachSettings.self, from: data)
        } else {
            // Return default settings if none exist
            return CoachSettings.defaultSettings
        }
    }

    func updateSettings(_ settings: CoachSettings) async throws {
        guard let userId = try await supabase.auth.session.user.id else {
            throw CoachError.notAuthenticated
        }

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601

        var settingsDict: [String: Any] = [
            "user_id": userId.uuidString,
            "is_enabled": settings.isEnabled,
            "sensitivity_level": settings.sensitivityLevel.rawValue,
            "disabled_distortions": settings.disabledDistortions,
            "show_patterns": settings.showPatterns,
            "timezone": settings.timezone
        ]

        // Convert Date to TIME format (HH:MM:SS)
        if let start = settings.silentHoursStart {
            let calendar = Calendar.current
            let components = calendar.dateComponents([.hour, .minute], from: start)
            settingsDict["silent_hours_start"] = String(format: "%02d:%02d:00", components.hour ?? 0, components.minute ?? 0)
        }

        if let end = settings.silentHoursEnd {
            let calendar = Calendar.current
            let components = calendar.dateComponents([.hour, .minute], from: end)
            settingsDict["silent_hours_end"] = String(format: "%02d:%02d:00", components.hour ?? 0, components.minute ?? 0)
        }

        try await supabase
            .from("coach_settings")
            .upsert(settingsDict)
            .execute()
    }

    // MARK: - Interactions

    func recordInteraction(
        encounterId: UUID?,
        distortionCode: String,
        action: CoachInteraction.Action,
        confidence: Double? = nil
    ) async throws {
        guard let userId = try await supabase.auth.session.user.id else {
            throw CoachError.notAuthenticated
        }

        var interactionData: [String: Any] = [
            "user_id": userId.uuidString,
            "distortion_code": distortionCode,
            "action": action.rawValue,
            "occurred_at": ISO8601DateFormatter().string(from: Date())
        ]

        if let encounterId = encounterId {
            interactionData["encounter_id"] = encounterId.uuidString
        }

        if let confidence = confidence {
            interactionData["confidence"] = confidence
        }

        try await supabase
            .from("coach_interactions")
            .insert(interactionData)
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
        guard let userId = try await supabase.auth.session.user.id else {
            throw CoachError.notAuthenticated
        }

        let response = try await supabase.functions.invoke(
            "my-patterns",
            options: FunctionInvokeOptions()
        )

        guard let data = response.data else {
            throw CoachError.decodingError
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode(PatternAnalytics.self, from: data)
    }

    func getWeeklySummary() async throws -> WeeklyPatternSummary? {
        guard let userId = try await supabase.auth.session.user.id else {
            throw CoachError.notAuthenticated
        }

        let response = try await supabase
            .from("weekly_pattern_summaries")
            .select()
            .eq("user_id", value: userId)
            .order("week_start", ascending: false)
            .limit(1)
            .maybeSingle()
            .execute()

        if let data = response.data, !data.isEmpty {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(WeeklyPatternSummary.self, from: data)
        }

        return nil
    }

    // MARK: - Distortion Library

    func getDistortionLibrary() async throws -> [CognitiveDistortion] {
        let response = try await supabase
            .from("cognitive_distortions")
            .select()
            .order("display_order", ascending: true)
            .execute()

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode([CognitiveDistortion].self, from: response.data)
    }

    func getDistortion(code: String) async throws -> CognitiveDistortion? {
        let response = try await supabase
            .from("cognitive_distortions")
            .select()
            .eq("code", value: code)
            .maybeSingle()
            .execute()

        if let data = response.data, !data.isEmpty {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(CognitiveDistortion.self, from: data)
        }

        return nil
    }

    // MARK: - Encounters

    func getEncounters(limit: Int = 50) async throws -> [DistortionEncounter] {
        guard let userId = try await supabase.auth.session.user.id else {
            throw CoachError.notAuthenticated
        }

        let response = try await supabase
            .from("distortion_encounters")
            .select()
            .eq("user_id", value: userId)
            .order("occurred_at", ascending: false)
            .limit(limit)
            .execute()

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode([DistortionEncounter].self, from: response.data)
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
