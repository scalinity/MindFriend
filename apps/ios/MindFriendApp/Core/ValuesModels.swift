//
//  ValuesModels.swift
//  MindFriendApp
//
//  Values Compass & Decision Coach data models
//  Matches database schema and Edge Function API contracts
//

import Foundation

// MARK: - Value Category

enum ValueCategory: String, Codable, CaseIterable {
    case personal
    case relationships
    case work
    case growth

    var displayName: String {
        switch self {
        case .personal: return "Personal"
        case .relationships: return "Relationships"
        case .work: return "Work"
        case .growth: return "Growth"
        }
    }

    var icon: String {
        switch self {
        case .personal: return "person.fill"
        case .relationships: return "heart.fill"
        case .work: return "briefcase.fill"
        case .growth: return "chart.line.uptrend.xyaxis"
        }
    }
}

// MARK: - Value Card (from values_cards table)

struct ValueCard: Identifiable, Codable, Hashable {
    let id: String
    let valueKey: String
    let displayName: String
    let description: String
    let category: ValueCategory
    let icon: String // SF Symbol name
    let questions: [String]
    let examples: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case valueKey = "value_key"
        case displayName = "display_name"
        case description
        case category
        case icon
        case questions
        case examples
    }
}

// MARK: - User Values (from user_values table)

struct UserValues: Codable {
    let id: String
    let userId: String
    let valuesData: ValuesData
    let topValues: [String] // Array of value_keys
    let customValues: [String]
    let valuesCategories: [String: [String]] // category -> [value_keys]
    let completedAt: Date?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case valuesData = "values_data"
        case topValues = "top_values"
        case customValues = "custom_values"
        case valuesCategories = "values_categories"
        case completedAt = "completed_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Values Data (JSONB structure)

struct ValuesData: Codable {
    let phase1Selections: [String]?
    let phase2Rankings: [String]?
    let phase3Confirmed: [String]?
    let scores: [String: Double]? // value_key -> score
    let customDefinitions: [String: String]? // custom_value -> definition

    enum CodingKeys: String, CodingKey {
        case phase1Selections = "phase1_selections"
        case phase2Rankings = "phase2_rankings"
        case phase3Confirmed = "phase3_confirmed"
        case scores
        case customDefinitions = "custom_definitions"
    }
}

// MARK: - Discovery Phase Responses

struct DiscoveryResponse: Codable {
    let success: Bool
    let nextPhase: NextPhase?
    let confidenceScore: Double?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success
        case nextPhase = "nextPhase"
        case confidenceScore = "confidenceScore"
        case error
    }

    enum NextPhase: Codable {
        case phase2
        case phase3
        case complete

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let intValue = try? container.decode(Int.self) {
                switch intValue {
                case 2: self = .phase2
                case 3: self = .phase3
                default: throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid phase")
                }
            } else if let stringValue = try? container.decode(String.self), stringValue == "complete" {
                self = .complete
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid phase type")
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .phase2: try container.encode(2)
            case .phase3: try container.encode(3)
            case .complete: try container.encode("complete")
            }
        }
    }
}

// MARK: - Decision Models

struct Decision: Identifiable, Codable {
    let id: String
    let userId: String
    let question: String
    let options: [DecisionOption]
    let relevantValues: [String]
    let analysis: DecisionAnalysis?
    let decisionMade: String?
    let confidenceScore: Double?
    let outcome: String?
    let reflection: String?
    let createdAt: Date
    let resolvedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case question
        case options
        case relevantValues = "relevant_values"
        case analysis
        case decisionMade = "decision_made"
        case confidenceScore = "confidence_score"
        case outcome
        case reflection
        case createdAt = "created_at"
        case resolvedAt = "resolved_at"
    }
}

struct DecisionOption: Codable, Hashable {
    let id: String
    let label: String
    let notes: String?
}

struct DecisionAnalysis: Codable {
    let alignedValues: [ValueAlignment]
    let conflictingValues: [ValueAlignment]
    let suggestions: [String]
    let confidenceScore: Double
    let recommendation: String?

    enum CodingKeys: String, CodingKey {
        case alignedValues = "alignedValues"
        case conflictingValues = "conflictingValues"
        case suggestions
        case confidenceScore = "confidenceScore"
        case recommendation
    }
}

struct ValueAlignment: Codable, Hashable {
    let value: String // value_key
    let valueName: String
    let reason: String
    let strength: Double // 0.0-1.0
}

// MARK: - Analysis Response (from analyze-decision Edge Function)

struct AnalyzeDecisionResponse: Codable {
    let success: Bool
    let decisionId: String?
    let analysis: DecisionAnalysis?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success
        case decisionId = "decisionId"
        case analysis
        case error
    }
}

// MARK: - Journal Models

/// Represents a user's entry in their values journal
struct ValuesJournalEntry: Identifiable, Codable {
    let id: String
    let userId: String
    let valueKey: String
    let reflectionText: String
    let createdAt: Date
    let updatedAt: Date?
    let isPrivate: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case valueKey = "value_key"
        case reflectionText = "reflection_text"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case isPrivate = "is_private"
    }
}

// Note: Use ValuesJournalEntry for values-related entries, JournalEntry (in JournalModels) for general journal

struct GapAnalysis: Codable {
    let hasGap: Bool
    let message: String?
    let baseline: Double?
    let currentWeek: Int?
}

// MARK: - Journal Responses

struct GetJournalEntriesResponse: Codable {
    let success: Bool
    let entries: [ValuesJournalEntry]?
    let gapAnalysis: [String: GapAnalysis]? // value_key -> analysis
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success
        case entries
        case gapAnalysis = "gapAnalysis"
        case error
    }
}

struct CreateJournalEntryResponse: Codable {
    let success: Bool
    let entryId: String?
    let gapAnalysis: GapAnalysis?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success
        case entryId = "entryId"
        case gapAnalysis = "gapAnalysis"
        case error
    }
}

// MARK: - Trade-Off Models

struct TradeOffScenario: Identifiable, Codable {
    let id: String
    let text: String
    let valueA: ValueInfo
    let valueB: ValueInfo
    let questions: [String]

    struct ValueInfo: Codable {
        let key: String
        let name: String
    }
}

struct TradeOffScenarioResponse: Codable {
    let success: Bool
    let scenario: TradeOffScenario?
    let error: String?
}

struct RecordTradeOffResponse: Codable {
    let success: Bool
    let tradeOffId: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success
        case tradeOffId = "tradeOffId"
        case error
    }
}

// MARK: - Helper Extensions

extension Decision {
    var confidenceLevel: ConfidenceLevel {
        guard let score = confidenceScore else { return .unknown }
        if score > 0.7 { return .high }
        if score > 0.4 { return .medium }
        if score > 0 { return .low }
        return .conflicted
    }

    enum ConfidenceLevel {
        case high, medium, low, conflicted, unknown

        var displayName: String {
            switch self {
            case .high: return "High Confidence"
            case .medium: return "Medium Confidence"
            case .low: return "Low Confidence"
            case .conflicted: return "Values in Conflict"
            case .unknown: return "Not Analyzed"
            }
        }

        var color: String {
            switch self {
            case .high: return "green"
            case .medium: return "blue"
            case .low: return "orange"
            case .conflicted: return "red"
            case .unknown: return "gray"
            }
        }
    }
}
