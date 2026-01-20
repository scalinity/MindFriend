import Foundation
import Supabase

// MARK: - Coping Kit Service

@MainActor
final class CopingKitService: ObservableObject {
    private let supabase: SupabaseClient

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    // MARK: - Fetch Kits

    func fetchKits(contextTag: CopingKitContextTag? = nil) async throws -> [CopingKit] {
        var params: [String: String] = [:]
        if let context = contextTag {
            params["context_tag"] = context.rawValue
        }

        let apiResponse: GetCopingKitsResponse = try await supabase.functions.invoke(
            "get-coping-kits",
            options: FunctionInvokeOptions(body: params)
        )
        return apiResponse.kits
    }

    // MARK: - Fetch Active Progress

    func fetchActiveProgress() async throws -> [KitProgress] {
        let emptyParams: [String: String] = [:]
        let apiResponse: GetCopingKitsResponse = try await supabase.functions.invoke(
            "get-coping-kits",
            options: FunctionInvokeOptions(body: emptyParams)
        )
        return apiResponse.activeProgressKits
    }

    // MARK: - Start Kit

    func startKit(kitId: String) async throws -> String {
        let requestBody = TrackCopingKitRequest(
            kitId: kitId,
            action: .start,
            stepIndex: nil,
            stepResult: nil,
            feedback: nil
        )

        return try await sendTrackRequest(requestBody)
    }

    // MARK: - Complete Step

    func completeStep(
        progressId: String,
        stepIndex: Int,
        result: [String: String]? = nil
    ) async throws -> StepCompleteResult {
        let requestBody = TrackCopingKitRequest(
            kitId: progressId,
            action: .stepComplete,
            stepIndex: stepIndex,
            stepResult: result,
            feedback: nil
        )

        return try await sendStepCompleteRequest(requestBody)
    }

    // MARK: - Complete Kit

    func completeKit(progressId: String, feedback: KitFeedbackRequest? = nil) async throws -> KitCompletionResult {
        let requestBody = TrackCopingKitRequest(
            kitId: progressId,
            action: .complete,
            stepIndex: nil,
            stepResult: nil,
            feedback: feedback
        )

        return try await sendCompleteRequest(requestBody)
    }

    // MARK: - Cancel Kit

    func cancelKit(progressId: String) async throws {
        let requestBody = TrackCopingKitRequest(
            kitId: progressId,
            action: .cancel,
            stepIndex: nil,
            stepResult: nil,
            feedback: nil
        )

        _ = try await sendTrackRequest(requestBody)
    }

    // MARK: - Toggle Pin

    func togglePin(kitId: String, pinned: Bool) async throws {
        // This would typically be a separate API call, but for now
        // we just track it locally. In production, add a dedicated endpoint.
        // For now, we can use a mock or skip this implementation.
        // TODO: Implement dedicated toggle-pin endpoint
    }

    // MARK: - Submit Feedback

    func submitFeedback(kitId: String, helpful: Bool, comment: String?) async throws {
        let feedback = KitFeedbackRequest(helpful: helpful, comment: comment)
        let requestBody = TrackCopingKitRequest(
            kitId: kitId,
            action: .complete,
            stepIndex: nil,
            stepResult: nil,
            feedback: feedback
        )

        _ = try await sendCompleteRequest(requestBody)
    }

    // MARK: - Private Helpers

    private func sendTrackRequest(_ request: TrackCopingKitRequest) async throws -> String {
        let successResponse: TrackSuccessResponse = try await supabase.functions.invoke(
            "track-coping-kit",
            options: FunctionInvokeOptions(body: request)
        )
        return successResponse.progressId ?? ""
    }

    private func sendStepCompleteRequest(_ request: TrackCopingKitRequest) async throws -> StepCompleteResult {
        let stepResponse: StepCompleteSuccessResponse = try await supabase.functions.invoke(
            "track-coping-kit",
            options: FunctionInvokeOptions(body: request)
        )
        return stepResponse.step
    }

    private func sendCompleteRequest(_ request: TrackCopingKitRequest) async throws -> KitCompletionResult {
        let completeResponse: CompleteSuccessResponse = try await supabase.functions.invoke(
            "track-coping-kit",
            options: FunctionInvokeOptions(body: request)
        )
        return completeResponse.complete
    }
}

// MARK: - Error Types

enum CopingKitError: LocalizedError {
    case invalidResponse
    case serverError(statusCode: Int)
    case apiError(message: String, code: String?)
    case notFound
    case unauthorized
    case premiumRequired

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response"
        case .serverError(let statusCode):
            return "Server error: \(statusCode)"
        case .apiError(let message, _):
            return message
        case .notFound:
            return "Kit not found"
        case .unauthorized:
            return "Unauthorized"
        case .premiumRequired:
            return "Premium subscription required"
        }
    }
}

// MARK: - Response Types

struct CopingKitErrorResponse: Codable {
    let error: String
    let code: String?
}

struct TrackSuccessResponse: Codable {
    let success: Bool
    let progressId: String?
    let activeProgress: ActiveProgressInfo?

    enum CodingKeys: String, CodingKey {
        case success
        case progressId = "progress_id"
        case activeProgress = "active_progress"
    }
}

struct ActiveProgressInfo: Codable {
    let currentStepIndex: Int
    let totalSteps: Int
    let expiresAt: String

    enum CodingKeys: String, CodingKey {
        case currentStepIndex = "current_step_index"
        case totalSteps = "total_steps"
        case expiresAt = "expires_at"
    }
}

struct StepCompleteSuccessResponse: Codable {
    let success: Bool
    let step: StepCompleteResult
}

struct CompleteSuccessResponse: Codable {
    let success: Bool
    let complete: KitCompletionResult
}
