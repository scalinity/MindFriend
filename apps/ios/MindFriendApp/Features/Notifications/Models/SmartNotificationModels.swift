import Foundation

// MARK: - Engagement Prediction

/// Result of ML prediction for engagement probability
struct EngagementPrediction: Codable, Equatable {
    let probability: Double       // 0.0-1.0
    let confidence: Double        // Model confidence
    let features: PredictionFeatures
    let predictedAt: Date

    /// Default prediction for new users (days 1-7)
    static let defaultForNewUser = EngagementPrediction(
        probability: 0.5,
        confidence: 0.0,
        features: .default,
        predictedAt: Date()
    )
}

/// Features used for ML prediction
struct PredictionFeatures: Codable, Equatable {
    // Temporal (6 features)
    let hourOfDay: Int            // 0-23
    let dayOfWeek: Int            // 1-7
    let isWeekend: Bool

    // Historical (3 features)
    let avgEngagementAtHour: Double
    let recentEngagementRate: Double  // Last 7 days
    let daysSinceLastOpen: Int

    // Context (4 features)
    let hasCalendarEvent: Bool
    let locationContext: String   // home, work, other
    let biometricStress: Double   // 0-1
    let focusModeActive: Bool

    // Notification (2 features)
    let notificationType: String
    let notificationPriority: Int

    /// Default features when insufficient data available
    static let `default` = PredictionFeatures(
        hourOfDay: Calendar.current.component(.hour, from: Date()),
        dayOfWeek: Calendar.current.component(.weekday, from: Date()),
        isWeekend: Calendar.current.isDateInWeekend(Date()),
        avgEngagementAtHour: 0.5,
        recentEngagementRate: 0.5,
        daysSinceLastOpen: 0,
        hasCalendarEvent: false,
        locationContext: "unknown",
        biometricStress: 0.5,
        focusModeActive: false,
        notificationType: "general",
        notificationPriority: NotificationPriority.normal.rawValue
    )
}

// MARK: - Context Models

/// Unified context aggregated from all providers
struct UnifiedContext: Codable, Equatable {
    let calendar: CalendarContext
    let location: LocationContext
    let biometric: BiometricContext
    let focusMode: FocusModeContext
    let timestamp: Date
    let shouldSuppressNotification: Bool
    let suppressionReason: String?

    /// Default context when providers unavailable
    static let `default` = UnifiedContext(
        calendar: .default,
        location: .default,
        biometric: .default,
        focusMode: .default,
        timestamp: Date(),
        shouldSuppressNotification: false,
        suppressionReason: nil
    )
}

/// Calendar context from EventKit
struct CalendarContext: Codable, Equatable {
    let isBusy: Bool
    let currentEventTitle: String?
    let minutesUntilNextEvent: Int?
    let eventCount24h: Int

    /// Default when EventKit permission denied
    static let `default` = CalendarContext(
        isBusy: false,
        currentEventTitle: nil,
        minutesUntilNextEvent: nil,
        eventCount24h: 0
    )
}

/// Location context from CoreLocation
struct LocationContext: Codable, Equatable {
    let type: LocationType
    let confidenceScore: Double

    /// Default when CoreLocation permission denied
    static let `default` = LocationContext(
        type: .unknown,
        confidenceScore: 0.0
    )
}

/// Location type for context-aware delivery
enum LocationType: String, Codable, CaseIterable {
    case home
    case work
    case other
    case unknown
}

/// Biometric context from HealthKit
struct BiometricContext: Codable, Equatable {
    let heartRate: Double?
    let hrvBaseline: Double?
    let hrvCurrent: Double?
    let sleepHoursLastNight: Double?
    let isStressed: Bool
    let isLowEnergy: Bool

    /// Default when HealthKit permission denied
    static let `default` = BiometricContext(
        heartRate: nil,
        hrvBaseline: nil,
        hrvCurrent: nil,
        sleepHoursLastNight: 7.0,
        isStressed: false,
        isLowEnergy: false
    )

    /// Calculate stress from HRV (stressed = hrvCurrent < hrvBaseline * 0.85)
    static func calculateStress(hrvCurrent: Double?, hrvBaseline: Double?) -> Bool {
        guard let current = hrvCurrent, let baseline = hrvBaseline, baseline > 0 else {
            return false
        }
        return current < baseline * 0.85
    }
}

/// Focus mode context from system
struct FocusModeContext: Codable, Equatable {
    let activeMode: FocusMode?
    let shouldSuppress: Bool

    /// Default when Focus Mode unavailable
    static let `default` = FocusModeContext(
        activeMode: FocusMode.none,
        shouldSuppress: false
    )
}

/// Focus modes that affect notification delivery
enum FocusMode: String, Codable, CaseIterable {
    case sleep          // Always suppress (except crisis)
    case driving        // Queue until stopped
    case work           // Selective delivery
    case doNotDisturb   // Suppress except crisis
    case none

    /// Whether this mode should suppress notifications
    var shouldSuppressNonCrisis: Bool {
        switch self {
        case .sleep, .driving, .doNotDisturb:
            return true
        case .work, .none:
            return false
        }
    }
}

// MARK: - Notification Queue Models

/// A notification waiting in the queue
struct QueuedNotification: Identifiable, Codable, Equatable {
    let id: UUID
    let type: SmartNotificationType
    let title: String
    let body: String
    let deepLink: String?
    let priority: NotificationPriority
    let engagementScore: Double
    let scheduledFor: Date?
    let context: UnifiedContext
    let createdAt: Date

    /// Whether this notification has expired (older than 24h)
    var isExpired: Bool {
        Date().timeIntervalSince(createdAt) > 24 * 60 * 60
    }
}

/// Notification types for smart notification system
enum SmartNotificationType: String, Codable, CaseIterable {
    case quest = "quest"
    case mood = "mood"
    case circle = "circle"
    case streak = "streak"
    case exercise = "exercise"
    case insight = "insight"
    case achievement = "achievement"
    case reminder = "reminder"
    case crisis = "crisis"
    case system = "system"

    /// Display name for settings UI
    var displayName: String {
        switch self {
        case .quest: return "Daily Quests"
        case .mood: return "Mood Check-ins"
        case .circle: return "Circle Updates"
        case .streak: return "Streak Reminders"
        case .exercise: return "Exercise Suggestions"
        case .insight: return "Insights"
        case .achievement: return "Achievements"
        case .reminder: return "Reminders"
        case .crisis: return "Crisis Support"
        case .system: return "System Alerts"
        }
    }

    /// Whether user can toggle this type off
    var canBeDisabled: Bool {
        switch self {
        case .crisis, .system:
            return false // Crisis and system are always enabled
        default:
            return true
        }
    }
}

/// Priority levels for notification delivery
enum NotificationPriority: Int, Codable, Comparable, CaseIterable {
    case crisis = 100     // Always deliver immediately
    case urgent = 80      // Bypass bundling
    case high = 60
    case normal = 40
    case low = 20

    static func < (lhs: NotificationPriority, rhs: NotificationPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Whether this priority bypasses suppression
    var bypassesSuppression: Bool {
        self == .crisis
    }

    /// Whether this priority bypasses bundling
    var bypassesBundling: Bool {
        self == .crisis || self == .urgent
    }
}

/// A bundle of multiple notifications delivered together
struct NotificationBundle: Codable, Equatable {
    let notifications: [QueuedNotification]
    let title: String     // "3 suggestions today"
    let body: String
    let deepLink: String  // Expand to list

    /// Create a bundle from multiple notifications
    static func create(from notifications: [QueuedNotification]) -> NotificationBundle {
        let count = notifications.count
        let types = Set(notifications.map { $0.type.displayName })
        let typeString = types.joined(separator: ", ")

        return NotificationBundle(
            notifications: notifications,
            title: "\(count) suggestions for you",
            body: "Tap to see: \(typeString)",
            deepLink: "mindfriend://notifications/bundle"
        )
    }
}

/// Result of processing the queue
enum DeliverableItem: Equatable {
    case single(QueuedNotification)
    case bundle(NotificationBundle)

    var notificationCount: Int {
        switch self {
        case .single: return 1
        case .bundle(let bundle): return bundle.notifications.count
        }
    }
}

// MARK: - Engagement Tracking Models

/// An engagement event logged for ML training
struct EngagementEvent: Codable, Equatable {
    let id: UUID?
    let notificationId: UUID
    let userId: UUID
    let notificationType: String
    let predictedEngagement: Double?
    let contextSnapshot: UnifiedContext?
    let outcome: EngagementOutcome
    let timestamp: Date
    let userFeedbackScore: Int?
    let userFeedbackText: String?

    /// Database column mapping
    enum CodingKeys: String, CodingKey {
        case id
        case notificationId = "notification_id"
        case userId = "user_id"
        case notificationType = "notification_type"
        case predictedEngagement = "predicted_engagement"
        case contextSnapshot = "context_snapshot"
        case outcome = "actual_outcome"
        case timestamp = "created_at"
        case userFeedbackScore = "user_feedback_score"
        case userFeedbackText = "user_feedback_text"
    }
}

/// Outcome of a notification delivery
enum EngagementOutcome: String, Codable, CaseIterable {
    case scheduled      // Queued for delivery
    case suppressed     // Blocked by context/threshold
    case delivered      // Sent to device
    case opened         // User tapped notification
    case completed      // User finished suggested action
    case dismissed      // Explicit dismiss
    case ignored        // No action for 24h
    case expired        // Removed from queue after 24h

    /// Whether this is a positive engagement signal
    var isPositive: Bool {
        self == .opened || self == .completed
    }

    /// Weight for ML training
    var trainingWeight: Double {
        switch self {
        case .completed: return 10.0
        case .opened: return 5.0
        case .dismissed: return -3.0
        case .ignored: return -1.0
        case .suppressed, .expired: return 0.0
        case .scheduled, .delivered: return 0.0
        }
    }
}

/// Weekly engagement statistics
struct EngagementStats: Codable, Equatable {
    let delivered: Int
    let opened: Int
    let completed: Int
    let dismissed: Int
    let rate: Double  // (opened + completed) / delivered
    let periodStart: Date
    let periodEnd: Date

    /// Calculate rate from counts
    static func calculate(delivered: Int, opened: Int, completed: Int) -> Double {
        guard delivered > 0 else { return 0.0 }
        return Double(opened + completed) / Double(delivered)
    }
}

// MARK: - Settings Models

/// User's notification frequency preference
enum NotificationFrequency: String, Codable, CaseIterable {
    case minimal   // 1-2/week
    case moderate  // 3-5/week
    case frequent  // 1-2/day

    /// Display name for UI
    var displayName: String {
        switch self {
        case .minimal: return "Minimal (1-2/week)"
        case .moderate: return "Moderate (3-5/week)"
        case .frequent: return "Frequent (1-2/day)"
        }
    }

    /// Max notifications per week for this frequency
    var maxPerWeek: Int {
        switch self {
        case .minimal: return 2
        case .moderate: return 5
        case .frequent: return 14
        }
    }
}

/// Default notification settings
struct SmartNotificationDefaults {
    static let smartEnabled = true
    static let maxPerDay = 5
    static let quietHoursStart = 22  // 10 PM
    static let quietHoursEnd = 8     // 8 AM
    static let frequency: NotificationFrequency = .moderate
    static let enabledTypes: [SmartNotificationType] = [
        .quest, .mood, .streak, .circle, .exercise, .insight, .achievement, .reminder, .crisis, .system
    ]
    static let betaOptIn = false
    static let expirationInterval: TimeInterval = 24 * 60 * 60 // 24 hours
}

// MARK: - Error Types

/// Errors from smart notification operations
enum SmartNotificationError: LocalizedError {
    case modelNotReady
    case contextFetchFailed(String)
    case predictionFailed(String)
    case notificationPermissionDenied
    case databaseError(String)
    case invalidConfiguration(String)

    var errorDescription: String? {
        switch self {
        case .modelNotReady:
            return "ML model not ready. Using fallback predictions."
        case .contextFetchFailed(let reason):
            return "Failed to fetch context: \(reason)"
        case .predictionFailed(let reason):
            return "Prediction failed: \(reason)"
        case .notificationPermissionDenied:
            return "Notification permission not granted"
        case .databaseError(let reason):
            return "Database error: \(reason)"
        case .invalidConfiguration(let reason):
            return "Invalid configuration: \(reason)"
        }
    }
}
