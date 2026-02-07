import Foundation
import EventKit

/// Protocol for calendar context provision (enables testing)
protocol CalendarContextProviding {
    func getContext() async -> CalendarContext
    func requestAccess() async -> Bool
}

/// Provides calendar context using EventKit
@MainActor
final class CalendarContextProvider: CalendarContextProviding {
    private let eventStore = EKEventStore()
    private var hasAccess = false

    init() {}

    /// Request calendar access from the user
    func requestAccess() async -> Bool {
        do {
            if #available(iOS 17.0, *) {
                hasAccess = try await eventStore.requestFullAccessToEvents()
            } else {
                hasAccess = try await eventStore.requestAccess(to: .event)
            }
            return hasAccess
        } catch {
            Log.notifications.debug("[CalendarContext] Access request failed: \(error)")
            return false
        }
    }

    /// Get current calendar context
    /// Returns default context if permission denied
    func getContext() async -> CalendarContext {
        // Check authorization status
        let status = EKEventStore.authorizationStatus(for: .event)
        guard status == .fullAccess else {
            return .default
        }

        let now = Date()
        let calendar = Calendar.current

        // Get events for the next 24 hours
        let endDate = calendar.date(byAdding: .hour, value: 24, to: now)!
        let predicate = eventStore.predicateForEvents(
            withStart: now,
            end: endDate,
            calendars: nil
        )
        let events = eventStore.events(matching: predicate)

        // Find current event (if any)
        let currentEvent = events.first { event in
            event.startDate <= now && event.endDate > now
        }

        // Find next event
        let nextEvent = events.first { event in
            event.startDate > now
        }

        // Calculate minutes until next event
        let minutesUntilNext: Int?
        if let next = nextEvent {
            minutesUntilNext = Int(next.startDate.timeIntervalSince(now) / 60)
        } else {
            minutesUntilNext = nil
        }

        // Check if currently busy (in a meeting)
        let isBusy = currentEvent != nil && currentEvent?.availability == .busy

        return CalendarContext(
            isBusy: isBusy,
            currentEventTitle: currentEvent?.title,
            minutesUntilNextEvent: minutesUntilNext,
            eventCount24h: events.count
        )
    }
}
