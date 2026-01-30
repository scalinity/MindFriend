//  CalendarTriggerMonitor.swift
//  MindFriendApp
//
//  Created by Contextual Micro-Interventions Feature
//  Monitors EventKit calendars for upcoming stressful events and schedules preemptive interventions

import Foundation
import EventKit
import Supabase

// MARK: - Protocol

protocol CalendarTriggerMonitoring {
    func requestCalendarPermission() async -> Bool
    func hasCalendarPermission() -> Bool
    func refreshEventStore()
    func scanUpcomingEvents(window: TimeInterval) async throws -> [ClassifiedEvent]
    func classifyEvent(_ event: EKEvent) -> ClassifiedEvent
    func updateTriggerConfig(_ config: CalendarTriggerConfig) async throws
    func markEventAsNeedsArmor(_ eventId: String) async throws
    func getTriggerConfig() async throws -> CalendarTriggerConfig
}

// MARK: - Configuration Constants

private enum CalendarConstants {
    static let defaultScanWindow: TimeInterval = 48 * 60 * 60 // 48 hours
    static let scanIntervalSeconds: TimeInterval = 6 * 60 * 60 // 6 hours
    static let meetingKeywords = ["meeting", "call", "zoom", "teams", "presentation", "interview", "review"]
    static let deadlineKeywords = ["deadline", "due", "submit", "presentation", "exam", "test"]
    static let travelKeywords = ["flight", "train", "drive", "commute", "trip", "travel"]
    static let medicalKeywords = ["doctor", "dentist", "appointment", "surgery", "therapy", "checkup"]
    static let shortEventThresholdMinutes: TimeInterval = 30 // Events shorter than this are likely stressful
}

// MARK: - Implementation

@MainActor
final class CalendarTriggerMonitor: CalendarTriggerMonitoring {
    // MARK: - Properties

    /// Event store - recreated after permission changes to ensure fresh state
    private var eventStore: EKEventStore
    private let supabase: SupabaseClient
    private var scanTimer: Timer?
    private var cachedConfig: CalendarTriggerConfig?
    private var lastScanDate: Date?

    // MARK: - Initialization

    init(supabase: SupabaseClient) {
        self.eventStore = EKEventStore()
        self.supabase = supabase
    }

    /// Refresh the event store instance after permission changes
    /// On iOS 17+, the EKEventStore instance may need recreation after permission state changes
    func refreshEventStore() {
        eventStore = EKEventStore()
    }

    deinit {
        scanTimer?.invalidate()
        scanTimer = nil
    }

    // MARK: - Public Methods

    /// Last error from permission request (for debugging)
    var lastPermissionError: String?

    func requestCalendarPermission() async -> Bool {
        lastPermissionError = nil
        do {
            if #available(iOS 17.0, *) {
                let granted = try await eventStore.requestFullAccessToEvents()
                if granted {
                    // Refresh event store after permission granted to ensure fresh state
                    refreshEventStore()
                }
                return granted
            } else {
                return await withCheckedContinuation { continuation in
                    eventStore.requestAccess(to: .event) { granted, error in
                        if let error = error {
                            self.lastPermissionError = error.localizedDescription
                        }
                        if granted {
                            // Refresh event store on main thread
                            Task { @MainActor in
                                self.refreshEventStore()
                            }
                        }
                        continuation.resume(returning: granted)
                    }
                }
            }
        } catch {
            lastPermissionError = error.localizedDescription
            return false
        }
    }

    func hasCalendarPermission() -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(iOS 17.0, *) {
            return status == .fullAccess
        } else {
            return status == .authorized
        }
    }

    func scanUpcomingEvents(window: TimeInterval = CalendarConstants.defaultScanWindow) async throws -> [ClassifiedEvent] {
        guard hasCalendarPermission() else {
            throw CalendarError.permissionDenied
        }

        let config = try await getTriggerConfig()

        // If no calendars enabled, return empty
        guard !config.enabledCalendarIds.isEmpty else {
            return []
        }

        let startDate = Date()
        let endDate = startDate.addingTimeInterval(window)

        // Get enabled calendars
        let allCalendars = eventStore.calendars(for: .event)
        let enabledCalendars = allCalendars.filter { config.enabledCalendarIds.contains($0.calendarIdentifier) }

        guard !enabledCalendars.isEmpty else {
            return []
        }

        // Create predicate for event search
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: enabledCalendars)

        // Fetch events
        let events = eventStore.events(matching: predicate)

        // Classify and filter
        let classifiedEvents = events.map { classifyEvent($0) }
            .filter { $0.warrantsIntervention(threshold: config.minStressScore) }

        // Update last scan timestamp
        lastScanDate = Date()

        return classifiedEvents
    }

    func classifyEvent(_ event: EKEvent) -> ClassifiedEvent {
        let title = event.title?.lowercased() ?? ""
        let notes = event.notes?.lowercased() ?? ""
        let combined = "\(title) \(notes)"

        // Classify based on keywords
        var classification: EventClassification = .unknown
        var stressScore = EventClassification.unknown.defaultStressScore

        if CalendarConstants.deadlineKeywords.contains(where: { combined.contains($0) }) {
            classification = .deadline
            stressScore = EventClassification.deadline.defaultStressScore
        } else if CalendarConstants.medicalKeywords.contains(where: { combined.contains($0) }) {
            classification = .medical
            stressScore = EventClassification.medical.defaultStressScore
        } else if CalendarConstants.travelKeywords.contains(where: { combined.contains($0) }) {
            classification = .travel
            stressScore = EventClassification.travel.defaultStressScore
        } else if CalendarConstants.meetingKeywords.contains(where: { combined.contains($0) }) {
            classification = .meeting
            stressScore = EventClassification.meeting.defaultStressScore
        } else if event.attendees?.count ?? 0 > 0 {
            // Has attendees = likely meeting/social
            let attendeeCount = event.attendees?.count ?? 0
            if attendeeCount > 5 {
                classification = .meeting
                stressScore = EventClassification.meeting.defaultStressScore
            } else {
                classification = .social
                stressScore = EventClassification.social.defaultStressScore
            }
        } else {
            classification = .personal
            stressScore = EventClassification.personal.defaultStressScore
        }

        // Adjust stress score based on duration
        if !event.isAllDay {
            let durationSeconds = event.endDate.timeIntervalSince(event.startDate)
            let durationMinutes = durationSeconds / 60
            if durationMinutes <= CalendarConstants.shortEventThresholdMinutes {
                // Short events are often more intense
                stressScore = min(1.0, stressScore + 0.2)
            }
        }

        // Very large meetings (>5 attendees) increase stress slightly
        if event.attendees?.count ?? 0 > 5 {
            stressScore = min(1.0, stressScore + 0.1)
        }

        // Check if user marked as needs armor
        let needsArmor = cachedConfig?.needsArmorEventIds.contains(event.eventIdentifier) ?? false
        if needsArmor {
            stressScore = 1.0 // Maximum stress for user-marked events
        }

        return ClassifiedEvent(
            id: event.eventIdentifier,
            title: event.title ?? "Untitled Event",
            startDate: event.startDate,
            endDate: event.endDate,
            classification: classification,
            stressScore: stressScore,
            isAllDay: event.isAllDay,
            needsArmor: needsArmor,
            calendarId: event.calendar.calendarIdentifier
        )
    }

    func updateTriggerConfig(_ config: CalendarTriggerConfig) async throws {
        let session = try await supabase.auth.session
        let userId = session.user.id

        // Find or create calendar trigger
        let triggers: [InterventionTrigger] = try await supabase
            .from("intervention_triggers")
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq("trigger_type", value: "calendar")
            .execute()
            .value

        let encoder = JSONEncoder()
        let configData = try encoder.encode(config)
        let configDict = try JSONSerialization.jsonObject(with: configData) as? [String: Any] ?? [:]

        if let existingTrigger = triggers.first {
            // Update existing
            struct TriggerUpdate: Encodable {
                let triggerConfig: [String: Any]
                let isActive: Bool
                let updatedAt: String

                enum CodingKeys: String, CodingKey {
                    case triggerConfig = "trigger_config"
                    case isActive = "is_active"
                    case updatedAt = "updated_at"
                }

                func encode(to encoder: Encoder) throws {
                    var container = encoder.container(keyedBy: CodingKeys.self)
                    let jsonData = try JSONSerialization.data(withJSONObject: triggerConfig)
                    guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                        throw EncodingError.invalidValue(
                            triggerConfig,
                            EncodingError.Context(codingPath: [CodingKeys.triggerConfig], debugDescription: "Failed to convert JSON data to UTF-8 string")
                        )
                    }
                    try container.encode(jsonString, forKey: .triggerConfig)
                    try container.encode(isActive, forKey: .isActive)
                    try container.encode(updatedAt, forKey: .updatedAt)
                }
            }

            let update = TriggerUpdate(
                triggerConfig: configDict,
                isActive: !config.enabledCalendarIds.isEmpty,
                updatedAt: ISO8601DateFormatter().string(from: Date())
            )

            try await supabase
                .from("intervention_triggers")
                .update(update)
                .eq("id", value: existingTrigger.id.uuidString)
                .execute()
        } else {
            // Create new
            struct TriggerInsert: Encodable {
                let userId: String
                let triggerType: String
                let triggerConfig: String
                let isActive: Bool
                let priority: Int

                enum CodingKeys: String, CodingKey {
                    case userId = "user_id"
                    case triggerType = "trigger_type"
                    case triggerConfig = "trigger_config"
                    case isActive = "is_active"
                    case priority
                }
            }

            let jsonData = try JSONSerialization.data(withJSONObject: configDict)
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                throw CalendarError.encodingFailed("Failed to convert calendar config to UTF-8 string")
            }

            let insert = TriggerInsert(
                userId: userId.uuidString,
                triggerType: "calendar",
                triggerConfig: jsonString,
                isActive: !config.enabledCalendarIds.isEmpty,
                priority: 100 // Higher than time-based (0), lower than biometric (200)
            )

            try await supabase
                .from("intervention_triggers")
                .insert(insert)
                .execute()
        }

        // Update cache
        cachedConfig = config
    }

    func markEventAsNeedsArmor(_ eventId: String) async throws {
        var config = try await getTriggerConfig()
        config.needsArmorEventIds.insert(eventId)
        try await updateTriggerConfig(config)
    }

    func getTriggerConfig() async throws -> CalendarTriggerConfig {
        // Return cached if available and recent
        if let cached = cachedConfig {
            return cached
        }

        let session = try await supabase.auth.session
        let userId = session.user.id

        // Fetch from database
        let triggers: [InterventionTrigger] = try await supabase
            .from("intervention_triggers")
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq("trigger_type", value: "calendar")
            .execute()
            .value

        if let trigger = triggers.first {
            // Decode config from JSONB
            let decoder = JSONDecoder()
            let jsonData = try JSONSerialization.data(withJSONObject: trigger.triggerConfig)
            let config = try decoder.decode(CalendarTriggerConfig.self, from: jsonData)
            cachedConfig = config
            return config
        } else {
            // Return default
            let defaultConfig = CalendarTriggerConfig.default
            cachedConfig = defaultConfig
            return defaultConfig
        }
    }

    // MARK: - Periodic Scanning

    func startPeriodicScanning() {
        scanTimer?.invalidate()

        scanTimer = Timer.scheduledTimer(
            withTimeInterval: CalendarConstants.scanIntervalSeconds,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.performPeriodicScan()
            }
        }

        // Perform initial scan
        Task {
            await performPeriodicScan()
        }
    }

    func stopPeriodicScanning() {
        scanTimer?.invalidate()
        scanTimer = nil
    }

    private func performPeriodicScan() async {
        do {
            let events = try await scanUpcomingEvents()
            print("Calendar scan found \(events.count) upcoming high-stress events")
            // Events will be processed by InterventionService
        } catch {
            print("Periodic calendar scan failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Error Types

enum CalendarError: LocalizedError {
    case permissionDenied
    case eventNotFound
    case invalidConfiguration
    case encodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Calendar access is required to detect upcoming stressful events. Please grant permission in Settings."
        case .eventNotFound:
            return "The event no longer exists in your calendar."
        case .invalidConfiguration:
            return "Calendar trigger configuration is invalid."
        case .encodingFailed(let message):
            return "Failed to encode calendar trigger config: \(message)"
        }
    }
}
