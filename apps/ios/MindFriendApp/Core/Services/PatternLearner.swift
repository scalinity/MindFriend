import Foundation
import Supabase

/// Service for learning stress signature patterns from historical crisis data
@MainActor
final class PatternLearner: ObservableObject {
    private let supabaseDataService: SupabaseDataService

    @Published private(set) var isLearning = false
    @Published private(set) var lastLearnedAt: Date?
    @Published private(set) var lastError: Error?

    init(supabaseDataService: SupabaseDataService) {
        self.supabaseDataService = supabaseDataService
    }

    /// Learn signature patterns from historical crisis events
    /// - Parameters:
    ///   - crisisEventIds: Optional specific crisis event IDs to analyze. If nil, analyzes all.
    ///   - lookbackDays: Number of days before each crisis to analyze (default 7)
    /// - Returns: The learned or updated stress signature
    func learnSignatureFromHistory(
        crisisEventIds: [UUID]? = nil,
        lookbackDays: Int = 7
    ) async throws -> WarningSignature {
        isLearning = true
        lastError = nil

        defer { isLearning = false }

        do {
            // Build request payload
            var payload: [String: Any] = [
                "lookback_days": lookbackDays
            ]

            if let ids = crisisEventIds, !ids.isEmpty {
                payload["crisis_event_ids"] = ids.map { $0.uuidString }
            }

            // Call the edge function
            let data = try await supabaseDataService.invokeFunction(
                name: "learn-signature-from-history",
                payload: payload
            )

            // Parse response
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let result = try decoder.decode(LearnSignatureResponse.self, from: data)

            guard let signature = result.signature else {
                if let message = result.message {
                    print("[PatternLearner] No patterns found: \(message)")
                }
                throw StressSignatureError.insufficientData
            }

            lastLearnedAt = Date()
            return signature

        } catch {
            lastError = error
            throw error
        }
    }

    /// Check if there's enough data to learn from
    func hasEnoughDataForLearning() async -> Bool {
        do {
            let crisisCount = try await supabaseDataService.countCrisisEvents()
            return crisisCount >= 1
        } catch {
            return false
        }
    }

    /// Get crisis events that haven't been analyzed yet
    func getUnanalyzedCrisisEvents() async throws -> [CrisisEvent] {
        try await supabaseDataService.fetchUnanalyzedCrisisEvents()
    }
}

// MARK: - Response Models

private struct LearnSignatureResponse: Decodable {
    let signature: WarningSignature?
    let patternsFound: Int
    let dataPointsAnalyzed: Int
    let crisesAnalyzed: Int?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case signature
        case patternsFound = "patterns_found"
        case dataPointsAnalyzed = "data_points_analyzed"
        case crisesAnalyzed = "crises_analyzed"
        case message
    }
}

// MARK: - SupabaseDataService Extensions

extension SupabaseDataService {
    func countCrisisEvents() async throws -> Int {
        let response = try await supabase
            .from("crisis_events")
            .select("id", head: true, count: .exact)
            .execute()

        return response.count ?? 0
    }

    func fetchUnanalyzedCrisisEvents() async throws -> [CrisisEvent] {
        let response = try await supabase
            .from("crisis_events")
            .select()
            .eq("analyzed", value: false)
            .order("occurred_at", ascending: false)
            .execute()

        return try JSONDecoder.supabaseDecoder.decode([CrisisEvent].self, from: response.data)
    }

    func invokeFunction(name: String, payload: [String: Any]) async throws -> Data {
        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        return try await supabase.functions.invoke(
            name,
            options: FunctionInvokeOptions(body: jsonData)
        )
    }
}
// Note: Uses JSONDecoder.supabaseDecoder from LiveService.swift
