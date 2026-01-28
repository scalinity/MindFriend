import Foundation
import Supabase
import OSLog

// MARK: - Longitudinal Service Errors

enum LongitudinalError: LocalizedError {
    case notAuthenticated
    case insufficientData
    case reportGenerationFailed(String)
    case exportFailed(String)
    case invalidDateRange
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated"
        case .insufficientData:
            return "Not enough data to generate insights"
        case .reportGenerationFailed(let message):
            return "Failed to generate report: \(message)"
        case .exportFailed(let message):
            return "Failed to export data: \(message)"
        case .invalidDateRange:
            return "Invalid date range specified"
        case .networkError(let message):
            return message
        }
    }
}

// MARK: - Longitudinal Service

/// Service for managing longitudinal wellness data and analytics
@MainActor
final class LongitudinalService: ObservableObject {
    private let authService: SupabaseAuthService
    private let logger = Logger(subsystem: "com.mindfriend", category: "LongitudinalService")

    init(authService: SupabaseAuthService) {
        self.authService = authService
    }

    private var userId: UUID {
        get throws {
            guard let id = authService.userId else {
                throw LongitudinalError.notAuthenticated
            }
            return id
        }
    }

    // MARK: - Weekly Stats

    /// Fetch weekly statistics for a date range
    func fetchWeeklyStats(from startDate: Date? = nil, to endDate: Date? = nil, limit: Int = 52) async throws -> [WeeklyStat] {
        let uid = try userId

        var query = supabase
            .from(Tables.longitudinalWeeklyStats)
            .select()
            .eq("user_id", value: uid)

        if let start = startDate {
            query = query.gte("week_start", value: ISO8601DateFormatter().string(from: start))
        }
        if let end = endDate {
            query = query.lt("week_start", value: ISO8601DateFormatter().string(from: end))
        }

        let stats: [WeeklyStat] = try await query
            .order("week_start", ascending: false)
            .limit(limit)
            .execute()
            .value

        logger.debug("Fetched \(stats.count) weekly stats")
        return stats
    }

    /// Get the most recent weekly stats
    func fetchRecentWeeklyStats(weeks: Int = 12) async throws -> [WeeklyStat] {
        return try await fetchWeeklyStats(limit: weeks)
    }

    // MARK: - Monthly Stats

    /// Fetch monthly statistics for a date range
    func fetchMonthlyStats(from startDate: Date? = nil, to endDate: Date? = nil, limit: Int = 24) async throws -> [MonthlyStat] {
        let uid = try userId

        var query = supabase
            .from(Tables.longitudinalMonthlyStats)
            .select()
            .eq("user_id", value: uid)

        if let start = startDate {
            query = query.gte("month_start", value: ISO8601DateFormatter().string(from: start))
        }
        if let end = endDate {
            query = query.lt("month_start", value: ISO8601DateFormatter().string(from: end))
        }

        let stats: [MonthlyStat] = try await query
            .order("month_start", ascending: false)
            .limit(limit)
            .execute()
            .value

        logger.debug("Fetched \(stats.count) monthly stats")
        return stats
    }

    /// Get the most recent monthly stats
    func fetchRecentMonthlyStats(months: Int = 12) async throws -> [MonthlyStat] {
        return try await fetchMonthlyStats(limit: months)
    }

    // MARK: - Yearly Stats

    /// Fetch yearly statistics
    func fetchYearlyStats(limit: Int = 5) async throws -> [YearlyStat] {
        let uid = try userId

        let stats: [YearlyStat] = try await supabase
            .from(Tables.longitudinalYearlyStats)
            .select()
            .eq("user_id", value: uid)
            .order("year", ascending: false)
            .limit(limit)
            .execute()
            .value

        logger.debug("Fetched \(stats.count) yearly stats")
        return stats
    }

    /// Get stats for a specific year
    func fetchYearlyStat(year: Int) async throws -> YearlyStat? {
        let uid = try userId

        let stats: [YearlyStat] = try await supabase
            .from(Tables.longitudinalYearlyStats)
            .select()
            .eq("user_id", value: uid)
            .eq("year", value: year)
            .limit(1)
            .execute()
            .value

        return stats.first
    }

    // MARK: - Patterns

    /// Fetch all active patterns
    func fetchPatterns(includeInactive: Bool = false) async throws -> [LongitudinalPattern] {
        let uid = try userId

        var query = supabase
            .from(Tables.longitudinalPatterns)
            .select()
            .eq("user_id", value: uid)

        if !includeInactive {
            query = query.eq("is_active", value: true)
        }

        let patterns: [LongitudinalPattern] = try await query
            .order("confidence", ascending: false)
            .execute()
            .value

        logger.debug("Fetched \(patterns.count) patterns")
        return patterns
    }

    /// Fetch patterns by type
    func fetchPatterns(ofType type: PatternType) async throws -> [LongitudinalPattern] {
        let uid = try userId

        let patterns: [LongitudinalPattern] = try await supabase
            .from(Tables.longitudinalPatterns)
            .select()
            .eq("user_id", value: uid)
            .eq("pattern_type", value: type.rawValue)
            .eq("is_active", value: true)
            .order("confidence", ascending: false)
            .execute()
            .value

        return patterns
    }

    // MARK: - Life Events

    /// Fetch all life events
    func fetchLifeEvents(limit: Int = 50) async throws -> [LifeEvent] {
        let uid = try userId

        let events: [LifeEvent] = try await supabase
            .from(Tables.longitudinalLifeEvents)
            .select()
            .eq("user_id", value: uid)
            .order("event_date", ascending: false)
            .limit(limit)
            .execute()
            .value

        logger.debug("Fetched \(events.count) life events")
        return events
    }

    /// Fetch life events within a date range
    func fetchLifeEvents(from startDate: Date, to endDate: Date) async throws -> [LifeEvent] {
        let uid = try userId
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        let events: [LifeEvent] = try await supabase
            .from(Tables.longitudinalLifeEvents)
            .select()
            .eq("user_id", value: uid)
            .gte("event_date", value: formatter.string(from: startDate))
            .lte("event_date", value: formatter.string(from: endDate))
            .order("event_date", ascending: false)
            .execute()
            .value

        return events
    }

    /// Add a new life event
    func addLifeEvent(_ input: LifeEventInput) async throws -> LifeEvent {
        let uid = try userId
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        let insertData: [String: LongitudinalAnyEncodable] = [
            "user_id": LongitudinalAnyEncodable(uid),
            "event_type": LongitudinalAnyEncodable(input.eventType.rawValue),
            "event_date": LongitudinalAnyEncodable(formatter.string(from: input.eventDate)),
            "notes": LongitudinalAnyEncodable(input.notes)
        ]

        let event: LifeEvent = try await supabase
            .from(Tables.longitudinalLifeEvents)
            .insert(insertData)
            .select()
            .single()
            .execute()
            .value

        logger.info("Added life event: \(input.eventType.rawValue)")
        return event
    }

    /// Update a life event
    func updateLifeEvent(id: UUID, notes: String?) async throws {
        let uid = try userId

        try await supabase
            .from(Tables.longitudinalLifeEvents)
            .update(["notes": notes])
            .eq("id", value: id)
            .eq("user_id", value: uid)
            .execute()

        logger.info("Updated life event: \(id)")
    }

    /// Delete a life event
    func deleteLifeEvent(id: UUID) async throws {
        let uid = try userId

        try await supabase
            .from(Tables.longitudinalLifeEvents)
            .delete()
            .eq("id", value: id)
            .eq("user_id", value: uid)
            .execute()

        logger.info("Deleted life event: \(id)")
    }

    // MARK: - Reports

    /// Fetch all generated reports
    func fetchReports(limit: Int = 20) async throws -> [LongitudinalReport] {
        let uid = try userId

        let reports: [LongitudinalReport] = try await supabase
            .from(Tables.longitudinalReports)
            .select()
            .eq("user_id", value: uid)
            .order("generated_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        logger.debug("Fetched \(reports.count) reports")
        return reports
    }

    /// Fetch reports by type
    func fetchReports(ofType type: ReportType) async throws -> [LongitudinalReport] {
        let uid = try userId

        let reports: [LongitudinalReport] = try await supabase
            .from(Tables.longitudinalReports)
            .select()
            .eq("user_id", value: uid)
            .eq("report_type", value: type.rawValue)
            .order("generated_at", ascending: false)
            .execute()
            .value

        return reports
    }

    /// Get a specific report
    func fetchReport(id: UUID) async throws -> LongitudinalReport? {
        let uid = try userId

        let reports: [LongitudinalReport] = try await supabase
            .from(Tables.longitudinalReports)
            .select()
            .eq("id", value: id)
            .eq("user_id", value: uid)
            .limit(1)
            .execute()
            .value

        return reports.first
    }

    /// Generate a new report via Edge Function
    func generateReport(type: ReportType, timePeriod: TimePeriod? = nil) async throws -> LongitudinalReport {
        let request = LongitudinalReportRequest(reportType: type, timePeriod: timePeriod)

        // Response structure from edge function
        struct GenerateReportResponse: Codable {
            let success: Bool
            let reportId: UUID
            let reportType: String
            let timePeriod: TimePeriod
            let contentJson: ReportContent
            let generatedAt: Date
            let expiresAt: Date

            enum CodingKeys: String, CodingKey {
                case success
                case reportId = "report_id"
                case reportType = "report_type"
                case timePeriod = "time_period"
                case contentJson = "content_json"
                case generatedAt = "generated_at"
                case expiresAt = "expires_at"
            }
        }

        let reportResponse: GenerateReportResponse = try await supabase.functions.invoke(
            "generate-longitudinal-report",
            options: .init(body: request)
        )

        // Construct the report object
        let report = LongitudinalReport(
            id: reportResponse.reportId,
            userId: try userId,
            reportType: type,
            timePeriod: reportResponse.timePeriod,
            contentJson: reportResponse.contentJson,
            generatedAt: reportResponse.generatedAt,
            expiresAt: reportResponse.expiresAt
        )

        logger.info("Generated \(type.rawValue) report: \(report.id)")
        return report
    }

    // MARK: - FHIR Export

    /// Export longitudinal data in FHIR R4 format
    func exportFHIR(from startDate: Date? = nil, to endDate: Date? = nil) async throws -> FHIRExportBundle {
        let uid = try userId

        // Fetch all relevant data
        async let weeklyStatsTask = fetchWeeklyStats(from: startDate, to: endDate, limit: 520) // 10 years
        async let monthlyStatsTask = fetchMonthlyStats(from: startDate, to: endDate, limit: 120) // 10 years
        async let yearlyStatsTask = fetchYearlyStats(limit: 10)
        async let patternsTask = fetchPatterns()
        async let lifeEventsTask = fetchLifeEvents(limit: 500)

        let (weeklyStats, monthlyStats, yearlyStats, patterns, lifeEvents) = try await (
            weeklyStatsTask,
            monthlyStatsTask,
            yearlyStatsTask,
            patternsTask,
            lifeEventsTask
        )

        // Build FHIR bundle
        let bundle = FHIRExportBundle(
            resourceType: "Bundle",
            type: "collection",
            timestamp: ISO8601DateFormatter().string(from: Date()),
            entry: buildFHIREntries(
                userId: uid,
                weeklyStats: weeklyStats,
                monthlyStats: monthlyStats,
                yearlyStats: yearlyStats,
                patterns: patterns,
                lifeEvents: lifeEvents
            )
        )

        logger.info("Exported FHIR bundle with \(bundle.entry.count) entries")
        return bundle
    }

    /// Convert export bundle to JSON data
    func exportFHIRAsJSON(from startDate: Date? = nil, to endDate: Date? = nil) async throws -> Data {
        let bundle = try await exportFHIR(from: startDate, to: endDate)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(bundle)
    }

    // MARK: - Dashboard Data

    /// Fetch aggregated dashboard data for the longitudinal overview
    func fetchDashboardData() async throws -> LongitudinalDashboardData {
        // Use resilient parallel fetches - return empty on failure so we can fall back to raw moods
        async let weeklyTask = resilientFetch { try await self.fetchRecentWeeklyStats(weeks: 12) }
        async let monthlyTask = resilientFetch { try await self.fetchRecentMonthlyStats(months: 12) }
        async let yearlyTask = resilientFetch { try await self.fetchYearlyStats(limit: 2) }
        async let patternsTask = resilientFetch { try await self.fetchPatterns() }
        async let recentEventsTask = resilientFetch { try await self.fetchLifeEvents(limit: 5) }
        async let reportsTask = resilientFetch { try await self.fetchReports(limit: 3) }

        let (weekly, monthly, yearly, patterns, recentEvents, reports) = await (
            weeklyTask,
            monthlyTask,
            yearlyTask,
            patternsTask,
            recentEventsTask,
            reportsTask
        )

        // If we have aggregated stats, return them
        if !weekly.isEmpty || !monthly.isEmpty {
            return LongitudinalDashboardData(
                weeklyStats: weekly,
                monthlyStats: monthly,
                yearlyStats: yearly,
                patterns: patterns,
                recentLifeEvents: recentEvents,
                recentReports: reports,
                rawMoodStats: nil
            )
        }

        // Fallback: compute stats from raw mood data
        logger.debug("No aggregated stats found, computing from raw moods")
        
        // Make raw mood fallback resilient too
        let rawStats: RawMoodStats
        do {
            rawStats = try await computeStatsFromRawMoods()
        } catch {
            logger.error("Raw mood fallback failed: \(error.localizedDescription)")
            // Return empty data rather than throwing
            rawStats = RawMoodStats(
                totalEntries: 0,
                avgMood: nil,
                moodTrend: nil,
                weeklyStats: [],
                monthlyStats: [],
                firstMoodDate: nil,
                lastMoodDate: nil
            )
        }
        
        return LongitudinalDashboardData(
            weeklyStats: rawStats.weeklyStats,
            monthlyStats: rawStats.monthlyStats,
            yearlyStats: yearly,
            patterns: patterns,
            recentLifeEvents: recentEvents,
            recentReports: reports,
            rawMoodStats: rawStats
        )
    }
    
    /// Helper to fetch data resiliently - returns empty array on failure
    private func resilientFetch<T>(_ fetch: @escaping () async throws -> [T]) async -> [T] {
        do {
            return try await fetch()
        } catch {
            logger.debug("Resilient fetch failed (returning empty): \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Raw Mood Fallback
    
    /// Compute basic weekly/monthly stats from raw mood data (for users without aggregated stats yet)
    private func computeStatsFromRawMoods() async throws -> RawMoodStats {
        let uid = try userId
        
        // Fetch raw moods from the past 90 days
        let ninetyDaysAgo = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        
        let moods: [RawMood] = try await supabase
            .from(Tables.moods)
            .select("id, mood_score, created_at")
            .eq("user_id", value: uid)
            .gte("created_at", value: ninetyDaysAgo.toISODateString())
            .order("created_at", ascending: false)
            .execute()
            .value
        
        logger.debug("Fetched \(moods.count) raw moods for fallback stats")
        
        guard !moods.isEmpty else {
            return RawMoodStats(
                totalEntries: 0,
                avgMood: nil,
                moodTrend: nil,
                weeklyStats: [],
                monthlyStats: [],
                firstMoodDate: nil,
                lastMoodDate: nil
            )
        }
        
        // Group by week
        let weeklyStats = computeWeeklyStats(from: moods, userId: uid)
        
        // Group by month
        let monthlyStats = computeMonthlyStats(from: moods, userId: uid)
        
        // Calculate overall trend
        let sortedByDate = moods.sorted { ($0.createdAt ?? Date.distantPast) < ($1.createdAt ?? Date.distantPast) }
        let avgMood = moods.map { Double($0.moodScore) }.reduce(0, +) / Double(moods.count)
        
        // Simple trend calculation: compare first half to second half
        let midpoint = moods.count / 2
        var moodTrend: MoodTrend? = nil
        if moods.count >= 6 {
            let firstHalf = Array(sortedByDate.prefix(midpoint))
            let secondHalf = Array(sortedByDate.suffix(midpoint))
            let firstAvg = firstHalf.map { Double($0.moodScore) }.reduce(0, +) / Double(firstHalf.count)
            let secondAvg = secondHalf.map { Double($0.moodScore) }.reduce(0, +) / Double(secondHalf.count)
            
            let delta = secondAvg - firstAvg
            if delta > 0.3 {
                moodTrend = .improving
            } else if delta < -0.3 {
                moodTrend = .declining
            } else {
                moodTrend = .stable
            }
        }
        
        return RawMoodStats(
            totalEntries: moods.count,
            avgMood: avgMood,
            moodTrend: moodTrend,
            weeklyStats: weeklyStats,
            monthlyStats: monthlyStats,
            firstMoodDate: sortedByDate.first?.createdAt,
            lastMoodDate: sortedByDate.last?.createdAt
        )
    }
    
    private func computeWeeklyStats(from moods: [RawMood], userId: UUID) -> [WeeklyStat] {
        let calendar = Calendar.current
        
        // Group moods by week
        var weekGroups: [Date: [RawMood]] = [:]
        for mood in moods {
            guard let createdAt = mood.createdAt else { continue }
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: createdAt)?.start ?? createdAt
            weekGroups[weekStart, default: []].append(mood)
        }
        
        // Convert to WeeklyStat objects (sorted by date descending)
        return weekGroups.sorted { $0.key > $1.key }.prefix(12).map { weekStart, weekMoods in
            let scores = weekMoods.map { Double($0.moodScore) }
            let avg = scores.reduce(0, +) / Double(scores.count)
            let variance = scores.count > 1 ? calculateVariance(scores) : 0.0
            let uniqueDays = Set(weekMoods.compactMap { $0.createdAt?.dayOfYear }).count
            
            return WeeklyStat(
                id: UUID(),
                userId: userId,
                weekStart: weekStart,
                avgMood: avg,
                moodVariance: variance,
                activeDays: uniqueDays,
                exercisesCompleted: 0,
                createdAt: Date(),
                updatedAt: Date()
            )
        }
    }
    
    private func computeMonthlyStats(from moods: [RawMood], userId: UUID) -> [MonthlyStat] {
        let calendar = Calendar.current
        
        // Group moods by month
        var monthGroups: [Date: [RawMood]] = [:]
        for mood in moods {
            guard let createdAt = mood.createdAt else { continue }
            let monthStart = calendar.dateInterval(of: .month, for: createdAt)?.start ?? createdAt
            monthGroups[monthStart, default: []].append(mood)
        }
        
        // Convert to MonthlyStat objects (sorted by date descending)
        let sortedMonths = monthGroups.sorted { $0.key > $1.key }
        return sortedMonths.prefix(12).enumerated().map { index, element in
            let (monthStart, monthMoods) = element
            let scores = monthMoods.map { Double($0.moodScore) }
            let avg = scores.reduce(0, +) / Double(scores.count)
            
            // Calculate trend vs previous month
            var trend: MoodTrend? = nil
            if index < sortedMonths.count - 1 {
                let prevMonthMoods = sortedMonths[index + 1].value
                let prevAvg = prevMonthMoods.map { Double($0.moodScore) }.reduce(0, +) / Double(prevMonthMoods.count)
                let delta = avg - prevAvg
                if delta > 0.3 {
                    trend = .improving
                } else if delta < -0.3 {
                    trend = .declining
                } else {
                    trend = .stable
                }
            }
            
            let daysInMonth = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
            let uniqueDays = Set(monthMoods.compactMap { $0.createdAt?.dayOfYear }).count
            let activePct = (Double(uniqueDays) / Double(daysInMonth)) * 100
            
            return MonthlyStat(
                id: UUID(),
                userId: userId,
                monthStart: monthStart,
                avgMood: avg,
                moodTrend: trend,
                activeDaysPct: activePct,
                notableEvents: [],
                createdAt: Date()
            )
        }
    }
    
    private func calculateVariance(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let squaredDiffs = values.map { pow($0 - mean, 2) }
        return squaredDiffs.reduce(0, +) / Double(values.count)
    }

    // MARK: - Private Helpers

    private func buildFHIREntries(
        userId: UUID,
        weeklyStats: [WeeklyStat],
        monthlyStats: [MonthlyStat],
        yearlyStats: [YearlyStat],
        patterns: [LongitudinalPattern],
        lifeEvents: [LifeEvent]
    ) -> [FHIRBundleEntry] {
        var entries: [FHIRBundleEntry] = []
        let dateFormatter = ISO8601DateFormatter()

        // Add mood observations from weekly stats
        for stat in weeklyStats {
            if let avgMood = stat.avgMood {
                let observation = FHIRObservation(
                    resourceType: "Observation",
                    id: stat.id.uuidString,
                    status: "final",
                    category: [FHIRCodeableConcept(
                        coding: [FHIRCoding(
                            system: "http://terminology.hl7.org/CodeSystem/observation-category",
                            code: "survey",
                            display: "Survey"
                        )]
                    )],
                    code: FHIRCodeableConcept(
                        coding: [FHIRCoding(
                            system: "http://loinc.org",
                            code: "72100-1",
                            display: "Patient mood"
                        )],
                        text: "Weekly Average Mood Score"
                    ),
                    subject: FHIRReference(reference: "Patient/\(userId.uuidString)"),
                    effectiveDateTime: dateFormatter.string(from: stat.weekStart),
                    valueQuantity: FHIRQuantity(
                        value: avgMood,
                        unit: "score",
                        system: "http://unitsofmeasure.org",
                        code: "{score}"
                    )
                )
                entries.append(FHIRBundleEntry(
                    fullUrl: "urn:uuid:\(stat.id.uuidString)",
                    resource: .observation(observation)
                ))
            }
        }

        // Add life events as Condition resources
        for event in lifeEvents {
            let condition = FHIRCondition(
                resourceType: "Condition",
                id: event.id.uuidString,
                clinicalStatus: FHIRCodeableConcept(
                    coding: [FHIRCoding(
                        system: "http://terminology.hl7.org/CodeSystem/condition-clinical",
                        code: event.isOngoing ? "active" : "resolved",
                        display: event.isOngoing ? "Active" : "Resolved"
                    )]
                ),
                category: [FHIRCodeableConcept(
                    coding: [FHIRCoding(
                        system: "http://terminology.hl7.org/CodeSystem/condition-category",
                        code: "problem-list-item",
                        display: "Problem List Item"
                    )]
                )],
                code: FHIRCodeableConcept(
                    coding: [FHIRCoding(
                        system: "http://mindfriend.app/life-event-types",
                        code: event.eventType.rawValue,
                        display: event.eventType.displayName
                    )],
                    text: event.eventType.displayName
                ),
                subject: FHIRReference(reference: "Patient/\(userId.uuidString)"),
                onsetDateTime: dateFormatter.string(from: event.eventDate),
                note: event.notes.map { [FHIRAnnotation(text: $0)] }
            )
            entries.append(FHIRBundleEntry(
                fullUrl: "urn:uuid:\(event.id.uuidString)",
                resource: .condition(condition)
            ))
        }

        return entries
    }
}

// MARK: - Raw Mood Stats Model

/// Statistics computed on-the-fly from raw mood data (used when aggregated stats don't exist yet)
struct RawMoodStats {
    let totalEntries: Int
    let avgMood: Double?
    let moodTrend: MoodTrend?
    let weeklyStats: [WeeklyStat]
    let monthlyStats: [MonthlyStat]
    let firstMoodDate: Date?
    let lastMoodDate: Date?
    
    var hasData: Bool {
        totalEntries > 0
    }
}

/// Minimal raw mood structure for fetching
private struct RawMood: Codable {
    let id: UUID
    let moodScore: Int
    let createdAt: Date?
    
    enum CodingKeys: String, CodingKey {
        case id
        case moodScore = "mood_score"
        case createdAt = "created_at"
    }
}

// MARK: - Date Extension

private extension Date {
    var dayOfYear: Int {
        Calendar.current.ordinality(of: .day, in: .year, for: self) ?? 0
    }
}

// MARK: - Dashboard Data Model

struct LongitudinalDashboardData {
    let weeklyStats: [WeeklyStat]
    let monthlyStats: [MonthlyStat]
    let yearlyStats: [YearlyStat]
    let patterns: [LongitudinalPattern]
    let recentLifeEvents: [LifeEvent]
    let recentReports: [LongitudinalReport]
    let rawMoodStats: RawMoodStats?

    var hasData: Bool {
        !weeklyStats.isEmpty || !monthlyStats.isEmpty || (rawMoodStats?.hasData ?? false)
    }

    var currentYearStat: YearlyStat? {
        yearlyStats.first
    }

    var previousYearStat: YearlyStat? {
        yearlyStats.dropFirst().first
    }

    var highConfidencePatterns: [LongitudinalPattern] {
        patterns.filter { $0.confidence >= 0.7 }
    }

    var mostRecentMoodTrend: MoodTrend? {
        monthlyStats.first?.moodTrend
    }
}

// MARK: - FHIR Export Models

struct FHIRExportBundle: Codable {
    let resourceType: String
    let type: String
    let timestamp: String
    let entry: [FHIRBundleEntry]
}

struct FHIRBundleEntry: Codable {
    let fullUrl: String
    let resource: FHIRResource
}

enum FHIRResource: Codable {
    case observation(FHIRObservation)
    case condition(FHIRCondition)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .observation(let obs):
            try container.encode(obs)
        case .condition(let cond):
            try container.encode(cond)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let obs = try? container.decode(FHIRObservation.self) {
            self = .observation(obs)
        } else if let cond = try? container.decode(FHIRCondition.self) {
            self = .condition(cond)
        } else {
            throw DecodingError.typeMismatch(
                FHIRResource.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Unknown FHIR resource type")
            )
        }
    }
}

struct FHIRObservation: Codable {
    let resourceType: String
    let id: String
    let status: String
    let category: [FHIRCodeableConcept]
    let code: FHIRCodeableConcept
    let subject: FHIRReference
    let effectiveDateTime: String
    let valueQuantity: FHIRQuantity?
}

struct FHIRCondition: Codable {
    let resourceType: String
    let id: String
    let clinicalStatus: FHIRCodeableConcept
    let category: [FHIRCodeableConcept]
    let code: FHIRCodeableConcept
    let subject: FHIRReference
    let onsetDateTime: String
    let note: [FHIRAnnotation]?
}

struct FHIRCodeableConcept: Codable {
    let coding: [FHIRCoding]
    var text: String?
}

struct FHIRCoding: Codable {
    let system: String
    let code: String
    let display: String
}

struct FHIRReference: Codable {
    let reference: String
}

struct FHIRQuantity: Codable {
    let value: Double
    let unit: String
    let system: String
    let code: String
}

struct FHIRAnnotation: Codable {
    let text: String
}

// MARK: - LongitudinalAnyEncodable Helper

private struct LongitudinalAnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        _encode = { encoder in
            try value.encode(to: encoder)
        }
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}
