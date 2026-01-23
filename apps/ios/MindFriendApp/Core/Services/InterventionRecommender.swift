import Foundation
import Supabase

/// Recommends interventions based on nervous system state
final class InterventionRecommender {
    // MARK: - Properties

    private let supabase: SupabaseClient

    // MARK: - Initialization

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    // MARK: - Public Interface

    /// Recommend interventions for current state
    /// - Parameters:
    ///   - state: Current nervous system state
    ///   - cascadeEvent: Optional cascade event (escalates urgency)
    ///   - userId: User ID for personalized efficacy lookup
    /// - Returns: Sorted list of intervention recommendations
    func recommend(
        for state: NervousSystemState,
        cascadeEvent: CascadeEvent? = nil,
        userId: UUID
    ) async throws -> [InterventionRecommendation] {
        // Get baseline recommendations for state
        var recommendations = getBaselineRecommendations(for: state)

        // Escalate urgency if cascade detected
        if let cascade = cascadeEvent {
            recommendations = escalateForCascade(recommendations, cascade: cascade)
        }

        // Personalize with user efficacy data
        recommendations = try await personalize(recommendations, for: userId, state: state)

        // Sort by urgency (critical first) then efficacy
        return recommendations.sorted { lhs, rhs in
            if lhs.urgency != rhs.urgency {
                return lhs.urgency.rawValue > rhs.urgency.rawValue
            }
            return (lhs.efficacyScore ?? 0.5) > (rhs.efficacyScore ?? 0.5)
        }
    }

    // MARK: - Private Methods - Baseline Recommendations

    private func getBaselineRecommendations(for state: NervousSystemState) -> [InterventionRecommendation] {
        switch state {
        case .sympathetic:
            return sympatheticInterventions()
        case .dorsal:
            return dorsalInterventions()
        case .ventral:
            return ventralMaintenanceInterventions()
        case .mixed:
            return mixedStateInterventions()
        case .unknown:
            return []
        }
    }

    private func sympatheticInterventions() -> [InterventionRecommendation] {
        return [
            InterventionRecommendation(
                id: UUID(),
                type: .breathing,
                title: "4-7-8 Breathing",
                description: "Exhale longer than you inhale to activate the vagus nerve and calm your nervous system.",
                estimatedDuration: 180, // 3 minutes
                urgency: .medium,
                efficacyScore: nil
            ),
            InterventionRecommendation(
                id: UUID(),
                type: .grounding,
                title: "5-4-3-2-1 Grounding",
                description: "Bring yourself back to the present moment by engaging your senses.",
                estimatedDuration: 180,
                urgency: .medium,
                efficacyScore: nil
            ),
            InterventionRecommendation(
                id: UUID(),
                type: .movement,
                title: "Gentle Shaking",
                description: "Release tension and discharge sympathetic activation through gentle movement.",
                estimatedDuration: 120,
                urgency: .low,
                efficacyScore: nil
            )
        ]
    }

    private func dorsalInterventions() -> [InterventionRecommendation] {
        return [
            InterventionRecommendation(
                id: UUID(),
                type: .grounding,
                title: "Orienting Exercise",
                description: "Gently look around and name what you see to reconnect with your environment.",
                estimatedDuration: 120,
                urgency: .high,
                efficacyScore: nil
            ),
            InterventionRecommendation(
                id: UUID(),
                type: .movement,
                title: "Gentle Stretching",
                description: "Invite gentle movement to help your system shift out of shutdown.",
                estimatedDuration: 180,
                urgency: .high,
                efficacyScore: nil
            ),
            InterventionRecommendation(
                id: UUID(),
                type: .socialConnection,
                title: "Reach Out to Someone",
                description: "Connection with a safe person can help your nervous system find regulation.",
                estimatedDuration: 300,
                urgency: .medium,
                efficacyScore: nil
            )
        ]
    }

    private func ventralMaintenanceInterventions() -> [InterventionRecommendation] {
        return [
            InterventionRecommendation(
                id: UUID(),
                type: .socialConnection,
                title: "Share Your Progress",
                description: "Your nervous system is regulated. Consider sharing this moment with your circle.",
                estimatedDuration: 120,
                urgency: .low,
                efficacyScore: nil
            ),
            InterventionRecommendation(
                id: UUID(),
                type: .movement,
                title: "Gratitude Practice",
                description: "Notice and savor what feels good right now.",
                estimatedDuration: 120,
                urgency: .low,
                efficacyScore: nil
            )
        ]
    }

    private func mixedStateInterventions() -> [InterventionRecommendation] {
        // Combine sympathetic and dorsal interventions
        return sympatheticInterventions() + dorsalInterventions()
    }

    // MARK: - Private Methods - Cascade Escalation

    private func escalateForCascade(_ recommendations: [InterventionRecommendation], cascade: CascadeEvent) -> [InterventionRecommendation] {
        var escalated = recommendations

        // Escalate all urgencies
        escalated = escalated.map { intervention in
            var updated = intervention
            updated.urgency = escalateUrgency(intervention.urgency, for: cascade.severity)
            return updated
        }

        // Add professional support for severe cascades
        if cascade.severity == .severe {
            escalated.insert(
                InterventionRecommendation(
                    id: UUID(),
                    type: .professionalSupport,
                    title: "Reach Out for Support",
                    description: "Your nervous system needs extra support right now. Consider reaching out to a mental health professional.",
                    estimatedDuration: 600,
                    urgency: .critical,
                    efficacyScore: nil
                ),
                at: 0
            )
        }

        return escalated
    }

    private func escalateUrgency(_ baseUrgency: InterventionUrgency, for severity: CascadeSeverity) -> InterventionUrgency {
        switch (severity, baseUrgency) {
        case (.severe, .low), (.severe, .medium):
            return .critical
        case (.severe, .high):
            return .critical
        case (.moderate, .low):
            return .medium
        case (.moderate, .medium):
            return .high
        case (.moderate, .high):
            return .critical
        case (.mild, .low):
            return .medium
        default:
            return baseUrgency
        }
    }

    // MARK: - Private Methods - Personalization

    private func personalize(
        _ recommendations: [InterventionRecommendation],
        for userId: UUID,
        state: NervousSystemState
    ) async throws -> [InterventionRecommendation] {
        // Query user's intervention efficacy history
        let efficacyData: [UserInterventionEfficacy] = try await supabase
            .from("user_intervention_efficacy")
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq("target_state", value: state.rawValue)
            .execute()
            .value

        // Create efficacy lookup
        var efficacyMap: [NervousSystemInterventionType: Double] = [:]
        for entry in efficacyData {
            if let type = NervousSystemInterventionType(rawValue: entry.interventionType) {
                efficacyMap[type] = entry.avgEfficacy
            }
        }

        // Update recommendations with personalized efficacy
        return recommendations.map { recommendation in
            var updated = recommendation
            updated.efficacyScore = efficacyMap[recommendation.type]
            return updated
        }
    }
}

// MARK: - Supporting Types

private struct UserInterventionEfficacy: Codable {
    let userId: String
    let interventionType: String
    let targetState: String
    let totalCompleted: Int
    let avgEfficacy: Double

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case interventionType = "intervention_type"
        case targetState = "target_state"
        case totalCompleted = "total_completed"
        case avgEfficacy = "avg_efficacy"
    }
}
