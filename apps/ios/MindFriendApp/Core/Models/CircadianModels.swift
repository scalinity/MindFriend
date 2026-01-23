//
//  CircadianModels.swift
//  MindFriendApp
//
//  Created: 2026-01-22
//  Spec: N002 - Circadian Vulnerability Shield
//

import Foundation
import SwiftUI

// MARK: - Chronotype

/// User's circadian preference (morning person vs evening person)
enum Chronotype: String, Codable, CaseIterable {
    case extremeMorning = "extreme_morning"
    case moderateMorning = "moderate_morning"
    case intermediate = "intermediate"
    case moderateEvening = "moderate_evening"
    case extremeEvening = "extreme_evening"

    var displayName: String {
        switch self {
        case .extremeMorning:
            return "Early Bird"
        case .moderateMorning:
            return "Morning Person"
        case .intermediate:
            return "Balanced"
        case .moderateEvening:
            return "Night Owl"
        case .extremeEvening:
            return "Extreme Night Owl"
        }
    }

    var icon: String {
        switch self {
        case .extremeMorning, .moderateMorning:
            return "sunrise.fill"
        case .intermediate:
            return "sun.max.fill"
        case .moderateEvening, .extremeEvening:
            return "moon.stars.fill"
        }
    }

    var description: String {
        switch self {
        case .extremeMorning:
            return "You naturally wake very early (4-5am) and feel most alert in the morning."
        case .moderateMorning:
            return "You prefer early mornings (5-6:30am) and perform best before noon."
        case .intermediate:
            return "You have a balanced rhythm, comfortable with standard schedules (6:30-8am wake)."
        case .moderateEvening:
            return "You prefer later schedules (8-9:30am wake) with peak energy in evening."
        case .extremeEvening:
            return "You're a true night owl, naturally waking late (10am+) with peak performance at night."
        }
    }

    var color: Color {
        switch self {
        case .extremeMorning:
            return Color.orange
        case .moderateMorning:
            return Color.yellow
        case .intermediate:
            return Color.green
        case .moderateEvening:
            return Color.blue
        case .extremeEvening:
            return Color.indigo
        }
    }
}

// MARK: - Sleep Record

/// Sleep record for chronotype classification
struct SleepRecord: Codable, Identifiable {
    let id: UUID
    let date: Date
    let startTime: Date
    let endTime: Date
    let duration: TimeInterval  // Total sleep duration in seconds
    let isWeekend: Bool

    init(id: UUID = UUID(), date: Date, startTime: Date, endTime: Date, duration: TimeInterval, isWeekend: Bool) {
        self.id = id
        self.date = date
        self.startTime = startTime
        self.endTime = endTime
        self.duration = duration
        self.isWeekend = isWeekend
    }

    /// Midpoint of sleep (MSF) - gold standard for chronotype
    /// Returns seconds from midnight of the sleep day
    var midpointOfSleep: TimeInterval {
        let calendar = Calendar.current
        let midpoint = startTime.addingTimeInterval(duration / 2)
        
        // Use the midnight of the sleep start day as reference
        // This handles sleep crossing midnight correctly
        let referenceMidnight = calendar.startOfDay(for: startTime)
        let secondsSinceMidnight = midpoint.timeIntervalSince(referenceMidnight)
        
        // If midpoint is before midnight (e.g., 11pm start + 8h = 7am next day)
        // we want the time relative to the start day's midnight
        return secondsSinceMidnight
    }

    /// Convert midpoint to hours from midnight
    var midpointHours: Double {
        midpointOfSleep / 3600
    }
}

// MARK: - Time Window

/// Time window for circadian events (vulnerable periods, peak performance)
struct TimeWindow: Codable, Equatable, Hashable {
    let start: String  // "HH:mm" format
    let end: String    // "HH:mm" format

    init(start: String, end: String) {
        self.start = start
        self.end = end
    }

    /// Create from TimeInterval (seconds from midnight)
    init(startSeconds: TimeInterval, endSeconds: TimeInterval) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        let startDate = Date(timeIntervalSince1970: startSeconds)
        let endDate = Date(timeIntervalSince1970: endSeconds)

        self.start = formatter.string(from: startDate)
        self.end = formatter.string(from: endDate)
    }

    /// Parse to Date objects for today
    func toDateRange(on date: Date = Date()) -> (start: Date, end: Date)? {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        guard let startTime = formatter.date(from: start),
              let endTime = formatter.date(from: end) else {
            return nil
        }

        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
        let endComponents = calendar.dateComponents([.hour, .minute], from: endTime)

        guard let startDate = calendar.date(bySettingHour: startComponents.hour ?? 0,
                                            minute: startComponents.minute ?? 0,
                                            second: 0,
                                            of: date),
              let endDate = calendar.date(bySettingHour: endComponents.hour ?? 0,
                                          minute: endComponents.minute ?? 0,
                                          second: 0,
                                          of: date) else {
            return nil
        }

        return (startDate, endDate)
    }
}

// MARK: - Circadian Profile

/// User's circadian profile (chronotype, natural sleep times, vulnerable windows)
struct CircadianProfile: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let chronotype: Chronotype
    let chronotypeConfidence: Double
    let naturalWakeTime: TimeInterval    // Seconds from midnight
    let naturalSleepTime: TimeInterval   // Seconds from midnight
    let socialJetLagMinutes: Int
    let vulnerableWindows: [TimeWindow]  // Personalized vulnerable periods
    let peakPerformanceWindow: TimeWindow?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case chronotype
        case chronotypeConfidence = "chronotype_confidence"
        case naturalWakeTime = "natural_wake_time"
        case naturalSleepTime = "natural_sleep_time"
        case socialJetLagMinutes = "social_jet_lag_minutes"
        case vulnerableWindows = "vulnerable_windows"
        case peakPerformanceWindow = "peak_performance_window"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Format wake time as "HH:mm"
    var wakeTimeFormatted: String {
        let hours = Int(naturalWakeTime) / 3600
        let minutes = (Int(naturalWakeTime) % 3600) / 60
        return String(format: "%02d:%02d", hours, minutes)
    }

    /// Format sleep time as "HH:mm"
    var sleepTimeFormatted: String {
        let hours = Int(naturalSleepTime) / 3600
        let minutes = (Int(naturalSleepTime) % 3600) / 60
        return String(format: "%02d:%02d", hours, minutes)
    }

    /// Is chronotype classification reliable?
    var isReliable: Bool {
        chronotypeConfidence >= 0.75
    }
}

// MARK: - Vulnerable Window

/// Predicted vulnerable window when user is susceptible to mood crashes
struct VulnerableWindow: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let date: Date
    let startTime: Date
    let endTime: Date
    let severity: VulnerabilitySeverity
    let confidence: Double
    let predictedTriggers: [String]
    var armorDelivered: Bool
    var armorCompleted: Bool
    let armorExerciseId: String?
    var moodDuringWindow: Double?
    var crashOccurred: Bool?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case startTime = "start_time"
        case endTime = "end_time"
        case severity
        case confidence
        case predictedTriggers = "predicted_triggers"
        case armorDelivered = "armor_delivered"
        case armorCompleted = "armor_completed"
        case armorExerciseId = "armor_exercise_id"
        case moodDuringWindow = "mood_during_window"
        case crashOccurred = "crash_occurred"
        case createdAt = "created_at"
    }

    /// Duration of the vulnerable window
    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }

    /// Is the window currently active?
    func isActive(at date: Date = Date()) -> Bool {
        return date >= startTime && date <= endTime
    }

    /// Has the window passed?
    func hasPassed(at date: Date = Date()) -> Bool {
        return date > endTime
    }

    /// Time until window starts (nil if already started)
    func timeUntilStart(from date: Date = Date()) -> TimeInterval? {
        guard date < startTime else { return nil }
        return startTime.timeIntervalSince(date)
    }

    /// Shifted copy for fallback (e.g., yesterday's windows +24h)
    func shiftedBy(days: Int) -> VulnerableWindow {
        let calendar = Calendar.current
        guard let newDate = calendar.date(byAdding: .day, value: days, to: date),
              let newStart = calendar.date(byAdding: .day, value: days, to: startTime),
              let newEnd = calendar.date(byAdding: .day, value: days, to: endTime) else {
            return self
        }

        return VulnerableWindow(
            id: UUID(),
            userId: userId,
            date: newDate,
            startTime: newStart,
            endTime: newEnd,
            severity: severity,
            confidence: confidence,
            predictedTriggers: predictedTriggers,
            armorDelivered: false,
            armorCompleted: false,
            armorExerciseId: armorExerciseId,
            moodDuringWindow: nil,
            crashOccurred: nil,
            createdAt: Date()
        )
    }
}

// MARK: - Vulnerability Severity

extension VulnerableWindow {
    enum VulnerabilitySeverity: String, Codable, Comparable {
        case low
        case moderate
        case high

        var color: Color {
            switch self {
            case .low:
                return .yellow.opacity(0.3)
            case .moderate:
                return .orange.opacity(0.4)
            case .high:
                return .red.opacity(0.5)
            }
        }

        var displayName: String {
            switch self {
            case .low:
                return "Low Risk"
            case .moderate:
                return "Moderate Risk"
            case .high:
                return "High Risk"
            }
        }

        /// Lead time before window for armor notification
        var armorLeadTime: TimeInterval {
            switch self {
            case .low:
                return 15 * 60  // 15 minutes
            case .moderate:
                return 20 * 60  // 20 minutes
            case .high:
                return 30 * 60  // 30 minutes
            }
        }

        static func < (lhs: VulnerabilitySeverity, rhs: VulnerabilitySeverity) -> Bool {
            let order: [VulnerabilitySeverity] = [.low, .moderate, .high]
            guard let lhsIndex = order.firstIndex(of: lhs),
                  let rhsIndex = order.firstIndex(of: rhs) else {
                return false
            }
            return lhsIndex < rhsIndex
        }
    }
}

// MARK: - Armor Intervention

/// Brief exercise to strengthen resilience before vulnerable window
struct ArmorIntervention: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let durationSeconds: Int
    let interventionType: InterventionType
    let efficacyScore: Double

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case durationSeconds = "duration_seconds"
        case interventionType = "intervention_type"
        case efficacyScore = "efficacy_score"
    }

    enum InterventionType: String, Codable {
        case breathing
        case grounding
        case movement
        case cognitive

        var icon: String {
            switch self {
            case .breathing:
                return "wind"
            case .grounding:
                return "figure.mind.and.body"
            case .movement:
                return "figure.walk"
            case .cognitive:
                return "brain.head.profile"
            }
        }
    }

    /// Duration in minutes
    var durationMinutes: Int {
        durationSeconds / 60
    }
}

// MARK: - Circadian Error

/// Errors specific to circadian operations
enum CircadianError: LocalizedError {
    case profileNotFound
    case insufficientSleepData(daysAvailable: Int, required: Int)
    case predictionFailed(underlying: Error)
    case timezoneChanged
    case healthKitUnauthorized
    case invalidTimeWindow

    var errorDescription: String? {
        switch self {
        case .profileNotFound:
            return "Your circadian profile is still being built."
        case .insufficientSleepData(let available, let required):
            return "Not enough sleep data yet. Have \(available) days, need \(required) days."
        case .predictionFailed:
            return "Could not generate predictions."
        case .timezoneChanged:
            return "Timezone changed - updating your rhythm."
        case .healthKitUnauthorized:
            return "Sleep tracking permission needed."
        case .invalidTimeWindow:
            return "Invalid time window format."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .profileNotFound:
            return "Keep using the app. We'll analyze your rhythm in a few days."
        case .insufficientSleepData:
            return "Connect Apple Health to track sleep data."
        case .predictionFailed:
            return "Using general patterns. Try again later."
        case .timezoneChanged:
            return "Your predictions are being updated for your new location."
        case .healthKitUnauthorized:
            return "Open Settings → Health → MindFriend to allow sleep data access."
        case .invalidTimeWindow:
            return "Check the time format is HH:mm."
        }
    }
}

// MARK: - Extensions

extension Date {
    /// Get date at specific hour and minute
    func at(hour: Int, minute: Int) -> Date {
        let calendar = Calendar.current
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: self) ?? self
    }
}

extension TimeInterval {
    /// Convert hours to TimeInterval (seconds)
    static func hours(_ hours: Double) -> TimeInterval {
        return hours * 3600
    }

    /// Convert minutes to TimeInterval (seconds)
    static func minutes(_ minutes: Double) -> TimeInterval {
        return minutes * 60
    }

    /// Format as HH:mm string
    func toTimeString() -> String {
        let totalSeconds = Int(self)
        let hours = (totalSeconds / 3600) % 24
        let minutes = (totalSeconds % 3600) / 60
        return String(format: "%02d:%02d", hours, minutes)
    }
}

extension Array where Element == Double {
    /// Calculate average of array
    func average() -> Double {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }

    /// Calculate standard deviation
    func standardDeviation() -> Double {
        guard count > 1 else { return 0 }
        let mean = average()
        let variance = reduce(0) { $0 + pow($1 - mean, 2) } / Double(count - 1)
        return sqrt(variance)
    }
}
