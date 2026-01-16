import Foundation
import HealthKit

// MARK: - HealthKit Connection

struct HealthKitConnection: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    var isConnected: Bool
    var authorizedTypes: [String]
    var lastSyncAt: Date?
    var lastSyncStatus: SyncStatus?
    var syncErrorMessage: String?
    var syncFrequencyHours: Int
    var enableInsights: Bool
    var enableAlerts: Bool
    let createdAt: Date
    var updatedAt: Date

    enum SyncStatus: String, Codable {
        case success
        case partial
        case failed
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case isConnected = "is_connected"
        case authorizedTypes = "authorized_types"
        case lastSyncAt = "last_sync_at"
        case lastSyncStatus = "last_sync_status"
        case syncErrorMessage = "sync_error_message"
        case syncFrequencyHours = "sync_frequency_hours"
        case enableInsights = "enable_insights"
        case enableAlerts = "enable_alerts"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Biometric Daily Summary

struct BiometricDailySummary: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let date: String // Date stored as string (YYYY-MM-DD)

    // Sleep
    var sleepDurationMinutes: Int?
    var sleepQualityScore: Double?
    var sleepStartTime: String?
    var sleepEndTime: String?
    var timeInBedMinutes: Int?
    var sleepEfficiency: Double?

    // HRV
    var hrvAverageMs: Double?
    var hrvMinMs: Double?
    var hrvMaxMs: Double?
    var restingHeartRate: Int?

    // Activity
    var stepsCount: Int?
    var activeEnergyKcal: Int?
    var exerciseMinutes: Int?
    var standHours: Int?
    var distanceMeters: Int?

    // Mindfulness
    var mindfulMinutes: Int?

    // Computed
    var overallWellnessScore: Double?

    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case sleepDurationMinutes = "sleep_duration_minutes"
        case sleepQualityScore = "sleep_quality_score"
        case sleepStartTime = "sleep_start_time"
        case sleepEndTime = "sleep_end_time"
        case timeInBedMinutes = "time_in_bed_minutes"
        case sleepEfficiency = "sleep_efficiency"
        case hrvAverageMs = "hrv_average_ms"
        case hrvMinMs = "hrv_min_ms"
        case hrvMaxMs = "hrv_max_ms"
        case restingHeartRate = "resting_heart_rate"
        case stepsCount = "steps_count"
        case activeEnergyKcal = "active_energy_kcal"
        case exerciseMinutes = "exercise_minutes"
        case standHours = "stand_hours"
        case distanceMeters = "distance_meters"
        case mindfulMinutes = "mindful_minutes"
        case overallWellnessScore = "overall_wellness_score"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // Computed properties for display
    var sleepHours: Double? {
        guard let minutes = sleepDurationMinutes else { return nil }
        return Double(minutes) / 60.0
    }

    var formattedSleepDuration: String? {
        guard let minutes = sleepDurationMinutes else { return nil }
        let hours = minutes / 60
        let mins = minutes % 60
        return "\(hours)h \(mins)m"
    }

    var stepsFormatted: String? {
        guard let steps = stepsCount else { return nil }
        return NumberFormatter.localizedString(from: NSNumber(value: steps), number: .decimal)
    }

    var distanceFormatted: String? {
        guard let meters = distanceMeters else { return nil }
        let km = Double(meters) / 1000.0
        return String(format: "%.1f km", km)
    }
}

// MARK: - Biometric Workout

struct BiometricWorkout: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let healthkitUuid: String?
    let workoutType: String
    let startTime: Date
    let endTime: Date
    let durationMinutes: Int
    var activeEnergyKcal: Int?
    var distanceMeters: Int?
    var averageHeartRate: Int?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case healthkitUuid = "healthkit_uuid"
        case workoutType = "workout_type"
        case startTime = "start_time"
        case endTime = "end_time"
        case durationMinutes = "duration_minutes"
        case activeEnergyKcal = "active_energy_kcal"
        case distanceMeters = "distance_meters"
        case averageHeartRate = "average_heart_rate"
        case createdAt = "created_at"
    }

    var workoutTypeDisplay: String {
        switch workoutType {
        case "running": return "Running"
        case "walking": return "Walking"
        case "cycling": return "Cycling"
        case "yoga": return "Yoga"
        case "strength": return "Strength Training"
        case "hiit": return "HIIT"
        case "swimming": return "Swimming"
        case "hiking": return "Hiking"
        case "dance": return "Dance"
        case "pilates": return "Pilates"
        case "elliptical": return "Elliptical"
        case "rowing": return "Rowing"
        default: return workoutType.capitalized
        }
    }

    var workoutIcon: String {
        switch workoutType {
        case "running": return "figure.run"
        case "walking": return "figure.walk"
        case "cycling": return "bicycle"
        case "yoga": return "figure.yoga"
        case "strength": return "dumbbell"
        case "hiit": return "flame"
        case "swimming": return "figure.pool.swim"
        case "hiking": return "figure.hiking"
        case "dance": return "figure.dance"
        case "pilates": return "figure.pilates"
        case "elliptical": return "figure.elliptical"
        case "rowing": return "figure.rower"
        default: return "figure.mixed.cardio"
        }
    }
}

// MARK: - Biometric Insight

struct BiometricInsight: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let insightType: String
    let insightCategory: InsightCategory
    let title: String
    let description: String
    var correlationStrength: Double?
    var confidenceScore: Double?
    var dataPointsCount: Int?
    var periodStartDate: String?
    var periodEndDate: String?
    var isRead: Bool
    var readAt: Date?
    var isDismissed: Bool
    var userRating: Int?
    var userFeedback: String?
    let createdAt: Date
    var expiresAt: Date?

    enum InsightCategory: String, Codable, CaseIterable {
        case sleep
        case activity
        case stress
        case general

        var icon: String {
            switch self {
            case .sleep: return "moon.zzz.fill"
            case .activity: return "figure.walk"
            case .stress: return "heart.text.square"
            case .general: return "chart.line.uptrend.xyaxis"
            }
        }

        var color: String {
            switch self {
            case .sleep: return "indigo"
            case .activity: return "green"
            case .stress: return "orange"
            case .general: return "blue"
            }
        }

        var displayName: String {
            switch self {
            case .sleep: return "Sleep"
            case .activity: return "Activity"
            case .stress: return "Stress"
            case .general: return "General"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case insightType = "insight_type"
        case insightCategory = "insight_category"
        case title
        case description
        case correlationStrength = "correlation_strength"
        case confidenceScore = "confidence_score"
        case dataPointsCount = "data_points_count"
        case periodStartDate = "period_start_date"
        case periodEndDate = "period_end_date"
        case isRead = "is_read"
        case readAt = "read_at"
        case isDismissed = "is_dismissed"
        case userRating = "user_rating"
        case userFeedback = "user_feedback"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }

    var correlationLabel: String? {
        guard let strength = correlationStrength else { return nil }
        let absStrength = abs(strength)
        if absStrength >= 0.7 { return "Strong" }
        if absStrength >= 0.4 { return "Moderate" }
        if absStrength >= 0.2 { return "Weak" }
        return nil
    }
}

// MARK: - Biometric Alert

struct BiometricAlert: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let alertType: AlertType
    let severity: Severity
    let title: String
    let message: String
    let triggerMetric: String
    let triggerValue: Double
    let baselineValue: Double
    let deviationPercent: Double
    var suggestedActionType: String?
    var suggestedActionId: UUID?
    var isSent: Bool
    var sentAt: Date?
    var isRead: Bool
    var readAt: Date?
    var actionTaken: Bool?
    var actionTakenAt: Date?
    let createdAt: Date

    enum AlertType: String, Codable, CaseIterable {
        case lowSleep = "low_sleep"
        case hrvDrop = "hrv_drop"
        case inactivity
        case stressElevated = "stress_elevated"

        var icon: String {
            switch self {
            case .lowSleep: return "moon.zzz"
            case .hrvDrop: return "heart.slash"
            case .inactivity: return "figure.stand"
            case .stressElevated: return "exclamationmark.heart"
            }
        }

        var displayName: String {
            switch self {
            case .lowSleep: return "Low Sleep"
            case .hrvDrop: return "HRV Drop"
            case .inactivity: return "Low Activity"
            case .stressElevated: return "Elevated Stress"
            }
        }
    }

    enum Severity: String, Codable {
        case info
        case warning
        case urgent

        var color: String {
            switch self {
            case .info: return "blue"
            case .warning: return "orange"
            case .urgent: return "red"
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case alertType = "alert_type"
        case severity
        case title
        case message
        case triggerMetric = "trigger_metric"
        case triggerValue = "trigger_value"
        case baselineValue = "baseline_value"
        case deviationPercent = "deviation_percent"
        case suggestedActionType = "suggested_action_type"
        case suggestedActionId = "suggested_action_id"
        case isSent = "is_sent"
        case sentAt = "sent_at"
        case isRead = "is_read"
        case readAt = "read_at"
        case actionTaken = "action_taken"
        case actionTakenAt = "action_taken_at"
        case createdAt = "created_at"
    }
}

// MARK: - Mood Biometric Correlation

struct MoodBiometricCorrelation: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let biometricType: String
    let correlationCoefficient: Double
    let pValue: Double?
    let dataPoints: Int
    let periodDays: Int
    let computedAt: Date
    let strengthLabel: String?
    let directionLabel: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case biometricType = "biometric_type"
        case correlationCoefficient = "correlation_coefficient"
        case pValue = "p_value"
        case dataPoints = "data_points"
        case periodDays = "period_days"
        case computedAt = "computed_at"
        case strengthLabel = "strength_label"
        case directionLabel = "direction_label"
    }

    var biometricTypeDisplay: String {
        switch biometricType {
        case "sleep_duration": return "Sleep Duration"
        case "sleep_quality": return "Sleep Quality"
        case "hrv": return "Heart Rate Variability"
        case "steps": return "Steps"
        case "exercise": return "Exercise"
        case "resting_hr": return "Resting Heart Rate"
        default: return biometricType.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

// MARK: - Biometric Baseline

struct BiometricBaseline: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let metricType: String
    let baselineValue: Double
    var baselineStdDev: Double?
    var baselineMin: Double?
    var baselineMax: Double?
    let computedFromDays: Int
    let lastComputedAt: Date
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case metricType = "metric_type"
        case baselineValue = "baseline_value"
        case baselineStdDev = "baseline_std_dev"
        case baselineMin = "baseline_min"
        case baselineMax = "baseline_max"
        case computedFromDays = "computed_from_days"
        case lastComputedAt = "last_computed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - HealthKit Type Mapping

enum HealthKitDataType: String, CaseIterable {
    case sleep
    case hrv
    case steps
    case activity
    case mindful
    case workouts

    var displayName: String {
        switch self {
        case .sleep: return "Sleep"
        case .hrv: return "Heart Rate Variability"
        case .steps: return "Steps"
        case .activity: return "Active Energy"
        case .mindful: return "Mindful Minutes"
        case .workouts: return "Workouts"
        }
    }

    var icon: String {
        switch self {
        case .sleep: return "bed.double.fill"
        case .hrv: return "heart.fill"
        case .steps: return "figure.walk"
        case .activity: return "flame.fill"
        case .mindful: return "brain.head.profile"
        case .workouts: return "figure.run"
        }
    }

    var description: String {
        switch self {
        case .sleep: return "Understand sleep's impact on mood"
        case .hrv: return "Track stress through heart rate variability"
        case .steps: return "See how activity affects wellbeing"
        case .activity: return "Monitor exercise and energy"
        case .mindful: return "Track mindfulness from other apps"
        case .workouts: return "View workout sessions"
        }
    }

    var healthKitTypes: Set<HKSampleType> {
        switch self {
        case .sleep:
            return [HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!]
        case .hrv:
            return [HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!]
        case .steps:
            return [HKObjectType.quantityType(forIdentifier: .stepCount)!]
        case .activity:
            return [HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!]
        case .mindful:
            return [HKObjectType.categoryType(forIdentifier: .mindfulSession)!]
        case .workouts:
            return [HKObjectType.workoutType()]
        }
    }
}

// MARK: - Sync Payload

struct BiometricSyncPayload: Codable {
    let dailySummaries: [DailySummaryPayload]
    let workouts: [WorkoutPayload]

    struct DailySummaryPayload: Codable {
        let date: String
        var sleepDurationMinutes: Int?
        var sleepQualityScore: Double?
        var sleepStartTime: String?
        var sleepEndTime: String?
        var timeInBedMinutes: Int?
        var hrvAverageMs: Double?
        var hrvMinMs: Double?
        var hrvMaxMs: Double?
        var restingHeartRate: Int?
        var stepsCount: Int?
        var activeEnergyKcal: Int?
        var exerciseMinutes: Int?
        var standHours: Int?
        var distanceMeters: Int?
        var mindfulMinutes: Int?
    }

    struct WorkoutPayload: Codable {
        let healthkitUuid: String
        let workoutType: String
        let startTime: String
        let endTime: String
        let durationMinutes: Int
        var activeEnergyKcal: Int?
        var distanceMeters: Int?
        var averageHeartRate: Int?
    }
}

// MARK: - HealthKit Errors

enum HealthKitError: Error, LocalizedError {
    case notAvailable
    case notAuthorized
    case queryFailed(Error)
    case syncFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device"
        case .notAuthorized:
            return "HealthKit authorization required"
        case .queryFailed(let error):
            return "Failed to query HealthKit: \(error.localizedDescription)"
        case .syncFailed(let error):
            return "Failed to sync biometrics: \(error.localizedDescription)"
        }
    }
}
