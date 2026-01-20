import Foundation
import SwiftUI

// MARK: - Ritual Types

/// The type of ritual ceremony
enum RitualType: String, Codable, CaseIterable, Identifiable {
    case gratitude
    case grounding
    case wins
    case breathing

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gratitude: return "Gratitude"
        case .grounding: return "Grounding"
        case .wins: return "Wins"
        case .breathing: return "Breathing"
        }
    }

    var icon: String {
        switch self {
        case .gratitude: return "heart.fill"
        case .grounding: return "leaf.fill"
        case .wins: return "star.fill"
        case .breathing: return "wind"
        }
    }

    var description: String {
        switch self {
        case .gratitude:
            return "Share what you're grateful for today"
        case .grounding:
            return "5-4-3-2-1 grounding technique"
        case .wins:
            return "Celebrate your accomplishments"
        case .breathing:
            return "Box breathing for calm"
        }
    }

    var color: String {
        switch self {
        case .gratitude: return "pink"
        case .grounding: return "green"
        case .wins: return "yellow"
        case .breathing: return "blue"
        }
    }

    /// SwiftUI Color for the ritual type
    var swiftUIColor: Color {
        switch self {
        case .gratitude: return .pink
        case .grounding: return .green
        case .wins: return .yellow
        case .breathing: return .blue
        }
    }
}

/// The status of a ritual
enum RitualStatus: String, Codable {
    case scheduled
    case active
    case completed
    case cancelled
}

// MARK: - Circle Ritual

/// Represents a ritual session for a circle
struct CircleRitual: Codable, Identifiable, Equatable {
    let id: UUID
    let circleId: UUID
    let createdBy: UUID
    let title: String
    let ritualType: RitualType
    let scheduledFor: Date
    let durationSeconds: Int
    let status: RitualStatus
    let createdAt: Date
    let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case circleId = "circle_id"
        case createdBy = "created_by"
        case title
        case ritualType = "ritual_type"
        case scheduledFor = "scheduled_for"
        case durationSeconds = "duration_seconds"
        case status
        case createdAt = "created_at"
        case completedAt = "completed_at"
    }

    /// Whether the ritual is currently active and can be joined
    var isJoinable: Bool {
        guard status == .scheduled || status == .active else { return false }
        let now = Date()
        let gracePeriodEnd = scheduledFor.addingTimeInterval(2 * 60) // 2 minute grace
        return now <= gracePeriodEnd
    }

    /// Whether the ritual has started
    var hasStarted: Bool {
        Date() >= scheduledFor
    }

    /// Whether the ritual time has elapsed
    var hasElapsed: Bool {
        Date() >= scheduledFor.addingTimeInterval(Double(durationSeconds))
    }

    /// Time until the ritual starts (negative if already started)
    var timeUntilStart: TimeInterval {
        scheduledFor.timeIntervalSinceNow
    }

    /// Formatted time until start
    var formattedTimeUntilStart: String {
        let seconds = Int(timeUntilStart)
        if seconds <= 0 {
            return "Starting now"
        } else if seconds < 60 {
            return "Starting in \(seconds)s"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "Starting in \(minutes)m"
        } else {
            let hours = seconds / 3600
            return "Starting in \(hours)h"
        }
    }
}

// MARK: - Ritual Attendee

/// Represents a user's attendance at a ritual
struct RitualAttendee: Codable, Identifiable, Equatable {
    let id: UUID
    let ritualId: UUID
    let userId: UUID
    let joinedAt: Date
    let leftAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case ritualId = "ritual_id"
        case userId = "user_id"
        case joinedAt = "joined_at"
        case leftAt = "left_at"
    }
}

/// Simplified attendee info for display
struct RitualAttendeeInfo: Identifiable, Equatable {
    let userId: UUID
    let displayName: String
    let joinedAt: Date

    var id: UUID { userId }
}

// MARK: - Ritual Reflection

/// A reflection submitted after a ritual
struct RitualReflection: Codable, Identifiable, Equatable {
    let id: UUID
    let ritualId: UUID
    let userId: UUID
    let content: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ritualId = "ritual_id"
        case userId = "user_id"
        case content = "body_text"
        case createdAt = "created_at"
    }
}

/// Reflection with user info for display
struct RitualReflectionInfo: Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let displayName: String
    let content: String
    let createdAt: Date
}

// MARK: - Ritual Step

/// A step in the ritual with its prompt
struct RitualStep: Equatable {
    let stepIndex: Int
    let prompt: String
    let timeRemaining: Int
    let completed: Bool
}

// MARK: - API Response Types

/// Response from join ritual endpoint
struct JoinRitualResponse: Codable {
    let attendance: AttendanceResponse
    let ritual: RitualResponse
    let currentStep: CurrentStepResponse?
    let attendees: [AttendeeResponse]

    struct AttendanceResponse: Codable {
        let id: UUID
        let ritualId: UUID
        let userId: UUID
        let joinedAt: String
    }

    struct RitualResponse: Codable {
        let id: UUID
        let title: String
        let ritualType: String
        let status: String
        let scheduledFor: String
        let durationSeconds: Int
    }

    struct CurrentStepResponse: Codable {
        let stepIndex: Int
        let prompt: String
        let timeRemaining: Int
        let completed: Bool
    }

    struct AttendeeResponse: Codable {
        let userId: UUID
        let displayName: String
        let joinedAt: String
    }
}

/// Response from create ritual endpoint
struct CreateRitualResponse: Codable {
    let ritual: RitualData

    struct RitualData: Codable {
        let id: UUID
        let circleId: UUID
        let createdBy: UUID
        let title: String
        let ritualType: String
        let scheduledFor: String
        let durationSeconds: Int
        let status: String
        let createdAt: String
    }
}

/// Response from complete ritual endpoint
struct CompleteRitualResponse: Codable {
    let ritual: RitualStatusData
    let recapPostId: UUID?

    struct RitualStatusData: Codable {
        let id: UUID
        let status: String
        let completedAt: String
        let attendeeCount: Int
    }
}

/// Response from add reflection endpoint
struct AddReflectionResponse: Codable {
    let reflection: ReflectionData
    let updated: Bool

    struct ReflectionData: Codable {
        let id: UUID
        let ritualId: UUID
        let userId: UUID
        let content: String
        let createdAt: String
    }
}

// MARK: - Prompt Sequences

/// Hardcoded prompt sequences matching the backend
struct RitualPromptSequence {
    let type: RitualType
    let totalDuration: Int
    let steps: [(duration: Int, prompt: String)]

    static let gratitude = RitualPromptSequence(
        type: .gratitude,
        totalDuration: 180,
        steps: [
            (60, "What's something small that brought you joy today?"),
            (60, "Who's someone you're grateful for right now?"),
            (60, "What's going well in your life, even if it's tiny?"),
        ]
    )

    static let grounding = RitualPromptSequence(
        type: .grounding,
        totalDuration: 180,
        steps: [
            (45, "Name 5 things you can see around you"),
            (45, "Name 4 things you can touch right now"),
            (45, "Name 3 things you can hear"),
            (45, "Take 3 slow breaths and notice how you feel"),
        ]
    )

    static let wins = RitualPromptSequence(
        type: .wins,
        totalDuration: 180,
        steps: [
            (60, "What's one thing you accomplished today?"),
            (60, "What challenge did you overcome this week?"),
            (60, "What progress are you proud of?"),
        ]
    )

    static let breathing = RitualPromptSequence(
        type: .breathing,
        totalDuration: 180,
        steps: [
            (36, "Breathe in for 4... Hold for 4... Out for 4... Hold for 4"),
            (36, "Breathe in for 4... Hold for 4... Out for 4... Hold for 4"),
            (36, "Breathe in for 4... Hold for 4... Out for 4... Hold for 4"),
            (36, "Breathe in for 4... Hold for 4... Out for 4... Hold for 4"),
            (36, "Breathe in for 4... Hold for 4... Out for 4... Hold for 4"),
        ]
    )

    static func forType(_ type: RitualType) -> RitualPromptSequence {
        switch type {
        case .gratitude: return gratitude
        case .grounding: return grounding
        case .wins: return wins
        case .breathing: return breathing
        }
    }

    /// Calculate current step based on elapsed seconds
    func currentStep(elapsedSeconds: Int) -> RitualStep? {
        guard elapsedSeconds < totalDuration else {
            // Ritual completed
            let lastStep = steps[steps.count - 1]
            return RitualStep(
                stepIndex: steps.count - 1,
                prompt: lastStep.prompt,
                timeRemaining: 0,
                completed: true
            )
        }

        var accumulatedTime = 0
        for (index, step) in steps.enumerated() {
            let stepEndTime = accumulatedTime + step.duration
            if elapsedSeconds < stepEndTime {
                return RitualStep(
                    stepIndex: index,
                    prompt: step.prompt,
                    timeRemaining: stepEndTime - elapsedSeconds,
                    completed: false
                )
            }
            accumulatedTime = stepEndTime
        }

        // Fallback
        let lastStep = steps[steps.count - 1]
        return RitualStep(
            stepIndex: steps.count - 1,
            prompt: lastStep.prompt,
            timeRemaining: 0,
            completed: true
        )
    }
}
