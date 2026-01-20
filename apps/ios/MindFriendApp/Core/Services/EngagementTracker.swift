import Foundation
import OSLog

/// Tracks notification engagement for ML training and analytics
@MainActor
final class EngagementTracker: ObservableObject {
    private let supabaseDataService: SupabaseDataService

    /// Weekly engagement stats (cached)
    @Published private(set) var weeklyStats: EngagementStats?

    /// Last stats update time
    private var lastStatsUpdate: Date?

    init(supabaseDataService: SupabaseDataService) {
        self.supabaseDataService = supabaseDataService
    }

    // MARK: - Event Logging

    /// Log an engagement event
    func logEvent(_ event: EngagementEvent) async throws {
        try await supabaseDataService.logNotificationEngagement(event)
        Log.notifications.debug("[EngagementTracker] Logged event: \(event.outcome.rawValue) for \(event.notificationType)")
    }

    /// Log notification scheduled
    func logScheduled(
        notificationId: UUID,
        type: SmartNotificationType,
        prediction: EngagementPrediction,
        context: UnifiedContext
    ) async {
        let event = EngagementEvent(
            id: nil,
            notificationId: notificationId,
            userId: supabaseDataService.currentUserId ?? UUID(),
            notificationType: type.rawValue,
            predictedEngagement: prediction.probability,
            contextSnapshot: context,
            outcome: .scheduled,
            timestamp: Date(),
            userFeedbackScore: nil,
            userFeedbackText: nil
        )

        do {
            try await logEvent(event)
        } catch {
            Log.notifications.error("[EngagementTracker] Failed to log scheduled: \(error)")
        }
    }

    /// Log notification suppressed
    func logSuppressed(
        notificationId: UUID,
        type: SmartNotificationType,
        prediction: EngagementPrediction?,
        context: UnifiedContext,
        reason: String
    ) async {
        let event = EngagementEvent(
            id: nil,
            notificationId: notificationId,
            userId: supabaseDataService.currentUserId ?? UUID(),
            notificationType: type.rawValue,
            predictedEngagement: prediction?.probability,
            contextSnapshot: context,
            outcome: .suppressed,
            timestamp: Date(),
            userFeedbackScore: nil,
            userFeedbackText: nil
        )

        do {
            try await logEvent(event)
        } catch {
            Log.notifications.error("[EngagementTracker] Failed to log suppressed: \(error)")
        }
    }

    /// Log notification delivered
    func logDelivered(notificationId: UUID, type: SmartNotificationType) async {
        let event = EngagementEvent(
            id: nil,
            notificationId: notificationId,
            userId: supabaseDataService.currentUserId ?? UUID(),
            notificationType: type.rawValue,
            predictedEngagement: nil,
            contextSnapshot: nil,
            outcome: .delivered,
            timestamp: Date(),
            userFeedbackScore: nil,
            userFeedbackText: nil
        )

        do {
            try await logEvent(event)
        } catch {
            Log.notifications.error("[EngagementTracker] Failed to log delivered: \(error)")
        }
    }

    /// Log notification opened
    func logOpened(notificationId: UUID, type: SmartNotificationType) async {
        let event = EngagementEvent(
            id: nil,
            notificationId: notificationId,
            userId: supabaseDataService.currentUserId ?? UUID(),
            notificationType: type.rawValue,
            predictedEngagement: nil,
            contextSnapshot: nil,
            outcome: .opened,
            timestamp: Date(),
            userFeedbackScore: nil,
            userFeedbackText: nil
        )

        do {
            try await logEvent(event)
        } catch {
            Log.notifications.error("[EngagementTracker] Failed to log opened: \(error)")
        }
    }

    /// Log notification action completed
    func logCompleted(notificationId: UUID, type: SmartNotificationType) async {
        let event = EngagementEvent(
            id: nil,
            notificationId: notificationId,
            userId: supabaseDataService.currentUserId ?? UUID(),
            notificationType: type.rawValue,
            predictedEngagement: nil,
            contextSnapshot: nil,
            outcome: .completed,
            timestamp: Date(),
            userFeedbackScore: nil,
            userFeedbackText: nil
        )

        do {
            try await logEvent(event)
        } catch {
            Log.notifications.error("[EngagementTracker] Failed to log completed: \(error)")
        }
    }

    /// Log notification dismissed
    func logDismissed(notificationId: UUID, type: SmartNotificationType) async {
        let event = EngagementEvent(
            id: nil,
            notificationId: notificationId,
            userId: supabaseDataService.currentUserId ?? UUID(),
            notificationType: type.rawValue,
            predictedEngagement: nil,
            contextSnapshot: nil,
            outcome: .dismissed,
            timestamp: Date(),
            userFeedbackScore: nil,
            userFeedbackText: nil
        )

        do {
            try await logEvent(event)
        } catch {
            Log.notifications.error("[EngagementTracker] Failed to log dismissed: \(error)")
        }
    }

    /// Log notification expired
    func logExpired(notificationId: UUID, type: SmartNotificationType) async {
        let event = EngagementEvent(
            id: nil,
            notificationId: notificationId,
            userId: supabaseDataService.currentUserId ?? UUID(),
            notificationType: type.rawValue,
            predictedEngagement: nil,
            contextSnapshot: nil,
            outcome: .expired,
            timestamp: Date(),
            userFeedbackScore: nil,
            userFeedbackText: nil
        )

        do {
            try await logEvent(event)
        } catch {
            Log.notifications.error("[EngagementTracker] Failed to log expired: \(error)")
        }
    }

    // MARK: - Training Data

    /// Fetch training data for ML model (last 30 days)
    func fetchTrainingData() async throws -> [EngagementEvent] {
        try await supabaseDataService.fetchNotificationTrainingData()
    }

    // MARK: - Statistics

    /// Get weekly engagement stats
    func getWeeklyStats() async throws -> EngagementStats {
        // Return cached if recent (< 1 hour)
        if let cached = weeklyStats,
           let lastUpdate = lastStatsUpdate,
           Date().timeIntervalSince(lastUpdate) < 3600 {
            return cached
        }

        let stats = try await supabaseDataService.fetchNotificationEngagementStats()
        weeklyStats = stats
        lastStatsUpdate = Date()
        return stats
    }

    /// Invalidate cached stats
    func invalidateStatsCache() {
        weeklyStats = nil
        lastStatsUpdate = nil
    }
}
