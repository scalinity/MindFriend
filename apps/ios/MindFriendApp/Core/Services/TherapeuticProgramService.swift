import Foundation
import Supabase

/// Service for managing therapeutic program operations including clinical assessments,
/// thought records, emotion regulation logs, and values assessments.
@MainActor
final class TherapeuticProgramService: ObservableObject {
    private let supabase: SupabaseClient

    @Published var isLoading = false
    @Published var error: Error?

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    // MARK: - Program Operations

    /// Fetch all therapeutic programs (programs with methodology != null)
    func fetchTherapeuticPrograms() async throws -> [Program] {
        let response: [DBProgram] = try await supabase
            .from("programs")
            .select()
            .not("methodology", operator: .is, value: "null")
            .order("sort_order")
            .execute()
            .value

        return response.map { $0.toProgram() }
    }

    /// Fetch therapeutic programs by methodology
    func fetchPrograms(methodology: TherapeuticMethodology) async throws -> [Program] {
        let response: [DBProgram] = try await supabase
            .from("programs")
            .select()
            .eq("methodology", value: methodology.rawValue)
            .order("sort_order")
            .execute()
            .value

        return response.map { $0.toProgram() }
    }

    /// Get module unlock status for a therapeutic program enrollment
    func getModuleUnlockStatus(enrollmentId: String, weekNumber: Int) async throws -> ModuleUnlockStatus {
        let response = try await supabase
            .rpc("get_module_unlock_status", params: [
                "p_enrollment_id": enrollmentId,
                "p_week_number": weekNumber
            ])
            .execute()

        let data = response.data
        return try JSONDecoder().decode(ModuleUnlockStatus.self, from: data)
    }

    /// Check if user can enroll in a therapeutic program
    func canEnrollInTherapeuticProgram() async throws -> Bool {
        guard let userId = supabase.auth.currentUser?.id else {
            throw TherapeuticServiceError.notAuthenticated
        }

        // Check for existing active therapeutic enrollment
        let existingEnrollments: [DBProgramEnrollment] = try await supabase
            .from("program_enrollments")
            .select("*, programs(*)")
            .eq("user_id", value: userId.uuidString)
            .eq("status", value: "active")
            .execute()
            .value

        // Filter to therapeutic enrollments
        let therapeuticEnrollments = existingEnrollments.filter { enrollment in
            enrollment.programs?.methodology != nil
        }

        return therapeuticEnrollments.isEmpty
    }

    // MARK: - Clinical Assessment Operations

    /// Submit a clinical assessment (PHQ-9 or GAD-7)
    func submitAssessment(
        type: AssessmentType,
        responses: [Int],
        enrollmentId: String? = nil,
        assessmentPoint: AssessmentPoint = .standalone
    ) async throws -> AssessmentSubmissionResult {
        let params: [String: AnyJSON] = [
            "p_assessment_type": .string(type.rawValue),
            "p_responses": .array(responses.map { .integer($0) }),
            "p_enrollment_id": enrollmentId.map { .string($0) } ?? .null,
            "p_assessment_point": .string(assessmentPoint.rawValue)
        ]

        let response = try await supabase
            .rpc("submit_clinical_assessment", params: params)
            .execute()

        let data = response.data
        return try JSONDecoder().decode(AssessmentSubmissionResult.self, from: data)
    }

    /// Fetch assessment history for current user
    func fetchAssessmentHistory(
        type: AssessmentType? = nil,
        limit: Int = 20
    ) async throws -> [ClinicalAssessment] {
        guard let userId = supabase.auth.currentUser?.id else {
            throw TherapeuticServiceError.notAuthenticated
        }

        var query = supabase
            .from("clinical_assessments")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)

        if let type = type {
            query = query.eq("assessment_type", value: type.rawValue)
        }

        let response: [DBClinicalAssessment] = try await query.execute().value
        return response.map { $0.toClinicalAssessment() }
    }

    /// Fetch assessments for an enrollment
    func fetchEnrollmentAssessments(enrollmentId: String) async throws -> [ClinicalAssessment] {
        let response: [DBClinicalAssessment] = try await supabase
            .from("clinical_assessments")
            .select()
            .eq("enrollment_id", value: enrollmentId)
            .order("created_at", ascending: true)
            .execute()
            .value

        return response.map { $0.toClinicalAssessment() }
    }

    /// Get baseline and latest assessment comparison
    func getAssessmentProgress(enrollmentId: String, type: AssessmentType) async throws -> (baseline: ClinicalAssessment?, latest: ClinicalAssessment?, improvement: Int?) {
        let assessments = try await fetchEnrollmentAssessments(enrollmentId: enrollmentId)
            .filter { $0.assessmentType == type }

        let baseline = assessments.first { $0.assessmentPoint == .pre }
        let latest = assessments.last

        var improvement: Int?
        if let baselineScore = baseline?.totalScore, let latestScore = latest?.totalScore {
            improvement = baselineScore - latestScore
        }

        return (baseline, latest, improvement)
    }

    // MARK: - Thought Record Operations (CBT)

    /// Create a new thought record
    func createThoughtRecord(
        situation: String,
        automaticThought: String,
        emotions: [EmotionEntry],
        enrollmentId: String? = nil,
        programDayNumber: Int? = nil
    ) async throws -> ThoughtRecord {
        guard let userId = supabase.auth.currentUser?.id else {
            throw TherapeuticServiceError.notAuthenticated
        }

        let record: [String: AnyJSON] = [
            "user_id": .string(userId.uuidString),
            "enrollment_id": enrollmentId.map { .string($0) } ?? .null,
            "program_day_number": programDayNumber.map { .integer($0) } ?? .null,
            "situation": .string(situation),
            "automatic_thought": .string(automaticThought),
            "emotions": .array(emotions.map { emotion in
                .object([
                    "emotion": .string(emotion.emotion),
                    "intensity": .integer(emotion.intensity)
                ])
            }),
            "cognitive_distortions": .array([])
        ]

        let response: DBThoughtRecord = try await supabase
            .from("thought_records")
            .insert(record)
            .select()
            .single()
            .execute()
            .value

        return response.toThoughtRecord()
    }

    /// Update thought record with evidence and balanced thought
    func updateThoughtRecord(
        id: String,
        evidenceFor: String,
        evidenceAgainst: String,
        balancedThought: String,
        newEmotionIntensity: Int
    ) async throws -> ThoughtRecord {
        let updates: [String: AnyJSON] = [
            "evidence_for": .string(evidenceFor),
            "evidence_against": .string(evidenceAgainst),
            "balanced_thought": .string(balancedThought),
            "new_emotion_intensity": .integer(newEmotionIntensity),
            "updated_at": .string(ISO8601DateFormatter().string(from: Date()))
        ]

        let response: DBThoughtRecord = try await supabase
            .from("thought_records")
            .update(updates)
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value

        return response.toThoughtRecord()
    }

    /// Request AI analysis for a thought record
    func requestThoughtAnalysis(thoughtRecordId: String) async throws -> AIThoughtAnalysis {
        // Mark the record as awaiting analysis
        try await supabase
            .from("thought_records")
            .update(["ai_analysis_requested_at": ISO8601DateFormatter().string(from: Date())])
            .eq("id", value: thoughtRecordId)
            .execute()

        // Call the Edge Function for analysis
        let response = try await supabase.functions.invoke(
            "analyze-thought-record",
            options: .init(body: ["thoughtRecordId": thoughtRecordId])
        )

        guard let data = response.data else {
            throw TherapeuticServiceError.analysisUnavailable
        }

        struct AnalysisResponse: Decodable {
            let analysis: AIThoughtAnalysis
            let distortions: [String]
        }

        let result = try JSONDecoder().decode(AnalysisResponse.self, from: data)

        // Update the record with the analysis
        // Convert AIThoughtAnalysis to AnyJSON by encoding/decoding
        let analysisData = try JSONEncoder().encode(result.analysis)
        let analysisJson = try JSONDecoder().decode(AnyJSON.self, from: analysisData)

        // Convert [String] to AnyJSON array
        let distortionsJson = AnyJSON.array(result.distortions.map { AnyJSON.string($0) })

        try await supabase
            .from("thought_records")
            .update([
                "ai_analysis": analysisJson,
                "cognitive_distortions": distortionsJson
            ])
            .eq("id", value: thoughtRecordId)
            .execute()

        return result.analysis
    }

    /// Fetch thought records for current user
    func fetchThoughtRecords(
        enrollmentId: String? = nil,
        limit: Int = 20
    ) async throws -> [ThoughtRecord] {
        guard let userId = supabase.auth.currentUser?.id else {
            throw TherapeuticServiceError.notAuthenticated
        }

        var query = supabase
            .from("thought_records")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)

        if let enrollmentId = enrollmentId {
            query = query.eq("enrollment_id", value: enrollmentId)
        }

        let response: [DBThoughtRecord] = try await query.execute().value
        return response.map { $0.toThoughtRecord() }
    }

    // MARK: - Emotion Regulation Operations (DBT)

    /// Log an emotion regulation practice
    func logEmotionRegulation(
        triggerEvent: String,
        emotionsBefore: [EmotionEntry],
        bodyLocation: String?,
        urgeAction: String?,
        skillUsed: String,
        skillCategory: DBTSkillCategory,
        emotionsAfter: [EmotionEntry],
        effectivenessRating: Int,
        reflectionNotes: String?,
        enrollmentId: String? = nil,
        programDayNumber: Int? = nil
    ) async throws -> EmotionRegulationLog {
        guard let userId = supabase.auth.currentUser?.id else {
            throw TherapeuticServiceError.notAuthenticated
        }

        let record: [String: AnyJSON] = [
            "user_id": .string(userId.uuidString),
            "enrollment_id": enrollmentId.map { .string($0) } ?? .null,
            "program_day_number": programDayNumber.map { .integer($0) } ?? .null,
            "trigger_event": .string(triggerEvent),
            "emotions_before": .array(emotionsBefore.map { emotion in
                .object([
                    "emotion": .string(emotion.emotion),
                    "intensity": .integer(emotion.intensity)
                ])
            }),
            "body_location": bodyLocation.map { .string($0) } ?? .null,
            "urge_action": urgeAction.map { .string($0) } ?? .null,
            "skill_used": .string(skillUsed),
            "skill_category": .string(skillCategory.rawValue),
            "emotions_after": .array(emotionsAfter.map { emotion in
                .object([
                    "emotion": .string(emotion.emotion),
                    "intensity": .integer(emotion.intensity)
                ])
            }),
            "effectiveness_rating": .integer(effectivenessRating),
            "reflection_notes": reflectionNotes.map { .string($0) } ?? .null
        ]

        let response: DBEmotionRegulationLog = try await supabase
            .from("emotion_regulation_logs")
            .insert(record)
            .select()
            .single()
            .execute()
            .value

        return response.toEmotionRegulationLog()
    }

    /// Fetch emotion regulation logs
    func fetchEmotionRegulationLogs(
        enrollmentId: String? = nil,
        skillCategory: DBTSkillCategory? = nil,
        limit: Int = 20
    ) async throws -> [EmotionRegulationLog] {
        guard let userId = supabase.auth.currentUser?.id else {
            throw TherapeuticServiceError.notAuthenticated
        }

        var query = supabase
            .from("emotion_regulation_logs")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)

        if let enrollmentId = enrollmentId {
            query = query.eq("enrollment_id", value: enrollmentId)
        }

        if let skillCategory = skillCategory {
            query = query.eq("skill_category", value: skillCategory.rawValue)
        }

        let response: [DBEmotionRegulationLog] = try await query.execute().value
        return response.map { $0.toEmotionRegulationLog() }
    }

    /// Get skill usage statistics
    func getSkillUsageStats(enrollmentId: String? = nil) async throws -> [DBTSkillCategory: Int] {
        let logs = try await fetchEmotionRegulationLogs(enrollmentId: enrollmentId, limit: 100)

        var stats: [DBTSkillCategory: Int] = [:]
        for category in DBTSkillCategory.allCases {
            stats[category] = 0
        }

        for log in logs {
            stats[log.skillCategory, default: 0] += 1
        }

        return stats
    }

    // MARK: - Values Assessment Operations (ACT)

    /// Submit a values assessment
    func submitValuesAssessment(
        valueDomain: ValueDomain,
        valueStatement: String,
        importanceRating: Int,
        currentAlignmentRating: Int,
        barriers: [String],
        committedActions: [String],
        reflectionNotes: String?,
        enrollmentId: String? = nil,
        programDayNumber: Int? = nil
    ) async throws -> ValuesAssessment {
        guard let userId = supabase.auth.currentUser?.id else {
            throw TherapeuticServiceError.notAuthenticated
        }

        let record: [String: AnyJSON] = [
            "user_id": .string(userId.uuidString),
            "enrollment_id": enrollmentId.map { .string($0) } ?? .null,
            "program_day_number": programDayNumber.map { .integer($0) } ?? .null,
            "value_domain": .string(valueDomain.rawValue),
            "value_statement": .string(valueStatement),
            "importance_rating": .integer(importanceRating),
            "current_alignment_rating": .integer(currentAlignmentRating),
            "barriers": .array(barriers.map { .string($0) }),
            "committed_actions": .array(committedActions.map { .string($0) }),
            "reflection_notes": reflectionNotes.map { .string($0) } ?? .null
        ]

        let response: DBValuesAssessment = try await supabase
            .from("values_assessments")
            .insert(record)
            .select()
            .single()
            .execute()
            .value

        return response.toValuesAssessment()
    }

    /// Update a values assessment
    func updateValuesAssessment(
        id: String,
        currentAlignmentRating: Int?,
        barriers: [String]?,
        committedActions: [String]?,
        reflectionNotes: String?
    ) async throws -> ValuesAssessment {
        var updates: [String: AnyJSON] = [
            "updated_at": .string(ISO8601DateFormatter().string(from: Date()))
        ]

        if let rating = currentAlignmentRating {
            updates["current_alignment_rating"] = .integer(rating)
        }
        if let barriers = barriers {
            updates["barriers"] = .array(barriers.map { .string($0) })
        }
        if let actions = committedActions {
            updates["committed_actions"] = .array(actions.map { .string($0) })
        }
        if let notes = reflectionNotes {
            updates["reflection_notes"] = .string(notes)
        }

        let response: DBValuesAssessment = try await supabase
            .from("values_assessments")
            .update(updates)
            .eq("id", value: id)
            .select()
            .single()
            .execute()
            .value

        return response.toValuesAssessment()
    }

    /// Fetch values assessments
    func fetchValuesAssessments(
        enrollmentId: String? = nil,
        valueDomain: ValueDomain? = nil,
        limit: Int = 20
    ) async throws -> [ValuesAssessment] {
        guard let userId = supabase.auth.currentUser?.id else {
            throw TherapeuticServiceError.notAuthenticated
        }

        var query = supabase
            .from("values_assessments")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)

        if let enrollmentId = enrollmentId {
            query = query.eq("enrollment_id", value: enrollmentId)
        }

        if let valueDomain = valueDomain {
            query = query.eq("value_domain", value: valueDomain.rawValue)
        }

        let response: [DBValuesAssessment] = try await query.execute().value
        return response.map { $0.toValuesAssessment() }
    }

    /// Get values with largest alignment gaps
    func getValuesGaps(enrollmentId: String? = nil) async throws -> [ValuesAssessment] {
        let assessments = try await fetchValuesAssessments(enrollmentId: enrollmentId, limit: 50)

        // Get unique latest assessment per domain
        var latestByDomain: [ValueDomain: ValuesAssessment] = [:]
        for assessment in assessments {
            if latestByDomain[assessment.valueDomain] == nil {
                latestByDomain[assessment.valueDomain] = assessment
            }
        }

        // Sort by alignment gap (descending)
        return latestByDomain.values
            .sorted { $0.alignmentGap > $1.alignmentGap }
    }

    // MARK: - Progress Summary

    /// Get therapeutic progress summary for an enrollment
    func getProgressSummary(enrollmentId: String) async throws -> TherapeuticProgressSummary {
        // Fetch enrollment with program
        let enrollment: DBProgramEnrollment = try await supabase
            .from("program_enrollments")
            .select("*, programs(*)")
            .eq("id", value: enrollmentId)
            .single()
            .execute()
            .value

        guard let program = enrollment.programs else {
            throw TherapeuticServiceError.programNotFound
        }

        // Fetch counts
        let assessments = try await fetchEnrollmentAssessments(enrollmentId: enrollmentId)
        let thoughtRecords = try await fetchThoughtRecords(enrollmentId: enrollmentId, limit: 100)
        let emotionLogs = try await fetchEmotionRegulationLogs(enrollmentId: enrollmentId, limit: 100)
        let valuesAssessments = try await fetchValuesAssessments(enrollmentId: enrollmentId, limit: 100)

        // Calculate progress
        let totalWeeks = program.durationDays / 7
        let currentWeek = (enrollment.currentDay - 1) / 7 + 1

        // Get baseline and latest assessment scores
        let baselineAssessment = assessments.first { $0.assessmentPoint == .pre }
        let latestAssessment = assessments.last

        var scoreImprovement: Int?
        if let baselineScore = baselineAssessment?.totalScore,
           let latestScore = latestAssessment?.totalScore {
            scoreImprovement = baselineScore - latestScore
        }

        // Calculate unique value domains explored
        let uniqueDomains = Set(valuesAssessments.map { $0.valueDomain })

        return TherapeuticProgressSummary(
            enrollmentId: enrollmentId,
            programTitle: program.title,
            methodology: program.methodology ?? "mixed",
            currentWeek: currentWeek,
            totalWeeks: totalWeeks,
            assessmentsCompleted: assessments.count,
            thoughtRecordsCompleted: thoughtRecords.count,
            skillsLogged: emotionLogs.count,
            valuesExplored: uniqueDomains.count,
            overallProgress: Double(enrollment.currentDay) / Double(program.durationDays),
            latestAssessmentScore: latestAssessment?.totalScore,
            latestAssessmentSeverity: latestAssessment?.severity.rawValue,
            scoreImprovement: scoreImprovement
        )
    }
}

// MARK: - Errors

enum TherapeuticServiceError: LocalizedError {
    case notAuthenticated
    case programNotFound
    case enrollmentNotFound
    case analysisUnavailable
    case invalidAssessmentResponse
    case safetyFlagTriggered

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to use therapeutic programs."
        case .programNotFound:
            return "The requested program could not be found."
        case .enrollmentNotFound:
            return "Your enrollment could not be found."
        case .analysisUnavailable:
            return "AI analysis is temporarily unavailable. Please try again later."
        case .invalidAssessmentResponse:
            return "Please answer all questions to submit the assessment."
        case .safetyFlagTriggered:
            return "Based on your responses, we want to make sure you're safe."
        }
    }
}
