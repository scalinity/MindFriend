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

    // MARK: - Request/Response Models (Internal)
    
    private struct CreateAssessmentRequest: Encodable {
        let assessmentType: String
        let responses: AssessmentResponsesRequest
        
        enum CodingKeys: String, CodingKey {
            case assessmentType = "assessmentType"
            case responses = "responses"
        }
    }
    
    private struct AssessmentResponsesRequest: Encodable {
        let step1DrainTriggers: [String]
        let step2ImportanceRatings: [String: String]
        let step3CurrentlyMet: [String: String]
        let step4PriorityNeeds: [String]
        
        enum CodingKeys: String, CodingKey {
            case step1DrainTriggers = "step1_drain_triggers"
            case step2ImportanceRatings = "step2_importance_ratings"
            case step3CurrentlyMet = "step3_currently_met"
            case step4PriorityNeeds = "step4_priority_needs"
        }
        
        init(from responses: AssessmentResponses) {
            self.step1DrainTriggers = responses.step1DrainTriggers
            self.step2ImportanceRatings = responses.step2ImportanceRatings.mapValues { $0.rawValue }
            self.step3CurrentlyMet = responses.step3CurrentlyMet.mapValues { $0.rawValue }
            self.step4PriorityNeeds = responses.step4PriorityNeeds
        }
    }
    
    private struct GenerateBoundaryRequest: Encodable {
        let boundaryType: String
        let statement: String
        let whyMatters: String
        let assessmentId: String?
        let stakeholder: String?
        
        enum CodingKeys: String, CodingKey {
            case boundaryType = "boundaryType"
            case statement = "statement"
            case whyMatters = "whyMatters"
            case assessmentId = "assessmentId"
            case stakeholder = "stakeholder"
        }
    }
    
    private struct SaveBoundaryRequest: Encodable {
        let boundaryId: String
        let status: String
        
        enum CodingKeys: String, CodingKey {
            case boundaryId = "boundaryId"
            case status = "status"
        }
    }
    
    private struct GenerateScriptsRequest: Encodable {
        let boundaryId: String
        let relationshipType: String
        let variations: [String]
        
        enum CodingKeys: String, CodingKey {
            case boundaryId = "boundaryId"
            case relationshipType = "relationshipType"
            case variations = "variations"
        }
    }
    
    private struct ScheduleFollowUpRequest: Encodable {
        let boundaryId: String
        let checkInAt: String?
        
        enum CodingKeys: String, CodingKey {
            case boundaryId = "boundaryId"
            case checkInAt = "checkInAt"
        }
    }
    
    private struct RecordOutcomeRequest: Encodable {
        let followUpId: String
        let outcome: String
        let notes: String?
        let reflection: String?
        let nextAction: String?
        
        enum CodingKeys: String, CodingKey {
            case followUpId = "followUpId"
            case outcome = "outcome"
            case notes = "notes"
            case reflection = "reflection"
            case nextAction = "nextAction"
        }
    }

    // MARK: - Assessment

    /// Create a new needs assessment
    func createAssessment(
        type: BoundaryAssessmentType,
        responses: AssessmentResponses
    ) async throws -> CreateAssessmentResponse {
        let assessmentRequest = AssessmentResponsesRequest(from: responses)
        let request = CreateAssessmentRequest(
            assessmentType: type.rawValue,
            responses: assessmentRequest
        )
        
        let response: CreateAssessmentResponse = try await supabase.functions.invoke(
            "create-assessment",
            options: FunctionInvokeOptions(body: request)
        )

        return response
    }

    /// Get a specific assessment by ID
    func getAssessment(id: UUID) async throws -> NeedsAssessment {
        struct Response: Codable {
            let success: Bool
            let assessment: NeedsAssessment
        }

        let result: Response = try await supabase.functions.invoke(
            "get-assessment/\(id.uuidString)",
            options: FunctionInvokeOptions(method: .get)
        )

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
        let request = GenerateBoundaryRequest(
            boundaryType: boundaryType.rawValue,
            statement: statement,
            whyMatters: whyMatters,
            assessmentId: assessmentId?.uuidString,
            stakeholder: stakeholder
        )

        let response: GenerateBoundaryResponse = try await supabase.functions.invoke(
            "generate-boundary",
            options: FunctionInvokeOptions(body: request)
        )

        return response
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

        let response: ListBoundariesResponse = try await supabase.functions.invoke(
            path,
            options: FunctionInvokeOptions(method: .get)
        )

        return response
    }

    /// Save/update boundary status
    func saveBoundary(
        boundaryId: UUID,
        status: BoundaryStatus
    ) async throws -> SaveBoundaryResponse {
        let request = SaveBoundaryRequest(
            boundaryId: boundaryId.uuidString,
            status: status.rawValue
        )
        
        let response: SaveBoundaryResponse = try await supabase.functions.invoke(
            "save-boundary",
            options: FunctionInvokeOptions(body: request)
        )

        return response
    }

    // MARK: - Scripts

    /// Generate scripts for a boundary
    func generateScripts(
        boundaryId: UUID,
        relationshipType: String,
        variations: [ScriptVariation]
    ) async throws -> GenerateScriptsResponse {
        let request = GenerateScriptsRequest(
            boundaryId: boundaryId.uuidString,
            relationshipType: relationshipType,
            variations: variations.map { $0.rawValue }
        )
        
        let response: GenerateScriptsResponse = try await supabase.functions.invoke(
            "generate-scripts",
            options: FunctionInvokeOptions(body: request)
        )

        return response
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

        struct Response: Codable {
            let success: Bool
            let templates: [BoundaryScriptTemplate]
        }

        let result: Response = try await supabase.functions.invoke(
            "get-templates",
            options: FunctionInvokeOptions(
                method: .get,
                body: queryParams
            )
        )

        return result.templates
    }

    // MARK: - Follow-Ups

    /// Schedule a follow-up check-in
    func scheduleFollowUp(
        boundaryId: UUID,
        checkInAt: Date? = nil
    ) async throws -> ScheduleFollowUpResponse {
        let checkInAtString = checkInAt.map { ISO8601DateFormatter().string(from: $0) }
        let request = ScheduleFollowUpRequest(
            boundaryId: boundaryId.uuidString,
            checkInAt: checkInAtString
        )

        let response: ScheduleFollowUpResponse = try await supabase.functions.invoke(
            "schedule-followup",
            options: FunctionInvokeOptions(body: request)
        )

        return response
    }

    /// Record the outcome of a follow-up check-in
    func recordOutcome(
        followUpId: UUID,
        outcome: FollowUpOutcome,
        notes: String? = nil,
        reflection: String? = nil,
        nextAction: String? = nil
    ) async throws -> RecordOutcomeResponse {
        let request = RecordOutcomeRequest(
            followUpId: followUpId.uuidString,
            outcome: outcome.rawValue,
            notes: notes,
            reflection: reflection,
            nextAction: nextAction
        )

        let response: RecordOutcomeResponse = try await supabase.functions.invoke(
            "record-outcome",
            options: FunctionInvokeOptions(body: request)
        )

        return response
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
