import Foundation
import SwiftUI

// MARK: - Clinical Assessment Types

/// Assessment point in a program
enum AssessmentPoint: String, Codable {
    case pre
    case weekly
    case post
    case standalone
}

/// Severity levels for clinical assessments
enum AssessmentSeverity: String, Codable, CaseIterable {
    case minimal
    case mild
    case moderate
    case moderatelySevere = "moderately_severe"
    case severe

    var displayName: String {
        switch self {
        case .minimal: return "Minimal"
        case .mild: return "Mild"
        case .moderate: return "Moderate"
        case .moderatelySevere: return "Moderately Severe"
        case .severe: return "Severe"
        }
    }

    var color: Color {
        switch self {
        case .minimal: return .green
        case .mild: return .yellow
        case .moderate: return .orange
        case .moderatelySevere: return .red
        case .severe: return .purple
        }
    }

    var icon: String {
        switch self {
        case .minimal: return "checkmark.circle.fill"
        case .mild: return "exclamationmark.circle"
        case .moderate: return "exclamationmark.triangle"
        case .moderatelySevere: return "exclamationmark.triangle.fill"
        case .severe: return "xmark.octagon.fill"
        }
    }
}

// MARK: - PHQ-9 Questions

/// PHQ-9 question definitions
enum PHQ9Question: Int, CaseIterable {
    case interestPleasure = 0
    case depressedMood = 1
    case sleepProblems = 2
    case tiredness = 3
    case appetiteChanges = 4
    case selfWorth = 5
    case concentration = 6
    case motorChanges = 7
    case suicidalThoughts = 8

    var questionText: String {
        switch self {
        case .interestPleasure:
            return "Little interest or pleasure in doing things"
        case .depressedMood:
            return "Feeling down, depressed, or hopeless"
        case .sleepProblems:
            return "Trouble falling or staying asleep, or sleeping too much"
        case .tiredness:
            return "Feeling tired or having little energy"
        case .appetiteChanges:
            return "Poor appetite or overeating"
        case .selfWorth:
            return "Feeling bad about yourself — or that you are a failure or have let yourself or your family down"
        case .concentration:
            return "Trouble concentrating on things, such as reading the newspaper or watching television"
        case .motorChanges:
            return "Moving or speaking so slowly that other people could have noticed? Or the opposite — being so fidgety or restless that you have been moving around a lot more than usual"
        case .suicidalThoughts:
            return "Thoughts that you would be better off dead, or of hurting yourself in some way"
        }
    }

    /// Whether this question requires safety flagging
    var isSafetyQuestion: Bool {
        self == .suicidalThoughts
    }
}

// MARK: - GAD-7 Questions

/// GAD-7 question definitions
enum GAD7Question: Int, CaseIterable {
    case feelingNervous = 0
    case uncontrollableWorrying = 1
    case worryingTooMuch = 2
    case troubleRelaxing = 3
    case restlessness = 4
    case irritability = 5
    case feelingAfraid = 6

    var questionText: String {
        switch self {
        case .feelingNervous:
            return "Feeling nervous, anxious, or on edge"
        case .uncontrollableWorrying:
            return "Not being able to stop or control worrying"
        case .worryingTooMuch:
            return "Worrying too much about different things"
        case .troubleRelaxing:
            return "Trouble relaxing"
        case .restlessness:
            return "Being so restless that it's hard to sit still"
        case .irritability:
            return "Becoming easily annoyed or irritable"
        case .feelingAfraid:
            return "Feeling afraid as if something awful might happen"
        }
    }
}

// MARK: - Assessment Response Options

/// Standard response options for clinical assessments (0-3 scale)
enum AssessmentResponseOption: Int, CaseIterable {
    case notAtAll = 0
    case severalDays = 1
    case moreThanHalf = 2
    case nearlyEveryDay = 3

    var displayText: String {
        switch self {
        case .notAtAll: return "Not at all"
        case .severalDays: return "Several days"
        case .moreThanHalf: return "More than half the days"
        case .nearlyEveryDay: return "Nearly every day"
        }
    }
}

// MARK: - Clinical Assessment

/// A clinical assessment record
struct ClinicalAssessment: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let enrollmentId: String?
    let assessmentType: AssessmentType
    let responses: [Int]
    let totalScore: Int
    let severity: AssessmentSeverity
    let flaggedForReview: Bool
    let assessmentPoint: AssessmentPoint
    let createdAt: Date

    /// Whether this assessment contains concerning responses requiring follow-up
    var requiresFollowUp: Bool {
        flaggedForReview || severity == .severe || severity == .moderatelySevere
    }

    /// Get individual question response
    func response(for questionIndex: Int) -> Int? {
        guard questionIndex >= 0 && questionIndex < responses.count else { return nil }
        return responses[questionIndex]
    }

    enum CodingKeys: String, CodingKey {
        case id, responses, severity
        case userId = "user_id"
        case enrollmentId = "enrollment_id"
        case assessmentType = "assessment_type"
        case totalScore = "total_score"
        case flaggedForReview = "flagged_for_review"
        case assessmentPoint = "assessment_point"
        case createdAt = "created_at"
    }
}

/// Database representation of clinical assessment
struct DBClinicalAssessment: Codable {
    let id: UUID
    let userId: UUID
    let enrollmentId: UUID?
    let assessmentType: String
    let responses: [Int]
    let totalScore: Int
    let severity: String
    let flaggedForReview: Bool
    let assessmentPoint: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, responses, severity
        case userId = "user_id"
        case enrollmentId = "enrollment_id"
        case assessmentType = "assessment_type"
        case totalScore = "total_score"
        case flaggedForReview = "flagged_for_review"
        case assessmentPoint = "assessment_point"
        case createdAt = "created_at"
    }

    func toClinicalAssessment() -> ClinicalAssessment {
        ClinicalAssessment(
            id: id.uuidString,
            userId: userId.uuidString,
            enrollmentId: enrollmentId?.uuidString,
            assessmentType: AssessmentType(rawValue: assessmentType) ?? .phq9,
            responses: responses,
            totalScore: totalScore,
            severity: AssessmentSeverity(rawValue: severity) ?? .minimal,
            flaggedForReview: flaggedForReview,
            assessmentPoint: AssessmentPoint(rawValue: assessmentPoint) ?? .standalone,
            createdAt: createdAt
        )
    }
}

// MARK: - Assessment Submission Result

/// Result from submitting a clinical assessment
struct AssessmentSubmissionResult: Codable {
    let assessmentId: String
    let totalScore: Int
    let severity: String
    let requiresCrisisIntervention: Bool
    let crisisEventId: String?

    enum CodingKeys: String, CodingKey {
        case severity
        case assessmentId = "id"
        case totalScore = "total_score"
        case requiresCrisisIntervention = "crisis_intervention_needed"
        case crisisEventId = "crisis_event_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        assessmentId = try container.decode(String.self, forKey: .assessmentId)
        totalScore = try container.decode(Int.self, forKey: .totalScore)
        severity = try container.decode(String.self, forKey: .severity)
        requiresCrisisIntervention = try container.decode(Bool.self, forKey: .requiresCrisisIntervention)
        // crisis_event_id is not returned by SQL function, so use nil
        crisisEventId = try container.decodeIfPresent(String.self, forKey: .crisisEventId)
    }
}

// MARK: - Cognitive Distortion Types

/// Common cognitive distortions identified in CBT
enum CognitiveDistortionType: String, Codable, CaseIterable {
    case allOrNothing = "all_or_nothing"
    case overgeneralization = "overgeneralization"
    case mentalFilter = "mental_filter"
    case disqualifyingPositive = "disqualifying_positive"
    case mindReading = "mind_reading"
    case fortuneTelling = "fortune_telling"
    case catastrophizing = "catastrophizing"
    case emotionalReasoning = "emotional_reasoning"
    case shouldStatements = "should_statements"
    case labeling = "labeling"

    var displayName: String {
        switch self {
        case .allOrNothing: return "All-or-Nothing Thinking"
        case .overgeneralization: return "Overgeneralization"
        case .mentalFilter: return "Mental Filter"
        case .disqualifyingPositive: return "Disqualifying the Positive"
        case .mindReading: return "Mind Reading"
        case .fortuneTelling: return "Fortune Telling"
        case .catastrophizing: return "Catastrophizing"
        case .emotionalReasoning: return "Emotional Reasoning"
        case .shouldStatements: return "Should Statements"
        case .labeling: return "Labeling"
        }
    }

    var description: String {
        switch self {
        case .allOrNothing:
            return "Seeing things in black-and-white categories. If your performance falls short of perfect, you see yourself as a total failure."
        case .overgeneralization:
            return "Viewing a single negative event as a never-ending pattern of defeat."
        case .mentalFilter:
            return "Picking out a single negative detail and dwelling on it exclusively."
        case .disqualifyingPositive:
            return "Rejecting positive experiences by insisting they \"don't count.\""
        case .mindReading:
            return "Assuming you know what others are thinking without evidence."
        case .fortuneTelling:
            return "Predicting things will turn out badly without evidence."
        case .catastrophizing:
            return "Exaggerating the importance of things or expecting the worst."
        case .emotionalReasoning:
            return "Assuming that negative emotions reflect reality: \"I feel it, so it must be true.\""
        case .shouldStatements:
            return "Using \"should\" and \"must\" statements that create pressure and guilt."
        case .labeling:
            return "Attaching a negative label to yourself or others instead of describing behavior."
        }
    }

    var icon: String {
        switch self {
        case .allOrNothing: return "arrow.left.and.right"
        case .overgeneralization: return "arrow.right.to.line"
        case .mentalFilter: return "line.3.horizontal.decrease.circle"
        case .disqualifyingPositive: return "xmark.circle"
        case .mindReading: return "brain"
        case .fortuneTelling: return "sparkles"
        case .catastrophizing: return "exclamationmark.triangle"
        case .emotionalReasoning: return "heart.fill"
        case .shouldStatements: return "exclamationmark.circle"
        case .labeling: return "tag"
        }
    }

    var reframingTip: String {
        switch self {
        case .allOrNothing:
            return "Look for shades of gray. Are there any partial successes or middle ground?"
        case .overgeneralization:
            return "Challenge words like 'always' and 'never'. Is this really true every time?"
        case .mentalFilter:
            return "Zoom out. What positive aspects might you be overlooking?"
        case .disqualifyingPositive:
            return "Consider: Why does this positive not count? What evidence supports it?"
        case .mindReading:
            return "Ask: Do I have evidence for what they're thinking? Could there be other explanations?"
        case .fortuneTelling:
            return "Consider other possible outcomes. What evidence supports your prediction?"
        case .catastrophizing:
            return "What's the realistic worst case? How likely is it? What would you do if it happened?"
        case .emotionalReasoning:
            return "Feelings are valid but not facts. What evidence exists outside how you feel?"
        case .shouldStatements:
            return "Replace 'should' with 'I prefer' or 'It would be nice if'."
        case .labeling:
            return "Describe the behavior instead of using a label. What specifically happened?"
        }
    }

    /// A gentle, supportive description for journal analysis
    var supportiveDescription: String {
        switch self {
        case .allOrNothing:
            return "This is a common pattern where things feel either perfect or a total failure. Many people experience this."
        case .overgeneralization:
            return "Sometimes we see one event as part of a bigger pattern. It's natural to make these connections."
        case .mentalFilter:
            return "Our minds sometimes zoom in on one detail. This happens to everyone sometimes."
        case .disqualifyingPositive:
            return "It's common to brush off positive things when we're struggling. You're not alone in this."
        case .mindReading:
            return "We often try to guess what others think. It's a way our minds try to protect us."
        case .fortuneTelling:
            return "Predicting the future is something our minds naturally do to prepare us."
        case .catastrophizing:
            return "When we're worried, it's natural to imagine worst-case scenarios."
        case .emotionalReasoning:
            return "Our feelings are real and valid, even when they don't reflect the full picture."
        case .shouldStatements:
            return "Using 'should' is very common. It often shows we care about doing things well."
        case .labeling:
            return "Labeling is a shortcut our minds use. It doesn't define who you really are."
        }
    }
}

// MARK: - Emotion Entry

/// An emotion with intensity for thought records
struct EmotionEntry: Codable, Equatable, Hashable {
    let emotion: String
    let intensity: Int // 0-100

    var intensityDescription: String {
        switch intensity {
        case 0..<20: return "Very Low"
        case 20..<40: return "Low"
        case 40..<60: return "Moderate"
        case 60..<80: return "High"
        case 80...100: return "Very High"
        default: return "Unknown"
        }
    }
}

// MARK: - Thought Record

/// A CBT thought record entry
struct ThoughtRecord: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let enrollmentId: String?
    let programDayNumber: Int?

    // ABC Model fields
    let situation: String
    let automaticThought: String
    let emotions: [EmotionEntry]

    // Evidence and reframing
    let evidenceFor: String?
    let evidenceAgainst: String?
    let balancedThought: String?
    let newEmotionIntensity: Int?

    // AI analysis
    let cognitiveDistortions: [CognitiveDistortionType]
    let aiAnalysis: AIThoughtAnalysis?
    let aiAnalysisRequestedAt: Date?

    let createdAt: Date
    let updatedAt: Date

    /// Whether the record is complete (has evidence and balanced thought)
    var isComplete: Bool {
        evidenceFor != nil && evidenceAgainst != nil && balancedThought != nil
    }

    /// Whether AI analysis has been requested but not received
    var isAwaitingAnalysis: Bool {
        aiAnalysisRequestedAt != nil && aiAnalysis == nil
    }

    /// Primary emotion (highest intensity)
    var primaryEmotion: EmotionEntry? {
        emotions.max(by: { $0.intensity < $1.intensity })
    }

    /// Improvement in emotion intensity if reframing was done
    var emotionImprovement: Int? {
        guard let primary = primaryEmotion, let newIntensity = newEmotionIntensity else { return nil }
        return primary.intensity - newIntensity
    }

    enum CodingKeys: String, CodingKey {
        case id, situation, emotions
        case userId = "user_id"
        case enrollmentId = "enrollment_id"
        case programDayNumber = "program_day_number"
        case automaticThought = "automatic_thought"
        case evidenceFor = "evidence_for"
        case evidenceAgainst = "evidence_against"
        case balancedThought = "balanced_thought"
        case newEmotionIntensity = "new_emotion_intensity"
        case cognitiveDistortions = "cognitive_distortions"
        case aiAnalysis = "ai_analysis"
        case aiAnalysisRequestedAt = "ai_analysis_requested_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// AI-generated thought analysis
struct AIThoughtAnalysis: Codable, Equatable {
    let identifiedDistortions: [String]
    let distortionExplanations: [String: String]
    let reframingSuggestions: [String]
    let validationStatement: String?
    let copingStrategies: [String]

    enum CodingKeys: String, CodingKey {
        case identifiedDistortions = "identified_distortions"
        case distortionExplanations = "distortion_explanations"
        case reframingSuggestions = "reframing_suggestions"
        case validationStatement = "validation_statement"
        case copingStrategies = "coping_strategies"
    }
}

/// Database representation of thought record
struct DBThoughtRecord: Codable {
    let id: UUID
    let userId: UUID
    let enrollmentId: UUID?
    let programDayNumber: Int?
    let situation: String
    let automaticThought: String
    let emotions: [EmotionEntry]
    let evidenceFor: String?
    let evidenceAgainst: String?
    let balancedThought: String?
    let newEmotionIntensity: Int?
    let cognitiveDistortions: [String]
    let aiAnalysis: AIThoughtAnalysis?
    let aiAnalysisRequestedAt: Date?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, situation, emotions
        case userId = "user_id"
        case enrollmentId = "enrollment_id"
        case programDayNumber = "program_day_number"
        case automaticThought = "automatic_thought"
        case evidenceFor = "evidence_for"
        case evidenceAgainst = "evidence_against"
        case balancedThought = "balanced_thought"
        case newEmotionIntensity = "new_emotion_intensity"
        case cognitiveDistortions = "cognitive_distortions"
        case aiAnalysis = "ai_analysis"
        case aiAnalysisRequestedAt = "ai_analysis_requested_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func toThoughtRecord() -> ThoughtRecord {
        ThoughtRecord(
            id: id.uuidString,
            userId: userId.uuidString,
            enrollmentId: enrollmentId?.uuidString,
            programDayNumber: programDayNumber,
            situation: situation,
            automaticThought: automaticThought,
            emotions: emotions,
            evidenceFor: evidenceFor,
            evidenceAgainst: evidenceAgainst,
            balancedThought: balancedThought,
            newEmotionIntensity: newEmotionIntensity,
            cognitiveDistortions: cognitiveDistortions.compactMap { CognitiveDistortionType(rawValue: $0) },
            aiAnalysis: aiAnalysis,
            aiAnalysisRequestedAt: aiAnalysisRequestedAt,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: - Emotion Regulation (DBT)

/// An emotion regulation log entry for DBT programs
struct EmotionRegulationLog: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let enrollmentId: String?
    let programDayNumber: Int?

    let triggerEvent: String
    let emotionsBefore: [EmotionEntry]
    let bodyLocation: String?
    let urgeAction: String?
    let skillUsed: String
    let skillCategory: DBTSkillCategory
    let emotionsAfter: [EmotionEntry]
    let effectivenessRating: Int // 1-5
    let reflectionNotes: String?

    let createdAt: Date

    /// Improvement in primary emotion intensity
    var emotionImprovement: Int? {
        guard let before = emotionsBefore.first, let after = emotionsAfter.first else { return nil }
        return before.intensity - after.intensity
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case enrollmentId = "enrollment_id"
        case programDayNumber = "program_day_number"
        case triggerEvent = "trigger_event"
        case emotionsBefore = "emotions_before"
        case bodyLocation = "body_location"
        case urgeAction = "urge_action"
        case skillUsed = "skill_used"
        case skillCategory = "skill_category"
        case emotionsAfter = "emotions_after"
        case effectivenessRating = "effectiveness_rating"
        case reflectionNotes = "reflection_notes"
        case createdAt = "created_at"
    }
}

/// DBT skill categories
enum DBTSkillCategory: String, Codable, CaseIterable {
    case mindfulness
    case distressTolerance = "distress_tolerance"
    case emotionRegulation = "emotion_regulation"
    case interpersonalEffectiveness = "interpersonal_effectiveness"

    var displayName: String {
        switch self {
        case .mindfulness: return "Mindfulness"
        case .distressTolerance: return "Distress Tolerance"
        case .emotionRegulation: return "Emotion Regulation"
        case .interpersonalEffectiveness: return "Interpersonal Effectiveness"
        }
    }

    var icon: String {
        switch self {
        case .mindfulness: return "brain.head.profile"
        case .distressTolerance: return "shield"
        case .emotionRegulation: return "heart.text.square"
        case .interpersonalEffectiveness: return "person.2"
        }
    }

    var color: Color {
        switch self {
        case .mindfulness: return .cyan
        case .distressTolerance: return .orange
        case .emotionRegulation: return .purple
        case .interpersonalEffectiveness: return .green
        }
    }

    /// Common skills in this category
    var skills: [String] {
        switch self {
        case .mindfulness:
            return ["Observe", "Describe", "Participate", "Non-judgmental Stance", "One-Mindfulness", "Effectiveness"]
        case .distressTolerance:
            return ["TIPP", "STOP", "Pros and Cons", "IMPROVE the Moment", "Radical Acceptance", "Self-Soothe", "Distraction"]
        case .emotionRegulation:
            return ["ABC PLEASE", "Check the Facts", "Opposite Action", "Problem Solving", "Accumulate Positives", "Build Mastery"]
        case .interpersonalEffectiveness:
            return ["DEAR MAN", "GIVE", "FAST", "Validate", "Set Boundaries"]
        }
    }
}

/// Database representation of emotion regulation log
struct DBEmotionRegulationLog: Codable {
    let id: UUID
    let userId: UUID
    let enrollmentId: UUID?
    let programDayNumber: Int?
    let triggerEvent: String
    let emotionsBefore: [EmotionEntry]
    let bodyLocation: String?
    let urgeAction: String?
    let skillUsed: String
    let skillCategory: String
    let emotionsAfter: [EmotionEntry]
    let effectivenessRating: Int
    let reflectionNotes: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case enrollmentId = "enrollment_id"
        case programDayNumber = "program_day_number"
        case triggerEvent = "trigger_event"
        case emotionsBefore = "emotions_before"
        case bodyLocation = "body_location"
        case urgeAction = "urge_action"
        case skillUsed = "skill_used"
        case skillCategory = "skill_category"
        case emotionsAfter = "emotions_after"
        case effectivenessRating = "effectiveness_rating"
        case reflectionNotes = "reflection_notes"
        case createdAt = "created_at"
    }

    func toEmotionRegulationLog() -> EmotionRegulationLog {
        EmotionRegulationLog(
            id: id.uuidString,
            userId: userId.uuidString,
            enrollmentId: enrollmentId?.uuidString,
            programDayNumber: programDayNumber,
            triggerEvent: triggerEvent,
            emotionsBefore: emotionsBefore,
            bodyLocation: bodyLocation,
            urgeAction: urgeAction,
            skillUsed: skillUsed,
            skillCategory: DBTSkillCategory(rawValue: skillCategory) ?? .mindfulness,
            emotionsAfter: emotionsAfter,
            effectivenessRating: effectivenessRating,
            reflectionNotes: reflectionNotes,
            createdAt: createdAt
        )
    }
}

// MARK: - Values Assessment (ACT)

/// A values assessment entry for ACT programs
struct ValuesAssessment: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let enrollmentId: String?
    let programDayNumber: Int?

    let valueDomain: ValueDomain
    let valueStatement: String
    let importanceRating: Int // 1-10
    let currentAlignmentRating: Int // 1-10
    let barriers: [String]
    let committedActions: [String]
    let reflectionNotes: String?

    let createdAt: Date
    let updatedAt: Date

    /// Gap between importance and current alignment
    var alignmentGap: Int {
        importanceRating - currentAlignmentRating
    }

    /// Whether there's a significant values gap (>3 points)
    var hasSignificantGap: Bool {
        alignmentGap > 3
    }

    enum CodingKeys: String, CodingKey {
        case id, barriers
        case userId = "user_id"
        case enrollmentId = "enrollment_id"
        case programDayNumber = "program_day_number"
        case valueDomain = "value_domain"
        case valueStatement = "value_statement"
        case importanceRating = "importance_rating"
        case currentAlignmentRating = "current_alignment_rating"
        case committedActions = "committed_actions"
        case reflectionNotes = "reflection_notes"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// ACT value domains
/// Life domains for ACT values assessments - matches SQL CHECK constraint
enum ValueDomain: String, Codable, CaseIterable {
    case family = "family"
    case relationships = "relationships"
    case parenting = "parenting"
    case friendships = "friendships"
    case work = "work"
    case education = "education"
    case recreation = "recreation"
    case spirituality = "spirituality"
    case citizenship = "citizenship"
    case health = "health"

    var displayName: String {
        switch self {
        case .family: return "Family"
        case .relationships: return "Intimate Relationships"
        case .parenting: return "Parenting"
        case .friendships: return "Friendships"
        case .work: return "Work & Career"
        case .education: return "Education & Growth"
        case .recreation: return "Recreation & Leisure"
        case .health: return "Health & Wellbeing"
        case .spirituality: return "Spirituality"
        case .citizenship: return "Citizenship & Community"
        }
    }

    var icon: String {
        switch self {
        case .family: return "house.fill"
        case .relationships: return "heart.fill"
        case .parenting: return "figure.and.child.holdinghands"
        case .friendships: return "person.2.fill"
        case .work: return "briefcase.fill"
        case .education: return "book.fill"
        case .recreation: return "figure.hiking"
        case .health: return "heart.text.square.fill"
        case .spirituality: return "sparkles"
        case .citizenship: return "person.3.fill"
        }
    }

    var promptQuestion: String {
        switch self {
        case .family:
            return "What kind of family member do you want to be? What qualities do you value in family relationships?"
        case .relationships:
            return "What kind of partner do you want to be? What matters most in your close relationships?"
        case .parenting:
            return "What kind of parent do you want to be? What values do you want to instill in your children?"
        case .friendships:
            return "What kind of friend do you want to be? What qualities do you value in friendships?"
        case .work:
            return "What kind of work is meaningful to you? What do you want to contribute through your career?"
        case .education:
            return "What do you want to learn or develop? How do you want to grow as a person?"
        case .recreation:
            return "How do you want to play and enjoy life? What brings you joy and renewal?"
        case .health:
            return "How do you want to care for your body and mind? What does wellbeing mean to you?"
        case .spirituality:
            return "What gives your life meaning? What connects you to something larger?"
        case .citizenship:
            return "How do you want to contribute to your community? What role do you want to play in society?"
        }
    }
}

/// Database representation of values assessment
struct DBValuesAssessment: Codable {
    let id: UUID
    let userId: UUID
    let enrollmentId: UUID?
    let programDayNumber: Int?
    let valueDomain: String
    let valueStatement: String
    let importanceRating: Int
    let currentAlignmentRating: Int
    let barriers: [String]
    let committedActions: [String]
    let reflectionNotes: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, barriers
        case userId = "user_id"
        case enrollmentId = "enrollment_id"
        case programDayNumber = "program_day_number"
        case valueDomain = "value_domain"
        case valueStatement = "value_statement"
        case importanceRating = "importance_rating"
        case currentAlignmentRating = "current_alignment_rating"
        case committedActions = "committed_actions"
        case reflectionNotes = "reflection_notes"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func toValuesAssessment() -> ValuesAssessment {
        ValuesAssessment(
            id: id.uuidString,
            userId: userId.uuidString,
            enrollmentId: enrollmentId?.uuidString,
            programDayNumber: programDayNumber,
            valueDomain: ValueDomain(rawValue: valueDomain) ?? .health,
            valueStatement: valueStatement,
            importanceRating: importanceRating,
            currentAlignmentRating: currentAlignmentRating,
            barriers: barriers,
            committedActions: committedActions,
            reflectionNotes: reflectionNotes,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: - Module Unlock Status

/// Status of a therapeutic program module/week
struct ModuleUnlockStatus: Codable, Equatable {
    let weekNumber: Int
    let isUnlocked: Bool
    let unlockDate: Date?
    let daysUntilUnlock: Int?
    let isTherapeutic: Bool

    enum CodingKeys: String, CodingKey {
        case weekNumber = "week_number"
        case isUnlocked = "is_unlocked"
        case unlockDate = "unlock_date"
        case daysUntilUnlock = "days_until_unlock"
        case isTherapeutic = "is_therapeutic"
    }
}

// MARK: - Therapeutic Progress Summary

/// Summary of progress in a therapeutic program
struct TherapeuticProgressSummary: Codable, Equatable {
    let enrollmentId: String
    let programTitle: String
    let methodology: String // Raw value of TherapeuticMethodology
    let currentWeek: Int
    let totalWeeks: Int
    let assessmentsCompleted: Int
    let thoughtRecordsCompleted: Int
    let skillsLogged: Int
    let valuesExplored: Int
    let overallProgress: Double // 0.0-1.0
    let latestAssessmentScore: Int?
    let latestAssessmentSeverity: String? // Raw value of AssessmentSeverity
    let scoreImprovement: Int? // Compared to baseline

    enum CodingKeys: String, CodingKey {
        case methodology
        case enrollmentId = "enrollment_id"
        case programTitle = "program_title"
        case currentWeek = "current_week"
        case totalWeeks = "total_weeks"
        case assessmentsCompleted = "assessments_completed"
        case thoughtRecordsCompleted = "thought_records_completed"
        case skillsLogged = "skills_logged"
        case valuesExplored = "values_explored"
        case overallProgress = "overall_progress"
        case latestAssessmentScore = "latest_assessment_score"
        case latestAssessmentSeverity = "latest_assessment_severity"
        case scoreImprovement = "score_improvement"
    }
}
