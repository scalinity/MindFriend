//
//  DailyBriefingViewModel.swift
//  MindFriendApp
//
//  F009: Daily Briefing ViewModel
//  Manages briefing state and orchestrates calendar + API calls
//

import Foundation
import SwiftUI
import OSLog

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

    /// Whether briefing has been successfully loaded (prevents redundant fetches)
    private var hasLoaded = false

    /// The calendar day (yyyy-MM-dd) for which briefing was loaded.
    /// Resets hasLoaded automatically when the day changes.
    private var loadedDate: String?

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
    /// Skips fetch if already loaded or currently loading to prevent request storms.
    func loadTodaysBriefing() async {
        // Reset if the day has changed since last load
        let today = formatDate(Date())
        if loadedDate != today {
            hasLoaded = false
            loadedDate = nil
        }

        // Skip if already loaded successfully
        guard !hasLoaded || briefing == nil else { return }
        // Skip if already loading (prevents concurrent requests)
        guard !isLoading else { return }

        isLoading = true
        error = nil

        do {
            // First, try to fetch cached briefing
            if let cached = try await briefingService.fetchTodaysBriefing() {
                self.briefing = cached
                self.hasLoaded = true
                self.loadedDate = today
                isLoading = false
                return
            }

            // No cached briefing, generate new one
            await generateBriefing()
            if briefing != nil {
                hasLoaded = true
                loadedDate = today
            }
        } catch {
            isLoading = false
            // Don't log cancelled errors (expected when view disappears)
            if Task.isCancelled || error.isCancellation { return }
            Log.general.error("DailyBriefing: failed to load", error: error)
            self.briefing = nil
            self.error = "Load failed: \(error.localizedDescription)"
        }
    }

    /// Force refresh briefing (for pull-to-refresh or retry)
    func refreshBriefing() async {
        hasLoaded = false
        loadedDate = nil
        // Note: Don't set isLoading = false here - loadTodaysBriefing() manages it
        briefing = nil
        await loadTodaysBriefing()
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
            Log.general.warning("Failed to mark briefing as viewed: \(error.localizedDescription)")
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
            isLoading = false
            // User-navigation cancellations are expected, don't report to Sentry
            // and don't clear state — the view may be dismounting or retrying.
            if Task.isCancelled || error.isCancellation { return }
            Log.general.error("DailyBriefing: failed to generate", error: error)
            self.briefing = nil
            self.error = "Generate failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Date Formatting

    /// Cached DateFormatter for date formatting (DateFormatter is expensive to create)
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    /// Format date to YYYY-MM-DD
    private func formatDate(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }
}
