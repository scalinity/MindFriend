//
//  CalendarService.swift
//  MindFriendApp
//
//  F009: Calendar integration via EventKit
//  Requests permission and fetches calendar events for briefing
//

import Foundation
import EventKit

/// Service for accessing device calendar via EventKit
@MainActor
final class CalendarService: ObservableObject {
    // MARK: - Properties

    /// Current authorization status for calendar access
    @Published private(set) var authorizationStatus: EKAuthorizationStatus

    /// Event store for calendar access
    private let eventStore: EKEventStore

    // MARK: - Initialization

    init() {
        self.eventStore = EKEventStore()
        self.authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    // MARK: - Permission Management

    /// Request calendar access permission from user
    /// - Returns: True if permission granted, false otherwise
    func requestAccess() async throws -> Bool {
        // iOS 17+ has new requestFullAccessToEvents API
        if #available(iOS 17.0, *) {
            let granted = try await eventStore.requestFullAccessToEvents()
            await MainActor.run {
                self.authorizationStatus = EKEventStore.authorizationStatus(for: .event)
            }
            return granted
        } else {
            // iOS 16 and earlier
            return try await withCheckedThrowingContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, error in
                    Task { @MainActor in
                        self.authorizationStatus = EKEventStore.authorizationStatus(for: .event)
                    }

                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: granted)
                    }
                }
            }
        }
    }

    /// Check if calendar access is currently authorized
    var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorized, .fullAccess:
            return true
        default:
            return false
        }
    }

    // MARK: - Event Fetching

    /// Fetch calendar events for briefing
    /// - Parameters:
    ///   - from: Start date (default: now)
    ///   - to: End date (default: now + 24 hours)
    ///   - limit: Maximum number of events to return (default: 5)
    /// - Returns: Array of calendar events formatted for briefing
    func fetchEvents(
        from startDate: Date = Date(),
        to endDate: Date? = nil,
        limit: Int = 5
    ) async throws -> [BriefingCalendarEvent] {
        // Check authorization first
        guard isAuthorized else {
            throw CalendarServiceError.permissionDenied
        }

        // Default end date is 24 hours from start
        let actualEndDate = endDate ?? Calendar.current.date(byAdding: .hour, value: 24, to: startDate)!

        // Create predicate for event query
        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: actualEndDate,
            calendars: nil // nil = all calendars
        )

        // Fetch events
        let ekEvents = eventStore.events(matching: predicate)

        // Filter and transform events
        let briefingEvents = ekEvents
            .filter { event in
                // Filter out all-day events
                !event.isAllDay &&
                // Filter out events that have already ended
                event.endDate >= Date() &&
                // Filter out declined events
                event.status != .canceled
            }
            .sorted { $0.startDate < $1.startDate } // Sort by start time
            .prefix(limit) // Limit to max number
            .map { event in
                BriefingCalendarEvent(
                    id: event.eventIdentifier,
                    title: event.title,
                    startTime: event.startDate,
                    endTime: event.endDate,
                    location: event.location
                )
            }

        return Array(briefingEvents)
    }
}

// MARK: - Errors

enum CalendarServiceError: LocalizedError {
    case permissionDenied
    case fetchFailed(Error)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Calendar access denied. Enable in Settings to include events."
        case .fetchFailed(let error):
            return "Failed to fetch calendar events: \(error.localizedDescription)"
        }
    }
}
