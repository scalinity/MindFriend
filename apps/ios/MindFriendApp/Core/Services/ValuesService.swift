//
//  ValuesService.swift
//  MindFriendApp
//
//  Service for Values Compass & Decision Coach Edge Function API calls
//

import Foundation
import Supabase

@MainActor
final class ValuesService: ObservableObject {
    private let supabase: SupabaseClient

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    // MARK: - Values Cards

    /// Load all 32 predefined value cards from the library
    func loadAllCards() async throws -> [ValueCard] {
        let response = try await supabase
            .from("values_cards")
            .select()
            .order("category")
            .order("display_name")
            .execute()

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        let data = response.data
        let cards = try decoder.decode([ValueCard].self, from: data)
        return cards
    }

    /// Load value cards filtered by category
    func loadCards(category: ValueCategory) async throws -> [ValueCard] {
        let response = try await supabase
            .from("values_cards")
            .select()
            .eq("category", value: category.rawValue)
            .order("display_name")
            .execute()

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let data = response.data
        let cards = try decoder.decode([ValueCard].self, from: data)
        return cards
    }

    // MARK: - Values Discovery (3-Phase Assessment)

    /// Submit Phase 1: Select 8-12 values
    func submitPhase1(selectedCardIds: [String]) async throws -> DiscoveryResponse {
        struct Request: Codable {
            let phase: Int
            let selectedCardIds: [String]
        }
        
        let request = Request(phase: 1, selectedCardIds: selectedCardIds)
        let response: DiscoveryResponse = try await supabase.functions
            .invoke("values-discovery", options: .init(body: request))
        return response
    }

    /// Submit Phase 2: Rank top 5 from Phase 1 selections
    func submitPhase2(rankedCardIds: [String]) async throws -> DiscoveryResponse {
        struct Request: Codable {
            let phase: Int
            let rankedCardIds: [String]
        }
        
        let request = Request(phase: 2, rankedCardIds: rankedCardIds)
        let response: DiscoveryResponse = try await supabase.functions
            .invoke("values-discovery", options: .init(body: request))
        return response
    }

    /// Submit Phase 3: Confirm final 5 values
    func submitPhase3(confirmedCardIds: [String]) async throws -> DiscoveryResponse {
        struct Request: Codable {
            let phase: Int
            let confirmedCardIds: [String]
        }
        
        let request = Request(phase: 3, confirmedCardIds: confirmedCardIds)
        let response: DiscoveryResponse = try await supabase.functions
            .invoke("values-discovery", options: .init(body: request))
        return response
    }

    /// Get user's current values (if discovery completed)
    func getUserValues() async throws -> UserValues? {
        let response = try await supabase
            .from("user_values")
            .select()
            .single()
            .execute()

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        let data = response.data
        let userValues = try? decoder.decode(UserValues.self, from: data)
        return userValues
    }

    // MARK: - Decision Analysis

    /// Analyze a decision using the Decision Coach Edge Function
    func analyzeDecision(
        context: String,
        options: [String]? = nil
    ) async throws -> AnalyzeDecisionResponse {
        struct Request: Codable {
            let context: String
            let options: [String]?
        }
        
        let request = Request(context: context, options: options)
        let response: AnalyzeDecisionResponse = try await supabase.functions
            .invoke("analyze-decision", options: .init(body: request))
        return response
    }

    /// Get user's decision history
    func getDecisions(limit: Int = 20) async throws -> [Decision] {
        let response = try await supabase
            .from("user_decisions")
            .select()
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        let data = response.data
        let decisions = try decoder.decode([Decision].self, from: data)
        return decisions
    }

    /// Update decision with user's final choice and outcome
    func updateDecision(id: String, decisionMade: String, outcome: String?, reflection: String?) async throws {
        struct UpdateData: Codable {
            let decisionMade: String
            let resolvedAt: String
            let outcome: String?
            let reflection: String?
            
            enum CodingKeys: String, CodingKey {
                case decisionMade = "decision_made"
                case resolvedAt = "resolved_at"
                case outcome
                case reflection
            }
        }
        
        let data = UpdateData(
            decisionMade: decisionMade,
            resolvedAt: ISO8601DateFormatter().string(from: Date()),
            outcome: outcome,
            reflection: reflection
        )
        
        _ = try await supabase
            .from("user_decisions")
            .update(data)
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Values Journal

    /// Create a journal entry with automatic gap analysis
    func createJournalEntry(
        valueKey: String,
        entryType: String,
        description: String,
        impactLevel: Int? = nil
    ) async throws -> CreateJournalEntryResponse {
        struct Request: Codable {
            let valueKey: String
            let entryType: String
            let description: String
            let impactLevel: Int?
        }
        
        let request = Request(
            valueKey: valueKey,
            entryType: entryType,
            description: description,
            impactLevel: impactLevel
        )
        
        let response: CreateJournalEntryResponse = try await supabase.functions
            .invoke("values-journal", options: .init(body: request))
        return response
    }

    /// Get journal entries with gap analysis
    func getJournalEntries() async throws -> GetJournalEntriesResponse {
        let response: GetJournalEntriesResponse = try await supabase.functions
            .invoke("values-journal")
        return response
    }

    // MARK: - Trade-Off Exercises

    /// Get a random trade-off scenario
    func getTradeOffScenario() async throws -> TradeOffScenarioResponse {
        let response: TradeOffScenarioResponse = try await supabase.functions
            .invoke("trade-off-exercise", options: FunctionInvokeOptions(method: .get))

        return response
    }

    /// Record user's choice in a trade-off exercise
    func recordTradeOffChoice(
        scenarioId: String,
        choice: TradeOffChoice,
        reasoning: String? = nil
    ) async throws -> RecordTradeOffResponse {
        struct Request: Codable {
            let scenarioId: String
            let choice: String
            let reasoning: String?
        }
        
        let request = Request(
            scenarioId: scenarioId,
            choice: choice.rawValue,
            reasoning: reasoning
        )

        let response: RecordTradeOffResponse = try await supabase.functions
            .invoke("trade-off-exercise", options: .init(body: request))

        return response
    }

    enum TradeOffChoice: String {
        case valueA = "value_a"
        case valueB = "value_b"
        case both = "both"
    }

    // MARK: - Error Handling

    enum ValuesServiceError: LocalizedError {
        case invalidResponse
        case apiError(String)
        case networkError
        case decodingError

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "Invalid response from server"
            case .apiError(let message):
                return message
            case .networkError:
                return "Network connection failed"
            case .decodingError:
                return "Failed to decode server response"
            }
        }
    }
}
