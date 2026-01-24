import Foundation

// MARK: - Transition Pathway Models

struct TransitionPathway: Codable, Identifiable, Hashable {
    let id: UUID
    let key: String
    let name: String
    let description: String
    let category: PathwayCategory
    let durationWeeks: Int
    let phases: [PathwayPhaseOverview]
    let isPremium: Bool
    let iconName: String
    let color: String
    let crisisResources: PathwayCrisisResources?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, key, name, description, category, phases, color
        case durationWeeks = "duration_weeks"
        case isPremium = "is_premium"
        case iconName = "icon_name"
        case crisisResources = "crisis_resources"
        case createdAt = "created_at"
    }
}

enum PathwayCategory: String, Codable, CaseIterable, Hashable {
    case career
    case relationship
    case loss
    case family
    case health
    case lifeStage = "life_stage"

    var displayName: String {
        switch self {
        case .career: return "Career"
        case .relationship: return "Relationships"
        case .loss: return "Loss & Grief"
        case .family: return "Family"
        case .health: return "Health"
        case .lifeStage: return "Life Changes"
        }
    }

    var icon: String {
        switch self {
        case .career: return "briefcase.fill"
        case .relationship: return "heart.fill"
        case .loss: return "leaf.fill"
        case .family: return "figure.2.and.child.holdinghands"
        case .health: return "heart.text.square.fill"
        case .lifeStage: return "house.fill"
        }
    }
}

struct PathwayPhaseOverview: Codable, Hashable, Identifiable {
    var id: Int { number }
    let number: Int
    let name: String
    let focus: String
}

struct PathwayCrisisResources: Codable, Hashable {
    let hotline: String?
    let resources: [String]?
}

struct PathwayPhase: Codable, Identifiable, Hashable {
    let id: UUID
    let pathwayId: UUID
    let phaseNumber: Int
    let name: String
    let description: String
    let durationDays: Int
    let objectives: [String]
    let dailyThemes: [DailyTheme]
    let exercises: [String]
    let journalPrompts: [String]
    let milestones: [PhaseMilestone]
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, description, objectives, exercises, milestones
        case pathwayId = "pathway_id"
        case phaseNumber = "phase_number"
        case durationDays = "duration_days"
        case dailyThemes = "daily_themes"
        case journalPrompts = "journal_prompts"
        case createdAt = "created_at"
    }
}

struct DailyTheme: Codable, Hashable {
    let day: Int
    let title: String
    let message: String
    let focusArea: String

    enum CodingKeys: String, CodingKey {
        case day, title, message
        case focusArea = "focus_area"
    }
}

struct PhaseMilestone: Codable, Hashable {
    let key: String
    let name: String
    let description: String
    let criteria: String
}

struct UserPathway: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    let pathwayId: UUID
    let startedAt: Date
    var currentPhase: Int
    var currentDay: Int
    var status: PathwayStatus
    var pausedAt: Date?
    var completedAt: Date?
    var personalization: PathwayPersonalization
    let createdAt: Date
    let updatedAt: Date

    // Joined data (optional)
    var pathway: TransitionPathway?
    var progress: [PathwayProgress]?

    var totalDays: Int {
        (pathway?.durationWeeks ?? 8) * 7
    }

    var progressPercentage: Double {
        Double(currentDay) / Double(totalDays)
    }

    var currentPhaseName: String {
        pathway?.phases.first { $0.number == currentPhase }?.name ?? "Phase \(currentPhase)"
    }

    enum CodingKeys: String, CodingKey {
        case id, status, personalization, pathway, progress
        case userId = "user_id"
        case pathwayId = "pathway_id"
        case startedAt = "started_at"
        case currentPhase = "current_phase"
        case currentDay = "current_day"
        case pausedAt = "paused_at"
        case completedAt = "completed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum PathwayStatus: String, Codable, Hashable {
    case active
    case paused
    case completed
    case abandoned

    var displayName: String {
        switch self {
        case .active: return "Active"
        case .paused: return "Paused"
        case .completed: return "Completed"
        case .abandoned: return "Abandoned"
        }
    }
}

struct PathwayPersonalization: Codable, Hashable {
    var transitionDate: Date?
    var specificContext: String?
    var supportPeople: [String]?
    var goals: [String]?

    enum CodingKeys: String, CodingKey {
        case transitionDate = "transition_date"
        case specificContext = "specific_context"
        case supportPeople = "support_people"
        case goals
    }

    init(transitionDate: Date? = nil, specificContext: String? = nil, supportPeople: [String]? = nil, goals: [String]? = nil) {
        self.transitionDate = transitionDate
        self.specificContext = specificContext
        self.supportPeople = supportPeople
        self.goals = goals
    }
}

struct PathwayProgress: Codable, Identifiable, Hashable {
    let id: UUID
    let userPathwayId: UUID
    let dayNumber: Int
    let phaseNumber: Int
    var checkInCompleted: Bool
    var checkInData: CheckInData?
    var exercisesCompleted: [String]
    var journalEntry: String?
    var milestonesAchieved: [String]
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userPathwayId = "user_pathway_id"
        case dayNumber = "day_number"
        case phaseNumber = "phase_number"
        case checkInCompleted = "check_in_completed"
        case checkInData = "check_in_data"
        case exercisesCompleted = "exercises_completed"
        case journalEntry = "journal_entry"
        case milestonesAchieved = "milestones_achieved"
        case createdAt = "created_at"
    }
}

struct CheckInData: Codable, Hashable {
    let mood: Int
    let energy: Int
    let notes: String?
    let responses: [String: String]?
}

struct PathwayMilestone: Codable, Identifiable, Hashable {
    let id: UUID
    let userPathwayId: UUID
    let milestoneKey: String
    let achievedAt: Date
    let phaseNumber: Int
    var celebrationShown: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case userPathwayId = "user_pathway_id"
        case milestoneKey = "milestone_key"
        case achievedAt = "achieved_at"
        case phaseNumber = "phase_number"
        case celebrationShown = "celebration_shown"
    }
}

// MARK: - Daily Content

struct DailyPathwayContent: Codable, Hashable {
    let dayNumber: Int
    let phaseNumber: Int
    let theme: DailyTheme
    let checkInPrompt: String
    let exercises: [Exercise]
    let journalPrompt: String?
    let affirmation: String
    let upcomingMilestone: UpcomingMilestone?

    enum CodingKeys: String, CodingKey {
        case dayNumber = "day_number"
        case phaseNumber = "phase_number"
        case theme
        case checkInPrompt = "check_in_prompt"
        case exercises
        case journalPrompt = "journal_prompt"
        case affirmation
        case upcomingMilestone = "upcoming_milestone"
    }
}

struct UpcomingMilestone: Codable, Hashable {
    let key: String
    let name: String
    let daysAway: Int

    enum CodingKeys: String, CodingKey {
        case key, name
        case daysAway = "days_away"
    }
}

// MARK: - API Response Types

struct EnrollPathwayResponse: Codable {
    let userPathway: UserPathway
    let todayContent: DailyPathwayContent

    enum CodingKeys: String, CodingKey {
        case userPathway = "user_pathway"
        case todayContent = "today_content"
    }
}

struct AdvancePhaseResponse: Codable {
    let success: Bool
    let newPhase: Int
    let phaseName: String
    let celebration: Celebration

    enum CodingKeys: String, CodingKey {
        case success
        case newPhase = "new_phase"
        case phaseName = "phase_name"
        case celebration
    }
}

struct Celebration: Codable {
    let title: String
    let message: String
    let milestones: [String]
}

struct CheckInResponse: Codable {
    let success: Bool
    let newDay: Int
    let newPhase: Int
    let phaseAdvanced: Bool
    
    enum CodingKeys: String, CodingKey {
        case success
        case newDay = "newDay"
        case newPhase = "newPhase"
        case phaseAdvanced = "phaseAdvanced"
    }
}
