//
//  DailyBriefingModels.swift
//  MindFriendApp
//
//  F009: Personalized Daily Briefing Models
//  MVP scope: Excludes wellness score, voice, important dates (Phase 2)
//

import Foundation

// MARK: - Daily Briefing

/// Personalized daily briefing synthesizing mood, quest, calendar, and suggestions
struct DailyBriefing: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let localDate: String // YYYY-MM-DD format

    // Greeting
    let greeting: String

    // Mood prediction (from F003)
    let predictedMood: Double?
    let moodContext: String?

    // Quest
    let questId: UUID?
    let questTitle: String?

    // Calendar events
    let calendarEvents: [BriefingCalendarEvent]

    // Personalized suggestion
    let suggestion: String

    // Metadata
    let generatedAt: Date
    var lastViewedAt: Date?

    // Phase 2 fields (nullable in MVP)
    let wellnessScore: Double?
    let importantDates: [BriefingImportantDate]?
    let audioText: String?
    let audioUrl: String?
    let voicePlayed: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case localDate = "local_date"
        case greeting
        case predictedMood = "predicted_mood"
        case moodContext = "mood_context"
        case questId = "quest_id"
        case questTitle = "quest_title"
        case calendarEvents = "calendar_events"
        case suggestion
        case generatedAt = "generated_at"
        case lastViewedAt = "last_viewed_at"
        case wellnessScore = "wellness_score"
        case importantDates = "important_dates"
        case audioText = "audio_text"
        case audioUrl = "audio_url"
        case voicePlayed = "voice_played"
    }

    /// Mood outlook category based on predicted mood score
    var moodOutlook: MoodOutlook? {
        guard let mood = predictedMood else { return nil }

        switch mood {
        case 0..<4:
            return .challenging
        case 4..<6:
            return .moderate
        case 6..<8:
            return .good
        case 8...10:
            return .great
        default:
            return nil
        }
    }

    /// Whether the briefing has been viewed by the user
    var isViewed: Bool {
        lastViewedAt != nil
    }

    /// Whether there are any calendar events today
    var hasCalendarEvents: Bool {
        !calendarEvents.isEmpty
    }

    /// Next calendar event (first in the list, as they're sorted)
    var nextEvent: BriefingCalendarEvent? {
        calendarEvents.first
    }
}

// MARK: - Mood Outlook

enum MoodOutlook: String, Codable {
    case challenging
    case moderate
    case good
    case great

    var emoji: String {
        switch self {
        case .challenging:
            return "🌧️"
        case .moderate:
            return "⛅"
        case .good:
            return "🌤️"
        case .great:
            return "☀️"
        }
    }

    var displayText: String {
        switch self {
        case .challenging:
            return "Challenging"
        case .moderate:
            return "Moderate"
        case .good:
            return "Good"
        case .great:
            return "Great"
        }
    }

    var color: String {
        switch self {
        case .challenging:
            return "red"
        case .moderate:
            return "orange"
        case .good:
            return "blue"
        case .great:
            return "green"
        }
    }
}

// MARK: - Calendar Event

/// Calendar event from EventKit included in daily briefing
struct BriefingCalendarEvent: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let startTime: Date
    let endTime: Date
    let location: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case startTime = "start_time"
        case endTime = "end_time"
        case location
    }

    /// Duration of the event in minutes
    var durationMinutes: Int {
        Int(endTime.timeIntervalSince(startTime) / 60)
    }

    /// Whether the event is happening soon (within 2 hours)
    var isSoon: Bool {
        let now = Date()
        let twoHoursFromNow = now.addingTimeInterval(2 * 60 * 60)
        return startTime >= now && startTime <= twoHoursFromNow
    }

    /// Whether the event has already started
    var hasStarted: Bool {
        startTime <= Date()
    }

    /// Whether the event is currently happening
    var isHappening: Bool {
        let now = Date()
        return startTime <= now && endTime >= now
    }

    /// Formatted start time (e.g., "2:00 PM")
    var formattedStartTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: startTime)
    }

    /// Time until event starts (e.g., "in 2 hours")
    var timeUntilStart: String {
        let now = Date()
        let interval = startTime.timeIntervalSince(now)

        if interval < 0 {
            return "started"
        } else if interval < 60 * 60 {
            let minutes = Int(interval / 60)
            return "in \(minutes) min"
        } else if interval < 24 * 60 * 60 {
            let hours = Int(interval / (60 * 60))
            return "in \(hours) hr"
        } else {
            return "tomorrow"
        }
    }
}

// MARK: - Important Date (Phase 2)

/// Important date from companion memory (birthdays, anniversaries)
struct BriefingImportantDate: Codable, Identifiable, Equatable {
    let id: String
    let type: String // 'birthday', 'anniversary', 'custom'
    let name: String
    let daysUntil: Int

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case name
        case daysUntil = "days_until"
    }

    /// Display text for the important date
    var displayText: String {
        if daysUntil == 0 {
            return "Today is \(name)'s \(type)"
        } else if daysUntil == 1 {
            return "\(name)'s \(type) is tomorrow"
        } else {
            return "\(name)'s \(type) in \(daysUntil) days"
        }
    }
}

// MARK: - Briefing Preferences

/// User preferences for briefing generation and delivery
struct BriefingPreferences: Codable, Equatable {
    var userId: UUID?
    var enabled: Bool
    var includeCalendar: Bool
    var calendarLookaheadHours: Int

    // Phase 2: Notification time
    var preferredTime: String? // HH:MM:SS format

    // Phase 2: Voice preferences
    var voiceEnabled: Bool?
    var voiceProvider: String?
    var voiceId: String?

    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case enabled
        case includeCalendar = "include_calendar"
        case calendarLookaheadHours = "calendar_lookahead_hours"
        case preferredTime = "preferred_time"
        case voiceEnabled = "voice_enabled"
        case voiceProvider = "voice_provider"
        case voiceId = "voice_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Default preferences for new users
    static var `default`: BriefingPreferences {
        BriefingPreferences(
            userId: nil,
            enabled: true,
            includeCalendar: true,
            calendarLookaheadHours: 24,
            preferredTime: "08:00:00",
            voiceEnabled: false,
            voiceProvider: nil,
            voiceId: nil,
            createdAt: nil,
            updatedAt: nil
        )
    }

    /// Whether calendar integration is active (enabled in prefs)
    var isCalendarActive: Bool {
        enabled && includeCalendar
    }
}

// MARK: - Edge Function Request/Response Models

/// Request payload for generate-daily-briefing Edge Function
struct GenerateBriefingRequest: Codable {
    let localDate: String
    let timezone: String
    let calendarEvents: [BriefingCalendarEvent]?

    enum CodingKeys: String, CodingKey {
        case localDate = "local_date"
        case timezone
        case calendarEvents = "calendar_events"
    }
}

/// Response from generate-daily-briefing Edge Function
typealias GenerateBriefingResponse = DailyBriefing

// MARK: - Service Errors

enum DailyBriefingError: LocalizedError {
    case unauthorized
    case invalidDate(String)
    case generationFailed(String)
    case rateLimited
    case networkError(Error)
    case notFound
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Session expired. Please sign in again."
        case .invalidDate(let date):
            return "Invalid date: \(date)"
        case .generationFailed(let reason):
            return "Couldn't generate briefing: \(reason)"
        case .rateLimited:
            return "Daily limit reached. Showing last briefing."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .notFound:
            return "Briefing not found"
        case .unknown(let message):
            return message
        }
    }
}
