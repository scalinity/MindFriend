//
//  DailyBriefingViewModel.swift
//  MindFriendApp
//
//  F009: Daily Briefing ViewModel
//  Manages briefing state and orchestrates calendar + API calls
//

import Foundation
import SwiftUI

/// ViewModel for daily briefing feature
@MainActor
final class DailyBriefingViewModel: ObservableObject {
    // MARK: - Published State

    /// Current briefing (nil if not loaded yet)
    @Published var briefing: DailyBriefing?

    /// Whether briefing is currently loading
    @Published var isLoading: Bool = false

    /// Error message if loading failed
    @Published var error: String?

    /// User's briefing preferences
    @Published var preferences: BriefingPreferences?

    /// Whether expanded view is presented
    @Published var isExpanded: Bool = false

    // MARK: - Dependencies

    private let briefingService: DailyBriefingService
    private let calendarService: CalendarService

    // MARK: - Initialization

    init(
        briefingService: DailyBriefingService,
        calendarService: CalendarService
    ) {
        self.briefingService = briefingService
        self.calendarService = calendarService
    }

    // MARK: - Public Methods

    /// Load today's briefing (fetch cached or generate new)
    func loadTodaysBriefing() async {
        isLoading = true
        error = nil

        do {
            // First, try to fetch cached briefing
            if let cached = try await briefingService.fetchTodaysBriefing() {
                self.briefing = cached
                isLoading = false
                return
            }

            // No cached briefing, generate new one
            await generateBriefing()
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    /// Regenerate briefing (bypass cache)
    func regenerateBriefing() async {
        await generateBriefing()
    }

    /// Mark briefing as viewed
    func markAsViewed() async {
        guard let briefing = briefing, !briefing.isViewed else { return }

        do {
            try await briefingService.markViewed(briefingId: briefing.id)
            // Update local state
            var updatedBriefing = briefing
            updatedBriefing.lastViewedAt = Date()
            self.briefing = updatedBriefing
        } catch {
            // Silently fail - not critical
            print("Failed to mark briefing as viewed: \(error)")
        }
    }

    /// Load user preferences
    func loadPreferences() async {
        do {
            self.preferences = try await briefingService.fetchPreferences()
        } catch {
            // Use defaults if fetch fails
            self.preferences = .default
        }
    }

    /// Update preferences
    func updatePreferences(_ newPreferences: BriefingPreferences) async {
        do {
            try await briefingService.updatePreferences(newPreferences)
            self.preferences = newPreferences
        } catch {
            self.error = "Failed to save preferences: \(error.localizedDescription)"
        }
    }

    // MARK: - Private Methods

    /// Generate new briefing with calendar events
    private func generateBriefing() async {
        isLoading = true
        error = nil

        do {
            // Fetch calendar events if authorized
            var calendarEvents: [BriefingCalendarEvent] = []
            if calendarService.isAuthorized {
                calendarEvents = try await calendarService.fetchEvents()
            }

            // Get current date and timezone
            let today = formatDate(Date())
            let timezone = await briefingService.getCurrentTimezone()

            // Generate briefing via Edge Function
            let newBriefing = try await briefingService.generateBriefing(
                localDate: today,
                timezone: timezone,
                calendarEvents: calendarEvents
            )

            self.briefing = newBriefing
            isLoading = false
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    /// Format date to YYYY-MM-DD
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }
}
