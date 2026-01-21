//
//  BoundaryPlannerService.swift
//  MindFriendApp
//
//  Service layer for Boundary & Needs Planner feature
//  Wraps all 9 Edge Functions with proper error handling
//

import Foundation
import Supabase

@MainActor
final class BoundaryPlannerService: ObservableObject {
    private let supabase: SupabaseClient

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    // MARK: - Assessment

    /// Create a new needs assessment
    func createAssessment(
        type: BoundaryAssessmentType,
        responses: AssessmentResponses
    ) async throws -> CreateAssessmentResponse {
        let response = try await supabase.functions.invoke(
            "create-assessment",
            options: FunctionInvokeOptions(
                body: [
                    "assessmentType": type.rawValue,
                    "responses": [
                        "step1_drain_triggers": responses.step1DrainTriggers,
                        "step2_importance_ratings": responses.step2ImportanceRatings,
                        "step3_currently_met": responses.step3CurrentlyMet,
                        "step4_priority_needs": responses.step4PriorityNeeds
                    ]
                ]
            )
        )

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(CreateAssessmentResponse.self, from: response.data)
    }

    /// Get a specific assessment by ID
    func getAssessment(id: UUID) async throws -> NeedsAssessment {
        let response = try await supabase.functions.invoke(
            "get-assessment/\(id.uuidString)",
            options: FunctionInvokeOptions(
                method: .get
            )
        )

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        struct Response: Codable {
            let success: Bool
            let assessment: NeedsAssessment
        }

        let result = try decoder.decode(Response.self, from: response.data)
        return result.assessment
    }

    // MARK: - Boundaries

    /// Generate a new boundary
    func generateBoundary(
        assessmentId: UUID? = nil,
        boundaryType: BoundaryType,
        statement: String,
        whyMatters: String,
        stakeholder: String? = nil
    ) async throws -> GenerateBoundaryResponse {
        var body: [String: Any] = [
            "boundaryType": boundaryType.rawValue,
            "statement": statement,
            "whyMatters": whyMatters
        ]

        if let assessmentId = assessmentId {
            body["assessmentId"] = assessmentId.uuidString
        }

        if let stakeholder = stakeholder {
            body["stakeholder"] = stakeholder
        }

        let response = try await supabase.functions.invoke(
            "generate-boundary",
            options: FunctionInvokeOptions(body: body)
        )

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(GenerateBoundaryResponse.self, from: response.data)
    }

    /// List all boundaries for the current user
    func listBoundaries(
        status: String = "all",
        limit: Int = 20,
        offset: Int = 0
    ) async throws -> ListBoundariesResponse {
        // Build query string for GET request
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "status", value: status),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]

        let queryString = components.url?.query ?? ""
        let path = queryString.isEmpty ? "list-boundaries" : "list-boundaries?\(queryString)"

        let response = try await supabase.functions.invoke(
            path,
            options: FunctionInvokeOptions(
                method: .get
            )
        )

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ListBoundariesResponse.self, from: response.data)
    }

    /// Save/update boundary status
    func saveBoundary(
        boundaryId: UUID,
        status: BoundaryStatus
    ) async throws -> SaveBoundaryResponse {
        let response = try await supabase.functions.invoke(
            "save-boundary",
            options: FunctionInvokeOptions(
                body: [
                    "boundaryId": boundaryId.uuidString,
                    "status": status.rawValue
                ]
            )
        )

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SaveBoundaryResponse.self, from: response.data)
    }

    // MARK: - Scripts

    /// Generate scripts for a boundary
    func generateScripts(
        boundaryId: UUID,
        relationshipType: String,
        variations: [ScriptVariation]
    ) async throws -> GenerateScriptsResponse {
        let response = try await supabase.functions.invoke(
            "generate-scripts",
            options: FunctionInvokeOptions(
                body: [
                    "boundaryId": boundaryId.uuidString,
                    "relationshipType": relationshipType,
                    "variations": variations.map { $0.rawValue }
                ]
            )
        )

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(GenerateScriptsResponse.self, from: response.data)
    }

    /// Get script templates with filters
    func getTemplates(
        boundaryType: BoundaryType? = nil,
        relationshipType: String? = nil,
        locale: String = "en"
    ) async throws -> [BoundaryScriptTemplate] {
        var queryParams: [String: String] = ["locale": locale]

        if let boundaryType = boundaryType {
            queryParams["boundaryType"] = boundaryType.rawValue
        }

        if let relationshipType = relationshipType {
            queryParams["relationshipType"] = relationshipType
        }

        let response = try await supabase.functions.invoke(
            "get-templates",
            options: FunctionInvokeOptions(
                method: .get,
                body: queryParams
            )
        )

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        struct Response: Codable {
            let success: Bool
            let templates: [BoundaryScriptTemplate]
        }

        let result = try decoder.decode(Response.self, from: response.data)
        return result.templates
    }

    // MARK: - Follow-Ups

    /// Schedule a follow-up check-in
    func scheduleFollowUp(
        boundaryId: UUID,
        checkInAt: Date? = nil
    ) async throws -> ScheduleFollowUpResponse {
        var body: [String: Any] = [
            "boundaryId": boundaryId.uuidString
        ]

        if let checkInAt = checkInAt {
            let formatter = ISO8601DateFormatter()
            body["checkInAt"] = formatter.string(from: checkInAt)
        }

        let response = try await supabase.functions.invoke(
            "schedule-followup",
            options: FunctionInvokeOptions(body: body)
        )

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ScheduleFollowUpResponse.self, from: response.data)
    }

    /// Record the outcome of a follow-up check-in
    func recordOutcome(
        followUpId: UUID,
        outcome: FollowUpOutcome,
        notes: String? = nil,
        reflection: String? = nil,
        nextAction: String? = nil
    ) async throws -> RecordOutcomeResponse {
        var body: [String: Any] = [
            "followUpId": followUpId.uuidString,
            "outcome": outcome.rawValue
        ]

        if let notes = notes {
            body["notes"] = notes
        }

        if let reflection = reflection {
            body["reflection"] = reflection
        }

        if let nextAction = nextAction {
            body["nextAction"] = nextAction
        }

        let response = try await supabase.functions.invoke(
            "record-outcome",
            options: FunctionInvokeOptions(body: body)
        )

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(RecordOutcomeResponse.self, from: response.data)
    }

    // MARK: - Error Handling

    enum BoundaryPlannerError: LocalizedError {
        case unauthorized
        case tierLimitReached(currentCount: Int)
        case boundaryNotFound
        case invalidTransition(current: String, requested: String, allowed: [String])
        case networkError(Error)
        case decodingError(Error)
        case unknown(String)

        var errorDescription: String? {
            switch self {
            case .unauthorized:
                return "You must be signed in to use this feature"
            case .tierLimitReached(let count):
                return "You've reached the free tier limit of 3 boundaries (\(count) created). Upgrade to Premium for unlimited boundaries."
            case .boundaryNotFound:
                return "Boundary not found"
            case .invalidTransition(let current, let requested, let allowed):
                return "Cannot transition from '\(current)' to '\(requested)'. Allowed: \(allowed.joined(separator: ", "))"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .decodingError(let error):
                return "Data error: \(error.localizedDescription)"
            case .unknown(let message):
                return message
            }
        }
    }
}
