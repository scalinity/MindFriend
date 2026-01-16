import Foundation
import SwiftUI

// MARK: - Micro-Moment Type

/// Types of micro-moment exercises
enum MicroMomentType: String, Codable, CaseIterable {
    case breathing
    case checkIn = "check_in"
    case grounding
    case movement
    case transition
    case gratitude

    var displayName: String {
        switch self {
        case .breathing: return "Breathing"
        case .checkIn: return "Check-In"
        case .grounding: return "Grounding"
        case .movement: return "Movement"
        case .transition: return "Transition"
        case .gratitude: return "Gratitude"
        }
    }

    var icon: String {
        switch self {
        case .breathing: return "wind"
        case .checkIn: return "checkmark.circle"
        case .grounding: return "leaf"
        case .movement: return "figure.walk"
        case .transition: return "arrow.triangle.swap"
        case .gratitude: return "heart"
        }
    }

    var color: Color {
        switch self {
        case .breathing: return .blue
        case .checkIn: return .green
        case .grounding: return .teal
        case .movement: return .orange
        case .transition: return .purple
        case .gratitude: return .pink
        }
    }
}

// MARK: - Check-In Type

/// Types of quick check-ins
enum CheckInType: String, Codable, CaseIterable {
    case mood
    case energy
    case gratitude
    case intention
    case stressLevel = "stress_level"

    var displayName: String {
        switch self {
        case .mood: return "Mood"
        case .energy: return "Energy"
        case .gratitude: return "Gratitude"
        case .intention: return "Intention"
        case .stressLevel: return "Stress Level"
        }
    }

    var icon: String {
        switch self {
        case .mood: return "face.smiling"
        case .energy: return "bolt"
        case .gratitude: return "heart"
        case .intention: return "target"
        case .stressLevel: return "waveform.path.ecg"
        }
    }
}

// MARK: - Trigger Source

/// How a micro-moment was triggered
enum TriggerSource: String, Codable {
    case manual
    case notification
    case widget
    case siri
    case watch
    case suggestion
}

// MARK: - Energy Effect

/// The energy effect of a micro-moment
enum EnergyEffect: String, Codable {
    case calming
    case energizing
    case neutral

    var displayName: String {
        rawValue.capitalized
    }
}

// MARK: - Animation Type

/// Animation types for micro-moment exercises
enum AnimationType: String, Codable {
    case breathingCircle = "breathing_circle"
    case bodyScan = "body_scan"
    case countdown
    case pulse
    case wave
}

// MARK: - Instruction Action

/// Actions within exercise instructions
enum InstructionAction: String, Codable {
    case inhale
    case exhale
    case hold
    case observe
    case move
    case speak
    case tap
}

// MARK: - Micro Instruction

/// A single instruction step within a micro-moment
struct MicroInstruction: Codable, Equatable {
    let id: String
    let step: Int
    let text: String
    let durationSeconds: Int
    let action: InstructionAction?

    enum CodingKeys: String, CodingKey {
        case id, step, text, action
        case durationSeconds = "duration_seconds"
    }
}

// MARK: - Haptic Pattern

/// Haptic feedback pattern for exercises
struct HapticPattern: Codable, Equatable {
    let events: [HapticEvent]
}

/// A single haptic event
struct HapticEvent: Codable, Equatable {
    let time: Double
    let type: String
    let intensity: Double?
}

// MARK: - Micro-Moment Template

/// A micro-moment exercise template from the database
struct MicroMomentTemplate: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let slug: String
    let type: MicroMomentType
    let title: String
    let description: String?
    let durationSeconds: Int
    let instructions: [MicroInstruction]
    let animationType: AnimationType?
    let audioUrl: String?
    let hapticPattern: HapticPattern?
    let suggestedContexts: [String]?
    let energyEffect: EnergyEffect?
    let isPremium: Bool
    let isActive: Bool
    let sortOrder: Int
    let createdAt: String
    let updatedAt: String

    var formattedDuration: String {
        if durationSeconds < 60 {
            return "\(durationSeconds)s"
        } else {
            let minutes = durationSeconds / 60
            let seconds = durationSeconds % 60
            if seconds == 0 {
                return "\(minutes)m"
            }
            return "\(minutes)m \(seconds)s"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, name, slug, type, title, description, instructions
        case durationSeconds = "duration_seconds"
        case animationType = "animation_type"
        case audioUrl = "audio_url"
        case hapticPattern = "haptic_pattern"
        case suggestedContexts = "suggested_contexts"
        case energyEffect = "energy_effect"
        case isPremium = "is_premium"
        case isActive = "is_active"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Micro-Moment Completion

/// A completed micro-moment exercise
struct MicroMomentCompletion: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let templateId: String
    let triggerSource: TriggerSource?
    let context: String?
    let startedAt: String
    let completedAt: String?
    let durationActualSeconds: Int?
    let completed: Bool
    let feltHelpful: Bool?
    let createdAt: String

    // Joined template data (populated when fetching with relations)
    var template: MicroMomentTemplate?

    enum CodingKeys: String, CodingKey {
        case id, context, completed
        case userId = "user_id"
        case templateId = "template_id"
        case triggerSource = "trigger_source"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case durationActualSeconds = "duration_actual_seconds"
        case feltHelpful = "felt_helpful"
        case createdAt = "created_at"
        case template
    }

    var createdDate: Date {
        ISO8601DateFormatter().date(from: createdAt) ?? Date()
    }
}

// MARK: - Quick Check-In

/// A quick check-in entry (mood, energy, gratitude, etc.)
struct QuickCheckIn: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let type: CheckInType
    let valueNumeric: Int?
    let valueEmoji: String?
    let valueText: String?
    let contextTags: [String]?
    let source: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, type, source
        case userId = "user_id"
        case valueNumeric = "value_numeric"
        case valueEmoji = "value_emoji"
        case valueText = "value_text"
        case contextTags = "context_tags"
        case createdAt = "created_at"
    }

    var createdDate: Date {
        ISO8601DateFormatter().date(from: createdAt) ?? Date()
    }
}

// MARK: - Micro Streak

/// User's micro-moment streak and statistics
struct MicroStreak: Codable, Identifiable, Equatable {
    let id: String
    let userId: String
    let currentStreak: Int
    let longestStreak: Int
    let lastMicroDate: String?
    let totalMicroMoments: Int
    let totalCheckIns: Int
    let totalSecondsPracticed: Int
    let achievementsUnlocked: [String]?
    let createdAt: String
    let updatedAt: String

    var totalMinutesPracticed: Int {
        totalSecondsPracticed / 60
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case currentStreak = "current_streak"
        case longestStreak = "longest_streak"
        case lastMicroDate = "last_micro_date"
        case totalMicroMoments = "total_micro_moments"
        case totalCheckIns = "total_check_ins"
        case totalSecondsPracticed = "total_seconds_practiced"
        case achievementsUnlocked = "achievements_unlocked"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Micro Delivery Preferences

/// User preferences for micro-moment suggestions and notifications
struct MicroDeliveryPreferences: Codable, Equatable {
    var morningCheckinEnabled: Bool
    var morningCheckinTime: String?
    var eveningCheckinEnabled: Bool
    var eveningCheckinTime: String?
    var preMeetingReminder: Bool
    var preMeetingMinutes: Int
    var postMeetingSuggestion: Bool
    var maxSuggestionsPerDay: Int
    var minHoursBetweenSuggestions: Double
    var preferredTypes: [MicroMomentType]?
    var preferredDurations: [Int]?
    var silentModeOnly: Bool

    enum CodingKeys: String, CodingKey {
        case morningCheckinEnabled = "morning_checkin_enabled"
        case morningCheckinTime = "morning_checkin_time"
        case eveningCheckinEnabled = "evening_checkin_enabled"
        case eveningCheckinTime = "evening_checkin_time"
        case preMeetingReminder = "pre_meeting_reminder"
        case preMeetingMinutes = "pre_meeting_minutes"
        case postMeetingSuggestion = "post_meeting_suggestion"
        case maxSuggestionsPerDay = "max_suggestions_per_day"
        case minHoursBetweenSuggestions = "min_hours_between_suggestions"
        case preferredTypes = "preferred_types"
        case preferredDurations = "preferred_durations"
        case silentModeOnly = "silent_mode_only"
    }

    static var `default`: MicroDeliveryPreferences {
        MicroDeliveryPreferences(
            morningCheckinEnabled: true,
            morningCheckinTime: "08:00",
            eveningCheckinEnabled: true,
            eveningCheckinTime: "20:00",
            preMeetingReminder: false,
            preMeetingMinutes: 5,
            postMeetingSuggestion: false,
            maxSuggestionsPerDay: 5,
            minHoursBetweenSuggestions: 2.0,
            preferredTypes: nil,
            preferredDurations: nil,
            silentModeOnly: false
        )
    }
}

// MARK: - API Response Types

/// Response from the get-micro-suggestions edge function
struct MicroSuggestionResponse: Codable {
    let suggestions: [MicroMomentTemplate]
    let context: String?
    let preferences: SuggestionPreferences
}

/// Preferences returned with suggestions
struct SuggestionPreferences: Codable {
    let maxDuration: Int
    let silentMode: Bool
    let isPremium: Bool?
}

/// Response from the complete-micro-moment edge function
struct MicroCompletionResponse: Codable {
    let completion: CompletionInfo
    let streak: StreakInfo
    let newAchievements: [String]
}

/// Completion info from API response
struct CompletionInfo: Codable {
    let id: String
    let templateId: String
    let completed: Bool
    let createdAt: String
}

/// Streak info from API response
struct StreakInfo: Codable {
    let currentStreak: Int
    let longestStreak: Int
    let lastMicroDate: String?
    let totalMicroMoments: Int
    let totalCheckIns: Int
    let totalSecondsPracticed: Int
    let achievementsUnlocked: [String]
}

// MARK: - Local Data Types

/// Data for recording a micro-moment completion
struct MicroCompletionData {
    let templateId: String
    let triggerSource: TriggerSource
    let context: String?
    let startedAt: Date
    let completedAt: Date
    let durationActualSeconds: Int
    let feltHelpful: Bool?
}

/// Data for saving a quick check-in
struct QuickCheckInData {
    let type: CheckInType
    let valueNumeric: Int?
    let valueEmoji: String?
    let valueText: String?
    let contextTags: [String]
}

// MARK: - Check-In Trend

/// Trend data for mood/energy over time
struct CheckInTrend: Identifiable, Equatable {
    let date: String
    let moodAverage: Double?
    let energyAverage: Double?
    let count: Int

    var id: String { date }

    var dateFormatted: Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: date)
    }
}
