import Foundation
import Supabase

@MainActor
final class TransitionService {
    private let supabase: SupabaseClient

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    // MARK: - Browse Pathways

    /// Fetch all available transition pathways (calls database directly since it's public data)
    func fetchAvailablePathways(category: PathwayCategory? = nil) async throws -> [TransitionPathway] {
        // For MVP, return all pathways - filtering can be done client-side
        let pathways: [TransitionPathway] = try await supabase
            .from("transition_pathways")
            .select()
            .execute()
            .value

        if let category = category {
            return pathways.filter { $0.category == category }
        }
        return pathways
    }

    // MARK: - Enrollment

    /// Enroll user in a pathway with personalization
    func enrollPathway(key: String, personalization: PathwayPersonalization) async throws -> EnrollPathwayResponse {
        struct EnrollRequest: Codable {
            let pathwayKey: String
            let personalization: PersonalizationData
        }

        struct PersonalizationData: Codable {
            let transitionDate: String?
            let specificContext: String?
            let supportPeople: [String]?
            let goals: [String]?
        }

        let request = EnrollRequest(
            pathwayKey: key,
            personalization: PersonalizationData(
                transitionDate: personalization.transitionDate?.ISO8601Format(),
                specificContext: personalization.specificContext,
                supportPeople: personalization.supportPeople,
                goals: personalization.goals
            )
        )

        let response: EnrollPathwayResponse = try await supabase.functions.invoke(
            "enroll-pathway",
            options: FunctionInvokeOptions(body: request)
        )

        return response
    }

    // MARK: - Active Pathways

    /// Fetch user's active pathways
    func fetchActivePathways() async throws -> [UserPathway] {
        let pathways: [UserPathway] = try await supabase
            .from("user_pathways")
            .select("*, pathway:transition_pathways(*)")
            .execute()
            .value

        return pathways.filter { $0.status == .active }
    }

    // MARK: - Daily Content

    /// Get today's pathway content
    func getDailyContent(userPathwayId: UUID) async throws -> DailyPathwayContent {
        struct ContentRequest: Codable {
            let userPathwayId: String
        }

        let request = ContentRequest(userPathwayId: userPathwayId.uuidString)

        let response: DailyPathwayContent = try await supabase.functions.invoke(
            "get-pathway-content",
            options: FunctionInvokeOptions(body: request)
        )

        return response
    }

    /// Submit daily check-in
    func completeCheckIn(
        userPathwayId: UUID,
        checkInData: CheckInData,
        exercisesCompleted: [String] = [],
        journalEntry: String? = nil
    ) async throws -> CheckInResponse {
        struct CheckInRequest: Codable {
            let userPathwayId: String
            let checkInData: CheckInData
            let exercisesCompleted: [String]
            let journalEntry: String?
        }

        let request = CheckInRequest(
            userPathwayId: userPathwayId.uuidString,
            checkInData: checkInData,
            exercisesCompleted: exercisesCompleted,
            journalEntry: journalEntry
        )

        let response: CheckInResponse = try await supabase.functions.invoke(
            "submit-pathway-checkin",
            options: FunctionInvokeOptions(body: request)
        )

        return response
    }

    // MARK: - Phase Progression

    /// Advance to next phase
    func advancePhase(userPathwayId: UUID) async throws -> AdvancePhaseResponse {
        struct AdvanceRequest: Codable {
            let userPathwayId: String
        }

        let request = AdvanceRequest(userPathwayId: userPathwayId.uuidString)

        let response: AdvancePhaseResponse = try await supabase.functions.invoke(
            "advance-pathway-phase",
            options: FunctionInvokeOptions(body: request)
        )

        return response
    }

    // MARK: - Pathway State Management

    /// Pause active pathway
    func pausePathway(userPathwayId: UUID, reason: String? = nil) async throws {
        struct PauseRequest: Codable {
            let userPathwayId: String
            let reason: String?
        }

        let request = PauseRequest(userPathwayId: userPathwayId.uuidString, reason: reason)
        let data = try JSONEncoder().encode(request)

        _ = try await supabase.functions.invoke(
            "pause-pathway",
            options: FunctionInvokeOptions(body: data)
        )
    }

    /// Resume paused pathway
    func resumePathway(userPathwayId: UUID) async throws {
        struct ResumeRequest: Codable {
            let userPathwayId: String
        }

        let request = ResumeRequest(userPathwayId: userPathwayId.uuidString)
        let data = try JSONEncoder().encode(request)

        _ = try await supabase.functions.invoke(
            "resume-pathway",
            options: FunctionInvokeOptions(body: data)
        )
    }

    /// Abandon pathway
    func abandonPathway(userPathwayId: UUID, feedback: String? = nil) async throws {
        struct AbandonRequest: Codable {
            let userPathwayId: String
            let feedback: String?
        }

        let request = AbandonRequest(userPathwayId: userPathwayId.uuidString, feedback: feedback)
        let data = try JSONEncoder().encode(request)

        _ = try await supabase.functions.invoke(
            "abandon-pathway",
            options: FunctionInvokeOptions(body: data)
        )
    }
}
