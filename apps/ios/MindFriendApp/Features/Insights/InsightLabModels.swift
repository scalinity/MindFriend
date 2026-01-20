// InsightLabModels.swift
// Data models for 7-day insight experiments

import Foundation

// MARK: - Experiment Action Types

enum ExperimentActionType: String, CaseIterable, Codable, Identifiable {
    case morningWalk = "morning_walk"
    case meditationDaily = "meditation_daily"
    case noPhoneBeforeBed = "no_phone_before_bed"
    case gratitudeJournaling = "gratitude_journaling"
    case coldShower = "cold_shower"
    case digitalDetoxEvening = "digital_detox_evening"
    case exercise30min = "exercise_30min"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morningWalk: return "Morning Walk"
        case .meditationDaily: return "Daily Meditation"
        case .noPhoneBeforeBed: return "No Phone Before Bed"
        case .gratitudeJournaling: return "Gratitude Journaling"
        case .coldShower: return "Cold Shower"
        case .digitalDetoxEvening: return "Digital Detox Evening"
        case .exercise30min: return "30-Min Exercise"
        }
    }

    var description: String {
        switch self {
        case .morningWalk:
            return "Take a 15-minute walk each morning to boost energy and improve mood throughout the day."
        case .meditationDaily:
            return "Practice 10 minutes of meditation daily to reduce stress and increase mindfulness."
        case .noPhoneBeforeBed:
            return "Put your phone away 1 hour before bed to improve sleep quality."
        case .gratitudeJournaling:
            return "Write 3 things you're grateful for each day to shift focus toward positivity."
        case .coldShower:
            return "End your shower with 30 seconds of cold water to boost alertness and resilience."
        case .digitalDetoxEvening:
            return "Avoid screens for 2 hours each evening to reconnect with yourself and others."
        case .exercise30min:
            return "Complete 30 minutes of physical activity daily to boost endorphins and energy."
        }
    }

    var icon: String {
        switch self {
        case .morningWalk: return "figure.walk"
        case .meditationDaily: return "brain.head.profile"
        case .noPhoneBeforeBed: return "moon.zzz"
        case .gratitudeJournaling: return "heart.text.square"
        case .coldShower: return "drop.fill"
        case .digitalDetoxEvening: return "iphone.slash"
        case .exercise30min: return "figure.run"
        }
    }

    var color: String {
        switch self {
        case .morningWalk: return "green"
        case .meditationDaily: return "purple"
        case .noPhoneBeforeBed: return "indigo"
        case .gratitudeJournaling: return "orange"
        case .coldShower: return "cyan"
        case .digitalDetoxEvening: return "teal"
        case .exercise30min: return "red"
        }
    }
}

// MARK: - Experiment Status

enum ExperimentStatus: String, Codable {
    case active
    case completed
    case cancelled
}

// MARK: - Experiment Day

struct ExperimentDay: Codable, Identifiable {
    let dayIndex: Int
    var completed: Bool
    var completedAt: Date?
    var moodScore: Int?
    var energyScore: Int?

    var id: Int { dayIndex }

    enum CodingKeys: String, CodingKey {
        case dayIndex
        case completed
        case completedAt
        case moodScore
        case energyScore
    }
}

// MARK: - Insight Experiment

struct InsightExperiment: Codable, Identifiable {
    let id: UUID
    let title: String
    let description: String
    let actionType: String
    let startedAt: Date
    var endedAt: Date?
    var status: ExperimentStatus
    let baselineMoodAvg: Double?
    let baselineEnergyAvg: Double?
    var days: [ExperimentDay]

    var hasBaseline: Bool {
        baselineMoodAvg != nil || baselineEnergyAvg != nil
    }

    var currentDay: Int {
        let completedCount = days.filter { $0.completed }.count
        return min(completedCount + 1, 7)
    }

    var completedDays: Int {
        days.filter { $0.completed }.count
    }

    var daysRemaining: Int {
        7 - completedDays
    }

    var actionTypeEnum: ExperimentActionType? {
        ExperimentActionType(rawValue: actionType)
    }

    enum CodingKeys: String, CodingKey {
        case id = "experimentId"
        case title
        case description
        case actionType
        case startedAt
        case endedAt
        case status
        case baselineMoodAvg
        case baselineEnergyAvg
        case days
    }
}

// MARK: - API Response Models

struct StartExperimentResponse: Codable {
    let experimentId: UUID
    let title: String
    let description: String
    let actionType: String
    let startedAt: Date
    let status: ExperimentStatus
    let baselineMoodAvg: Double?
    let baselineEnergyAvg: Double?
    let hasBaseline: Bool
    let baselineDataPoints: Int
    let currentDay: Int
    let totalDays: Int
    let days: [ExperimentDay]
}

struct RecordDayResponse: Codable {
    let success: Bool
    let alreadyCompleted: Bool
    let dayIndex: Int
    let completedAt: Date?
    let moodScore: Int?
    let energyScore: Int?
    let experimentStatus: ExperimentStatus
    let completedDays: Int
    let daysRemaining: Int
    let reportReady: Bool
}

// MARK: - Report Models

struct MetricChange: Codable {
    let delta: Double?
    let baseline: Double?
    let experiment: Double?
    let hasBaseline: Bool
}

struct AdherenceStats: Codable {
    let rate: Double
    let completedDays: Int
    let totalDays: Int
}

struct Recommendation: Codable {
    let text: String
    let nextSteps: [String]
}

struct DateRange: Codable {
    let start: String
    let end: String
}

struct ExperimentReport: Codable, Identifiable {
    let experimentId: UUID
    let title: String
    let description: String
    let actionType: String
    let dateRange: DateRange
    let adherence: AdherenceStats
    let moodChange: MetricChange
    let energyChange: MetricChange
    let recommendation: Recommendation
    let insights: [String]
    let days: [ExperimentDay]
    let generatedAt: Date

    var id: UUID { experimentId }

    var actionTypeEnum: ExperimentActionType? {
        ExperimentActionType(rawValue: actionType)
    }

    var adherencePercentage: Int {
        Int(adherence.rate * 100)
    }

    var moodImproved: Bool {
        guard let delta = moodChange.delta else { return false }
        return delta >= 0.5
    }

    var moodDeclined: Bool {
        guard let delta = moodChange.delta else { return false }
        return delta <= -0.5
    }

    var shareText: String {
        var text = "\(title) Results\n"
        text += "Duration: \(dateRange.start) - \(dateRange.end)\n"
        text += "Adherence: \(adherencePercentage)% (\(adherence.completedDays)/\(adherence.totalDays) days)\n"

        if let delta = moodChange.delta {
            let direction = delta >= 0 ? "+" : ""
            text += "Mood Change: \(direction)\(String(format: "%.1f", delta))\n"
        }

        text += "\n\(recommendation.text)\n"
        text += "\n- Shared from MindFriend Insight Lab"

        return text
    }
}

// MARK: - Request Models

struct StartExperimentRequest: Encodable {
    let actionType: String
    let title: String
    let description: String
}

struct RecordDayRequest: Encodable {
    let experimentId: UUID
    let dayIndex: Int
    let moodScore: Int?
    let energyScore: Int?
}

struct GenerateReportRequest: Encodable {
    let experimentId: UUID
}
