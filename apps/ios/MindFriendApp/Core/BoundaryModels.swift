//
//  BoundaryModels.swift
//  MindFriendApp
//
//  Boundary & Needs Planner Feature Models
//  Matches database schema from migration 20260121300000
//

import Foundation
import LocalizedStringKey
import SwiftUI

// MARK: - Assessment Models

enum BoundaryAssessmentType: String, Codable, CaseIterable {
    case work
    case relationships
    case family
    case friends
}

enum ImportanceLevel: String, Codable {
    case high
    case medium
    case low
}

enum MetLevel: String, Codable {
    case yes
    case sometimes
    case no
}

struct AssessmentResponses: Codable {
    let step1DrainTriggers: [String]
    let step2ImportanceRatings: [String: ImportanceLevel]
    let step3CurrentlyMet: [String: MetLevel]
    let step4PriorityNeeds: [String]

    enum CodingKeys: String, CodingKey {
        case step1DrainTriggers = "step1_drain_triggers"
        case step2ImportanceRatings = "step2_importance_ratings"
        case step3CurrentlyMet = "step3_currently_met"
        case step4PriorityNeeds = "step4_priority_needs"
    }
}

struct NeedsAssessment: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let assessmentType: BoundaryAssessmentType
    let responses: AssessmentResponses
    let topNeeds: [String]
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case assessmentType = "assessment_type"
        case responses
        case topNeeds = "top_needs"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Boundary Models

enum BoundaryType: String, Codable, CaseIterable, Identifiable {
    case time
    case emotional
    case digital
    case physical
    case financial

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .time: return "definition.type_time"
        case .emotional: return "definition.type_emotional"
        case .digital: return "definition.type_digital"
        case .physical: return "definition.type_physical"
        case .financial: return "definition.type_financial"
        }
    }

    var icon: String {
        switch self {
        case .time: return "clock"
        case .emotional: return "heart"
        case .digital: return "iphone"
        case .physical: return "person.crop.circle"
        case .financial: return "dollarsign.circle"
        }
    }
}

enum BoundaryStatus: String, Codable, CaseIterable {
    case draft
    case ready
    case practiced
    case set
    case adjusted
    case archived

    var displayName: LocalizedStringKey {
        switch self {
        case .draft: return "status.draft"
        case .ready: return "status.ready"
        case .practiced: return "status.practiced"
        case .set: return "status.set"
        case .adjusted: return "status.adjusted"
        case .archived: return "status.archived"
        }
    }

    var color: Color {
        switch self {
        case .draft: return .gray
        case .ready: return .blue
        case .practiced: return .purple
        case .set: return .green
        case .adjusted: return .orange
        case .archived: return .secondary
        }
    }
}

enum ScriptVariation: String, Codable, CaseIterable {
    case direct
    case gentle
    case assertive
    case collaborative

    var displayName: LocalizedStringKey {
        switch self {
        case .direct: return "scripts.variation_direct"
        case .gentle: return "scripts.variation_gentle"
        case .assertive: return "scripts.variation_assertive"
        case .collaborative: return "scripts.variation_collaborative"
        }
    }

    var icon: String {
        switch self {
        case .direct: return "arrow.right.circle"
        case .gentle: return "leaf"
        case .assertive: return "exclamationmark.triangle"
        case .collaborative: return "person.2"
        }
    }
}

struct BoundaryScript: Codable {
    let variation: ScriptVariation
    let text: String
    let toneDescription: String
    let templateId: UUID?

    enum CodingKeys: String, CodingKey {
        case variation
        case text
        case toneDescription = "tone_description"
        case templateId = "template_id"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Try to decode variation as enum first, then as string
        if let variationEnum = try container.decodeIfPresent(ScriptVariation.self, forKey: .variation) {
            self.variation = variationEnum
        } else if let variationString = try container.decodeIfPresent(String.self, forKey: .variation),
                  let variationEnum = ScriptVariation(rawValue: variationString) {
            self.variation = variationEnum
        } else {
            throw DecodingError.dataCorruptedError(forKey: .variation, in: container, debugDescription: "Cannot decode variation")
        }
        
        self.text = try container.decode(String.self, forKey: .text)
        self.toneDescription = try container.decode(String.self, forKey: .toneDescription)
        self.templateId = try container.decodeIfPresent(UUID.self, forKey: .templateId)
    }
}

struct DefinedBoundary: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let needsAssessmentId: UUID?
    let boundaryType: BoundaryType
    let statementText: String
    let whyMatters: String?
    let stakeholder: String?
    let expectedImpact: String?
    var status: BoundaryStatus
    let scripts: [BoundaryScript]?
    let practiceCount: Int
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case needsAssessmentId = "needs_assessment_id"
        case boundaryType = "boundary_type"
        case statementText = "statement_text"
        case whyMatters = "why_matters"
        case stakeholder
        case expectedImpact = "expected_impact"
        case status
        case scripts
        case practiceCount = "practice_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var isPracticed: Bool {
        practiceCount >= 3
    }

    var hasScripts: Bool {
        scripts?.isEmpty == false
    }
}

// MARK: - Follow-Up Models

enum FollowUpOutcome: String, Codable {
    case successful
    case partiallySuccessful = "partially_successful"
    case challenged
    case ignored

    var displayName: LocalizedStringKey {
        switch self {
        case .successful: return "followup.outcome_success"
        case .partiallySuccessful: return "followup.outcome_partial"
        case .challenged: return "followup.outcome_needs_work"
        case .ignored: return "followup.outcome_needs_work"
        }
    }

    var icon: String {
        switch self {
        case .successful: return "checkmark.circle.fill"
        case .partiallySuccessful: return "exclamationmark.circle.fill"
        case .challenged: return "xmark.circle.fill"
        case .ignored: return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .successful: return .green
        case .partiallySuccessful: return .orange
        case .challenged: return .red
        case .ignored: return .red
        }
    }
}

struct BoundaryFollowUp: Codable, Identifiable {
    let id: UUID
    let boundaryId: UUID
    let checkInAt: Date
    var outcome: FollowUpOutcome?
    var notes: String?
    var userReflection: String?
    var nextAction: String?
    var completedAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case boundaryId = "boundary_id"
        case checkInAt = "check_in_at"
        case outcome
        case notes
        case userReflection = "user_reflection"
        case nextAction = "next_action"
        case completedAt = "completed_at"
        case createdAt = "created_at"
    }

    var isCompleted: Bool {
        completedAt != nil
    }

    var isPending: Bool {
        !isCompleted && checkInAt > Date()
    }

    var isOverdue: Bool {
        !isCompleted && checkInAt <= Date()
    }
}

// MARK: - Template Models

struct BoundaryScriptTemplate: Codable, Identifiable {
    let id: UUID
    let boundaryType: BoundaryType
    let relationshipType: String
    let templateVariation: ScriptVariation
    let templateText: String
    let toneDescription: String?
    let exampleContext: String?
    let locale: String
    let isPremium: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case boundaryType = "boundary_type"
        case relationshipType = "relationship_type"
        case templateVariation = "template_variation"
        case templateText = "template_text"
        case toneDescription = "tone_description"
        case exampleContext = "example_context"
        case locale
        case isPremium = "is_premium"
        case createdAt = "created_at"
    }
}

// MARK: - API Response Models

struct CreateAssessmentResponse: Codable {
    let success: Bool
    let assessmentId: UUID
    let topNeeds: [String]
    let recommendedBoundaries: [RecommendedBoundary]

    enum CodingKeys: String, CodingKey {
        case success
        case assessmentId = "assessmentId"
        case topNeeds
        case recommendedBoundaries
    }
}

struct RecommendedBoundary: Codable {
    let type: BoundaryType
    let suggestion: String
    let priority: String
}

struct GenerateBoundaryResponse: Codable {
    let success: Bool
    let boundary: BoundaryResponseData
    let nextSteps: [String]
}

struct BoundaryResponseData: Codable {
    let id: UUID
    let type: BoundaryType
    let statement: String
    let whyMatters: String
    let stakeholder: String?
    let expectedImpact: String
    let status: BoundaryStatus
}

struct GenerateScriptsResponse: Codable {
    let success: Bool
    let scripts: [ScriptResponse]
    let practicePrompts: [String]
}

struct ScriptResponse: Codable {
    let variation: ScriptVariation
    let script: String
    let toneDescription: String
    let tips: [String]
    
    enum CodingKeys: String, CodingKey {
        case variation
        case script
        case toneDescription = "tone_description"
        case tips
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Try to decode variation as enum first, then as string
        if let variationEnum = try container.decodeIfPresent(ScriptVariation.self, forKey: .variation) {
            self.variation = variationEnum
        } else if let variationString = try container.decodeIfPresent(String.self, forKey: .variation),
                  let variationEnum = ScriptVariation(rawValue: variationString) {
            self.variation = variationEnum
        } else {
            throw DecodingError.dataCorruptedError(forKey: .variation, in: container, debugDescription: "Cannot decode variation")
        }
        
        self.script = try container.decode(String.self, forKey: .script)
        self.toneDescription = try container.decode(String.self, forKey: .toneDescription)
        self.tips = try container.decode([String].self, forKey: .tips)
    }
}

struct SaveBoundaryResponse: Codable {
    let success: Bool
    let boundary: BoundarySaveData
}

struct BoundarySaveData: Codable {
    let id: UUID
    let status: BoundaryStatus
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case updatedAt
    }
}

struct ListBoundariesResponse: Codable {
    let success: Bool
    let boundaries: [BoundaryListItem]
    let total: Int
    let limit: Int
    let offset: Int
}

struct BoundaryListItem: Codable, Identifiable {
    let id: UUID
    let boundaryType: BoundaryType
    let statementText: String
    let whyMatters: String?
    let stakeholder: String?
    let expectedImpact: String?
    let status: BoundaryStatus
    let practiceCount: Int
    let createdAt: Date
    let updatedAt: Date
    let hasFollowUp: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case boundaryType = "boundary_type"
        case statementText = "statement_text"
        case whyMatters = "why_matters"
        case stakeholder
        case expectedImpact = "expected_impact"
        case status
        case practiceCount = "practice_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case hasFollowUp = "has_follow_up"
    }
}

struct ScheduleFollowUpResponse: Codable {
    let success: Bool
    let followUpId: UUID
    let reminderSet: Bool
}

struct RecordOutcomeResponse: Codable {
    let success: Bool
    let boundaryUpdated: BoundarySaveData
    let encouragement: String?
    let suggestions: [String]?
}

// MARK: - SwiftUI Extensions

extension BoundaryType {
    var colorScheme: Color {
        switch self {
        case .time: return .blue
        case .emotional: return .pink
        case .digital: return .purple
        case .physical: return .orange
        case .financial: return .green
        }
    }
}

// MARK: - Preview Helpers

#if DEBUG
extension DefinedBoundary {
    static var preview: DefinedBoundary {
        DefinedBoundary(
            id: UUID(),
            userId: UUID(),
            needsAssessmentId: nil,
            boundaryType: .time,
            statementText: "I need to stop working at 6pm every day so I can be present for dinner with my family.",
            whyMatters: "My mental health improves when I have time to recharge.",
            stakeholder: "My manager",
            expectedImpact: "Better work-life balance",
            status: .ready,
            scripts: [
                BoundaryScript(
                    variation: .direct,
                    text: "I appreciate the work we do together, but I need to stop working at 6pm every day so I can be present for dinner with my family.",
                    toneDescription: "Clear and professional",
                    templateId: nil
                )
            ],
            practiceCount: 2,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

extension NeedsAssessment {
    static var preview: NeedsAssessment {
        NeedsAssessment(
            id: UUID(),
            userId: UUID(),
            assessmentType: .work,
            responses: AssessmentResponses(
                step1DrainTriggers: ["When I can't say no"],
                step2ImportanceRatings: ["personal_time": .high],
                step3CurrentlyMet: ["personal_time": .no],
                step4PriorityNeeds: ["personal_time", "autonomy"]
            ),
            topNeeds: ["personal_time", "autonomy", "respect"],
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
#endif
