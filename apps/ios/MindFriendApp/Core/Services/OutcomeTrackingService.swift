import Foundation
import Combine
import Supabase
import OSLog

/// Service for outcome tracking and clinical assessments
/// Manages PHQ-9, GAD-7, and other standardized assessment instruments
@MainActor
final class OutcomeTrackingService: ObservableObject {

    private let supabase: SupabaseClient
    private let currentUserID: @MainActor () -> UUID?
    private let logger = Logger(subsystem: "com.mindfriend", category: "OutcomeTrackingService")

    // MARK: - Published State

    @Published private(set) var assessmentTemplates: [AssessmentTemplate] = []
    @Published private(set) var assessmentSchedules: [AssessmentSchedule] = []
    @Published private(set) var recentResponses: [AssessmentResponse] = []
    @Published private(set) var outcomeGoals: [OutcomeGoal] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?

    // MARK: - Initialization

    convenience init(supabase: SupabaseClient, authService: SupabaseAuthService) {
        self.init(supabase: supabase, currentUserID: { authService.userId })
    }

    init(supabase: SupabaseClient, currentUserID: @escaping @MainActor () -> UUID?) {
        self.supabase = supabase
        self.currentUserID = currentUserID
    }

    private var userId: UUID {
        get throws {
            guard let id = currentUserID() else {
                throw OutcomeTrackingError.notAuthenticated
            }
            return id
        }
    }

    // MARK: - Assessment Templates

    /// Load standardized assessment templates
    func loadAssessmentTemplates() async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            let templates: [AssessmentTemplate] = try await supabase
                .from("assessment_templates")
                .select()
                .eq("is_active", value: true)
                .execute()
                .value

            self.assessmentTemplates = templates
            logger.info("Loaded \(templates.count) assessment templates")
        } catch {
            self.error = error
            logger.error("Failed to load assessment templates: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Assessment Scheduling

    /// Fetch user's assessment schedules
    func loadAssessmentSchedules() async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            let uid = try userId
            let schedules: [AssessmentSchedule] = try await supabase
                .from("assessment_schedule")
                .select()
                .eq("user_id", value: uid)
                .eq("enabled", value: true)
                .execute()
                .value

            self.assessmentSchedules = schedules
            logger.info("Loaded \(schedules.count) assessment schedules")
        } catch {
            self.error = error
            logger.error("Failed to load assessment schedules: \(error.localizedDescription)")
            throw error
        }
    }

    /// Initialize assessment schedules for new user (create default schedules)
    func initializeSchedules(for assessmentTypes: [AssessmentType]) async throws {
        let uid = try userId
        let templates = try await getAssessmentTemplates()

        for type in assessmentTypes {
            guard let template = templates.first(where: { $0.code == type.rawValue }) else {
                logger.warning("Template not found for assessment type: \(type.rawValue)")
                continue
            }

            let schedule = AssessmentSchedule(
                id: UUID(),
                userId: uid,
                assessmentTemplateId: template.id,
                nextDueAt: Date(),  // Due immediately for first assessment
                lastCompletedAt: nil,
                reminderSent: false,
                enabled: true,
                customFrequencyDays: nil,
                createdAt: Date(),
                updatedAt: Date()
            )

            try await createAssessmentSchedule(schedule)
        }

        try await loadAssessmentSchedules()
        logger.info("Initialized assessment schedules for \(assessmentTypes.count) assessment types")
    }

    private func createAssessmentSchedule(_ schedule: AssessmentSchedule) async throws {
        struct ScheduleInsert: Encodable {
            let user_id: UUID
            let assessment_template_id: UUID
            let next_due_at: Date
            let enabled: Bool
            let custom_frequency_days: Int?
        }

        let insert = ScheduleInsert(
            user_id: schedule.userId,
            assessment_template_id: schedule.assessmentTemplateId,
            next_due_at: schedule.nextDueAt,
            enabled: schedule.enabled,
            custom_frequency_days: schedule.customFrequencyDays
        )

        try await supabase
            .from("assessment_schedule")
            .insert(insert)
            .execute()
    }

    // MARK: - Assessment Completion

    /// Capture the initiating owner once; retain this entire value for every retry.
    func makeAssessmentSubmission(
        type: AssessmentType,
        answers: [String: Int],
        notes: String? = nil,
        timeZone: String = TimeZone.autoupdatingCurrent.identifier
    ) throws -> OutcomeAssessmentSubmission {
        let uid = try userId
        guard let template = assessmentTemplates.first(where: { $0.code == type.rawValue }) else {
            throw OutcomeTrackingError.templateNotFound
        }
        _ = try type.score(answers: answers, questions: template.questions)
        return OutcomeAssessmentSubmission(expectedUserID: uid, responseID: UUID(), templateID: template.id,
            answers: answers, notes: notes, timeZone: timeZone)
    }

    /// The server repeats the owner check after the SDK obtains the request's access token.
    func submitAssessment(_ request: OutcomeAssessmentSubmission) async throws -> AssessmentResponse {
        let uid = try userId
        guard request.expectedUserID == uid else { throw OutcomeTrackingError.notAuthenticated }
        guard let template = assessmentTemplates.first(where: { $0.id == request.templateID }),
              let type = AssessmentType(rawValue: template.code) else {
            throw OutcomeTrackingError.templateNotFound
        }
        _ = try type.score(answers: request.answers, questions: template.questions)
        let result: OutcomeAssessmentSubmissionResult = try await supabase
            .rpc("submit_outcome_assessment", params: request)
            .execute().value
        guard result.response.userId == request.expectedUserID, result.response.id == request.responseID,
              result.response.assessmentTemplateId == request.templateID, try userId == uid else {
            throw OutcomeTrackingError.notAuthenticated
        }

        let response = result.response.recalculatedIfNeeded(using: template)
        recentResponses.removeAll { $0.id == response.id }
        recentResponses.append(response)
        recentResponses.sort { $0.completedAt > $1.completedAt }
        if let schedule = result.schedule, schedule.userId == uid {
            assessmentSchedules.removeAll { $0.id == schedule.id }
            if schedule.enabled { assessmentSchedules.append(schedule) }
        }
        if let goal = result.goal, goal.userId == uid {
            outcomeGoals.removeAll { $0.id == goal.id }
            if !goal.achieved { outcomeGoals.append(goal) }
        }
        return response
    }

    // MARK: - Score Calculation & Severity

    /// Get PHQ-9 specific severity level
    func getPHQ9SeverityLevel(score: Int) -> PHQ9SeverityLevel {
        switch score {
        case 0...4: return .minimal
        case 5...9: return .mild
        case 10...14: return .moderate
        case 15...19: return .moderatelySevere
        case 20...: return .severe
        default: return .minimal
        }
    }

    /// Get GAD-7 specific severity level
    func getGAD7SeverityLevel(score: Int) -> GAD7SeverityLevel {
        switch score {
        case 0...4: return .minimal
        case 5...9: return .mild
        case 10...14: return .moderate
        case 15...: return .severe
        default: return .minimal
        }
    }

    // MARK: - Outcome Goals

    /// Public method for creating custom outcome goals (called from GoalSettingView)
    func createCustomOutcomeGoal(
        assessmentTemplateId: UUID,
        baselineScore: Int,
        targetScore: Int,
        targetDate: Date,
        notes: String? = nil,
        baselineResponseId: UUID? = nil
    ) async throws -> OutcomeGoal {
        let uid = try userId
        let goalId = UUID()
        let baselineDate = Date()

        struct GoalInsert: Encodable {
            let id: UUID
            let user_id: UUID
            let assessment_template_id: UUID
            let target_score: Int
            let target_date: Date
            let baseline_score: Int
            let baseline_date: Date
            let notes: String?
            let baseline_response_id: UUID?
        }

        let insert = GoalInsert(
            id: goalId,
            user_id: uid,
            assessment_template_id: assessmentTemplateId,
            target_score: targetScore,
            target_date: targetDate,
            baseline_score: baselineScore,
            baseline_date: baselineDate,
            notes: notes,
            baseline_response_id: baselineResponseId
        )

        try await supabase
            .from("outcome_goals")
            .insert(insert)
            .execute()

        let goal = OutcomeGoal(
            id: goalId,
            userId: uid,
            assessmentTemplateId: assessmentTemplateId,
            targetScore: targetScore,
            targetDate: targetDate,
            baselineScore: baselineScore,
            baselineDate: baselineDate,
            achieved: false,
            achievedAt: nil,
            createdAt: Date(),
            updatedAt: nil,
            baselineResponseId: baselineResponseId
        )

        // Reload goals to update published property
        try await loadOutcomeGoals()

        logger.info("Created custom outcome goal: target \(targetScore), deadline \(targetDate.formatted(date: .abbreviated, time: .omitted))")

        return goal
    }

    /// Load user's outcome goals
    func loadOutcomeGoals() async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            let uid = try userId
            let goals: [OutcomeGoal] = try await supabase
                .from("outcome_goals")
                .select()
                .eq("user_id", value: uid)
                .eq("achieved", value: false)
                .execute()
                .value

            self.outcomeGoals = goals
            logger.info("Loaded \(goals.count) active outcome goals")
        } catch {
            self.error = error
            logger.error("Failed to load outcome goals: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Progress Tracking

    /// Load recent assessment responses for the current user
    /// Used by the Progress tab to show recent results.
    func loadRecentResponses(limit: Int = 10) async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            let uid = try userId
            logger.info("Loading assessment responses")

            let responses: [AssessmentResponse] = try await supabase
                .from("assessment_responses")
                .select()
                .eq("user_id", value: uid)
                .order("completed_at", ascending: false)
                .limit(limit)
                .execute()
                .value

            _ = try await getAssessmentTemplates()
            self.recentResponses = reconciledResponses(responses)
            logger.info("Loaded \(responses.count) recent assessment responses")
        } catch {
            self.error = error
            logger.error("Failed to load recent assessment responses: \(error.localizedDescription)")
            throw error
        }
    }

    /// Get assessment history for trend analysis
    func getAssessmentHistory(
        for type: AssessmentType,
        limit: Int = 10
    ) async throws -> [AssessmentResponse] {
        guard let template = assessmentTemplates.first(where: { $0.code == type.rawValue }) else {
            throw OutcomeTrackingError.templateNotFound
        }

        let uid = try userId
        let responses: [AssessmentResponse] = try await supabase
            .from("assessment_responses")
            .select()
            .eq("user_id", value: uid)
            .eq("assessment_template_id", value: template.id)
            .order("completed_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        _ = try await getAssessmentTemplates()
        return reconciledResponses(responses)
    }

    /// Get assessment responses directly by template ID
    func getAssessmentResponses(
        assessmentTemplateId: UUID,
        limit: Int = 10
    ) async throws -> [AssessmentResponse] {
        let uid = try userId
        let responses: [AssessmentResponse] = try await supabase
            .from("assessment_responses")
            .select()
            .eq("user_id", value: uid)
            .eq("assessment_template_id", value: assessmentTemplateId)
            .order("completed_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        _ = try await getAssessmentTemplates()
        return reconciledResponses(responses)
    }

    /// Query relative to the displayed result, independent of the dashboard's recent-response cache.
    func getPreviousAssessmentResponse(to response: AssessmentResponse) async throws -> AssessmentResponse? {
        let uid = try userId
        guard response.userId == uid else { throw OutcomeTrackingError.notAuthenticated }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let history: [AssessmentResponse] = try await supabase
            .from("assessment_responses")
            .select()
            .eq("user_id", value: uid)
            .eq("assessment_template_id", value: response.assessmentTemplateId)
            .lt("completed_at", value: formatter.string(from: response.completedAt))
            .order("completed_at", ascending: false)
            .order("id", ascending: false)
            .limit(1)
            .execute().value
        _ = try await getAssessmentTemplates()
        guard try userId == uid else { throw OutcomeTrackingError.notAuthenticated }
        return response.previousResponse(in: reconciledResponses(history))
    }

    /// Calculate trend using the instrument's score direction and chronological observations.
    func calculateTrend(responses: [AssessmentResponse]) -> TrendDirection {
        guard let templateID = responses.first?.assessmentTemplateId,
              let template = assessmentTemplates.first(where: { $0.id == templateID }),
              let type = AssessmentType(rawValue: template.code) else { return .stable }
        let scores = responses.filter { $0.assessmentTemplateId == templateID }
            .sorted { $0.completedAt < $1.completedAt }.compactMap(\.availableScore)
        guard scores.count >= 2 else { return .stable }
        let split = scores.count / 2
        let previous = Double(scores.prefix(split).reduce(0, +)) / Double(split)
        let current = Double(scores.suffix(scores.count - split).reduce(0, +)) / Double(scores.count - split)
        let improvement = type.higherScoresAreBetter ? current - previous : previous - current
        return improvement > 0 ? .improving : improvement < 0 ? .declining : .stable
    }

    // MARK: - Helpers

    private func reconciledResponses(_ responses: [AssessmentResponse]) -> [AssessmentResponse] {
        responses.map { response in
            response.recalculatedIfNeeded(using: assessmentTemplates.first { $0.id == response.assessmentTemplateId })
        }
    }

    private func getAssessmentTemplates() async throws -> [AssessmentTemplate] {
        if assessmentTemplates.isEmpty {
            try await loadAssessmentTemplates()
        }
        return assessmentTemplates
    }
}

// MARK: - Error Types

enum OutcomeTrackingError: LocalizedError {
    case notAuthenticated
    case templateNotFound
    case invalidScore
    case databaseError(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User not authenticated"
        case .templateNotFound:
            return "Assessment template not found"
        case .invalidScore:
            return "Invalid assessment score"
        case .databaseError(let message):
            return "Database error: \(message)"
        }
    }
}

// MARK: - Trend Direction Helper
// NOTE: Uses TrendDirection from PredictiveModels.swift
// Mapping for local use: .improving -> .up, .stable -> .stable, .declining -> .down
typealias OutcomeTrendDirection = TrendDirection
