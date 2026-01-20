import Foundation
import OSLog

/// In-memory priority queue for smart notifications with bundling logic
@MainActor
final class NotificationQueue: ObservableObject {
    /// Queued notifications sorted by priority and creation time
    @Published private(set) var queue: [QueuedNotification] = []

    /// Number of notifications delivered today
    @Published private(set) var deliveredToday: Int = 0

    /// Date of last reset (for daily counter)
    private var lastResetDate: Date = Date()

    init() {
        resetDailyCounterIfNeeded()
    }

    // MARK: - Queue Operations

    /// Add a notification to the queue
    func enqueue(_ notification: QueuedNotification) {
        queue.append(notification)
        sortQueue()
        Log.notifications.debug("[NotificationQueue] Enqueued: \(notification.type.rawValue), priority: \(notification.priority.rawValue)")
    }

    /// Remove a notification from the queue
    func dequeue(id: UUID) {
        queue.removeAll { $0.id == id }
    }

    /// Remove multiple notifications
    func dequeue(ids: [UUID]) {
        let idSet = Set(ids)
        queue.removeAll { idSet.contains($0.id) }
    }

    /// Get notifications ready for delivery
    /// Returns bundled notifications if 3+ are ready
    func getDeliverableNotifications(maxPerDay: Int) -> [DeliverableItem] {
        resetDailyCounterIfNeeded()

        // Calculate remaining slots for today
        let remainingSlots = max(0, maxPerDay - deliveredToday)
        guard remainingSlots > 0 else {
            Log.notifications.debug("[NotificationQueue] Daily limit reached (\(maxPerDay))")
            return []
        }

        // Filter out expired and get deliverable notifications
        let now = Date()
        let deliverable = queue.filter { notification in
            // Not expired
            guard !notification.isExpired else { return false }

            // Scheduled time has passed (or no scheduled time)
            if let scheduledFor = notification.scheduledFor {
                return scheduledFor <= now
            }
            return true
        }

        guard !deliverable.isEmpty else { return [] }

        // Separate crisis/urgent from regular
        let crisis = deliverable.filter { $0.priority.bypassesSuppression }
        let urgent = deliverable.filter { $0.priority == .urgent }
        let regular = deliverable.filter { !$0.priority.bypassesSuppression && $0.priority != .urgent }

        var result: [DeliverableItem] = []

        // Crisis notifications always delivered immediately (don't count toward limit)
        for notification in crisis {
            result.append(.single(notification))
        }

        // Urgent notifications delivered individually (count toward limit)
        let urgentToDeliver = Array(urgent.prefix(remainingSlots))
        for notification in urgentToDeliver {
            result.append(.single(notification))
        }

        let slotsAfterUrgent = remainingSlots - urgentToDeliver.count
        guard slotsAfterUrgent > 0 && !regular.isEmpty else {
            return result
        }

        // Regular notifications: bundle if 3+
        if regular.count >= 3 && slotsAfterUrgent >= 1 {
            // Bundle all regular notifications
            let bundle = NotificationBundle.create(from: Array(regular))
            result.append(.bundle(bundle))
        } else {
            // Deliver individually up to limit
            let toDeliver = Array(regular.prefix(slotsAfterUrgent))
            for notification in toDeliver {
                result.append(.single(notification))
            }
        }

        return result
    }

    /// Expire notifications older than 24 hours
    /// Returns IDs of expired notifications
    func expireOldNotifications() -> [UUID] {
        let expiredIds = queue.filter { $0.isExpired }.map { $0.id }
        queue.removeAll { $0.isExpired }

        if !expiredIds.isEmpty {
            Log.notifications.debug("[NotificationQueue] Expired \(expiredIds.count) notifications")
        }

        return expiredIds
    }

    /// Mark notifications as delivered
    func markDelivered(ids: [UUID]) {
        dequeue(ids: ids)
        deliveredToday += ids.count
    }

    /// Clear all queued notifications
    func clearQueue() {
        queue.removeAll()
    }

    // MARK: - Private Methods

    private func sortQueue() {
        queue.sort { lhs, rhs in
            // Sort by priority (descending), then by creation time (ascending)
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private func resetDailyCounterIfNeeded() {
        let calendar = Calendar.current
        if !calendar.isDate(lastResetDate, inSameDayAs: Date()) {
            deliveredToday = 0
            lastResetDate = Date()
            Log.notifications.debug("[NotificationQueue] Daily counter reset")
        }
    }
}

// MARK: - Queue Statistics

extension NotificationQueue {
    /// Get queue statistics
    var statistics: QueueStatistics {
        let byType = Dictionary(grouping: queue, by: { $0.type })
        let byPriority = Dictionary(grouping: queue, by: { $0.priority })

        return QueueStatistics(
            totalQueued: queue.count,
            deliveredToday: deliveredToday,
            byType: byType.mapValues { $0.count },
            byPriority: byPriority.mapValues { $0.count },
            oldestNotification: queue.min(by: { $0.createdAt < $1.createdAt })?.createdAt
        )
    }
}

/// Statistics about the notification queue
struct QueueStatistics {
    let totalQueued: Int
    let deliveredToday: Int
    let byType: [SmartNotificationType: Int]
    let byPriority: [NotificationPriority: Int]
    let oldestNotification: Date?
}
