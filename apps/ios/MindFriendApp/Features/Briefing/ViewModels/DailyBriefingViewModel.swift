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

protocol DailyBriefingProviding: Sendable {
    func fetchTodaysBriefing() async throws -> DailyBriefing?
    func generateBriefing(localDate: String, timezone: String, calendarEvents: [BriefingCalendarEvent]) async throws -> DailyBriefing
    func markViewed(briefingId: UUID) async throws
    func fetchPreferences() async throws -> BriefingPreferences
    func updatePreferences(_ preferences: BriefingPreferences) async throws
}

extension DailyBriefingService: DailyBriefingProviding { }

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

    private let briefingService: any DailyBriefingProviding
    private let calendarService: CalendarService
    private let currentUserId: () -> UUID?
    private var ownerId: UUID?
    private var generation = 0

    /// Whether briefing has been successfully loaded (prevents redundant fetches)
    private var hasLoaded = false

    /// The calendar day (yyyy-MM-dd) for which briefing was loaded.
    /// Resets hasLoaded automatically when the day changes.
    private var loadedDate: String?

    // MARK: - Initialization

    init(
        briefingService: any DailyBriefingProviding,
        calendarService: CalendarService,
        currentUserId: @escaping () -> UUID?
    ) {
        self.briefingService = briefingService
        self.calendarService = calendarService
        self.currentUserId = currentUserId
    }

    // MARK: - Public Methods

    /// Clear private state before the next account can render this retained view model.
    func resetForAccountChange(to userId: UUID?) {
        generation += 1
        ownerId = userId
        briefing = nil
        preferences = nil
        hasLoaded = false
        loadedDate = nil
        isLoading = false
        error = nil
        isExpanded = false
    }

    private func prepareOwner() -> UUID? {
        let activeOwner = currentUserId()
        if ownerId != activeOwner { resetForAccountChange(to: activeOwner) }
        return activeOwner
    }

    private func isCurrent(owner: UUID, generation: Int) -> Bool {
        !Task.isCancelled && self.generation == generation && ownerId == owner && currentUserId() == owner
    }

    /// Load today's briefing (fetch cached or generate new)
    /// Skips fetch if already loaded or currently loading to prevent request storms.
    func loadTodaysBriefing() async {
        guard let owner = prepareOwner() else { return }
        // Reset if the day has changed since last load
        let today = formatDate(Date())
        if loadedDate != today {
            hasLoaded = false
            loadedDate = nil
            briefing = nil
        }

        // Skip if already loaded successfully
        guard !hasLoaded || briefing == nil else { return }
        // Skip if already loading (prevents concurrent requests)
        guard !isLoading else { return }

        isLoading = true
        error = nil
        let requestGeneration = generation
        defer {
            if generation == requestGeneration, ownerId == owner { isLoading = false }
        }

        do {
            // First, try to fetch cached briefing
            if let cached = try await briefingService.fetchTodaysBriefing() {
                guard isCurrent(owner: owner, generation: requestGeneration),
                      cached.userId == owner, cached.localDate == today,
                      formatDate(Date()) == today else { return }
                self.briefing = cached
                self.hasLoaded = true
                self.loadedDate = today
                return
            }

            // No cached briefing, generate new one
            guard isCurrent(owner: owner, generation: requestGeneration) else { return }
            await generateBriefing(owner: owner, generation: requestGeneration, date: today)
            if isCurrent(owner: owner, generation: requestGeneration), briefing != nil {
                hasLoaded = true
                loadedDate = today
            }
        } catch {
            guard isCurrent(owner: owner, generation: requestGeneration) else { return }
            // Don't log cancelled errors (expected when view disappears)
            if Task.isCancelled || error.isCancellation { return }
            Log.general.error("DailyBriefing: failed to load", error: error)
            self.briefing = nil
            self.error = "Load failed: \(error.localizedDescription)"
        }
    }

    /// Force refresh briefing (for pull-to-refresh or retry)
    func refreshBriefing() async {
        resetForAccountChange(to: currentUserId())
        await loadTodaysBriefing()
    }

    /// Regenerate briefing (bypass cache)
    func regenerateBriefing() async {
        guard let owner = prepareOwner() else { return }
        generation += 1
        await generateBriefing(owner: owner, generation: generation, date: formatDate(Date()))
    }

    /// Mark briefing as viewed
    func markAsViewed() async {
        guard let owner = prepareOwner(), let briefing, briefing.userId == owner, !briefing.isViewed else { return }
        let requestGeneration = generation

        do {
            try await briefingService.markViewed(briefingId: briefing.id)
            guard isCurrent(owner: owner, generation: requestGeneration), self.briefing?.id == briefing.id else { return }
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
        guard let owner = prepareOwner() else { return }
        let requestGeneration = generation
        do {
            var preferences = try await briefingService.fetchPreferences()
            guard isCurrent(owner: owner, generation: requestGeneration),
                  preferences.userId == nil || preferences.userId == owner else { return }
            preferences.userId = owner
            self.preferences = preferences
        } catch {
            guard isCurrent(owner: owner, generation: requestGeneration) else { return }
            // Use defaults if fetch fails
            self.preferences = .default
        }
    }

    /// Update preferences
    func updatePreferences(_ newPreferences: BriefingPreferences) async {
        guard let owner = prepareOwner(), newPreferences.userId == nil || newPreferences.userId == owner else { return }
        let requestGeneration = generation
        var ownedPreferences = newPreferences
        ownedPreferences.userId = owner
        do {
            try await briefingService.updatePreferences(ownedPreferences)
            guard isCurrent(owner: owner, generation: requestGeneration) else { return }
            self.preferences = ownedPreferences
        } catch {
            guard isCurrent(owner: owner, generation: requestGeneration) else { return }
            self.error = "Failed to save preferences: \(error.localizedDescription)"
        }
    }

    // MARK: - Private Methods

    /// Generate new briefing with calendar events
    private func generateBriefing(owner: UUID, generation requestGeneration: Int, date today: String) async {
        guard isCurrent(owner: owner, generation: requestGeneration) else { return }
        isLoading = true
        error = nil
        defer {
            if generation == requestGeneration, ownerId == owner { isLoading = false }
        }

        do {
            // Fetch calendar events if authorized
            var calendarEvents: [BriefingCalendarEvent] = []
            if calendarService.isAuthorized {
                calendarEvents = try await calendarService.fetchEvents()
            }
            guard isCurrent(owner: owner, generation: requestGeneration) else { return }

            // Get current date and timezone
            let timezone = TimeZone.current.identifier

            // Generate briefing via Edge Function
            let newBriefing = try await briefingService.generateBriefing(
                localDate: today,
                timezone: timezone,
                calendarEvents: calendarEvents
            )
            guard isCurrent(owner: owner, generation: requestGeneration),
                  newBriefing.userId == owner, newBriefing.localDate == today,
                  formatDate(Date()) == today else { return }
            self.briefing = newBriefing
            hasLoaded = true
            loadedDate = today
        } catch {
            guard isCurrent(owner: owner, generation: requestGeneration) else { return }
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
        Self.dateFormatter.timeZone = .current
        return Self.dateFormatter.string(from: date)
    }
}
