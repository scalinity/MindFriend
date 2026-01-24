//  CalendarTriggerModels.swift
//  MindFriendApp
//
//  Created by Contextual Micro-Interventions Feature
//  Models for calendar-based triggers, event classification, and ML timing preferences

import Foundation
import EventKit

// MARK: - Event Classification

/// Classification categories for calendar events
enum EventClassification: String, Codable, CaseIterable {
    case meeting
    case deadline
    case travel
    case medical
    case social
    case personal
    case unknown

    var displayName: String {
        switch self {
        case .meeting: return "Meeting"
        case .deadline: return "Deadline"
        case .travel: return "Travel"
        case .medical: return "Medical Appointment"
        case .social: return "Social Event"
        case .personal: return "Personal"
        case .unknown: return "Event"
        }
    }

    /// Default stress score for each classification type
    var defaultStressScore: Double {
        switch self {
        case .meeting: return 0.7
        case .deadline: return 0.9
        case .travel: return 0.6
        case .medical: return 0.8
        case .social: return 0.4
        case .personal: return 0.3
        case .unknown: return 0.5
        }
    }
}

// MARK: - Classified Event

/// A calendar event with stress classification and metadata
struct ClassifiedEvent: Codable, Identifiable {
    let id: String // EKEvent identifier
    let title: String // Potentially encrypted for privacy
    let startDate: Date
    let endDate: Date
    let classification: EventClassification
    let stressScore: Double // 0.0 - 1.0
    let isAllDay: Bool
    var needsArmor: Bool // User-marked for preemptive intervention
    let calendarId: String

    /// Duration in seconds
    var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }

    /// Whether this event warrants a trigger (stress score >= threshold)
    func warrantsIntervention(threshold: Double = 0.7) -> Bool {
        return stressScore >= threshold
    }
}

// MARK: - Calendar Trigger Configuration

/// User configuration for calendar-based triggers
struct CalendarTriggerConfig: Codable {
    var enabledCalendarIds: [String] // EKCalendar identifiers to monitor
    var needsArmorEventIds: Set<String> // User-marked event IDs
    var leadTimeMinutes: Int // How many minutes before event to deliver intervention
    var minStressScore: Double // Minimum stress score to trigger (0.0-1.0)

    enum CodingKeys: String, CodingKey {
        case enabledCalendarIds = "enabled_calendar_ids"
        case needsArmorEventIds = "needs_armor_event_ids"
        case leadTimeMinutes = "lead_time_minutes"
        case minStressScore = "min_stress_score"
    }

    static var `default`: CalendarTriggerConfig {
        CalendarTriggerConfig(
            enabledCalendarIds: [],
            needsArmorEventIds: [],
            leadTimeMinutes: 45,
            minStressScore: 0.7
        )
    }
}

// MARK: - Timing Preferences (ML-Learned)

/// ML-learned timing preferences from historical intervention data
struct TimingPreferences: Codable {
    var hourlyConfidence: [Int: HourlyMetrics] // Hour (0-23) -> metrics
    var lastUpdated: Date
    var sampleCount: Int
    var minimumDataMet: Bool

    enum CodingKeys: String, CodingKey {
        case hourlyConfidence = "hourly_confidence"
        case lastUpdated = "last_updated"
        case sampleCount = "sample_count"
        case minimumDataMet = "minimum_data_met"
    }

    /// Get confidence boost for a specific hour (-0.5 to +0.5)
    func getConfidenceBoost(for hour: Int) -> Double {
        guard let metrics = hourlyConfidence[hour] else {
            return 0.0 // Neutral (no data for this hour)
        }
        return metrics.confidence
    }

    /// Get hours with highest completion rates (for UI display)
    func bestHours() -> [Int] {
        hourlyConfidence
            .filter { $0.value.completionRate > 0.7 }
            .sorted { $0.value.completionRate > $1.value.completionRate }
            .prefix(3)
            .map { $0.key }
    }

    /// Get hours with highest dismissal rates (for UI warning)
    func worstHours() -> [Int] {
        hourlyConfidence
            .filter { $0.value.dismissRate > 0.6 }
            .sorted { $0.value.dismissRate > $1.value.dismissRate }
            .prefix(3)
            .map { $0.key }
    }
}

/// Metrics for a specific hour of the day
struct HourlyMetrics: Codable {
    let completionRate: Double // 0.0 - 1.0
    let avgRating: Double // 1.0 - 5.0
    let dismissRate: Double // 0.0 - 1.0
    let confidence: Double // -0.5 to +0.5 (boost/suppress)
    let sampleCount: Int

    enum CodingKeys: String, CodingKey {
        case completionRate = "completion_rate"
        case avgRating = "avg_rating"
        case dismissRate = "dismiss_rate"
        case confidence
        case sampleCount = "sample_count"
    }
}

// MARK: - Intervention Deep Link

/// Deep link data for opening interventions from notifications
struct InterventionDeepLink {
    let deliveryId: UUID
    let interventionId: UUID
    let action: DeepLinkAction

    enum DeepLinkAction: String {
        case open
        case complete
        case dismiss
        case remindLater = "remind_later"
    }

    /// Parse deep link from notification userInfo
    static func parse(from userInfo: [AnyHashable: Any]) -> InterventionDeepLink? {
        guard let deliveryIdString = userInfo["delivery_id"] as? String,
              let deliveryId = UUID(uuidString: deliveryIdString),
              let interventionIdString = userInfo["intervention_id"] as? String,
              let interventionId = UUID(uuidString: interventionIdString),
              let actionString = userInfo["action"] as? String,
              let action = DeepLinkAction(rawValue: actionString) else {
            return nil
        }

        return InterventionDeepLink(
            deliveryId: deliveryId,
            interventionId: interventionId,
            action: action
        )
    }

    /// Build userInfo dictionary for notification payload
    var userInfo: [String: Any] {
        return [
            "delivery_id": deliveryId.uuidString,
            "intervention_id": interventionId.uuidString,
            "action": action.rawValue,
            "type": "intervention"
        ]
    }
}

// MARK: - Calendar Event Context

/// Context data for calendar-triggered interventions
struct CalendarEventContext: Codable {
    let eventId: String
    let classification: EventClassification
    let stressScore: Double
    let startDate: Date
    let leadTimeMinutes: Int

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case classification
        case stressScore = "stress_score"
        case startDate = "start_date"
        case leadTimeMinutes = "lead_time_minutes"
    }

    /// Convert to dictionary for API payload
    var dictionary: [String: Any] {
        return [
            "eventId": eventId,
            "classification": classification.rawValue,
            "stressScore": stressScore,
            "startDate": ISO8601DateFormatter().string(from: startDate),
            "leadTimeMinutes": leadTimeMinutes
        ]
    }
}
