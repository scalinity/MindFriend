import Foundation
import Supabase

// MARK: - Sleep Service Error

enum SleepServiceError: LocalizedError {
    case notAuthenticated
    case contentNotFound
    case sessionNotFound
    case sessionCreationFailed
    case invalidContentType

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to use sleep features"
        case .contentNotFound:
            return "Sleep content not found"
        case .sessionNotFound:
            return "Sleep session not found"
        case .sessionCreationFailed:
            return "Failed to start sleep session"
        case .invalidContentType:
            return "Invalid content type"
        }
    }
}

// MARK: - Sleep Service

@MainActor
final class SleepService {
    private let supabase: SupabaseClient

    init(supabase: SupabaseClient) {
        self.supabase = supabase
    }

    // MARK: - Content Queries

    /// Fetch all active sleep content
    func fetchAllContent() async throws -> [SleepContent] {
        let content: [SleepContent] = try await supabase
            .from("sleep_content")
            .select()
            .eq("is_active", value: true)
            .order("sort_order", ascending: true)
            .order("created_at", ascending: false)
            .execute()
            .value

        return content
    }

    /// Fetch sleep content with optional filters
    func fetchContent(filter: SleepContentFilter = .all) async throws -> [SleepContent] {
        var query = supabase
            .from("sleep_content")
            .select()
            .eq("is_active", value: true)

        if let contentType = filter.contentType {
            query = query.eq("content_type", value: contentType.rawValue)
        }

        if let category = filter.category {
            query = query.eq("category", value: category.rawValue)
        }

        if filter.isPremiumOnly {
            query = query.eq("is_premium", value: true)
        }

        if filter.isKidsOnly {
            query = query.eq("is_kids", value: true)
        }

        if filter.isFeaturedOnly {
            query = query.eq("is_featured", value: true)
        }

        let content: [SleepContent] = try await query
            .order("sort_order", ascending: true)
            .order("created_at", ascending: false)
            .execute()
            .value

        return content
    }

    /// Fetch sleep content by type
    func fetchContent(type: SleepContentType, category: SleepCategory? = nil) async throws -> [SleepContent] {
        var query = supabase
            .from("sleep_content")
            .select()
            .eq("is_active", value: true)
            .eq("content_type", value: type.rawValue)

        if let category = category {
            query = query.eq("category", value: category.rawValue)
        }

        let content: [SleepContent] = try await query
            .order("sort_order", ascending: true)
            .order("created_at", ascending: false)
            .execute()
            .value

        return content
    }

    /// Fetch featured sleep content
    func fetchFeaturedContent(limit: Int = 8) async throws -> [SleepContent] {
        let content: [SleepContent] = try await supabase
            .from("sleep_content")
            .select()
            .eq("is_active", value: true)
            .eq("is_featured", value: true)
            .order("sort_order", ascending: true)
            .limit(limit)
            .execute()
            .value

        return content
    }

    /// Fetch sleep content by ID
    func fetchContent(id: String) async throws -> SleepContent {
        let content: [SleepContent] = try await supabase
            .from("sleep_content")
            .select()
            .eq("id", value: id)
            .execute()
            .value

        guard let item = content.first else {
            throw SleepServiceError.contentNotFound
        }

        return item
    }

    /// Fetch kids sleep content
    func fetchKidsContent() async throws -> [SleepContent] {
        let content: [SleepContent] = try await supabase
            .from("sleep_content")
            .select()
            .eq("is_active", value: true)
            .eq("is_kids", value: true)
            .order("sort_order", ascending: true)
            .execute()
            .value

        return content
    }

    /// Search sleep content by title or description
    func searchContent(query: String) async throws -> [SleepContent] {
        let searchQuery = "%\(query)%"

        let content: [SleepContent] = try await supabase
            .from("sleep_content")
            .select()
            .eq("is_active", value: true)
            .or("title.ilike.\(searchQuery),description.ilike.\(searchQuery)")
            .order("sort_order", ascending: true)
            .execute()
            .value

        return content
    }

    // MARK: - Session Management

    /// Start a new sleep session
    @discardableResult
    func startSession(contentId: String, sleepTimerMinutes: Int? = nil) async throws -> SleepSession {
        guard let userId = supabase.auth.currentUser?.id.uuidString else {
            throw SleepServiceError.notAuthenticated
        }

        let dto = CreateSleepSessionDTO(
            userId: userId,
            contentId: contentId,
            sleepTimerUsed: sleepTimerMinutes != nil,
            timerDurationMinutes: sleepTimerMinutes
        )

        let sessions: [SleepSession] = try await supabase
            .from("sleep_sessions")
            .insert(dto)
            .select()
            .execute()
            .value

        guard let session = sessions.first else {
            throw SleepServiceError.sessionCreationFailed
        }

        return session
    }

    /// End a sleep session
    func endSession(
        sessionId: String,
        completed: Bool,
        lastPosition: Int,
        durationListened: Int? = nil
    ) async throws {
        let dto = UpdateSleepSessionDTO(
            endedAt: Date(),
            durationListenedSeconds: durationListened,
            completed: completed,
            lastPositionSeconds: lastPosition
        )

        try await supabase
            .from("sleep_sessions")
            .update(dto)
            .eq("id", value: sessionId)
            .execute()
    }

    /// Update playback position during session (debounced externally)
    func updatePlaybackPosition(sessionId: String, position: Int) async throws {
        let dto = UpdateSleepSessionDTO(
            endedAt: nil,
            durationListenedSeconds: nil,
            completed: nil,
            lastPositionSeconds: position
        )

        try await supabase
            .from("sleep_sessions")
            .update(dto)
            .eq("id", value: sessionId)
            .execute()
    }

    /// Get resume position for content (if user has an incomplete session)
    func getResumePosition(for contentId: String) async throws -> Int? {
        guard let userId = supabase.auth.currentUser?.id.uuidString else {
            return nil
        }

        struct ResumeInfo: Decodable {
            let lastPositionSeconds: Int

            enum CodingKeys: String, CodingKey {
                case lastPositionSeconds = "last_position_seconds"
            }
        }

        let sessions: [ResumeInfo] = try await supabase
            .from("sleep_sessions")
            .select("last_position_seconds")
            .eq("user_id", value: userId)
            .eq("content_id", value: contentId)
            .eq("completed", value: false)
            .order("started_at", ascending: false)
            .limit(1)
            .execute()
            .value

        guard let session = sessions.first,
              session.lastPositionSeconds > 30 else { // Only resume if > 30 seconds in
            return nil
        }

        return session.lastPositionSeconds
    }

    /// Fetch recent sleep sessions for the current user
    func fetchRecentSessions(limit: Int = 10) async throws -> [SleepSession] {
        guard let userId = supabase.auth.currentUser?.id.uuidString else {
            throw SleepServiceError.notAuthenticated
        }

        let sessions: [SleepSession] = try await supabase
            .from("sleep_sessions")
            .select()
            .eq("user_id", value: userId)
            .order("started_at", ascending: false)
            .limit(limit)
            .execute()
            .value

        return sessions
    }

    /// Fetch a specific session by ID
    func fetchSession(id: String) async throws -> SleepSession {
        guard let userId = supabase.auth.currentUser?.id.uuidString else {
            throw SleepServiceError.notAuthenticated
        }

        let sessions: [SleepSession] = try await supabase
            .from("sleep_sessions")
            .select()
            .eq("id", value: id)
            .eq("user_id", value: userId)
            .execute()
            .value

        guard let session = sessions.first else {
            throw SleepServiceError.sessionNotFound
        }

        return session
    }

    // MARK: - Statistics

    /// Get sleep listening statistics for the current user
    func getSleepStats(days: Int = 30) async throws -> SleepStats {
        guard let userId = supabase.auth.currentUser?.id.uuidString else {
            throw SleepServiceError.notAuthenticated
        }

        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()

        let sessions: [SleepSession] = try await supabase
            .from("sleep_sessions")
            .select()
            .eq("user_id", value: userId)
            .gte("started_at", value: ISO8601DateFormatter().string(from: startDate))
            .execute()
            .value

        let totalSessions = sessions.count
        let completedSessions = sessions.filter { $0.completed }.count
        let totalListenedSeconds = sessions.reduce(0) { $0 + $1.durationListenedSeconds }
        let sessionsWithTimer = sessions.filter { $0.sleepTimerUsed }.count

        return SleepStats(
            totalSessions: totalSessions,
            completedSessions: completedSessions,
            totalListenedMinutes: totalListenedSeconds / 60,
            sessionsWithTimer: sessionsWithTimer,
            periodDays: days
        )
    }
}

// MARK: - Sleep Stats

struct SleepStats {
    let totalSessions: Int
    let completedSessions: Int
    let totalListenedMinutes: Int
    let sessionsWithTimer: Int
    let periodDays: Int

    var completionRate: Double {
        guard totalSessions > 0 else { return 0 }
        return Double(completedSessions) / Double(totalSessions)
    }

    var timerUsageRate: Double {
        guard totalSessions > 0 else { return 0 }
        return Double(sessionsWithTimer) / Double(totalSessions)
    }

    var averageSessionMinutes: Int {
        guard totalSessions > 0 else { return 0 }
        return totalListenedMinutes / totalSessions
    }

    var formattedTotalListened: String {
        let hours = totalListenedMinutes / 60
        let minutes = totalListenedMinutes % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
