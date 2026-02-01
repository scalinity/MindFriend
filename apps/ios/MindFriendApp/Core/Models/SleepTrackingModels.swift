import Foundation

// MARK: - Sleep Entry

/// Represents a daily sleep log (HealthKit sync or manual entry)
struct SleepEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let date: Date
    let source: SleepSource

    // Timing
    let bedtime: Date
    let wakeTime: Date
    let timeInBedMinutes: Int
    let timeAsleepMinutes: Int?

    // Sleep Stages (from wearables)
    let deepSleepMinutes: Int?
    let remSleepMinutes: Int?
    let lightSleepMinutes: Int?
    let awakeMinutes: Int?

    // Quality Metrics
    let sleepEfficiency: Double? // Percentage (0-100)
    let heartRateAvg: Int?
    let heartRateMin: Int?
    let hrvAvg: Double?
    let respiratoryRate: Double?

    // User Input
    var userRating: Int? // 1-5 stars
    var dreamNotes: String?
    var notes: String?

    // Calculated
    var sleepScore: Int? // 0-100
    var scoreBreakdown: SleepScoreBreakdown?

    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case source
        case bedtime
        case wakeTime = "wake_time"
        case timeInBedMinutes = "time_in_bed_minutes"
        case timeAsleepMinutes = "time_asleep_minutes"
        case deepSleepMinutes = "deep_sleep_minutes"
        case remSleepMinutes = "rem_sleep_minutes"
        case lightSleepMinutes = "light_sleep_minutes"
        case awakeMinutes = "awake_minutes"
        case sleepEfficiency = "sleep_efficiency"
        case heartRateAvg = "heart_rate_avg"
        case heartRateMin = "heart_rate_min"
        case hrvAvg = "hrv_avg"
        case respiratoryRate = "respiratory_rate"
        case userRating = "user_rating"
        case dreamNotes = "dream_notes"
        case notes
        case sleepScore = "sleep_score"
        case scoreBreakdown = "score_breakdown"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // MARK: - Date Format Helpers

    /// Formatter for PostgreSQL DATE type (YYYY-MM-DD)
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0) // UTC for date-only values
        return formatter
    }()

    // MARK: - Validation Constants

    private enum ValidationLimits {
        static let maxMinutesPerDay = 1440 // 24 hours
        static let maxHeartRate = 300 // Physiological maximum
        static let minHeartRate = 20 // Physiological minimum
        static let maxHRV = 500.0 // Physiological maximum ms
        static let maxRespiratoryRate = 60.0 // Physiological maximum breaths/min
        static let maxTextLength = 10000 // Characters
        static let ratingRange = 1...5
        static let scoreRange = 0...100
        static let efficiencyRange = 0.0...100.0
    }

    // MARK: - Custom Decoding for DATE column

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        userId = try container.decode(UUID.self, forKey: .userId)
        source = try container.decode(SleepSource.self, forKey: .source)

        // Decode DATE column as string and convert to Date
        let dateString = try container.decode(String.self, forKey: .date)
        guard let parsedDate = Self.dateFormatter.date(from: dateString) else {
            throw DecodingError.dataCorruptedError(
                forKey: .date,
                in: container,
                debugDescription: "Invalid date format"
            )
        }
        date = parsedDate

        // TIMESTAMPTZ fields decode normally as Date
        bedtime = try container.decode(Date.self, forKey: .bedtime)
        wakeTime = try container.decode(Date.self, forKey: .wakeTime)

        // Validate time duration fields (must be non-negative and reasonable)
        let decodedTimeInBed = try container.decode(Int.self, forKey: .timeInBedMinutes)
        guard decodedTimeInBed >= 0 && decodedTimeInBed <= ValidationLimits.maxMinutesPerDay else {
            throw DecodingError.dataCorruptedError(
                forKey: .timeInBedMinutes,
                in: container,
                debugDescription: "Invalid duration range"
            )
        }
        timeInBedMinutes = decodedTimeInBed

        timeAsleepMinutes = try Self.decodeValidatedMinutes(from: container, forKey: .timeAsleepMinutes)
        deepSleepMinutes = try Self.decodeValidatedMinutes(from: container, forKey: .deepSleepMinutes)
        remSleepMinutes = try Self.decodeValidatedMinutes(from: container, forKey: .remSleepMinutes)
        lightSleepMinutes = try Self.decodeValidatedMinutes(from: container, forKey: .lightSleepMinutes)
        awakeMinutes = try Self.decodeValidatedMinutes(from: container, forKey: .awakeMinutes)

        // Validate sleep efficiency (0-100%)
        if let efficiency = try container.decodeIfPresent(Double.self, forKey: .sleepEfficiency) {
            guard ValidationLimits.efficiencyRange.contains(efficiency) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .sleepEfficiency,
                    in: container,
                    debugDescription: "Invalid percentage"
                )
            }
            sleepEfficiency = efficiency
        } else {
            sleepEfficiency = nil
        }

        // Validate heart rate fields
        heartRateAvg = try Self.decodeValidatedHeartRate(from: container, forKey: .heartRateAvg)
        heartRateMin = try Self.decodeValidatedHeartRate(from: container, forKey: .heartRateMin)

        // Validate HRV
        if let hrv = try container.decodeIfPresent(Double.self, forKey: .hrvAvg) {
            guard hrv >= 0 && hrv <= ValidationLimits.maxHRV else {
                throw DecodingError.dataCorruptedError(
                    forKey: .hrvAvg,
                    in: container,
                    debugDescription: "Invalid HRV range"
                )
            }
            hrvAvg = hrv
        } else {
            hrvAvg = nil
        }

        // Validate respiratory rate
        if let rate = try container.decodeIfPresent(Double.self, forKey: .respiratoryRate) {
            guard rate >= 0 && rate <= ValidationLimits.maxRespiratoryRate else {
                throw DecodingError.dataCorruptedError(
                    forKey: .respiratoryRate,
                    in: container,
                    debugDescription: "Invalid respiratory rate"
                )
            }
            respiratoryRate = rate
        } else {
            respiratoryRate = nil
        }

        // Validate user rating (1-5)
        if let rating = try container.decodeIfPresent(Int.self, forKey: .userRating) {
            guard ValidationLimits.ratingRange.contains(rating) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .userRating,
                    in: container,
                    debugDescription: "Invalid rating range"
                )
            }
            userRating = rating
        } else {
            userRating = nil
        }

        // Validate text fields (length limit, strip control characters)
        dreamNotes = try Self.decodeValidatedText(from: container, forKey: .dreamNotes)
        notes = try Self.decodeValidatedText(from: container, forKey: .notes)

        // Validate sleep score (0-100)
        if let score = try container.decodeIfPresent(Int.self, forKey: .sleepScore) {
            guard ValidationLimits.scoreRange.contains(score) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .sleepScore,
                    in: container,
                    debugDescription: "Invalid score range"
                )
            }
            sleepScore = score
        } else {
            sleepScore = nil
        }

        scoreBreakdown = try container.decodeIfPresent(SleepScoreBreakdown.self, forKey: .scoreBreakdown)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)

        // Validate cross-field constraints
        try validateCrossFieldConstraints()
    }

    // MARK: - Validation Helpers

    private static func decodeValidatedMinutes(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Int? {
        guard let minutes = try container.decodeIfPresent(Int.self, forKey: key) else {
            return nil
        }
        guard minutes >= 0 && minutes <= ValidationLimits.maxMinutesPerDay else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Invalid duration range"
            )
        }
        return minutes
    }

    private static func decodeValidatedHeartRate(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Int? {
        guard let rate = try container.decodeIfPresent(Int.self, forKey: key) else {
            return nil
        }
        guard rate >= ValidationLimits.minHeartRate && rate <= ValidationLimits.maxHeartRate else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Invalid heart rate"
            )
        }
        return rate
    }

    private static func decodeValidatedText(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> String? {
        guard let text = try container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        guard text.count <= ValidationLimits.maxTextLength else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Text exceeds maximum length"
            )
        }
        // Strip control characters except newline and tab (safe whitespace)
        return text.filter { char in
            char == "\n" || char == "\t" || !char.isASCII || (char.isASCII && char.asciiValue! >= 32)
        }
    }

    // MARK: - Cross-Field Validation

    private func validateCrossFieldConstraints() throws {
        // Rule 1: timeAsleepMinutes <= timeInBedMinutes
        if let asleep = timeAsleepMinutes {
            guard asleep <= timeInBedMinutes else {
                throw ValidationError.invalidCrossFieldConstraint(
                    "Sleep time (\(asleep)m) cannot exceed time in bed (\(timeInBedMinutes)m)"
                )
            }
        }

        // Rule 2: Sleep stages sum <= timeAsleepMinutes (or timeInBedMinutes if asleep is nil)
        let maxStageTime = timeAsleepMinutes ?? timeInBedMinutes
        let stageSum = [deepSleepMinutes, remSleepMinutes, lightSleepMinutes, awakeMinutes]
            .compactMap { $0 }
            .reduce(0, +)

        if stageSum > 0 {
            guard stageSum <= maxStageTime else {
                throw ValidationError.invalidCrossFieldConstraint(
                    "Sleep stages (\(stageSum)m) cannot exceed total time (\(maxStageTime)m)"
                )
            }
        }
    }

    enum ValidationError: Error, LocalizedError {
        case invalidCrossFieldConstraint(String)

        var errorDescription: String? {
            switch self {
            case .invalidCrossFieldConstraint(let message):
                return message
            }
        }
    }

    // MARK: - Custom Encoding for DATE column

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)

        // Encode Date as DATE string (YYYY-MM-DD) for PostgreSQL DATE column
        let dateString = Self.dateFormatter.string(from: date)
        try container.encode(dateString, forKey: .date)

        try container.encode(source, forKey: .source)
        try container.encode(bedtime, forKey: .bedtime)
        try container.encode(wakeTime, forKey: .wakeTime)
        try container.encode(timeInBedMinutes, forKey: .timeInBedMinutes)
        try container.encodeIfPresent(timeAsleepMinutes, forKey: .timeAsleepMinutes)
        try container.encodeIfPresent(deepSleepMinutes, forKey: .deepSleepMinutes)
        try container.encodeIfPresent(remSleepMinutes, forKey: .remSleepMinutes)
        try container.encodeIfPresent(lightSleepMinutes, forKey: .lightSleepMinutes)
        try container.encodeIfPresent(awakeMinutes, forKey: .awakeMinutes)
        try container.encodeIfPresent(sleepEfficiency, forKey: .sleepEfficiency)
        try container.encodeIfPresent(heartRateAvg, forKey: .heartRateAvg)
        try container.encodeIfPresent(heartRateMin, forKey: .heartRateMin)
        try container.encodeIfPresent(hrvAvg, forKey: .hrvAvg)
        try container.encodeIfPresent(respiratoryRate, forKey: .respiratoryRate)
        try container.encodeIfPresent(userRating, forKey: .userRating)
        try container.encodeIfPresent(dreamNotes, forKey: .dreamNotes)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encodeIfPresent(sleepScore, forKey: .sleepScore)
        try container.encodeIfPresent(scoreBreakdown, forKey: .scoreBreakdown)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    // MARK: - Memberwise Initializer

    init(
        id: UUID,
        userId: UUID,
        date: Date,
        source: SleepSource,
        bedtime: Date,
        wakeTime: Date,
        timeInBedMinutes: Int,
        timeAsleepMinutes: Int?,
        deepSleepMinutes: Int?,
        remSleepMinutes: Int?,
        lightSleepMinutes: Int?,
        awakeMinutes: Int?,
        sleepEfficiency: Double?,
        heartRateAvg: Int?,
        heartRateMin: Int?,
        hrvAvg: Double?,
        respiratoryRate: Double?,
        userRating: Int?,
        dreamNotes: String?,
        notes: String?,
        sleepScore: Int?,
        scoreBreakdown: SleepScoreBreakdown?,
        createdAt: Date,
        updatedAt: Date
    ) {
        // Validate ranges (runtime safety)
        precondition(
            timeInBedMinutes >= 0 && timeInBedMinutes <= ValidationLimits.maxMinutesPerDay,
            "Invalid timeInBedMinutes: \(timeInBedMinutes)"
        )
        if let asleep = timeAsleepMinutes {
            precondition(
                asleep >= 0 && asleep <= ValidationLimits.maxMinutesPerDay,
                "Invalid timeAsleepMinutes: \(asleep)"
            )
            precondition(asleep <= timeInBedMinutes, "timeAsleepMinutes cannot exceed timeInBedMinutes")
        }
        if let rating = userRating {
            precondition(ValidationLimits.ratingRange.contains(rating), "Invalid userRating: \(rating)")
        }
        if let score = sleepScore {
            precondition(ValidationLimits.scoreRange.contains(score), "Invalid sleepScore: \(score)")
        }
        if let efficiency = sleepEfficiency {
            precondition(ValidationLimits.efficiencyRange.contains(efficiency), "Invalid sleepEfficiency")
        }
        if let hr = heartRateAvg {
            precondition(
                hr >= ValidationLimits.minHeartRate && hr <= ValidationLimits.maxHeartRate,
                "Invalid heartRateAvg"
            )
        }
        if let hr = heartRateMin {
            precondition(
                hr >= ValidationLimits.minHeartRate && hr <= ValidationLimits.maxHeartRate,
                "Invalid heartRateMin"
            )
        }

        self.id = id
        self.userId = userId
        self.date = date
        self.source = source
        self.bedtime = bedtime
        self.wakeTime = wakeTime
        self.timeInBedMinutes = timeInBedMinutes
        self.timeAsleepMinutes = timeAsleepMinutes
        self.deepSleepMinutes = deepSleepMinutes
        self.remSleepMinutes = remSleepMinutes
        self.lightSleepMinutes = lightSleepMinutes
        self.awakeMinutes = awakeMinutes
        self.sleepEfficiency = sleepEfficiency
        self.heartRateAvg = heartRateAvg
        self.heartRateMin = heartRateMin
        self.hrvAvg = hrvAvg
        self.respiratoryRate = respiratoryRate
        self.userRating = userRating
        self.dreamNotes = dreamNotes
        self.notes = notes
        self.sleepScore = sleepScore
        self.scoreBreakdown = scoreBreakdown
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Computed Properties

    var durationFormatted: String {
        let minutes = timeAsleepMinutes ?? timeInBedMinutes
        let hours = minutes / 60
        let mins = minutes % 60
        return "\(hours)h \(mins)m"
    }

    var hasWearableData: Bool {
        deepSleepMinutes != nil || remSleepMinutes != nil
    }

    var qualityLabel: String {
        guard let score = sleepScore else { return "Unknown" }
        switch score {
        case 85...100: return "Excellent"
        case 70..<85: return "Good"
        case 55..<70: return "Fair"
        default: return "Poor"
        }
    }
}

// MARK: - Sleep Source

enum SleepSource: String, Codable, CaseIterable {
    case healthkit
    case manual
    case appleWatch = "apple_watch"

    var displayName: String {
        switch self {
        case .healthkit: return "Health App"
        case .manual: return "Manual Entry"
        case .appleWatch: return "Apple Watch"
        }
    }
}

// MARK: - Sleep Score Breakdown

struct SleepScoreBreakdown: Codable, Equatable {
    let duration: Int // 0-25 points
    let efficiency: Int // 0-25 points
    let timing: Int // 0-20 points
    let stages: Int // 0-20 points
    let restfulness: Int // 0-10 points

    var total: Int {
        duration + efficiency + timing + stages + restfulness
    }

    /// Returns the lowest scoring component (the area needing improvement)
    var primaryFactor: String {
        let factors: [(String, Int)] = [
            ("Duration", duration),
            ("Efficiency", efficiency),
            ("Timing", timing),
            ("Sleep Stages", stages),
            ("Restfulness", restfulness)
        ]
        return factors.min(by: { $0.1 < $1.1 })?.0 ?? "Duration"
    }

    /// Returns explanation for each component score
    func explanation(for component: String) -> String {
        switch component {
        case "Duration":
            return "How close your sleep duration was to your target"
        case "Efficiency":
            return "Percentage of time in bed actually asleep"
        case "Timing":
            return "Consistency with your target bedtime"
        case "Sleep Stages":
            return "Quality of deep and REM sleep cycles"
        case "Restfulness":
            return "How often you woke during the night"
        default:
            return "Unknown component"
        }
    }
}

// MARK: - Sleep Goals

struct SleepGoals: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    var targetBedtime: Date? // Time component only
    var targetWakeTime: Date?
    var targetDurationMinutes: Int // Default: 480 (8 hours)
    var windDownDurationMinutes: Int // Default: 30
    var bedtimeReminderEnabled: Bool
    var bedtimeReminderOffsetMinutes: Int // Default: 60 (1 hour before)
    var preferredWindDownTypes: [String] // ["breathing", "meditation", etc.]
    var sleepEnvironmentPrefs: SleepEnvironmentPrefs
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case targetBedtime = "target_bedtime"
        case targetWakeTime = "target_wake_time"
        case targetDurationMinutes = "target_duration_minutes"
        case windDownDurationMinutes = "wind_down_duration_minutes"
        case bedtimeReminderEnabled = "bedtime_reminder_enabled"
        case bedtimeReminderOffsetMinutes = "bedtime_reminder_offset_minutes"
        case preferredWindDownTypes = "preferred_wind_down_types"
        case sleepEnvironmentPrefs = "sleep_environment_prefs"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
    
    // MARK: - Time Format Helpers

    /// Formatter for PostgreSQL TIME type (HH:mm:ss)
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0) // UTC for time-only values
        return formatter
    }()

    /// Formatter for displaying time to user (thread-safe, reusable)
    private static let displayTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    // MARK: - Validation Constants

    private enum ValidationLimits {
        static let maxMinutesPerDay = 1440 // 24 hours
        static let maxReminderOffsetMinutes = 480 // 8 hours
        static let validWindDownTypes: Set<String> = [
            "breathing", "meditation", "grounding", "journaling", "movement", "stretching"
        ]
    }

    // MARK: - Custom Encoding/Decoding for TIME columns

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        userId = try container.decode(UUID.self, forKey: .userId)

        // Validate duration fields
        let decodedDuration = try container.decode(Int.self, forKey: .targetDurationMinutes)
        guard decodedDuration >= 0 && decodedDuration <= ValidationLimits.maxMinutesPerDay else {
            throw DecodingError.dataCorruptedError(
                forKey: .targetDurationMinutes,
                in: container,
                debugDescription: "Invalid duration range"
            )
        }
        targetDurationMinutes = decodedDuration

        let decodedWindDown = try container.decode(Int.self, forKey: .windDownDurationMinutes)
        guard decodedWindDown >= 0 && decodedWindDown <= ValidationLimits.maxMinutesPerDay else {
            throw DecodingError.dataCorruptedError(
                forKey: .windDownDurationMinutes,
                in: container,
                debugDescription: "Invalid duration range"
            )
        }
        windDownDurationMinutes = decodedWindDown

        bedtimeReminderEnabled = try container.decode(Bool.self, forKey: .bedtimeReminderEnabled)

        let decodedOffset = try container.decode(Int.self, forKey: .bedtimeReminderOffsetMinutes)
        guard decodedOffset >= 0 && decodedOffset <= ValidationLimits.maxReminderOffsetMinutes else {
            throw DecodingError.dataCorruptedError(
                forKey: .bedtimeReminderOffsetMinutes,
                in: container,
                debugDescription: "Invalid offset range"
            )
        }
        bedtimeReminderOffsetMinutes = decodedOffset

        // Validate and filter wind-down types (allow only valid types)
        let decodedTypes = try container.decode([String].self, forKey: .preferredWindDownTypes)
        let filteredTypes = decodedTypes.filter { ValidationLimits.validWindDownTypes.contains($0) }
        preferredWindDownTypes = filteredTypes

        sleepEnvironmentPrefs = try container.decode(SleepEnvironmentPrefs.self, forKey: .sleepEnvironmentPrefs)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)

        // Decode TIME columns as strings and convert to Date (with validation)
        if let timeString = try container.decodeIfPresent(String.self, forKey: .targetBedtime) {
            guard let parsedTime = Self.timeFormatter.date(from: timeString) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .targetBedtime,
                    in: container,
                    debugDescription: "Invalid time format"
                )
            }
            targetBedtime = parsedTime
        } else {
            targetBedtime = nil
        }

        if let timeString = try container.decodeIfPresent(String.self, forKey: .targetWakeTime) {
            guard let parsedTime = Self.timeFormatter.date(from: timeString) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .targetWakeTime,
                    in: container,
                    debugDescription: "Invalid time format"
                )
            }
            targetWakeTime = parsedTime
        } else {
            targetWakeTime = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(targetDurationMinutes, forKey: .targetDurationMinutes)
        try container.encode(windDownDurationMinutes, forKey: .windDownDurationMinutes)
        try container.encode(bedtimeReminderEnabled, forKey: .bedtimeReminderEnabled)
        try container.encode(bedtimeReminderOffsetMinutes, forKey: .bedtimeReminderOffsetMinutes)
        try container.encode(preferredWindDownTypes, forKey: .preferredWindDownTypes)
        try container.encode(sleepEnvironmentPrefs, forKey: .sleepEnvironmentPrefs)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        
        // Encode Date as TIME string (HH:mm:ss) for PostgreSQL TIME columns
        if let bedtime = targetBedtime {
            try container.encode(Self.timeFormatter.string(from: bedtime), forKey: .targetBedtime)
        } else {
            try container.encodeNil(forKey: .targetBedtime)
        }
        
        if let wakeTime = targetWakeTime {
            try container.encode(Self.timeFormatter.string(from: wakeTime), forKey: .targetWakeTime)
        } else {
            try container.encodeNil(forKey: .targetWakeTime)
        }
    }
    
    // MARK: - Memberwise Initializer
    
    init(
        id: UUID,
        userId: UUID,
        targetBedtime: Date?,
        targetWakeTime: Date?,
        targetDurationMinutes: Int,
        windDownDurationMinutes: Int,
        bedtimeReminderEnabled: Bool,
        bedtimeReminderOffsetMinutes: Int,
        preferredWindDownTypes: [String],
        sleepEnvironmentPrefs: SleepEnvironmentPrefs,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.userId = userId
        self.targetBedtime = targetBedtime
        self.targetWakeTime = targetWakeTime
        self.targetDurationMinutes = targetDurationMinutes
        self.windDownDurationMinutes = windDownDurationMinutes
        self.bedtimeReminderEnabled = bedtimeReminderEnabled
        self.bedtimeReminderOffsetMinutes = bedtimeReminderOffsetMinutes
        self.preferredWindDownTypes = preferredWindDownTypes
        self.sleepEnvironmentPrefs = sleepEnvironmentPrefs
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Computed Properties

    var targetDurationFormatted: String {
        let hours = targetDurationMinutes / 60
        let mins = targetDurationMinutes % 60
        return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h"
    }

    var bedtimeFormatted: String? {
        targetBedtime.map { Self.displayTimeFormatter.string(from: $0) }
    }

    var wakeTimeFormatted: String? {
        targetWakeTime.map { Self.displayTimeFormatter.string(from: $0) }
    }
}

// MARK: - Sleep Environment Preferences

struct SleepEnvironmentPrefs: Codable, Equatable {
    var prefersDarkRoom: Bool?
    var prefersCoolRoom: Bool?
    var usesWhiteNoise: Bool?
    var hasBlueLight: Bool?

    init(
        prefersDarkRoom: Bool? = nil,
        prefersCoolRoom: Bool? = nil,
        usesWhiteNoise: Bool? = nil,
        hasBlueLight: Bool? = nil
    ) {
        self.prefersDarkRoom = prefersDarkRoom
        self.prefersCoolRoom = prefersCoolRoom
        self.usesWhiteNoise = usesWhiteNoise
        self.hasBlueLight = hasBlueLight
    }
}

// MARK: - Sleep Debt

struct SleepDebt: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    var currentDebtMinutes: Int
    let weekAvgDurationMinutes: Int?
    let optimalDurationMinutes: Int
    let lastCalculated: Date
    let debtHistory: [DailyDebt]
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case currentDebtMinutes = "current_debt_minutes"
        case weekAvgDurationMinutes = "week_avg_duration_minutes"
        case optimalDurationMinutes = "optimal_duration_minutes"
        case lastCalculated = "last_calculated"
        case debtHistory = "debt_history"
        case createdAt = "created_at"
    }

    // MARK: - Computed Properties

    var debtHours: Double {
        Double(currentDebtMinutes) / 60.0
    }

    var isInDebt: Bool {
        currentDebtMinutes > 30 // More than 30 minutes debt
    }

    var debtFormatted: String {
        let hours = abs(currentDebtMinutes) / 60
        let mins = abs(currentDebtMinutes) % 60

        if currentDebtMinutes < 0 {
            return "+\(hours)h \(mins)m" // Sleep surplus
        } else if currentDebtMinutes > 0 {
            return "-\(hours)h \(mins)m" // Sleep debt
        } else {
            return "0h" // No debt
        }
    }

    /// Estimate nights needed to recover (assuming 1 hour extra sleep per night)
    var recoveryNights: Int {
        guard currentDebtMinutes > 0 else { return 0 }
        return Int(ceil(Double(currentDebtMinutes) / 60.0))
    }
}

struct DailyDebt: Codable, Equatable {
    let date: Date
    let debtMinutes: Int
}

// MARK: - Wind-Down Session

struct WindDownSession: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let startedAt: Date
    var completedAt: Date?
    let routine: [WindDownActivity]
    let durationPlannedMinutes: Int
    var durationActualMinutes: Int?
    var completed: Bool
    var sleepEntryId: UUID?
    var feedbackRating: Int? // 1-5 stars
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case routine
        case durationPlannedMinutes = "duration_planned_minutes"
        case durationActualMinutes = "duration_actual_minutes"
        case completed
        case sleepEntryId = "sleep_entry_id"
        case feedbackRating = "feedback_rating"
        case createdAt = "created_at"
    }

    // MARK: - Computed Properties

    var progress: Double {
        let completedCount = routine.filter { $0.completed }.count
        return Double(completedCount) / Double(routine.count)
    }

    var progressFormatted: String {
        let completedCount = routine.filter { $0.completed }.count
        return "\(completedCount)/\(routine.count) activities"
    }

    var nextActivity: WindDownActivity? {
        routine.first { !$0.completed }
    }
}

struct WindDownActivity: Codable, Identifiable, Equatable {
    let id: UUID
    let type: String // "breathing", "meditation", "journaling", "stretching"
    let exerciseId: UUID?
    let name: String
    let durationMinutes: Int
    var completed: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case exerciseId = "exercise_id"
        case name
        case durationMinutes = "duration_minutes"
        case completed
    }

    var icon: String {
        switch type {
        case "breathing": return "wind"
        case "meditation": return "brain.head.profile"
        case "journaling": return "book.pages"
        case "stretching": return "figure.flexibility"
        default: return "moon.stars.fill"
        }
    }
}

// MARK: - Sleep Insight

struct SleepInsight: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let insightType: SleepInsightType
    let insightData: SleepInsightData
    let generatedAt: Date
    let validUntil: Date
    var viewed: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case insightType = "insight_type"
        case insightData = "insight_data"
        case generatedAt = "generated_at"
        case validUntil = "valid_until"
        case viewed
        case createdAt = "created_at"
    }

    var isValid: Bool {
        validUntil > Date()
    }
}

enum SleepInsightType: String, Codable, CaseIterable {
    case weeklyReport = "weekly_report"
    case moodCorrelation = "mood_correlation"
    case patternDetected = "pattern_detected"
    case improvement = "improvement"
    case concern = "concern"

    var icon: String {
        switch self {
        case .weeklyReport: return "chart.bar.fill"
        case .moodCorrelation: return "arrow.triangle.branch"
        case .patternDetected: return "waveform.path.ecg"
        case .improvement: return "arrow.up.circle.fill"
        case .concern: return "exclamationmark.triangle.fill"
        }
    }

    var color: String {
        switch self {
        case .weeklyReport: return "blue"
        case .moodCorrelation: return "purple"
        case .patternDetected: return "orange"
        case .improvement: return "green"
        case .concern: return "red"
        }
    }
}

struct SleepInsightData: Codable, Equatable {
    let title: String
    let message: String
    let metric: String?
    let value: Double?
    let trend: String? // "improving", "declining", "stable"
    let recommendation: String?

    var trendIcon: String? {
        guard let trend = trend else { return nil }
        switch trend {
        case "improving": return "arrow.up.right"
        case "declining": return "arrow.down.right"
        case "stable": return "arrow.right"
        default: return nil
        }
    }
}

// MARK: - Sleep Weekly Stats (for insights)

struct SleepWeeklyStats: Codable, Equatable {
    let avgDuration: Int // Average sleep duration in minutes
    let avgScore: Int // Average sleep score (0-100)
    let avgBedtime: String // Average bedtime (HH:MM format)
    let avgWakeTime: String // Average wake time (HH:MM format)
    let consistency: Double // Consistency score (0-1)
    let totalNights: Int

    enum CodingKeys: String, CodingKey {
        case avgDuration = "avg_duration"
        case avgScore = "avg_score"
        case avgBedtime = "avg_bedtime"
        case avgWakeTime = "avg_wake_time"
        case consistency
        case totalNights = "total_nights"
    }
}

// MARK: - Create/Update DTOs

struct CreateSleepEntryDTO: Encodable {
    let userId: UUID
    let date: String // YYYY-MM-DD
    let source: String
    let bedtime: String // ISO 8601
    let wakeTime: String // ISO 8601
    let timeInBedMinutes: Int
    let timeAsleepMinutes: Int?
    let deepSleepMinutes: Int?
    let remSleepMinutes: Int?
    let lightSleepMinutes: Int?
    let awakeMinutes: Int?
    let sleepEfficiency: Double?
    let heartRateAvg: Int?
    let heartRateMin: Int?
    let hrvAvg: Double?
    let respiratoryRate: Double?
    let userRating: Int?
    let dreamNotes: String?
    let notes: String?
    let sleepScore: Int?
    let scoreBreakdown: SleepScoreBreakdown?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case date, source, bedtime
        case wakeTime = "wake_time"
        case timeInBedMinutes = "time_in_bed_minutes"
        case timeAsleepMinutes = "time_asleep_minutes"
        case deepSleepMinutes = "deep_sleep_minutes"
        case remSleepMinutes = "rem_sleep_minutes"
        case lightSleepMinutes = "light_sleep_minutes"
        case awakeMinutes = "awake_minutes"
        case sleepEfficiency = "sleep_efficiency"
        case heartRateAvg = "heart_rate_avg"
        case heartRateMin = "heart_rate_min"
        case hrvAvg = "hrv_avg"
        case respiratoryRate = "respiratory_rate"
        case userRating = "user_rating"
        case dreamNotes = "dream_notes"
        case notes
        case sleepScore = "sleep_score"
        case scoreBreakdown = "score_breakdown"
    }
}

struct UpdateSleepEntryDTO: Encodable {
    let userRating: Int?
    let dreamNotes: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case userRating = "user_rating"
        case dreamNotes = "dream_notes"
        case notes
    }
}
