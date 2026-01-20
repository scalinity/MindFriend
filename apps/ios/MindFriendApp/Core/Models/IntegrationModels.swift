import Foundation

// MARK: - Integration Type Enum

/// Supported third-party integration types
enum IntegrationType: String, Codable, CaseIterable, Identifiable {
    case googleCalendar = "google_calendar"
    case tripIt = "tripit"
    case flightAware = "flightaware"
    case bear = "bear"
    case notion = "notion"
    case joplin = "joplin"
    case homeKit = "homekit"
    case ecobee = "ecobee"
    case nest = "nest"
    case garmin = "garmin"
    case fitbit = "fitbit"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .googleCalendar: return "Google Calendar"
        case .tripIt: return "TripIt (Unavailable)"
        case .flightAware: return "FlightAware"
        case .bear: return "Bear"
        case .notion: return "Notion"
        case .joplin: return "Joplin"
        case .homeKit: return "HomeKit"
        case .ecobee: return "Ecobee"
        case .nest: return "Nest"
        case .garmin: return "Garmin"
        case .fitbit: return "Fitbit"
        }
    }

    var category: IntegrationCategory {
        switch self {
        case .googleCalendar:
            return .calendar
        case .tripIt, .flightAware:
            return .travel
        case .bear, .notion, .joplin:
            return .notes
        case .homeKit, .ecobee, .nest:
            return .smartHome
        case .garmin, .fitbit:
            return .wearable
        }
    }

    var requiresOAuth: Bool {
        switch self {
        case .homeKit:
            return false // Uses native iOS HomeKit framework
        default:
            return true
        }
    }

    var oauthScopes: [String] {
        switch self {
        case .googleCalendar:
            return ["https://www.googleapis.com/auth/calendar.readonly"]
        case .tripIt:
            return ["read", "write"]
        case .notion:
            return ["authorization_code"]
        default:
            return []
        }
    }
}

// MARK: - Integration Category

enum IntegrationCategory: String, Codable, CaseIterable {
    case calendar
    case email
    case travel
    case notes
    case smartHome
    case wearable
    case healthcare

    var displayName: String {
        switch self {
        case .calendar: return "Calendar"
        case .email: return "Email"
        case .travel: return "Travel"
        case .notes: return "Notes"
        case .smartHome: return "Smart Home"
        case .wearable: return "Wearable"
        case .healthcare: return "Healthcare"
        }
    }

    var icon: String {
        switch self {
        case .calendar: return "calendar"
        case .email: return "envelope"
        case .travel: return "airplane"
        case .notes: return "note.text"
        case .smartHome: return "house.fill"
        case .wearable: return "applewatch"
        case .healthcare: return "cross.case"
        }
    }
}

// MARK: - Integration Status

enum IntegrationStatus: String, Codable {
    case pending = "pending"           // OAuth flow initiated but not complete
    case connected = "connected"       // Active connection
    case error = "error"               // Connection error
    case revoked = "revoked"           // User or provider revoked access
    case expired = "expired"           // Token expired
}

// MARK: - Integration Configuration

/// Database model for integration configuration
struct IntegrationConfig: Identifiable, Codable, Sendable {
    let id: UUID
    let userId: UUID
    let integrationType: IntegrationType
    var status: IntegrationStatus
    var providerId: String?  // Provider-specific ID (e.g., Google account email)
    var scopes: [String]
    var lastSyncDate: Date?
    var syncError: String?
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case integrationType = "integration_type"
        case status
        case providerId = "provider_id"
        case scopes
        case lastSyncDate = "last_sync_date"
        case syncError = "sync_error"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - OAuth Token (Encrypted)

/// Encrypted OAuth token stored in Keychain
struct OAuthToken: Codable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let tokenType: String
    let expiresAt: Date
    let scope: String?

    var isExpired: Bool {
        Date() >= expiresAt
    }

    var needsRefresh: Bool {
        guard let refreshToken = refreshToken else { return false }
        // Refresh if expires within 5 minutes
        return Date().addingTimeInterval(300) >= expiresAt
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresAt = "expires_at"
        case scope
    }
}

// MARK: - OAuth State

/// OAuth PKCE state for CSRF protection
struct OAuthState: Codable {
    let state: String
    let codeVerifier: String
    let integrationType: IntegrationType
    let redirectUri: String
    let createdAt: Date

    var isExpired: Bool {
        Date().addingTimeInterval(600) < createdAt // 10 minute expiry
    }

    enum CodingKeys: String, CodingKey {
        case state
        case codeVerifier = "code_verifier"
        case integrationType = "integration_type"
        case redirectUri = "redirect_uri"
        case createdAt = "created_at"
    }
}

// MARK: - Calendar Event Models

struct CalendarEvent: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let startTime: Date
    let endTime: Date
    let isAllDay: Bool
    let location: String?
    let attendeesCount: Int
    let meetingType: MeetingType
    let stressScore: Double?
    let isPrivate: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case startTime = "start_time"
        case endTime = "end_time"
        case isAllDay = "is_all_day"
        case location
        case attendeesCount = "attendees_count"
        case meetingType = "meeting_type"
        case stressScore = "stress_score"
        case isPrivate = "is_private"
    }
}

enum MeetingType: String, Codable, Sendable {
    case oneOnOne = "one_on_one"
    case allHands = "all_hands"
    case clientMeeting = "client_meeting"
    case performanceReview = "performance_review"
    case teamMeeting = "team_meeting"
    case other

    static func from(title: String) -> MeetingType {
        let lowercased = title.lowercased()
        if lowercased.contains("1:1") || lowercased.contains("one-on-one") || lowercased.contains("1 on 1") {
            return .oneOnOne
        } else if lowercased.contains("all-hands") || lowercased.contains("all hands") || lowercased.contains("town hall") {
            return .allHands
        } else if lowercased.contains("performance review") || lowercased.contains("annual review") {
            return .performanceReview
        } else if lowercased.contains("client") || lowercased.contains("customer") {
            return .clientMeeting
        } else if lowercased.contains("standup") || lowercased.contains("sync") || lowercased.contains("team") {
            return .teamMeeting
        }
        return .other
    }
}

// MARK: - Travel Models

struct TravelItinerary: Identifiable, Codable, Sendable {
    let id: String
    let tripId: String
    let confirmationNumber: String
    let origin: AirportInfo?
    let destination: AirportInfo?
    let departureTime: Date?
    let arrivalTime: Date?
    let flightNumber: String?
    let carrier: String?
    let status: FlightStatus

    enum CodingKeys: String, CodingKey {
        case id
        case tripId = "trip_id"
        case confirmationNumber = "confirmation_number"
        case origin
        case destination
        case departureTime = "departure_time"
        case arrivalTime = "arrival_time"
        case flightNumber = "flight_number"
        case carrier
        case status
    }
}

struct AirportInfo: Codable, Sendable {
    let code: String
    let city: String
    let timezone: String
}

enum FlightStatus: String, Codable, Sendable {
    case scheduled
    case delayed
    case departed
    case arrived
    case cancelled
}

// MARK: - Note Export Model

struct NoteExport: Identifiable, Codable, Sendable {
    let id: UUID
    let journalEntryId: UUID
    let targetApp: IntegrationType
    let noteId: String?
    let content: String
    let tags: [String]
    let moodScore: Double?
    let exportedAt: Date
    let syncStatus: SyncStatus

    enum CodingKeys: String, CodingKey {
        case id
        case journalEntryId = "journal_entry_id"
        case targetApp = "target_app"
        case noteId = "note_id"
        case content
        case tags
        case moodScore = "mood_score"
        case exportedAt = "exported_at"
        case syncStatus = "sync_status"
    }
}

enum SyncStatus: String, Codable, Sendable {
    case pending
    case syncing
    case completed
    case failed
}

// MARK: - Smart Home Models

struct SmartHomeScene: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let type: SceneType
    let actions: [SceneAction]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case type
        case actions
    }
}

enum SceneType: String, Codable, Sendable {
    case windDown = "wind_down"
    case sleep = "sleep"
    case wakeUp = "wake_up"
    case homeComing = "home_coming"
}

struct SceneAction: Codable, Sendable {
    let deviceType: DeviceType
    let action: String
    let value: String?

    enum CodingKeys: String, CodingKey {
        case deviceType = "device_type"
        case action
        case value
    }
}

enum DeviceType: String, Codable, Sendable {
    case thermostat
    case light
    case lock
    case fan
}

// MARK: - API Rate Limit

struct APIRateLimit: Codable, Sendable {
    let tier: RateLimitTier
    let requestsPerDay: Int
    let requestsRemaining: Int
    let resetAt: Date

    enum CodingKeys: String, CodingKey {
        case tier
        case requestsPerDay = "requests_per_day"
        case requestsRemaining = "requests_remaining"
        case resetAt = "reset_at"
    }
}

enum RateLimitTier: String, Codable, Sendable {
    case free
    case developer
    case enterprise
}
