import Foundation

// MARK: - Assessment Types

/// Standardized psychological assessment instruments
enum AssessmentType: String, Codable, CaseIterable, Identifiable {
    case phq9 = "PHQ9"
    case gad7 = "GAD7"
    case who5 = "WHO5"
    case pss10 = "PSS10"
    case wemwbs = "WEMWBS"

    var id: String { rawValue }

    /// Full name of assessment
    var displayName: String {
        switch self {
        case .phq9: return "Patient Health Questionnaire-9"
        case .gad7: return "Generalized Anxiety Disorder-7"
        case .who5: return "WHO Well-Being Index"
        case .pss10: return "Perceived Stress Scale-10"
        case .wemwbs: return "Warwick-Edinburgh Mental Wellbeing Scale"
        }
    }

    /// Short name for UI display
    var shortName: String {
        switch self {
        case .phq9: return "PHQ-9"
        case .gad7: return "GAD-7"
        case .who5: return "WHO-5"
        case .pss10: return "PSS-10"
        case .wemwbs: return "WEMWBS"
        }
    }

    /// Number of questions in this assessment
    var questionCount: Int {
        switch self {
        case .phq9: return 9
        case .gad7: return 7
        case .who5: return 5
        case .pss10: return 10
        case .wemwbs: return 14
        }
    }

    /// Maximum possible score for this assessment
    var maxScore: Int {
        switch self {
        case .phq9: return 27  // 9 questions × 3 points max
        case .gad7: return 21  // 7 questions × 3 points max
        case .who5: return 25  // 5 questions × 5 points max
        case .pss10: return 40 // 10 questions × 4 points max
        case .wemwbs: return 70 // 14 questions × 5 points max
        }
    }

    /// Recommended frequency in days
    var recommendedFrequencyDays: Int {
        switch self {
        case .phq9, .gad7: return 14  // Bi-weekly
        case .who5, .pss10: return 7   // Weekly
        case .wemwbs: return 14        // Bi-weekly
        }
    }

    /// Description of what this assessment measures
    var description: String {
        switch self {
        case .phq9: return "Screens for depression and suicide risk"
        case .gad7: return "Screens for generalized anxiety disorder"
        case .who5: return "Measures overall mental well-being"
        case .pss10: return "Measures perceived stress levels"
        case .wemwbs: return "Measures mental well-being and functioning"
        }
    }
}

// MARK: - PHQ-9 Severity Levels

/// PHQ-9 depression severity classification
enum PHQ9SeverityLevel: String, Codable, CaseIterable {
    case minimal
    case mild
    case moderate
    case moderatelySevere = "moderately_severe"
    case severe

    var scoreRange: ClosedRange<Int> {
        switch self {
        case .minimal: return 0...4
        case .mild: return 5...9
        case .moderate: return 10...14
        case .moderatelySevere: return 15...19
        case .severe: return 20...27
        }
    }

    var description: String {
        switch self {
        case .minimal: return "Minimal depression"
        case .mild: return "Mild depression"
        case .moderate: return "Moderate depression"
        case .moderatelySevere: return "Moderately severe depression"
        case .severe: return "Severe depression"
        }
    }
}

// MARK: - GAD-7 Severity Levels

/// GAD-7 anxiety severity classification
enum GAD7SeverityLevel: String, Codable, CaseIterable {
    case minimal
    case mild
    case moderate
    case severe

    var scoreRange: ClosedRange<Int> {
        switch self {
        case .minimal: return 0...4
        case .mild: return 5...9
        case .moderate: return 10...14
        case .severe: return 15...21
        }
    }

    var description: String {
        switch self {
        case .minimal: return "Minimal anxiety"
        case .mild: return "Mild anxiety"
        case .moderate: return "Moderate anxiety"
        case .severe: return "Severe anxiety"
        }
    }
}

// MARK: - Generic Severity Level

/// Generic severity classification for questionnaires
enum SeverityLevel: String, Codable, CaseIterable {
    case minimal
    case mild
    case moderate
    case high
    case critical

    var description: String {
        switch self {
        case .minimal: return "Minimal"
        case .mild: return "Mild"
        case .moderate: return "Moderate"
        case .high: return "High"
        case .critical: return "Critical"
        }
    }
}

// MARK: - Crisis Event Types

/// Types of crisis indicators detected
enum CrisisEventType: String, Codable, CaseIterable {
    case phq9Q9Scored = "phq9_q9_scored"          // Self-harm question answered
    case anxietySpike = "anxiety_spike"            // Sudden anxiety increase
    case depressionWorsening = "depression_worsening"  // Rapid decline
    case stressExceedingThreshold = "stress_exceeding_threshold"

    var description: String {
        switch self {
        case .phq9Q9Scored: return "Self-harm risk indicated"
        case .anxietySpike: return "Anxiety spike detected"
        case .depressionWorsening: return "Depression worsening"
        case .stressExceedingThreshold: return "Stress level critical"
        }
    }
}

// MARK: - Crisis Event Severity

/// Severity classification for crisis events
enum CrisisEventSeverity: String, Codable, CaseIterable {
    case low
    case medium
    case high
    case critical

    var description: String {
        switch self {
        case .low: return "Low risk"
        case .medium: return "Medium risk"
        case .high: return "High risk"
        case .critical: return "Critical risk - immediate intervention needed"
        }
    }
}

// MARK: - Assessment Template

/// Definition of a standardized assessment
struct AssessmentTemplate: Identifiable, Codable, Equatable {
    let id: UUID
    let code: String  // e.g., "PHQ9"
    let name: String
    let description: String?
    let questions: [AssessmentQuestion]
    let scoringRanges: [ScoringRange]
    let recommendedFrequencyDays: Int
    let isActive: Bool
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, code, name, description, questions
        case scoringRanges = "scoring_ranges"
        case recommendedFrequencyDays = "recommended_frequency_days"
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Assessment Question

/// Individual question in an assessment
struct AssessmentQuestion: Identifiable, Codable, Equatable {
    let id: String  // e.g., "phq9_q1"
    let number: Int
    let text: String
    let responseOptions: [String]  // Typically 4 options (Not at all, Several days, More than half, Nearly every day)
    let isCrisisIndicator: Bool  // Question 9 of PHQ-9 is a crisis indicator

    enum CodingKeys: String, CodingKey {
        case id, number, text
        case responseOptions = "response_options"
        case isCrisisIndicator = "is_crisis_indicator"
    }
}

// MARK: - Scoring Range

/// Score interpretation range
struct ScoringRange: Codable, Equatable {
    let minScore: Int
    let maxScore: Int
    let severityLevel: String  // e.g., "minimal", "mild", "moderate"
    let label: String
    let recommendations: [String]?

    enum CodingKeys: String, CodingKey {
        case minScore = "min"
        case maxScore = "max"
        case severityLevel = "level"
        case label
        case recommendations
    }
}

// MARK: - Assessment Response

/// User's completed assessment with scores
struct AssessmentResponse: Identifiable, Codable, Equatable {
    let id: UUID
    let userId: UUID
    let assessmentTemplateId: UUID
    let answers: [String: Int]  // Question ID to answer value mapping
    let totalScore: Int
    let severityLevel: String  // e.g., "minimal", "mild", etc.
    let isBaseline: Bool  // First assessment for this template
    let notes: String?
    let completedAt: Date
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case assessmentTemplateId = "assessment_template_id"
        case answers
        case totalScore = "total_score"
        case severityLevel = "severity_level"
        case isBaseline = "is_baseline"
        case notes
        case completedAt = "completed_at"
        case createdAt = "created_at"
    }
}

// MARK: - Assessment Schedule

/// User's assessment schedule and reminders
struct AssessmentSchedule: Identifiable, Codable, Equatable {
    let id: UUID
    let userId: UUID
    let assessmentTemplateId: UUID
    let nextDueAt: Date
    let lastCompletedAt: Date?
    let reminderSent: Bool
    let enabled: Bool
    let customFrequencyDays: Int?  // Override default
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case assessmentTemplateId = "assessment_template_id"
        case nextDueAt = "next_due_at"
        case lastCompletedAt = "last_completed_at"
        case reminderSent = "reminder_sent"
        case enabled
        case customFrequencyDays = "custom_frequency_days"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Is this assessment due now?
    var isDue: Bool {
        nextDueAt <= Date()
    }

    /// Days until next due date
    var daysUntilDue: Int {
        let components = Calendar.current.dateComponents([.day], from: Date(), to: nextDueAt)
        return max(0, components.day ?? 0)
    }
}

// MARK: - Outcome Goal

/// User's goal to improve a specific assessment score
struct OutcomeGoal: Identifiable, Codable, Equatable {
    let id: UUID
    let userId: UUID
    let assessmentTemplateId: UUID
    let targetScore: Int
    let targetDate: Date?
    let baselineScore: Int
    let baselineDate: Date
    let achieved: Bool
    let achievedAt: Date?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case assessmentTemplateId = "assessment_template_id"
        case targetScore = "target_score"
        case targetDate = "target_date"
        case baselineScore = "baseline_score"
        case baselineDate = "baseline_date"
        case achieved
        case achievedAt = "achieved_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Progress toward goal (0.0 to 1.0)
    var progressPercent: Double {
        let totalReduction = baselineScore - targetScore
        guard totalReduction > 0 else { return 0.0 }
        
        let currentReduction = baselineScore - targetScore  // Placeholder
        return min(1.0, Double(currentReduction) / Double(totalReduction))
    }
}

// MARK: - Assessment Crisis Event

/// Safety-critical event logged for audit trail (from outcome assessments)
struct AssessmentCrisisEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let userId: UUID
    let assessmentTemplateId: UUID?
    let assessmentResponseId: UUID?
    let eventType: String  // e.g., "phq9_q9_scored"
    let severity: String   // "low", "medium", "high", "critical"
    let context: [String: AnyCodable]?  // Additional context
    let respondedAt: Date?
    let responseAction: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case assessmentTemplateId = "assessment_template_id"
        case assessmentResponseId = "assessment_response_id"
        case eventType = "event_type"
        case severity
        case context
        case respondedAt = "responded_at"
        case responseAction = "response_action"
        case createdAt = "created_at"
    }
}

// MARK: - AnyCodable Helper

/// Helper type for encoding/decoding arbitrary JSON objects
enum AnyCodable: Codable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([AnyCodable])
    case object([String: AnyCodable])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([AnyCodable].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: AnyCodable].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode AnyCodable")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let bool):
            try container.encode(bool)
        case .int(let int):
            try container.encode(int)
        case .double(let double):
            try container.encode(double)
        case .string(let string):
            try container.encode(string)
        case .array(let array):
            try container.encode(array)
        case .object(let object):
            try container.encode(object)
        }
    }
}

// MARK: - Database Models (for Supabase)

/// Database representation of AssessmentTemplate
struct DBAssessmentTemplate: Codable {
    let id: UUID
    let code: String
    let name: String
    let description: String?
    let questions: [AssessmentQuestion]
    let scoring_ranges: [ScoringRange]
    let recommended_frequency_days: Int
    let is_active: Bool
    let created_at: String?  // ISO8601
    let updated_at: String?  // ISO8601

    func toAssessmentTemplate() -> AssessmentTemplate {
        AssessmentTemplate(
            id: id,
            code: code,
            name: name,
            description: description,
            questions: questions,
            scoringRanges: scoring_ranges,
            recommendedFrequencyDays: recommended_frequency_days,
            isActive: is_active,
            createdAt: created_at?.toDate(),
            updatedAt: updated_at?.toDate()
        )
    }
}

/// Database representation of AssessmentResponse
struct DBAssessmentResponse: Codable {
    let id: UUID?
    let user_id: UUID
    let assessment_template_id: UUID
    let answers: [String: Int]
    let total_score: Int
    let severity_level: String
    let is_baseline: Bool
    let notes: String?
    let completed_at: String?  // ISO8601
    let created_at: String?    // ISO8601

    func toAssessmentResponse() -> AssessmentResponse {
        AssessmentResponse(
            id: id ?? UUID(),
            userId: user_id,
            assessmentTemplateId: assessment_template_id,
            answers: answers,
            totalScore: total_score,
            severityLevel: severity_level,
            isBaseline: is_baseline,
            notes: notes,
            completedAt: completed_at?.toDate() ?? Date(),
            createdAt: created_at?.toDate()
        )
    }
}

/// Database representation of AssessmentSchedule
struct DBAssessmentSchedule: Codable {
    let id: UUID
    let user_id: UUID
    let assessment_template_id: UUID
    let next_due_at: String  // ISO8601
    let last_completed_at: String?  // ISO8601
    let reminder_sent: Bool
    let enabled: Bool
    let custom_frequency_days: Int?
    let created_at: String?  // ISO8601
    let updated_at: String?  // ISO8601

    func toAssessmentSchedule() -> AssessmentSchedule {
        AssessmentSchedule(
            id: id,
            userId: user_id,
            assessmentTemplateId: assessment_template_id,
            nextDueAt: next_due_at.toDate() ?? Date(),
            lastCompletedAt: last_completed_at?.toDate(),
            reminderSent: reminder_sent,
            enabled: enabled,
            customFrequencyDays: custom_frequency_days,
            createdAt: created_at?.toDate(),
            updatedAt: updated_at?.toDate()
        )
    }
}

/// Database representation of OutcomeGoal
struct DBOutcomeGoal: Codable {
    let id: UUID
    let user_id: UUID
    let assessment_template_id: UUID
    let target_score: Int
    let target_date: String?  // ISO8601
    let baseline_score: Int
    let baseline_date: String  // ISO8601
    let achieved: Bool
    let achieved_at: String?  // ISO8601
    let created_at: String?   // ISO8601
    let updated_at: String?   // ISO8601

    func toOutcomeGoal() -> OutcomeGoal {
        OutcomeGoal(
            id: id,
            userId: user_id,
            assessmentTemplateId: assessment_template_id,
            targetScore: target_score,
            targetDate: target_date?.toDate(),
            baselineScore: baseline_score,
            baselineDate: baseline_date.toDate() ?? Date(),
            achieved: achieved,
            achievedAt: achieved_at?.toDate(),
            createdAt: created_at?.toDate(),
            updatedAt: updated_at?.toDate()
        )
    }
}

/// Database representation of CrisisEvent
struct DBCrisisEvent: Codable {
    let id: UUID
    let user_id: UUID
    let assessment_template_id: UUID?
    let assessment_response_id: UUID?
    let event_type: String
    let severity: String
    let context: [String: AnyCodable]?
    let responded_at: String?  // ISO8601
    let response_action: String?
    let created_at: String  // ISO8601

    func toAssessmentCrisisEvent() -> AssessmentCrisisEvent {
        AssessmentCrisisEvent(
            id: id,
            userId: user_id,
            assessmentTemplateId: assessment_template_id,
            assessmentResponseId: assessment_response_id,
            eventType: event_type,
            severity: severity,
            context: context,
            respondedAt: responded_at?.toDate(),
            responseAction: response_action,
            createdAt: created_at.toDate() ?? Date()
        )
    }
}

// MARK: - Date Extensions

extension String {
    /// Convert ISO8601 date string to Date object
    func toDate() -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: self)
    }
}

extension Date {
    /// Convert Date to ISO8601 string for database storage
    func toISODateString() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: self)
    }
}
