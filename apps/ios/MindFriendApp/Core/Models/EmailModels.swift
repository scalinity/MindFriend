import Foundation

// MARK: - Email Preferences

struct EmailPreferences: Codable {
  let id: String
  let userId: String
  let timezone: String
  let preferredSendHour: Int
  let weeklySummary: Bool
  let streakCelebration: Bool
  let achievementUnlock: Bool
  let lapsedNudge: Bool
  let monthlyReport: Bool
  let unsubscribedAt: Date?
  let unsubscribeReason: String?
  let createdAt: Date
  let updatedAt: Date

  enum CodingKeys: String, CodingKey {
    case id
    case userId = "user_id"
    case timezone
    case preferredSendHour = "preferred_send_hour"
    case weeklySummary = "weekly_summary"
    case streakCelebration = "streak_celebration"
    case achievementUnlock = "achievement_unlock"
    case lapsedNudge = "lapsed_nudge"
    case monthlyReport = "monthly_report"
    case unsubscribedAt = "unsubscribed_at"
    case unsubscribeReason = "unsubscribe_reason"
    case createdAt = "created_at"
    case updatedAt = "updated_at"
  }
}

// MARK: - Email Preferences Update Request

struct UpdateEmailPreferencesRequest: Codable {
  let timezone: String?
  let preferredSendHour: Int?
  let weeklySummary: Bool?
  let streakCelebration: Bool?
  let achievementUnlock: Bool?
  let lapsedNudge: Bool?
  let monthlyReport: Bool?

  enum CodingKeys: String, CodingKey {
    case timezone
    case preferredSendHour = "preferred_send_hour"
    case weeklySummary = "weekly_summary"
    case streakCelebration = "streak_celebration"
    case achievementUnlock = "achievement_unlock"
    case lapsedNudge = "lapsed_nudge"
    case monthlyReport = "monthly_report"
  }
}

// MARK: - Supported Timezones

let SUPPORTED_TIMEZONES = [
  "UTC",
  "America/New_York",
  "America/Chicago",
  "America/Denver",
  "America/Los_Angeles",
  "America/Anchorage",
  "Pacific/Honolulu",
  "America/Toronto",
  "America/Mexico_City",
  "America/Argentina/Buenos_Aires",
  "Europe/London",
  "Europe/Paris",
  "Europe/Berlin",
  "Europe/Madrid",
  "Europe/Rome",
  "Europe/Amsterdam",
  "Europe/Brussels",
  "Europe/Vienna",
  "Europe/Prague",
  "Europe/Budapest",
  "Europe/Warsaw",
  "Europe/Moscow",
  "Europe/Istanbul",
  "Asia/Dubai",
  "Asia/Kolkata",
  "Asia/Bangkok",
  "Asia/Hong_Kong",
  "Asia/Shanghai",
  "Asia/Tokyo",
  "Asia/Seoul",
  "Asia/Singapore",
  "Asia/Manila",
  "Australia/Sydney",
  "Australia/Melbourne",
  "Australia/Brisbane",
  "Pacific/Auckland",
]
