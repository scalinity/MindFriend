import Foundation
import OSLog

/// Service for calendar integration and stress prediction
/// Analyzes meeting patterns to predict stress and suggest interventions
final class CalendarIntegrationService {
    private let oauthHandler: OAuthHandler
    private let logger = Logger(subsystem: "com.mindfriend", category: "Calendar")

    // MARK: - Stress Thresholds

    private struct Thresholds {
        /// Number of meetings considered "hectic"
        static let hecticDayThreshold = 6

        /// Minutes between meetings to be considered "back-to-back"
        static let backToBackGapMinutes = 15

        /// Hour before which meetings are considered "early"
        static let earlyMeetingHour = 8

        /// Duration in minutes for a "marathon" meeting
        static let marathonMeetingMinutes = 180

        /// Days ahead to analyze for stress prediction
        static let analysisDaysAhead = 7
    }

    init(oauthHandler: OAuthHandler) {
        self.oauthHandler = oauthHandler
    }

    // MARK: - Sync Operations

    /// Syncs calendar events from connected providers
    func sync() async throws {
        logger.info("Syncing calendar data")

        // This would fetch from Google Calendar API or Microsoft Graph API
        // For now, we'll work with cached/fetched events
    }

    // MARK: - Event Fetching

    /// Fetches calendar events for the specified number of days
    func getEvents(days: Int = 7) async throws -> [CalendarEvent] {
        // In production, this would call:
        // - Google Calendar API: GET /calendars/primary/events
        // - Microsoft Graph: GET /me/calendarView

        // For now, return mock data for testing
        return generateMockEvents(days: days)
    }

    /// Gets events for a specific date range
    func getEvents(from startDate: Date, to endDate: Date) async throws -> [CalendarEvent] {
        let allEvents = try await getEvents(days: 14)
        return allEvents.filter { event in
            event.startTime >= startDate && event.endTime <= endDate
        }
    }

    // MARK: - Stress Analysis

    /// Analyzes calendar for stress patterns
    func analyzeStress(daysAhead: Int = 7) async throws -> StressAnalysis {
        let events = try await getEvents(days: daysAhead)
        return analyzeEvents(events)
    }

    /// Analyzes a specific day's stress level
    func analyzeDay(_ date: Date) async throws -> DayStressAnalysis {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let events = try await getEvents(from: startOfDay, to: endOfDay)
        return analyzeEventsForDay(events, date: date)
    }

    // MARK: - Private Analysis

    private func analyzeEvents(_ events: [CalendarEvent]) -> StressAnalysis {
        var dailyAnalyses: [Date: DayStressAnalysis] = [:]
        let calendar = Calendar.current

        // Group events by day and analyze each day
        let groupedByDay = Dictionary(grouping: events) { event in
            calendar.startOfDay(for: event.startTime)
        }

        for (date, dayEvents) in groupedByDay {
            dailyAnalyses[date] = analyzeEventsForDay(dayEvents, date: date)
        }

        // Find highest stress days
        let sortedDays = dailyAnalyses.values.sorted { $0.stressScore > $1.stressScore }
        let highestStressDays = Array(sortedDays.prefix(3))

        // Calculate overall metrics
        let totalMeetings = events.count
        let busyDays = dailyAnalyses.values.filter { $0.stressLevel == .high || $0.stressLevel == .veryHigh }.count

        return StressAnalysis(
            dailyAnalyses: dailyAnalyses,
            highestStressDays: highestStressDays,
            totalMeetings: totalMeetings,
            busyDaysCount: busyDays,
            averageMeetingsPerDay: dailyAnalyses.isEmpty ? 0 : Double(totalMeetings) / Double(dailyAnalyses.count)
        )
    }

    private func analyzeEventsForDay(_ events: [CalendarEvent], date: Date) -> DayStressAnalysis {
        let calendar = Calendar.current

        // Sort events by start time
        let sortedEvents = events.sorted { $0.startTime < $1.startTime }

        // Calculate metrics
        let meetingCount = sortedEvents.count
        var backToBackCount = 0
        var earlyMeetingCount = 0
        var noLunchBreak = false
        var marathonMeetings = 0
        var meetingTypes: [MeetingType: Int] = [:]

        // Check for back-to-back meetings
        for i in 0..<(sortedEvents.count - 1) {
            let current = sortedEvents[i]
            let next = sortedEvents[i + 1]

            let gap = next.startTime.timeIntervalSince(current.endTime)
            let gapMinutes = gap / 60

            if gapMinutes <= Double(Thresholds.backToBackGapMinutes) {
                backToBackCount += 1
            }
        }

        // Check for early meetings
        for event in sortedEvents {
            let hour = calendar.component(.hour, from: event.startTime)
            if hour < Thresholds.earlyMeetingHour {
                earlyMeetingCount += 1
            }

            // Check for marathon meetings
            let duration = event.endTime.timeIntervalSince(event.startTime)
            if duration / 60 >= Double(Thresholds.marathonMeetingMinutes) {
                marathonMeetings += 1
            }

            // Count meeting types
            meetingTypes[event.meetingType, default: 0] += 1
        }

        // Check for no lunch break
        let lunchStartHour = 11
        let lunchEndHour = 14
        var hasLunchBreak = false

        for event in sortedEvents {
            let hour = calendar.component(.hour, from: event.startTime)
            if hour >= lunchStartHour && hour <= lunchEndHour {
                hasLunchBreak = true
                break
            }
        }
        noLunchBreak = !hasLunchBreak && meetingCount > 2

        // Calculate stress score
        var stressScore = 0.0

        if meetingCount >= Thresholds.hecticDayThreshold {
            stressScore += 3.0
        } else if meetingCount >= 4 {
            stressScore += 1.5
        }

        stressScore += Double(backToBackCount) * 1.5
        stressScore += Double(earlyMeetingCount) * 1.0
        if noLunchBreak { stressScore += 2.0 }
        stressScore += Double(marathonMeetings) * 1.5

        // Cap at 10
        stressScore = min(stressScore, 10.0)

        // Determine stress level
        let stressLevel: StressLevel
        switch stressScore {
        case 0..<3:
            stressLevel = .low
        case 3..<5:
            stressLevel = .moderate
        case 5..<7:
            stressLevel = .high
        default:
            stressLevel = .veryHigh
        }

        // Identify stress markers
        var stressMarkers: [StressMarker] = []
        if earlyMeetingCount > 0 {
            stressMarkers.append(.earlyMeeting)
        }
        if backToBackCount >= 3 {
            stressMarkers.append(.backToBackMeetings)
        }
        if meetingCount >= Thresholds.hecticDayThreshold {
            stressMarkers.append(.hecticDay)
        }
        if noLunchBreak {
            stressMarkers.append(.noLunchBreak)
        }
        if marathonMeetings > 0 {
            stressMarkers.append(.marathonMeeting)
        }

        // Identify high-stress meeting types
        let stressfulMeetingTypes = meetingTypes
            .filter { type, count in
                switch type {
                case .performanceReview, .clientMeeting:
                    return count > 0
                default:
                    return false
                }
            }
            .map { $0.key }

        return DayStressAnalysis(
            date: date,
            events: sortedEvents,
            meetingCount: meetingCount,
            stressScore: stressScore,
            stressLevel: stressLevel,
            stressMarkers: stressMarkers,
            stressfulMeetingTypes: stressfulMeetingTypes,
            backToBackCount: backToBackCount,
            earlyMeetingCount: earlyMeetingCount,
            noLunchBreak: noLunchBreak,
            marathonMeetings: marathonMeetings
        )
    }

    // MARK: - Mock Data Generation (for testing)

    private func generateMockEvents(days: Int) -> [CalendarEvent] {
        var events: [CalendarEvent] = []
        let calendar = Calendar.current
        let now = Date()

        for dayOffset in 0..<days {
            guard let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            let weekday = calendar.component(.weekday, from: dayDate)

            // Skip weekends for realistic work schedule
            if weekday == 1 || weekday == 7 { continue }

            let dayEvents = Int.random(in: 2...8)
            var currentHour = 9

            for _ in 0..<dayEvents {
                let duration = Int.random(in: 30...90)
                let startHour = currentHour + Int.random(in: 0...2)
                guard startHour < 18 else { break }

                let startTime = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: dayDate)!
                let endTime = calendar.date(byAdding: .minute, value: duration, to: startTime)!

                let titles = ["Team Standup", "1:1 with Manager", "Client Review", "All Hands", "Design Sync", "Sprint Planning", "Bug Triage", "Product Review"]
                let title = titles.randomElement()!

                let event = CalendarEvent(
                    id: UUID().uuidString,
                    title: title,
                    startTime: startTime,
                    endTime: endTime,
                    isAllDay: false,
                    location: Int.random(in: 0...2) == 0 ? "Conference Room A" : nil,
                    attendeesCount: Int.random(in: 2...10),
                    meetingType: MeetingType.from(title: title),
                    stressScore: nil,
                    isPrivate: false
                )

                events.append(event)
                currentHour = startHour + (duration / 60) + Int.random(in: 0...1)
            }
        }

        return events
    }
}

// MARK: - Stress Analysis Types

struct StressAnalysis {
    let dailyAnalyses: [Date: DayStressAnalysis]
    let highestStressDays: [DayStressAnalysis]
    let totalMeetings: Int
    let busyDaysCount: Int
    let averageMeetingsPerDay: Double
}

struct DayStressAnalysis {
    let date: Date
    let events: [CalendarEvent]
    let meetingCount: Int
    let stressScore: Double
    let stressLevel: StressLevel
    let stressMarkers: [StressMarker]
    let stressfulMeetingTypes: [MeetingType]
    let backToBackCount: Int
    let earlyMeetingCount: Int
    let noLunchBreak: Bool
    let marathonMeetings: Int

    var isStressful: Bool {
        stressLevel == .high || stressLevel == .veryHigh
    }

    var hasBreaks: Bool {
        backToBackCount < 3
    }
}

enum StressLevel: String, Comparable {
    case low
    case moderate
    case high
    case veryHigh

    static func < (lhs: StressLevel, rhs: StressLevel) -> Bool {
        let order: [StressLevel] = [.low, .moderate, .high, .veryHigh]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else {
            return false
        }
        return lhsIndex < rhsIndex
    }
}

enum StressMarker: String, Codable, CaseIterable {
    case earlyMeeting
    case backToBackMeetings
    case hecticDay
    case noLunchBreak
    case marathonMeeting
    case performanceReview
    case clientMeeting

    var displayName: String {
        switch self {
        case .earlyMeeting:
            return "Early morning meeting"
        case .backToBackMeetings:
            return "Back-to-back meetings"
        case .hecticDay:
            return "Hectic schedule"
        case .noLunchBreak:
            return "No lunch break"
        case .marathonMeeting:
            return "Long meeting"
        case .performanceReview:
            return "Performance review"
        case .clientMeeting:
            return "Client meeting"
        }
    }

    var recommendation: String {
        switch self {
        case .earlyMeeting:
            return "Try a 5-minute breathing exercise before your first meeting"
        case .backToBackMeetings:
            return "Schedule 5-minute breaks between meetings for mental reset"
        case .hecticDay:
            return "Consider blocking 15 minutes of focus time between meetings"
        case .noLunchBreak:
            return "Block 30 minutes for lunch - it's important for productivity"
        case .marathonMeeting:
            return "Take a 5-minute break halfway through long meetings"
        case .performanceReview:
            return "Practice the 4-7-8 breathing technique before your review"
        case .clientMeeting:
            return "Do a quick grounding exercise before connecting"
        }
    }
}
