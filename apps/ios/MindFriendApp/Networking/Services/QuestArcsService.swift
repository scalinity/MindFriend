//
//  QuestArcsService.swift
//  MindFriendApp
//
//  Quest Arc API service for multi-day quest programs
//  See: docs/specs/quest-arcs-formal-spec.md
//

import Foundation
import Supabase

/// Service for managing quest arc operations
@MainActor
final class QuestArcsService {
    private let supabase: SupabaseClient
    private let authService: SupabaseAuthService
    private weak var difficultyService: DifficultyService?

    init(supabase: SupabaseClient, authService: SupabaseAuthService, difficultyService: DifficultyService? = nil) {
        self.supabase = supabase
        self.authService = authService
        self.difficultyService = difficultyService
    }

    // MARK: - Difficulty Adjustment

    /// Get current difficulty multiplier for quest adjustments
    /// - Returns: Multiplier (0.5 for easy, 1.0 for normal, 1.25 for hard)
    func getDifficultyMultiplier() -> Double {
        return difficultyService?.getDifficultyMultiplier() ?? 1.0
    }

    // MARK: - Fetch Arcs

    /// Fetches all available quest arcs with user progress
    /// - Parameters:
    ///   - category: Optional category filter (stress, sleep, confidence, focus, resilience)
    ///   - includeCompleted: Whether to include arcs the user has already completed
    /// - Returns: Array of quest arcs enriched with user enrollment status
    /// - Throws: QuestArcError with specific error context
    func getQuestArcs(category: String? = nil, includeCompleted: Bool = false) async throws -> [QuestArc] {
        var body: [String: String] = [:]
        if let category = category {
            body["category"] = category
        }
        if includeCompleted {
            body["includeCompleted"] = "true"
        }

        do {
            let response: GetQuestArcsResponse = try await supabase.functions.invoke(
                "get-quest-arcs",
                options: FunctionInvokeOptions(
                    headers: authService.authHeaders,
                    body: body.isEmpty ? nil : body
                )
            )
            return response.arcs
        } catch {
            throw QuestArcError.networkError("Failed to fetch quest arcs: \(error.localizedDescription)")
        }
    }

    // MARK: - Start Arc

    /// Starts a quest arc for the current user
    /// - Parameter arcId: The ID of the arc to start
    /// - Returns: Response containing enrollment details and first quest template
    /// - Throws: QuestArcError if user already has an active arc, arc requires premium, or arc not found
    func startQuestArc(arcId: UUID) async throws -> StartQuestArcResponse {
        do {
            let response: StartQuestArcResponse = try await supabase.functions.invoke(
                "start-quest-arc",
                options: FunctionInvokeOptions(
                    headers: authService.authHeaders,
                    body: ["arcId": arcId.uuidString]
                )
            )

            // Check for error responses
            if let error = response.error, !error.isEmpty {
                throw QuestArcError.from(response: response) ?? QuestArcError.apiError(code: response.code ?? "UNKNOWN", message: error)
            }

            return response
        } catch let error as QuestArcError {
            throw error
        } catch {
            throw QuestArcError.networkError("Failed to start quest arc: \(error.localizedDescription)")
        }
    }

    // MARK: - Pause Arc

    /// Pauses the user's active quest arc
    /// - Parameter userArcId: Optional ID of specific enrollment to pause (pauses active arc if nil)
    /// - Returns: Response with pause timestamp and expiration date
    /// - Throws: QuestArcError if no active arc found or operation fails
    func pauseQuestArc(userArcId: UUID? = nil) async throws -> PauseQuestArcResponse {
        var body: [String: String] = [:]
        if let userArcId = userArcId {
            body["userArcId"] = userArcId.uuidString
        }

        do {
            let response: PauseQuestArcResponse = try await supabase.functions.invoke(
                "pause-quest-arc",
                options: FunctionInvokeOptions(
                    headers: authService.authHeaders,
                    body: body.isEmpty ? nil : body
                )
            )
            return response
        } catch {
            throw QuestArcError.networkError("Failed to pause quest arc: \(error.localizedDescription)")
        }
    }

    // MARK: - Resume Arc

    /// Resumes a paused quest arc
    /// - Parameter userArcId: ID of the enrollment to resume
    /// - Returns: Response with current progress and next quest template
    /// - Throws: QuestArcError if arc is expired (paused > 30 days) or operation fails
    func resumeQuestArc(userArcId: UUID) async throws -> ResumeQuestArcResponse {
        do {
            let response: ResumeQuestArcResponse = try await supabase.functions.invoke(
                "resume-quest-arc",
                options: FunctionInvokeOptions(
                    headers: authService.authHeaders,
                    body: ["userArcId": userArcId.uuidString]
                )
            )
            return response
        } catch {
            throw QuestArcError.networkError("Failed to resume quest arc: \(error.localizedDescription)")
        }
    }

    // MARK: - Exit Arc

    /// Exits (abandons) the user's active or paused quest arc
    /// - Parameter userArcId: Optional ID of specific enrollment to exit (exits active/paused arc if nil)
    /// - Returns: Response with abandonment timestamp
    /// - Throws: QuestArcError if no active/paused arc found or operation fails
    func exitQuestArc(userArcId: UUID? = nil) async throws -> ExitQuestArcResponse {
        var body: [String: String] = [:]
        if let userArcId = userArcId {
            body["userArcId"] = userArcId.uuidString
        }

        do {
            let response: ExitQuestArcResponse = try await supabase.functions.invoke(
                "exit-quest-arc",
                options: FunctionInvokeOptions(
                    headers: authService.authHeaders,
                    body: body.isEmpty ? nil : body
                )
            )
            return response
        } catch {
            throw QuestArcError.networkError("Failed to exit quest arc: \(error.localizedDescription)")
        }
    }

    // MARK: - Get Active Arc

    /// Fetches the user's currently active or paused arc enrollment, if any
    /// - Returns: The active/paused UserQuestArc or nil if no current arc
    /// - Throws: QuestArcError if database query fails
    func getActiveArc() async throws -> UserQuestArc? {
        do {
            let userId = try await supabase.auth.session.user.id

            // Include both active and paused arcs so UI can show paused state
            let response: [UserQuestArc] = try await supabase
                .from("user_quest_arcs")
                .select("*, quest_arcs(*)")
                .eq("user_id", value: userId)
                .in("status", values: ["active", "paused"])
                .execute()
                .value

            return response.first
        } catch {
            throw QuestArcError.networkError("Failed to fetch active arc: \(error.localizedDescription)")
        }
    }

    // MARK: - Get Arc History

    /// Fetches all of the user's arc enrollments (active, paused, completed, abandoned)
    /// - Returns: Array of UserQuestArc enrollments
    /// - Throws: QuestArcError if database query fails
    func getArcHistory() async throws -> [UserQuestArc] {
        do {
            let userId = try await supabase.auth.session.user.id

            let response: [UserQuestArc] = try await supabase
                .from("user_quest_arcs")
                .select("*, quest_arcs(*)")
                .eq("user_id", value: userId)
                .order("started_at", ascending: false)
                .execute()
                .value

            return response
        } catch {
            throw QuestArcError.networkError("Failed to fetch arc history: \(error.localizedDescription)")
        }
    }
}

// MARK: - Quest Arc Errors

enum QuestArcError: LocalizedError {
    case apiError(code: String, message: String)
    case alreadyEnrolled(currentArcTitle: String?)
    case premiumRequired
    case arcExpired
    case arcNotFound
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .apiError(_, let message):
            return message
        case .alreadyEnrolled(let title):
            if let title = title {
                return "You're already enrolled in \"\(title)\". Complete or exit it first."
            }
            return "You already have an active arc. Complete or exit it first."
        case .premiumRequired:
            return "This arc requires a premium subscription."
        case .arcExpired:
            return "This arc has expired (paused for more than \(QuestArcConstants.pauseExpirationDays) days)."
        case .arcNotFound:
            return "Arc not found."
        case .networkError(let message):
            return message
        }
    }

    static func from(response: StartQuestArcResponse) -> QuestArcError? {
        guard let code = response.code else { return nil }

        switch code {
        case "ALREADY_ENROLLED":
            return .alreadyEnrolled(currentArcTitle: response.currentArc?.title)
        case "PREMIUM_REQUIRED":
            return .premiumRequired
        case "ARC_NOT_FOUND":
            return .arcNotFound
        case "NO_STEPS":
            return .apiError(code: code, message: "This arc is not available yet.")
        default:
            return .apiError(code: code, message: response.error ?? "Unknown error")
        }
    }
}
