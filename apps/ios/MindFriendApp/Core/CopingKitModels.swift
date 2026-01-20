import Foundation

// MARK: - Coping Kit Context Tag

enum CopingKitContextTag: String, Codable, CaseIterable {
    case anxiety
    case stress
    case sadness
    case sleep
    case focus
    case crisis

    var displayName: String {
        switch self {
        case .anxiety: return "Anxiety"
        case .stress: return "Stress"
        case .sadness: return "Sadness"
        case .sleep: return "Sleep"
        case .focus: return "Focus"
        case .crisis: return "In Crisis"
        }
    }

    var icon: String {
        switch self {
        case .anxiety: return "waveform.path.ecg"
        case .stress: return "bolt.fill"
        case .sadness: return "cloud.rain"
        case .sleep: return "moon.zzz"
        case .focus: return "scope"
        case .crisis: return "lifebuoy"
        }
    }

    var color: String {
        switch self {
        case .anxiety: return "orange"
        case .stress: return "yellow"
        case .sadness: return "blue"
        case .sleep: return "indigo"
        case .focus: return "green"
        case .crisis: return "red"
        }
    }
}

// MARK: - Coping Kit Step Type

enum CopingKitStepType: String, Codable {
    case exercise
    case grounding
    case chatCheckin = "chat_checkin"
    case breathing
}

// MARK: - Breathing Pattern
// See SOSModels.swift for BreathingPattern enum definition

// MARK: - Coping Kit Step

struct CopingKitStep: Codable, Identifiable, Equatable {
    var id: String { prompt }
    let type: CopingKitStepType
    let exerciseType: String?
    let prompt: String
    let durationSeconds: Int?
    let durationCycles: Int?
    let breathingPattern: BreathingPattern?
    let instructions: String?

    enum CodingKeys: String, CodingKey {
        case type
        case exerciseType = "exercise_type"
        case prompt
        case durationSeconds = "duration_seconds"
        case durationCycles = "duration_cycles"
        case breathingPattern = "breathing_pattern"
        case instructions
    }

    /// Duration in seconds, with fallback to 60 seconds if not specified
    var effectiveDurationSeconds: Int {
        durationSeconds ?? 60
    }

    /// Check if this step is a breathing exercise
    var isBreathingExercise: Bool {
        breathingPattern != nil
    }

    /// Get breathing pattern with fallback to box breathing
    var effectiveBreathingPattern: BreathingPattern {
        breathingPattern ?? .boxBreathing
    }
}

// MARK: - Coping Kit

struct CopingKit: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let description: String
    let contextTag: CopingKitContextTag
    let steps: [CopingKitStep]
    let estimatedMinutes: Int
    let isPremium: Bool
    var userState: CopingKitUserState?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case contextTag = "context_tag"
        case steps
        case estimatedMinutes = "estimated_minutes"
        case isPremium = "is_premium"
        case userState = "user_state"
    }

    var stepsCount: Int {
        steps.count
    }

    var formattedDuration: String {
        "\(estimatedMinutes) min"
    }

    var contextIcon: String {
        contextTag.icon
    }
}

// MARK: - Coping Kit User State

struct CopingKitUserState: Codable, Equatable {
    let pinned: Bool
    let lastUsedAt: Date?
    let totalUses: Int
    let hasActiveProgress: Bool

    enum CodingKeys: String, CodingKey {
        case pinned
        case lastUsedAt = "last_used_at"
        case totalUses = "total_uses"
        case hasActiveProgress = "has_active_progress"
    }
}

// MARK: - Kit Progress

struct KitProgress: Codable, Identifiable, Equatable {
    let id: String
    let kitId: String
    let kitTitle: String
    let currentStepIndex: Int
    let totalSteps: Int
    let minutesRemaining: Int
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case kitId = "kit_id"
        case kitTitle = "kit_title"
        case currentStepIndex = "current_step_index"
        case totalSteps = "total_steps"
        case minutesRemaining = "minutes_remaining"
        case expiresAt = "expires_at"
    }

    var progressPercentage: Double {
        guard totalSteps > 0 else { return 0 }
        return Double(currentStepIndex) / Double(totalSteps)
    }

    var isExpired: Bool {
        Date() > expiresAt
    }

    var stepsRemaining: Int {
        max(0, totalSteps - currentStepIndex)
    }
}

// MARK: - Kit Completion Result

struct KitCompletionResult: Codable, Equatable {
    let xpAwarded: Int
    let levelUp: LevelUpInfo?
    let streakIncremented: Bool

    enum CodingKeys: String, CodingKey {
        case xpAwarded = "xp_awarded"
        case levelUp = "level_up"
        case streakIncremented = "streak_incremented"
    }

    struct LevelUpInfo: Codable, Equatable {
        let oldLevel: Int
        let newLevel: Int

        enum CodingKeys: String, CodingKey {
            case oldLevel = "old_level"
            case newLevel = "new_level"
        }
    }
}

// MARK: - Step Complete Result

struct StepCompleteResult: Codable, Equatable {
    let success: Bool
    let nextStepIndex: Int
    let isComplete: Bool
    let exerciseSessionId: String?

    enum CodingKeys: String, CodingKey {
        case success
        case nextStepIndex = "next_step_index"
        case isComplete = "is_complete"
        case exerciseSessionId = "exercise_session_id"
    }
}

// MARK: - API Response Types

struct GetCopingKitsResponse: Codable {
    let kits: [CopingKit]
    let activeProgressKits: [KitProgress]

    enum CodingKeys: String, CodingKey {
        case kits
        case activeProgressKits = "active_progress_kits"
    }
}

// MARK: - Track Request Types

enum CopingKitAction: String, Codable {
    case start
    case stepComplete = "step_complete"
    case complete
    case cancel
}

struct TrackCopingKitRequest: Codable {
    let kitId: String
    let action: CopingKitAction
    let stepIndex: Int?
    let stepResult: [String: String]?
    let feedback: KitFeedbackRequest?

    enum CodingKeys: String, CodingKey {
        case kitId = "kit_id"
        case action
        case stepIndex = "step_index"
        case stepResult = "step_result"
        case feedback
    }
}

struct KitFeedbackRequest: Codable {
    let helpful: Bool
    let comment: String?

    enum CodingKeys: String, CodingKey {
        case helpful
        case comment
    }
}

