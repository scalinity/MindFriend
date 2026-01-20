import Foundation
import Supabase
import OSLog

// MARK: - Supabase Client Protocol (for dependency injection)
protocol SupabaseClientProtocol {
    func from(_ table: String) -> PostgrestQueryBuilder
    var auth: Auth { get }
}

extension SupabaseClient: SupabaseClientProtocol {}

/// Service for outcome tracking and clinical assessments
/// Manages PHQ-9, GAD-7, and other standardized assessment instruments
@MainActor
final class OutcomeTrackingService: ObservableObject {

    private let supabase: SupabaseClientProtocol
    private let authService: SupabaseAuthService
    private let logger = Logger(subsystem: "com.mindfriend", category: "OutcomeTrackingService")

    // MARK: - Published State

    @Published private(set) var assessmentTemplates: [AssessmentTemplate] = []
    @Published private(set) var assessmentSchedules: [AssessmentSchedule] = []
    @Published private(set) var recentResponses: [AssessmentResponse] = []
    @Published private(set) var outcomeGoals: [OutcomeGoal] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?

    // MARK: - Initialization

    init(supabase: SupabaseClientProtocol, authService: SupabaseAuthService) {
        self.supabase = supabase
        self.authService = authService
    }

    private var userId: UUID {
        get throws {
            guard let id = authService.userId else {
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

    /// Submit completed assessment
    func submitAssessment(
        type: AssessmentType,
        answers: [String: Int],
        notes: String? = nil
    ) async throws -> AssessmentResponse {
        let uid = try userId

        guard let template = assessmentTemplates.first(where: { $0.code == type.rawValue }) else {
            throw OutcomeTrackingError.templateNotFound
        }

        // Calculate score
        let totalScore = answers.values.reduce(0, +)

        // Determine severity level
        let severityLevel = determineSeverityLevel(
            for: type,
            score: totalScore,
            template: template
        )

        // Check for crisis indicators
        if shouldLogCrisisEvent(for: type, answers: answers, score: totalScore) {
            try await logCrisisEvent(
                type: type,
                responseId: UUID(),  // Will be created server-side
                severity: .critical,
                context: ["score": totalScore, "severity": severityLevel]
            )
        }

        // Check if this is baseline assessment
        let isBaseline = recentResponses
            .filter { $0.assessmentTemplateId == template.id }
            .isEmpty

        // Create response record
        let response = AssessmentResponse(
            id: UUID(),
            userId: uid,
            assessmentTemplateId: template.id,
            answers: answers,
            totalScore: totalScore,
            severityLevel: severityLevel,
            isBaseline: isBaseline,
            notes: notes,
            completedAt: Date(),
            createdAt: Date()
        )

        // Save to database
        struct ResponseInsert: Encodable {
            let id: UUID
            let user_id: UUID
            let assessment_template_id: UUID
            let answers: [String: Int]
            let total_score: Int
            let severity_level: String
            let is_baseline: Bool
            let notes: String?
            let completed_at: Date
        }

        let insert = ResponseInsert(
            id: response.id,
            user_id: uid,
            assessment_template_id: template.id,
            answers: answers,
            total_score: totalScore,
            severity_level: severityLevel,
            is_baseline: isBaseline,
            notes: notes,
            completed_at: response.completedAt
        )

        try await supabase
            .from("assessment_responses")
            .insert(insert)
            .execute()

        // Update schedule
        try await updateScheduleAfterCompletion(for: template.id)

        // Create outcome goal if this is baseline
        if isBaseline {
            try await createOutcomeGoal(
                assessmentTemplateId: template.id,
                baselineScore: totalScore
            )
        }

        recentResponses.append(response)
        logger.info("Submitted \(type.shortName) assessment with score: \(totalScore)")

        return response
    }

    // MARK: - Score Calculation & Severity

    private func determineSeverityLevel(
        for type: AssessmentType,
        score: Int,
        template: AssessmentTemplate
    ) -> String {
        for range in template.scoringRanges {
            if score >= range.minScore && score <= range.maxScore {
                return range.severityLevel
            }
        }
        return "unknown"
    }

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

    // MARK: - Crisis Detection

    private func shouldLogCrisisEvent(
        for type: AssessmentType,
        answers: [String: Int],
        score: Int
    ) -> Bool {
        switch type {
        case .phq9:
            // PHQ-9 Question 9 (suicide/self-harm) - any non-zero answer is a crisis indicator
            if let q9Answer = answers["phq9_q9"], q9Answer > 0 {
                return true
            }
            // Also flag for severe depression scores
            if score >= 20 {
                return true
            }
            return false

        case .gad7:
            // GAD-7 severe anxiety
            return score >= 15

        case .pss10:
            // PSS-10 high stress
            return score >= 27

        default:
            return false
        }
    }

    /// Log crisis event to audit trail
    private func logCrisisEvent(
        type: AssessmentType,
        responseId: UUID,
        severity: CrisisEventSeverity,
        context: [String: Int]?
    ) async throws {
        let uid = try userId
        let templateId = assessmentTemplates
            .first(where: { $0.code == type.rawValue })?
            .id ?? UUID()

        struct CrisisInsert: Encodable {
            let user_id: UUID
            let assessment_template_id: UUID
            let assessment_response_id: UUID
            let event_type: String
            let severity: String
            let context: [String: Int]?
        }

        let insert = CrisisInsert(
            user_id: uid,
            assessment_template_id: templateId,
            assessment_response_id: responseId,
            event_type: CrisisEventType.phq9Q9Scored.rawValue,
            severity: severity.rawValue,
            context: context
        )

        try await supabase
            .from("assessment_crisis_events")
            .insert(insert)
            .execute()

        logger.warning("Crisis event logged for user \(uid.uuidString)")
    }

    // MARK: - Schedule Management

    private func updateScheduleAfterCompletion(for templateId: UUID) async throws {
        guard let schedule = assessmentSchedules.first(where: { $0.assessmentTemplateId == templateId }) else {
            logger.warning("Schedule not found for template: \(templateId.uuidString)")
            return
        }

        let frequency = schedule.customFrequencyDays ?? 14  // Default to bi-weekly
        let nextDue = Calendar.current.date(byAdding: .day, value: frequency, to: Date()) ?? Date()

        struct ScheduleUpdate: Encodable {
            let last_completed_at: Date
            let next_due_at: Date
            let reminder_sent: Bool
        }

        let update = ScheduleUpdate(
            last_completed_at: Date(),
            next_due_at: nextDue,
            reminder_sent: false
        )

        try await supabase
            .from("assessment_schedule")
            .update(update)
            .eq("id", value: schedule.id)
            .execute()

        logger.info("Updated assessment schedule for template: \(templateId.uuidString)")
    }

    // MARK: - Outcome Goals

    /// Create initial outcome goal based on baseline assessment
    private func createOutcomeGoal(
        assessmentTemplateId: UUID,
        baselineScore: Int
    ) async throws {
        let uid = try userId

        // Calculate target score (reduce by 25% or minimum 5 points)
        let reduction = max(5, baselineScore / 4)
        let targetScore = max(0, baselineScore - reduction)

        // Target 12 weeks out
        let targetDate = Calendar.current.date(byAdding: .weekOfYear, value: 12, to: Date())

        struct GoalInsert: Encodable {
            let id: UUID
            let user_id: UUID
            let assessment_template_id: UUID
            let target_score: Int
            let target_date: Date?
            let baseline_score: Int
            let baseline_date: Date
        }

        let insert = GoalInsert(
            id: UUID(),
            user_id: uid,
            assessment_template_id: assessmentTemplateId,
            target_score: targetScore,
            target_date: targetDate,
            baseline_score: baselineScore,
            baseline_date: Date()
        )

        try await supabase
            .from("outcome_goals")
            .insert(insert)
            .execute()

        logger.info("Created outcome goal with target score: \(targetScore)")
    }

    /// Public method for creating custom outcome goals (called from GoalSettingView)
    func createCustomOutcomeGoal(
        assessmentTemplateId: UUID,
        baselineScore: Int,
        targetScore: Int,
        targetDate: Date,
        notes: String? = nil
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
        }

        let insert = GoalInsert(
            id: goalId,
            user_id: uid,
            assessment_template_id: assessmentTemplateId,
            target_score: targetScore,
            target_date: targetDate,
            baseline_score: baselineScore,
            baseline_date: baselineDate,
            notes: notes
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
            updatedAt: nil
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

        return responses
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

        return responses
    }

    /// Calculate trend direction
    func calculateTrend(responses: [AssessmentResponse]) -> TrendDirection {
        guard responses.count >= 2 else { return .noData }

        let scores = responses.reversed().map { $0.totalScore }
        let firstHalf = scores.prefix(scores.count / 2).reduce(0, +) / max(1, scores.count / 2)
        let secondHalf = scores.suffix(scores.count - scores.count / 2).reduce(0, +) / max(1, scores.count - scores.count / 2)

        if secondHalf < firstHalf {
            return .improving
        } else if secondHalf > firstHalf {
            return .declining
        } else {
            return .stable
        }
    }

    // MARK: - Helpers

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

enum TrendDirection {
    case improving
    case stable
    case declining
    case noData

    var description: String {
        switch self {
        case .improving: return "Improving"
        case .stable: return "Stable"
        case .declining: return "Declining"
        case .noData: return "Insufficient data"
        }
    }
}
