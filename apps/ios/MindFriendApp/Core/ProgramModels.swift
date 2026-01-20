import Foundation
import SwiftUI

// MARK: - Program Category

/// Categories for structured wellness programs
enum ProgramCategory: String, Codable, CaseIterable {
    case anxiety
    case sleep
    case focus
    case stress
    case mindfulness
    case gratitude
    case intro
    case custom

    var displayName: String {
        switch self {
        case .anxiety: return "Anxiety"
        case .sleep: return "Sleep"
        case .focus: return "Focus"
        case .stress: return "Stress"
        case .mindfulness: return "Mindfulness"
        case .gratitude: return "Gratitude"
        case .intro: return "Getting Started"
        case .custom: return "Custom"
        }
    }

    var icon: String {
        switch self {
        case .anxiety: return "heart.text.square"
        case .sleep: return "moon.zzz"
        case .focus: return "scope"
        case .stress: return "waveform.path.ecg"
        case .mindfulness: return "brain.head.profile"
        case .gratitude: return "heart"
        case .intro: return "star"
        case .custom: return "square.grid.2x2"
        }
    }

    var color: Color {
        switch self {
        case .anxiety: return .purple
        case .sleep: return .indigo
        case .focus: return .orange
        case .stress: return .red
        case .mindfulness: return .cyan
        case .gratitude: return .pink
        case .intro: return .blue
        case .custom: return .gray
        }
    }
}

// MARK: - Therapeutic Methodology

/// Therapeutic methodology for evidence-based programs
enum TherapeuticMethodology: String, Codable, CaseIterable {
    case cbt = "cbt"
    case dbt = "dbt"
    case act = "act"
    case mbct = "mbct"
    case mixed = "mixed"
    
    var displayName: String {
        switch self {
        case .cbt: return "Cognitive Behavioral Therapy"
        case .dbt: return "Dialectical Behavior Therapy"
        case .act: return "Acceptance & Commitment Therapy"
        case .mbct: return "Mindfulness-Based Cognitive Therapy"
        case .mixed: return "Integrated Approach"
        }
    }
    
    var shortName: String {
        rawValue.uppercased()
    }
    
    var icon: String {
        switch self {
        case .cbt: return "brain.head.profile"
        case .dbt: return "heart.circle"
        case .act: return "arrow.right.circle"
        case .mbct: return "leaf"
        case .mixed: return "squares.leading.rectangle"
        }
    }
    
    var color: Color {
        switch self {
        case .cbt: return .blue
        case .dbt: return .purple
        case .act: return .green
        case .mbct: return .teal
        case .mixed: return .indigo
        }
    }
}

// MARK: - Program Difficulty

/// Difficulty levels for programs
enum ProgramDifficulty: String, Codable {
    case beginner
    case intermediate
    case advanced

    var displayName: String {
        rawValue.capitalized
    }
}

// MARK: - Program

/// A structured wellness program definition
struct Program: Codable, Identifiable, Equatable {
    let id: String
    let slug: String
    let title: String
    let description: String
    let durationDays: Int
    let category: ProgramCategory
    let difficulty: ProgramDifficulty
    let premiumOnly: Bool
    let learningObjectives: [String]
    let tags: [String]
    let coverImageUrl: String?
    let estimatedDailyMinutes: Int
    let sortOrder: Int
    
    // Therapeutic program fields (nil for general wellness programs)
    let methodology: TherapeuticMethodology?
    let evidenceSummary: String?
    let evidenceUrl: String?
    let targetConditions: [String]
    let requiresBaselineAssessment: Bool
    let assessmentType: String?

    var isTherapeutic: Bool {
        methodology != nil
    }

    var formattedDuration: String {
        if durationDays == 7 { return "1 week" }
        if durationDays == 14 { return "2 weeks" }
        if durationDays == 21 { return "3 weeks" }
        if durationDays == 30 { return "1 month" }
        return "\(durationDays) days"
    }

    var totalEstimatedMinutes: Int {
        durationDays * estimatedDailyMinutes
    }

    enum CodingKeys: String, CodingKey {
        case id, slug, title, description, tags, category, difficulty, methodology
        case durationDays = "duration_days"
        case premiumOnly = "premium_only"
        case learningObjectives = "learning_objectives"
        case coverImageUrl = "cover_image_url"
        case estimatedDailyMinutes = "estimated_daily_minutes"
        case sortOrder = "sort_order"
        case evidenceSummary = "evidence_summary"
        case evidenceUrl = "evidence_url"
        case targetConditions = "target_conditions"
        case requiresBaselineAssessment = "requires_baseline_assessment"
        case assessmentType = "assessment_type"
    }
}

// MARK: - Program Day Content Type

/// Types of content within a program day
enum ProgramContentType: String, Codable {
    case learn
    case practice
    case reflect
    case apply
    case checkIn = "check_in"

    var icon: String {
        switch self {
        case .learn: return "book"
        case .practice: return "figure.mind.and.body"
        case .reflect: return "pencil.and.outline"
        case .apply: return "checkmark.circle"
        case .checkIn: return "face.smiling"
        }
    }

    var displayName: String {
        switch self {
        case .learn: return "Learn"
        case .practice: return "Practice"
        case .reflect: return "Reflect"
        case .apply: return "Apply"
        case .checkIn: return "Check-In"
        }
    }
}

// MARK: - Program Day Content

/// A single content block within a program day
struct ProgramDayContent: Codable, Identifiable, Equatable {
    /// Stable ID computed from content properties - never generates random UUIDs
    var id: String {
        // Create a deterministic identifier from stable properties
        let components = [
            type.rawValue,
            title ?? "",
            exerciseId ?? "",
            prompt ?? "",
            challenge ?? "",
            String(body?.prefix(30) ?? "")
        ]
        return components.joined(separator: "-")
    }
    let type: ProgramContentType
    let title: String?
    let body: String?
    let exerciseId: String?
    let intro: String?
    let prompt: String?
    let minWords: Int?
    let challenge: String?
    let reportBack: Bool?
    let durationMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case type, title, body, intro, prompt, challenge
        case exerciseId = "exercise_id"
        case minWords = "min_words"
        case reportBack = "report_back"
        case durationMinutes = "duration_minutes"
    }
}

// MARK: - Completion Criteria

/// Criteria for completing a program day
struct CompletionCriteria: Codable, Equatable {
    let required: [String]
    let optional: [String]
}

// MARK: - Program Day

/// A single day within a program
struct ProgramDay: Codable, Identifiable, Equatable {
    let id: String
    let programId: String
    let dayNumber: Int
    let title: String
    let theme: String?
    let content: [ProgramDayContent]
    let completionCriteria: CompletionCriteria
    let isRestDay: Bool

    var estimatedMinutes: Int {
        content.reduce(0) { $0 + ($1.durationMinutes ?? 5) }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, theme, content
        case programId = "program_id"
        case dayNumber = "day_number"
        case completionCriteria = "completion_criteria"
        case isRestDay = "is_rest_day"
    }
}

// MARK: - Enrollment Status

/// Status of a program enrollment
enum EnrollmentStatus: String, Codable {
    case active
    case paused
    case completed
    case abandoned

    var displayName: String {
        rawValue.capitalized
    }

    var color: Color {
        switch self {
        case .active: return .green
        case .paused: return .orange
        case .completed: return .blue
        case .abandoned: return .gray
        }
    }
}

// MARK: - Program Enrollment

/// A user's enrollment in a program
struct ProgramEnrollment: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let programId: String
    var status: EnrollmentStatus
    let startedAt: Date
    var currentDay: Int
    var pausedAt: Date?
    var completedAt: Date?
    var preferredTimeLocal: String
    var skipsUsed: Int
    let skipsAllowed: Int
    var streakDays: Int
    var longestStreak: Int

    // Joined data (optional)
    var program: Program?
    var dayProgress: [ProgramDayProgress]?

    var progressPercentage: Double {
        guard let program = program else { return 0 }
        let completed = dayProgress?.filter { $0.status == .completed }.count ?? 0
        return Double(completed) / Double(program.durationDays)
    }

    var daysRemaining: Int {
        guard let program = program else { return 0 }
        return max(0, program.durationDays - currentDay + 1)
    }

    var canSkip: Bool {
        skipsUsed < skipsAllowed
    }

    var skipsRemaining: Int {
        skipsAllowed - skipsUsed
    }

    enum CodingKeys: String, CodingKey {
        case id, status, program
        case userId = "user_id"
        case programId = "program_id"
        case startedAt = "started_at"
        case currentDay = "current_day"
        case pausedAt = "paused_at"
        case completedAt = "completed_at"
        case preferredTimeLocal = "preferred_time_local"
        case skipsUsed = "skips_used"
        case skipsAllowed = "skips_allowed"
        case streakDays = "streak_days"
        case longestStreak = "longest_streak"
        case dayProgress = "day_progress"
    }
}

// MARK: - Day Progress Status

/// Status of a single day's progress
enum DayProgressStatus: String, Codable {
    case pending
    case inProgress = "in_progress"
    case completed
    case skipped
}

// MARK: - Program Day Progress

/// Progress on a single day within an enrollment
struct ProgramDayProgress: Codable, Identifiable, Equatable {
    let id: String
    let enrollmentId: String
    let dayNumber: Int
    var status: DayProgressStatus
    var startedAt: Date?
    var completedAt: Date?
    var contentCompleted: [String: Bool]
    var reflectionResponse: String?
    var applyReport: String?
    var exerciseSessionId: String?
    var moodBefore: Int?
    var moodAfter: Int?

    enum CodingKeys: String, CodingKey {
        case id, status
        case enrollmentId = "enrollment_id"
        case dayNumber = "day_number"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case contentCompleted = "content_completed"
        case reflectionResponse = "reflection_response"
        case applyReport = "apply_report"
        case exerciseSessionId = "exercise_session_id"
        case moodBefore = "mood_before"
        case moodAfter = "mood_after"
    }
}

// MARK: - Completion Stats

/// Statistics about a program completion
struct ProgramCompletionStats: Codable, Equatable {
    let daysCompleted: Int
    let streakBest: Int
    let skipsUsed: Int
    let programTitle: String?

    enum CodingKeys: String, CodingKey {
        case daysCompleted = "days_completed"
        case streakBest = "streak_best"
        case skipsUsed = "skips_used"
        case programTitle = "program_title"
    }
}

// MARK: - Program Certificate

/// A certificate issued upon program completion
struct ProgramCertificate: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let programId: String
    let enrollmentId: String
    let certificateNumber: String
    let completionStats: ProgramCompletionStats
    let issuedAt: Date
    var sharedToCircle: Bool
    var sharedExternally: Bool

    // Joined data
    var program: Program?

    enum CodingKeys: String, CodingKey {
        case id, program
        case userId = "user_id"
        case programId = "program_id"
        case enrollmentId = "enrollment_id"
        case certificateNumber = "certificate_number"
        case completionStats = "completion_stats"
        case issuedAt = "issued_at"
        case sharedToCircle = "shared_to_circle"
        case sharedExternally = "shared_externally"
    }
}

// MARK: - Complete Program Day Result

/// Result from completing a program day
struct CompleteProgramDayResult: Codable {
    let dayCompleted: Int
    let programComplete: Bool
    let nextDay: Int?
    let streak: Int
    let certificateNumber: String?

    enum CodingKeys: String, CodingKey {
        case dayCompleted = "day_completed"
        case programComplete = "program_complete"
        case nextDay = "next_day"
        case streak
        case certificateNumber = "certificate_number"
    }
}

// MARK: - Skip Program Day Result

/// Result from skipping a program day
struct SkipProgramDayResult: Codable {
    let daySkipped: Int
    let skipsRemaining: Int
    let nextDay: Int

    enum CodingKeys: String, CodingKey {
        case daySkipped = "day_skipped"
        case skipsRemaining = "skips_remaining"
        case nextDay = "next_day"
    }
}

// MARK: - Program Stats

/// User's overall program statistics
struct UserProgramStats: Codable {
    let programsCompleted: Int
    let programsActive: Int
    let programsPaused: Int
    let totalDaysCompleted: Int
    let certificatesEarned: Int

    enum CodingKeys: String, CodingKey {
        case programsCompleted = "programs_completed"
        case programsActive = "programs_active"
        case programsPaused = "programs_paused"
        case totalDaysCompleted = "total_days_completed"
        case certificatesEarned = "certificates_earned"
    }
}

// MARK: - DB Types (for Supabase mapping)

/// Database representation of a program (for Supabase queries)
struct DBProgram: Codable {
    let id: UUID
    let slug: String
    let title: String
    let description: String
    let durationDays: Int
    let category: String
    let difficulty: String
    let premiumOnly: Bool
    let learningObjectives: [String]
    let tags: [String]
    let coverImageUrl: String?
    let estimatedDailyMinutes: Int
    let sortOrder: Int
    
    // Therapeutic program fields
    let methodology: String?
    let evidenceSummary: String?
    let evidenceUrl: String?
    let targetConditions: [String]?
    let requiresBaselineAssessment: Bool?
    let assessmentType: String?

    enum CodingKeys: String, CodingKey {
        case id, slug, title, description, category, difficulty, tags, methodology
        case durationDays = "duration_days"
        case premiumOnly = "premium_only"
        case learningObjectives = "learning_objectives"
        case coverImageUrl = "cover_image_url"
        case estimatedDailyMinutes = "estimated_daily_minutes"
        case sortOrder = "sort_order"
        case evidenceSummary = "evidence_summary"
        case evidenceUrl = "evidence_url"
        case targetConditions = "target_conditions"
        case requiresBaselineAssessment = "requires_baseline_assessment"
        case assessmentType = "assessment_type"
    }

    func toProgram() -> Program {
        Program(
            id: id.uuidString,
            slug: slug,
            title: title,
            description: description,
            durationDays: durationDays,
            category: ProgramCategory(rawValue: category) ?? .custom,
            difficulty: ProgramDifficulty(rawValue: difficulty) ?? .beginner,
            premiumOnly: premiumOnly,
            learningObjectives: learningObjectives,
            tags: tags,
            coverImageUrl: coverImageUrl,
            estimatedDailyMinutes: estimatedDailyMinutes,
            sortOrder: sortOrder,
            methodology: methodology.flatMap { TherapeuticMethodology(rawValue: $0) },
            evidenceSummary: evidenceSummary,
            evidenceUrl: evidenceUrl,
            targetConditions: targetConditions ?? [],
            requiresBaselineAssessment: requiresBaselineAssessment ?? false,
            assessmentType: assessmentType
        )
    }
}

/// Database representation of a program day
struct DBProgramDay: Codable {
    let id: UUID
    let programId: UUID
    let dayNumber: Int
    let title: String
    let theme: String?
    let content: [ProgramDayContent]
    let completionCriteria: CompletionCriteria
    let isRestDay: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, theme, content
        case programId = "program_id"
        case dayNumber = "day_number"
        case completionCriteria = "completion_criteria"
        case isRestDay = "is_rest_day"
    }

    func toProgramDay() -> ProgramDay {
        ProgramDay(
            id: id.uuidString,
            programId: programId.uuidString,
            dayNumber: dayNumber,
            title: title,
            theme: theme,
            content: content,
            completionCriteria: completionCriteria,
            isRestDay: isRestDay
        )
    }
}

/// Database representation of a program enrollment
struct DBProgramEnrollment: Codable {
    let id: UUID
    let userId: UUID
    let programId: UUID
    let status: String
    let startedAt: Date
    let currentDay: Int
    let pausedAt: Date?
    let completedAt: Date?
    let preferredTimeLocal: String
    let skipsUsed: Int
    let skipsAllowed: Int
    let streakDays: Int
    let longestStreak: Int

    // Joined data (from select with programs(*))
    let programs: DBProgram?

    enum CodingKeys: String, CodingKey {
        case id, status, programs
        case userId = "user_id"
        case programId = "program_id"
        case startedAt = "started_at"
        case currentDay = "current_day"
        case pausedAt = "paused_at"
        case completedAt = "completed_at"
        case preferredTimeLocal = "preferred_time_local"
        case skipsUsed = "skips_used"
        case skipsAllowed = "skips_allowed"
        case streakDays = "streak_days"
        case longestStreak = "longest_streak"
    }

    func toEnrollment() -> ProgramEnrollment {
        ProgramEnrollment(
            id: id.uuidString,
            userId: userId.uuidString,
            programId: programId.uuidString,
            status: EnrollmentStatus(rawValue: status) ?? .active,
            startedAt: startedAt,
            currentDay: currentDay,
            pausedAt: pausedAt,
            completedAt: completedAt,
            preferredTimeLocal: preferredTimeLocal,
            skipsUsed: skipsUsed,
            skipsAllowed: skipsAllowed,
            streakDays: streakDays,
            longestStreak: longestStreak,
            program: programs?.toProgram()
        )
    }
}

/// Database representation of program day progress
struct DBProgramDayProgress: Codable {
    let id: UUID
    let enrollmentId: UUID
    let dayNumber: Int
    let status: String
    let startedAt: Date?
    let completedAt: Date?
    let contentCompleted: [String: Bool]
    let reflectionResponse: String?
    let applyReport: String?
    let exerciseSessionId: UUID?
    let moodBefore: Int?
    let moodAfter: Int?

    enum CodingKeys: String, CodingKey {
        case id, status
        case enrollmentId = "enrollment_id"
        case dayNumber = "day_number"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case contentCompleted = "content_completed"
        case reflectionResponse = "reflection_response"
        case applyReport = "apply_report"
        case exerciseSessionId = "exercise_session_id"
        case moodBefore = "mood_before"
        case moodAfter = "mood_after"
    }

    func toDayProgress() -> ProgramDayProgress {
        ProgramDayProgress(
            id: id.uuidString,
            enrollmentId: enrollmentId.uuidString,
            dayNumber: dayNumber,
            status: DayProgressStatus(rawValue: status) ?? .pending,
            startedAt: startedAt,
            completedAt: completedAt,
            contentCompleted: contentCompleted,
            reflectionResponse: reflectionResponse,
            applyReport: applyReport,
            exerciseSessionId: exerciseSessionId?.uuidString,
            moodBefore: moodBefore,
            moodAfter: moodAfter
        )
    }
}

/// Database representation of a program certificate
struct DBProgramCertificate: Codable {
    let id: UUID
    let userId: UUID
    let programId: UUID
    let enrollmentId: UUID
    let certificateNumber: String
    let completionStats: ProgramCompletionStats
    let issuedAt: Date
    let sharedToCircle: Bool
    let sharedExternally: Bool

    // Joined data
    let programs: DBProgram?

    enum CodingKeys: String, CodingKey {
        case id, programs
        case userId = "user_id"
        case programId = "program_id"
        case enrollmentId = "enrollment_id"
        case certificateNumber = "certificate_number"
        case completionStats = "completion_stats"
        case issuedAt = "issued_at"
        case sharedToCircle = "shared_to_circle"
        case sharedExternally = "shared_externally"
    }

    func toCertificate() -> ProgramCertificate {
        ProgramCertificate(
            id: id.uuidString,
            userId: userId.uuidString,
            programId: programId.uuidString,
            enrollmentId: enrollmentId.uuidString,
            certificateNumber: certificateNumber,
            completionStats: completionStats,
            issuedAt: issuedAt,
            sharedToCircle: sharedToCircle,
            sharedExternally: sharedExternally,
            program: programs?.toProgram()
        )
    }
}
