//
//  DailyBriefingService.swift
//  MindFriendApp
//
//  F009: Daily Briefing API client
//  Fetches and generates daily briefings via Supabase Edge Function
//

import Foundation
import Functions
import Supabase

/// Service for managing daily briefings
actor DailyBriefingService {
    // MARK: - Properties

    private let supabase: SupabaseClient

    /// JSON decoder configured for ISO 8601 dates (matching Supabase timestamp format)
    private static let iso8601Decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let whole = ISO8601DateFormatter()
            whole.formatOptions = [.withInternetDateTime]
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = fractional.date(from: string) { return date }
            if let date = whole.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date format: \(string)"
            )
        }
        return decoder
    }()

    // MARK: - Initialization

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    // MARK: - Briefing Operations

    /// Fetch today's briefing from cache (database)
    /// - Returns: Today's briefing if it exists, nil otherwise
    func fetchTodaysBriefing() async throws -> DailyBriefing? {
        let today = formatDate(Date())

        let response: [DailyBriefing] = try await supabase
            .from("daily_briefings")
            .select()
            .eq("local_date", value: today)
            .execute()
            .value

        return response.first
    }

    /// Generate a new daily briefing via Edge Function
    /// - Parameters:
    ///   - localDate: Date in YYYY-MM-DD format
    ///   - timezone: IANA timezone identifier
    ///   - calendarEvents: Calendar events to include in briefing
    /// - Returns: Newly generated briefing
    func generateBriefing(
        localDate: String,
        timezone: String,
        calendarEvents: [BriefingCalendarEvent]
    ) async throws -> DailyBriefing {
        let request = GenerateBriefingRequest(
            localDate: localDate,
            timezone: timezone,
            calendarEvents: calendarEvents.isEmpty ? nil : calendarEvents
        )

        do {
            let response: DailyBriefing = try await supabase.functions
                .invoke(
                    "generate-daily-briefing",
                    options: FunctionInvokeOptions(
                        body: request
                    ),
                    decoder: Self.iso8601Decoder
                )

            return response
        } catch let error as FunctionsError {
            // Extract detailed error information from FunctionsError
            var errorMessage = "Function invoke error"
            switch error {
            case .relayError:
                errorMessage = "Relay error invoking Edge Function"
            case .httpError(let code, let data):
                errorMessage = "Edge Function returned status code \(code)"
                if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("[DailyBriefingService] Error response JSON: \(errorJson)")
                    if let message = errorJson["message"] as? String {
                        errorMessage = message
                    }
                    if let stack = errorJson["stack"] as? String {
                        print("[DailyBriefingService] Error stack: \(stack)")
                    }
                } else if let errorString = String(data: data, encoding: .utf8) {
                    print("[DailyBriefingService] Error response raw: \(errorString)")
                }
            }
            print("[DailyBriefingService] FunctionsError: \(error)")
            throw DailyBriefingError.generationFailed(errorMessage)
        } catch {
            print("[DailyBriefingService] Unexpected error: \(error)")
            throw DailyBriefingError.generationFailed(error.localizedDescription)
        }
    }

    /// Mark a briefing as viewed
    /// - Parameter briefingId: ID of the briefing to mark
    func markViewed(briefingId: UUID) async throws {
        try await supabase
            .from("daily_briefings")
            .update(["last_viewed_at": ISO8601DateFormatter().string(from: Date())])
            .eq("id", value: briefingId.uuidString)
            .execute()
    }

    // MARK: - Preferences

    /// Fetch user's briefing preferences
    /// - Returns: User preferences, or default if none exist
    func fetchPreferences() async throws -> BriefingPreferences {
        do {
            let response: [BriefingPreferences] = try await supabase
                .from("briefing_preferences")
                .select()
                .execute()
                .value

            return response.first ?? .default
        } catch {
            // If no preferences exist, return defaults
            return .default
        }
    }

    /// Update user's briefing preferences
    /// - Parameter preferences: Updated preferences
    func updatePreferences(_ preferences: BriefingPreferences) async throws {
        // Upsert preferences (insert or update)
        try await supabase
            .from("briefing_preferences")
            .upsert(preferences)
            .execute()
    }

    // MARK: - Helpers

    /// Format a date to YYYY-MM-DD string
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }

    /// Get current timezone as IANA identifier
    func getCurrentTimezone() -> String {
        TimeZone.current.identifier
    }
}
