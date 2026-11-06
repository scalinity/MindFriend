//  OptimalTimingAnalyzer.swift
//  MindFriendApp
//
//  Created by Contextual Micro-Interventions Feature
//  Analyzes historical intervention delivery patterns to learn optimal timing windows

import Foundation
import Supabase

// MARK: - Protocol

protocol OptimalTimingAnalyzing {
    func analyzePatterns() async throws -> TimingPreferences
    func getConfidenceBoost(for hour: Int) -> Double
    func hasMinimumData() async throws -> Bool
    func refreshPatterns() async throws
}

// MARK: - Configuration Constants

private enum TimingConstants {
    static let cacheExpirationSeconds: TimeInterval = 7 * 24 * 60 * 60 // 1 week
    static let minimumDaysRequired = 14 // 2 weeks
    static let refreshIntervalSeconds: TimeInterval = 7 * 24 * 60 * 60 // Weekly refresh
}

// MARK: - Implementation

@MainActor
final class OptimalTimingAnalyzer: @preconcurrency OptimalTimingAnalyzing {
    // MARK: - Properties

    private let supabase: SupabaseClient
    private var cachedPreferences: TimingPreferences?
    private var cacheTimestamp: Date?
    private var refreshTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var accountId: UUID?
    private var accountGeneration = 0

    // MARK: - Initialization

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    deinit {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Public Methods

    func resetForAccountChange(to userId: UUID?) {
        stopPeriodicRefresh()
        accountId = userId
        cachedPreferences = nil
        cacheTimestamp = nil
    }

    private func isCurrent(_ owner: UUID, _ generation: Int) -> Bool {
        !Task.isCancelled && accountId == owner && accountGeneration == generation && supabase.auth.currentUser?.id == owner
    }

    func analyzePatterns() async throws -> TimingPreferences {
        guard let owner = supabase.auth.currentUser?.id else { throw AuthError.sessionExpired }
        if accountId != owner { resetForAccountChange(to: owner) }
        let generation = accountGeneration
        let session = try await supabase.auth.session
        guard session.user.id == owner, isCurrent(owner, generation) else { throw CancellationError() }
        // Check cache first
        if let cached = cachedPreferences,
           let timestamp = cacheTimestamp,
           Date().timeIntervalSince(timestamp) < TimingConstants.cacheExpirationSeconds {
            return cached
        }

        // Call Edge Function to perform server-side analysis
        struct EmptyRequest: Codable {}
        let response: TimingPreferences = try await supabase.functions.invoke(
            "analyze-intervention-patterns",
            options: FunctionInvokeOptions(
                headers: ["Authorization": "Bearer \(session.accessToken)"],
                body: EmptyRequest()
            )
        )
        guard isCurrent(owner, generation) else { throw CancellationError() }

        // Cache result
        cachedPreferences = response
        cacheTimestamp = Date()

        // Persist to database (intervention_preferences.preferred_times)
        try await persistToDatabase(response, owner: owner, generation: generation)
        guard isCurrent(owner, generation) else { throw CancellationError() }

        return response
    }

    func getConfidenceBoost(for hour: Int) -> Double {
        guard let accountId, supabase.auth.currentUser?.id == accountId, let preferences = cachedPreferences else {
            return 0.0 // Neutral (no learning data)
        }

        return preferences.getConfidenceBoost(for: hour)
    }

    func hasMinimumData() async throws -> Bool {
        do {
            let preferences = try await analyzePatterns()
            return preferences.minimumDataMet
        } catch {
            // If error is "insufficient_data", return false
            if let errorMessage = (error as NSError).userInfo["message"] as? String,
               errorMessage.contains("insufficient") {
                return false
            }
            throw error
        }
    }

    func refreshPatterns() async throws {
        // Force refresh by clearing cache
        cachedPreferences = nil
        cacheTimestamp = nil

        _ = try await analyzePatterns()
        print("Optimal timing patterns refreshed successfully")
    }

    // MARK: - Periodic Refresh

    func startPeriodicRefresh() {
        guard let owner = supabase.auth.currentUser?.id else { return }
        if accountId != owner { resetForAccountChange(to: owner) }
        refreshTimer?.invalidate()

        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: TimingConstants.refreshIntervalSeconds,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.beginRefresh()
            }
        }

        // Perform initial analysis
        beginRefresh()
    }

    private func beginRefresh() {
        guard refreshTask == nil else { return }
        let generation = accountGeneration
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if accountGeneration == generation { refreshTask = nil } }
            do {
                try await refreshPatterns()
            } catch let functionsError as FunctionsError {
                if case .httpError(let code, _) = functionsError, code == 400 {
                    // Expected for new users with no intervention history
                    print("Timing analysis: insufficient data (expected for new users)")
                } else {
                    print("Initial timing analysis failed: \(functionsError.localizedDescription)")
                }
            } catch {
                print("Initial timing analysis failed: \(error.localizedDescription)")
            }
        }
    }

    func stopPeriodicRefresh() {
        accountGeneration += 1
        refreshTimer?.invalidate()
        refreshTimer = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: - Private Methods

    private func persistToDatabase(_ preferences: TimingPreferences, owner userId: UUID, generation: Int) async throws {
        guard isCurrent(userId, generation) else { throw CancellationError() }

        // Convert preferences to JSONB format
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(preferences)
        let _ = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] ?? [:]

        // Update intervention_preferences.preferred_times
        struct PreferencesUpdate: Encodable {
            let preferredTimes: String
            let updatedAt: String

            enum CodingKeys: String, CodingKey {
                case preferredTimes = "preferred_times"
                case updatedAt = "updated_at"
            }
        }

        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            print("Failed to encode timing preferences to UTF-8 string")
            return
        }
        
        let update = PreferencesUpdate(
            preferredTimes: jsonString,
            updatedAt: ISO8601DateFormatter().string(from: Date())
        )

        // Upsert (update if exists, insert if not)
        try await supabase
            .from("intervention_preferences")
            .update(update)
            .eq("user_id", value: userId.uuidString)
            .execute()
    }

    // MARK: - Utility Methods

    /// Get best hours (highest completion rates) for UI display
    func getBestHours() -> [Int] {
        guard let accountId, supabase.auth.currentUser?.id == accountId, let preferences = cachedPreferences else {
            return []
        }
        return preferences.bestHours()
    }

    /// Get worst hours (highest dismissal rates) for UI display
    func getWorstHours() -> [Int] {
        guard let accountId, supabase.auth.currentUser?.id == accountId, let preferences = cachedPreferences else {
            return []
        }
        return preferences.worstHours()
    }

    /// Format hour for display
    static func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"

        var components = DateComponents()
        components.hour = hour

        let date = Calendar.current.date(from: components) ?? Date()
        return formatter.string(from: date)
    }
}

// MARK: - Error Types

enum TimingAnalysisError: LocalizedError {
    case insufficientData(days: Int, required: Int)
    case analysisUnavailable
    case networkError

    var errorDescription: String? {
        switch self {
        case .insufficientData(let days, let required):
            return "Need at least \(required) days of intervention history. You have \(days) days."
        case .analysisUnavailable:
            return "Timing analysis is temporarily unavailable. Try again later."
        case .networkError:
            return "Unable to analyze patterns. Check your connection."
        }
    }
}
