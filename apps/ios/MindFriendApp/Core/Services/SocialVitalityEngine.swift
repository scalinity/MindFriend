//
//  SocialVitalityEngine.swift
//  MindFriend
//
//  Created: 2026-01-23
//  Feature: N004 - Social Vitality Index
//

import Foundation
import Supabase

/// Main orchestrator for Social Vitality operations
@MainActor
final class SocialVitalityEngine: ObservableObject {
    // MARK: - Published State

    @Published var currentScore: SocialVitalityScore?
    @Published var dashboard: SocialVitalityDashboard?
    @Published var relationshipInsights: [RelationshipCorrelation] = []
    @Published var alertPreferences: PeerAlertPreferences?
    @Published var isLoading: Bool = false
    @Published var error: EngineError?

    // MARK: - Dependencies

    private let supabase: SupabaseClient

    // MARK: - Initialization

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    // MARK: - Public Methods

    /// Fetch complete dashboard data
    func fetchDashboard() async throws {
        isLoading = true
        error = nil

        do {
            guard let userId = supabase.auth.currentUser?.id else {
                throw EngineError.unauthorized
            }

            // Call get_social_vitality_dashboard RPC function
            let response = try await supabase
                .rpc("get_social_vitality_dashboard", params: ["p_user_id": userId])
                .execute()

            guard let data = response.data else {
                throw EngineError.noData
            }

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .iso8601

            let dashboardData = try decoder.decode(SocialVitalityDashboard.self, from: data)
            self.dashboard = dashboardData

            isLoading = false
        } catch {
            isLoading = false
            let engineError = EngineError.networkError(error)
            self.error = engineError
            throw engineError
        }
    }

    /// Fetch score history for charting
    func fetchScoreHistory(days: Int = 30) async throws -> [SocialVitalityScore] {
        guard let userId = supabase.auth.currentUser?.id else {
            throw EngineError.unauthorized
        }

        let daysAgo = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()

        let response = try await supabase
            .from("social_vitality_scores")
            .select()
            .eq("user_id", value: userId.uuidString)
            .gte("date", value: ISO8601DateFormatter().string(from: daysAgo))
            .order("date", ascending: true)
            .execute()

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        let scores = try decoder.decode([SocialVitalityScore].self, from: response.data)
        return scores
    }

    /// Fetch relationship insights (correlations)
    func fetchRelationshipInsights() async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw EngineError.unauthorized
        }

        let response = try await supabase
            .from("relationship_correlations")
            .select("""
                id,
                user_id,
                other_user_id,
                mood_correlation,
                interaction_count,
                confidence_level,
                classification,
                updated_at,
                other_user:profiles!other_user_id(full_name, email)
            """)
            .eq("user_id", value: userId.uuidString)
            .order("mood_correlation", ascending: false)
            .execute()

        // Parse response and map to RelationshipCorrelation with display names
        // Note: Simplified - would need custom decoding to handle joined profiles
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        // For MVP, just fetch without join and use otherUserId as display name
        let simpleResponse = try await supabase
            .from("relationship_correlations")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("mood_correlation", ascending: false)
            .execute()

        // TODO: Properly decode with joined profile data
        // For now, create placeholder with otherUserId as display name
        struct TempCorrelation: Codable {
            let id: UUID
            let userId: String
            let otherUserId: String
            let moodCorrelation: Double
            let interactionCount: Int
            let confidenceLevel: Double
            let classification: String
            let updatedAt: Date

            enum CodingKeys: String, CodingKey {
                case id, moodCorrelation, interactionCount, confidenceLevel, classification, updatedAt
                case userId = "user_id"
                case otherUserId = "other_user_id"
            }
        }

        let tempCorrelations = try decoder.decode([TempCorrelation].self, from: simpleResponse.data)

        self.relationshipInsights = tempCorrelations.map { temp in
            RelationshipCorrelation(
                id: temp.id,
                userId: temp.userId,
                otherUserId: temp.otherUserId,
                otherUserDisplayName: "User \(temp.otherUserId.prefix(8))", // TODO: Fetch actual name
                moodCorrelation: temp.moodCorrelation,
                interactionCount: temp.interactionCount,
                confidenceLevel: temp.confidenceLevel,
                classification: RelationshipCorrelation.RelationshipType(rawValue: temp.classification) ?? .neutral,
                updatedAt: temp.updatedAt
            )
        }
    }

    /// Update peer alert preferences
    func updateAlertPreferences(_ preferences: PeerAlertPreferences) async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw EngineError.unauthorized
        }

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(preferences)
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        try await supabase
            .from("peer_alert_preferences")
            .upsert(dict)
            .execute()

        self.alertPreferences = preferences
    }

    /// Fetch current alert preferences
    func fetchAlertPreferences() async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw EngineError.unauthorized
        }

        let response = try await supabase
            .from("peer_alert_preferences")
            .select()
            .eq("user_id", value: userId.uuidString)
            .single()
            .execute()

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        let preferences = try decoder.decode(PeerAlertPreferences.self, from: response.data)
        self.alertPreferences = preferences
    }

    /// Request supporter consent (send invitation)
    func requestSupporterConsent(supporterId: String) async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            throw EngineError.unauthorized
        }

        let consent: [String: Any] = [
            "supporter_id": supporterId,
            "requesting_user_id": userId.uuidString,
            "accepted": false,
            "created_at": ISO8601DateFormatter().string(from: Date()),
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]

        try await supabase
            .from("peer_support_consent")
            .insert(consent)
            .execute()

        // TODO: Send push notification to supporter asking for consent
    }

    /// Remove supporter from designated list
    func removeSupporter(supporterId: String) async throws {
        guard var preferences = alertPreferences else {
            throw EngineError.noData
        }

        preferences.designatedSupporters.removeAll { $0 == supporterId }

        try await updateAlertPreferences(preferences)
    }

    // MARK: - Error Types

    enum EngineError: LocalizedError {
        case notEnoughData
        case noData
        case networkError(Error)
        case unauthorized

        var errorDescription: String? {
            switch self {
            case .notEnoughData:
                return "Not enough activity data yet. Keep engaging in circles!"
            case .noData:
                return "No social vitality data available."
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .unauthorized:
                return "Please sign in to view social vitality."
            }
        }
    }
}
