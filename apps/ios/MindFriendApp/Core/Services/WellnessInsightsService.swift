import Foundation
import SwiftUI
import Supabase
import OSLog

/// Service that provides wellness insights by correlating mood data with activities
@MainActor
final class WellnessInsightsService: ObservableObject {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MindFriend", category: "WellnessInsights")

    private let supabaseClient: SupabaseClient
    private let authService: SupabaseAuthService

    @Published var weeklyMoodTrend: [WellnessMoodDataPoint] = []
    @Published var helpfulActivities: [HelpfulActivity] = []
    @Published var isLoading = false

    init(supabase: SupabaseClient = supabase, authService: SupabaseAuthService) {
        self.supabaseClient = supabase
        self.authService = authService
    }

    private var userId: UUID? {
        authService.userId
    }

    // MARK: - Public API

    /// Load weekly mood trend data (last 7 days)
    func loadWeeklyMoodTrend() async {
        guard userId != nil else {
            Self.logger.debug("Not authenticated, skipping mood trend load")
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            // Fetch mood entries from last 7 days (today + 6 previous days)
            let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date())) ?? Date()

            let entries: [MoodEntry] = try await supabaseClient
                .from("moods")
                .select("id, mood_score, anxiety_score, energy_score, note, local_date, source, created_at")
                .gte("created_at", value: sevenDaysAgo.toISODateString())
                .order("created_at", ascending: true)
                .execute()
                .value

            // Group by day and average
            let calendar = Calendar.current
            var dayMoods: [Date: [Int]] = [:]

            for entry in entries {
                let dayStart = calendar.startOfDay(for: entry.createdAt)
                dayMoods[dayStart, default: []].append(entry.moodScore)
            }

            // Generate data points for each of the last 7 days
            var points: [WellnessMoodDataPoint] = []
            for dayOffset in -6...0 {
                let date = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: Date()))!
                let moods = dayMoods[date] ?? []
                let avgMood = moods.isEmpty ? nil : Double(moods.reduce(0, +)) / Double(moods.count)

                points.append(WellnessMoodDataPoint(
                    date: date,
                    averageMood: avgMood,
                    entryCount: moods.count
                ))
            }

            weeklyMoodTrend = points
        } catch {
            Self.logger.error("Failed to load mood trend: \(error.localizedDescription)")
            weeklyMoodTrend = []
        }
    }

    /// Find activities that correlate with improved mood
    func findHelpfulActivities() async {
        guard userId != nil else {
            Self.logger.debug("Not authenticated, skipping helpful activities load")
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            // Look at exercise sessions in the past 30 days
            let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()

            // Fetch exercise sessions with their exercises
            let sessions: [ExerciseSessionWithDetails] = try await supabaseClient
                .from("exercise_sessions")
                .select("id, exercise_id, completed, rating, ended_at, exercises(title, type)")
                .gte("ended_at", value: thirtyDaysAgo.toISODateString())
                .eq("completed", value: true)
                .order("ended_at", ascending: false)
                .limit(50)
                .execute()
                .value

            // Group by exercise type and calculate helpfulness
            var typeStats: [String: (totalRating: Int, count: Int, exerciseName: String)] = [:]

            for session in sessions {
                guard let rating = session.rating,
                      let exercise = session.exercises else { continue }

                let type = exercise.type
                var stats = typeStats[type] ?? (totalRating: 0, count: 0, exerciseName: exercise.title)
                stats.totalRating += rating
                stats.count += 1
                if stats.count == 1 {
                    stats.exerciseName = exercise.title
                }
                typeStats[type] = stats
            }

            // Convert to helpful activities (top 3 by average rating)
            let activities = typeStats
                .map { type, stats in
                    HelpfulActivity(
                        exerciseType: ExerciseType(rawValue: type) ?? .breathing,
                        sampleExerciseName: stats.exerciseName,
                        averageRating: Double(stats.totalRating) / Double(stats.count),
                        completionCount: stats.count
                    )
                }
                .filter { $0.averageRating >= 3.5 } // Only show positively rated
                .sorted { $0.averageRating > $1.averageRating }
                .prefix(3)

            helpfulActivities = Array(activities)
        } catch {
            Self.logger.error("Failed to find helpful activities: \(error.localizedDescription)")
            helpfulActivities = []
        }
    }

    /// Load all insights data
    func loadAll() async {
        async let mood: () = loadWeeklyMoodTrend()
        async let activities: () = findHelpfulActivities()
        _ = await (mood, activities)
    }
}

// MARK: - Data Models

/// A single day's mood data point for the sparkline
struct WellnessMoodDataPoint: Identifiable {
    let date: Date
    let averageMood: Double?
    let entryCount: Int

    /// Stable ID based on date (not random UUID)
    var id: Date { date }

    /// Cached DateFormatter for day labels (DateFormatter is expensive to create)
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter
    }()

    var dayLabel: String {
        Self.dayFormatter.string(from: date)
    }

    var hasMoodData: Bool { averageMood != nil }
}

/// An activity type that correlates with improved mood
struct HelpfulActivity: Identifiable {
    let exerciseType: ExerciseType
    let sampleExerciseName: String
    let averageRating: Double
    let completionCount: Int

    /// Stable ID based on exercise type (not random UUID)
    var id: String { exerciseType.rawValue }

    var icon: String { exerciseType.icon }
    var color: Color { exerciseType.themeColor }
    var typeName: String { exerciseType.displayName }
}

// MARK: - Database Models

private struct ExerciseSessionWithDetails: Codable {
    let id: String
    let exerciseId: String
    let completed: Bool
    let rating: Int?
    let endedAt: Date?
    let exercises: ExerciseDetails?

    enum CodingKeys: String, CodingKey {
        case id
        case exerciseId = "exercise_id"
        case completed
        case rating
        case endedAt = "ended_at"
        case exercises
    }
}

private struct ExerciseDetails: Codable {
    let title: String
    let type: String
}
