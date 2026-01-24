//  InterventionTimingModels.swift
//  MindFriendApp
//
//  Created by Context-Aware Interventions Feature
//  Models for intervention preferences, triggers, and delivery tracking

import Foundation

// MARK: - Intervention Preferences

struct InterventionPreferences: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    var enabled: Bool
    var maxDaily: Int
    var quietHoursStart: String? // TIME format: "22:00:00"
    var quietHoursEnd: String? // TIME format: "06:00:00"
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case enabled
        case maxDaily = "max_daily"
        case quietHoursStart = "quiet_hours_start"
        case quietHoursEnd = "quiet_hours_end"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    static var `default`: InterventionPreferences {
        InterventionPreferences(
            id: UUID(),
            userId: UUID(),
            enabled: true,
            maxDaily: 5,
            quietHoursStart: nil,
            quietHoursEnd: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    // Helper: Get quiet hours as Date components for time pickers
    var quietStartTime: Date? {
        guard let timeString = quietHoursStart else { return nil }
        return parseTimeString(timeString)
    }

    var quietEndTime: Date? {
        guard let timeString = quietHoursEnd else { return nil }
        return parseTimeString(timeString)
    }

    private func parseTimeString(_ timeString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.date(from: timeString)
    }

    // Helper: Set quiet hours from Date (time components only)
    mutating func setQuietHours(start: Date?, end: Date?) {
        if let start = start {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            quietHoursStart = formatter.string(from: start)
        } else {
            quietHoursStart = nil
        }

        if let end = end {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            quietHoursEnd = formatter.string(from: end)
        } else {
            quietHoursEnd = nil
        }
    }
}

// MARK: - Intervention Trigger

enum TriggerType: String, Codable, CaseIterable {
    case timeBased = "time_based"
    case biometric = "biometric"
    case pattern = "pattern"
    case calendar = "calendar"
    case manual = "manual"

    var displayName: String {
        switch self {
        case .timeBased: return "Time-Based"
        case .biometric: return "Biometric"
        case .pattern: return "Pattern"
        case .calendar: return "Calendar"
        case .manual: return "Manual"
        }
    }
}

struct InterventionTrigger: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let triggerType: TriggerType
    let triggerConfig: [String: AnyCodableValue]
    let isActive: Bool
    let priority: Int
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case triggerType = "trigger_type"
        case triggerConfig = "trigger_config"
        case isActive = "is_active"
        case priority
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Intervention Delivery

struct InterventionDelivery: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let interventionId: UUID
    let triggerId: UUID?
    let triggerType: TriggerType?
    let contextSnapshot: [String: AnyCodableValue]?
    let deliveredAt: Date
    var completed: Bool
    var completedAt: Date?
    var dismissedAt: Date?
    var rating: Int?
    var feedback: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case interventionId = "intervention_id"
        case triggerId = "trigger_id"
        case triggerType = "trigger_type"
        case contextSnapshot = "context_snapshot"
        case deliveredAt = "delivered_at"
        case completed
        case completedAt = "completed_at"
        case dismissedAt = "dismissed_at"
        case rating
        case feedback
    }
}

// MARK: - API Request/Response Types

struct TriggerContext: Codable {
    let biometrics: Biometrics?
    let timeOfDay: String?
    let recentMood: Int?

    struct Biometrics: Codable {
        let heartRate: Double?
        let hrv: Double?
    }

    enum CodingKeys: String, CodingKey {
        case biometrics
        case timeOfDay = "time_of_day"
        case recentMood = "recent_mood"
    }
}

struct CheckTriggersRequest: Codable {
    let context: TriggerContext?
}

struct CheckTriggersResponse: Codable {
    let shouldTrigger: Bool
    let triggerType: TriggerType?
    let intervention: MicroMomentTemplate?
    let contextMessage: String?
    let suppressionReason: String?

    enum CodingKeys: String, CodingKey {
        case shouldTrigger = "should_trigger"
        case triggerType = "trigger_type"
        case intervention
        case contextMessage = "context_message"
        case suppressionReason = "suppression_reason"
    }
}

// MARK: - AnyCodable Helper

struct AnyCodableValue: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let arrayValue = try? container.decode([AnyCodableValue].self) {
            value = arrayValue.map { $0.value }
        } else if let dictValue = try? container.decode([String: AnyCodableValue].self) {
            value = dictValue.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let intValue as Int:
            try container.encode(intValue)
        case let doubleValue as Double:
            try container.encode(doubleValue)
        case let stringValue as String:
            try container.encode(stringValue)
        case let boolValue as Bool:
            try container.encode(boolValue)
        case let arrayValue as [Any]:
            try container.encode(arrayValue.map { AnyCodableValue($0) })
        case let dictValue as [String: Any]:
            try container.encode(dictValue.mapValues { AnyCodableValue($0) })
        default:
            try container.encodeNil()
        }
    }
}
