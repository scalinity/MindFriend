import XCTest
@testable import MindFriendApp

/// Tests for the Smart Notification system
final class SmartNotificationTests: XCTestCase {

    // MARK: - MLPredictionEngine Tests

    @MainActor
    func testPredictionEngineHeuristicsForNewUser() async throws {
        let engine = MLPredictionEngine()

        // Day 0 - should use heuristics, model not ready
        engine.initialize(accountCreatedAt: Date())
        XCTAssertFalse(engine.isReady, "Model should not be ready for new users")

        // Test morning prediction (should be favorable)
        let morningFeatures = PredictionFeatures(
            hourOfDay: 8,
            dayOfWeek: 2, // Monday
            isWeekend: false,
            avgEngagementAtHour: 0,
            recentEngagementRate: 0.5,
            daysSinceLastOpen: 0,
            hasCalendarEvent: false,
            locationContext: "home",
            biometricStress: 0.3,
            focusModeActive: false,
            notificationType: SmartNotificationType.quest.rawValue,
            notificationPriority: NotificationPriority.normal.rawValue
        )

        let morningPrediction = engine.predict(features: morningFeatures)
        XCTAssertGreaterThanOrEqual(morningPrediction.probability, 0.60, "Morning should have high engagement probability")

        // Test late night prediction (should be unfavorable)
        let nightFeatures = PredictionFeatures(
            hourOfDay: 23,
            dayOfWeek: 2,
            isWeekend: false,
            avgEngagementAtHour: 0,
            recentEngagementRate: 0.5,
            daysSinceLastOpen: 0,
            hasCalendarEvent: false,
            locationContext: "home",
            biometricStress: 0.3,
            focusModeActive: false,
            notificationType: SmartNotificationType.quest.rawValue,
            notificationPriority: NotificationPriority.normal.rawValue
        )

        let nightPrediction = engine.predict(features: nightFeatures)
        XCTAssertLessThan(nightPrediction.probability, 0.50, "Late night should have low engagement probability")
    }

    @MainActor
    func testPredictionEngineReadyAfter7Days() async throws {
        let engine = MLPredictionEngine()

        // 8 days ago
        let eightDaysAgo = Calendar.current.date(byAdding: .day, value: -8, to: Date())!
        engine.initialize(accountCreatedAt: eightDaysAgo)

        XCTAssertTrue(engine.isReady, "Model should be ready after 7 days")
    }

    @MainActor
    func testThresholdMeetsEngagement() async throws {
        let engine = MLPredictionEngine()

        // Initialize as established user
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        engine.initialize(accountCreatedAt: thirtyDaysAgo)

        // 70% should meet default 60% threshold
        let highPrediction = EngagementPrediction(
            probability: 0.70,
            confidence: 0.8,
            features: makeMockFeatures(),
            predictedAt: Date()
        )
        XCTAssertTrue(engine.meetsThreshold(highPrediction), "70% should meet 60% threshold")

        // 50% should not meet default 60% threshold
        let lowPrediction = EngagementPrediction(
            probability: 0.50,
            confidence: 0.8,
            features: makeMockFeatures(),
            predictedAt: Date()
        )
        XCTAssertFalse(engine.meetsThreshold(lowPrediction), "50% should not meet 60% threshold")
    }

    @MainActor
    func testRelaxedThresholdForDays8To14() async throws {
        let engine = MLPredictionEngine()

        // 10 days ago (in relaxed period)
        let tenDaysAgo = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        engine.initialize(accountCreatedAt: tenDaysAgo)

        // 50% should meet relaxed 50% threshold
        let prediction = EngagementPrediction(
            probability: 0.50,
            confidence: 0.8,
            features: makeMockFeatures(),
            predictedAt: Date()
        )
        XCTAssertTrue(engine.meetsThreshold(prediction), "50% should meet relaxed threshold for days 8-14")
    }

    // MARK: - NotificationQueue Tests

    @MainActor
    func testQueueEnqueueAndDequeue() async throws {
        let queue = NotificationQueue()

        let notification = makeQueuedNotification(type: .quest, priority: .normal)
        queue.enqueue(notification)

        XCTAssertEqual(queue.queue.count, 1, "Queue should have 1 notification")

        queue.dequeue(id: notification.id)
        XCTAssertEqual(queue.queue.count, 0, "Queue should be empty after dequeue")
    }

    @MainActor
    func testQueuePrioritySorting() async throws {
        let queue = NotificationQueue()

        let normalNotification = makeQueuedNotification(type: .quest, priority: .normal)
        let urgentNotification = makeQueuedNotification(type: .streak, priority: .urgent)
        let crisisNotification = makeQueuedNotification(type: .crisis, priority: .crisis)

        // Add in reverse priority order
        queue.enqueue(normalNotification)
        queue.enqueue(urgentNotification)
        queue.enqueue(crisisNotification)

        // Should be sorted: crisis, urgent, normal
        XCTAssertEqual(queue.queue[0].priority, .crisis)
        XCTAssertEqual(queue.queue[1].priority, .urgent)
        XCTAssertEqual(queue.queue[2].priority, .normal)
    }

    @MainActor
    func testQueueBundlingWith3PlusNotifications() async throws {
        let queue = NotificationQueue()

        // Add 4 normal notifications
        for i in 0..<4 {
            let notification = QueuedNotification(
                id: UUID(),
                type: .quest,
                title: "Quest \(i)",
                body: "Body \(i)",
                deepLink: nil,
                priority: .normal,
                engagementScore: 0.7,
                scheduledFor: nil,
                context: nil,
                createdAt: Date()
            )
            queue.enqueue(notification)
        }

        let deliverables = queue.getDeliverableNotifications(maxPerDay: 10)

        // Should be bundled into a single bundle
        XCTAssertEqual(deliverables.count, 1, "Should bundle 4 notifications into 1")

        if case .bundle(let bundle) = deliverables.first {
            XCTAssertEqual(bundle.notifications.count, 4, "Bundle should contain all 4 notifications")
        } else {
            XCTFail("Expected a bundle")
        }
    }

    @MainActor
    func testQueueCrisisNotificationBypassesBundling() async throws {
        let queue = NotificationQueue()

        // Add 3 normal + 1 crisis
        for i in 0..<3 {
            queue.enqueue(makeQueuedNotification(type: .quest, priority: .normal))
        }
        queue.enqueue(makeQueuedNotification(type: .crisis, priority: .crisis))

        let deliverables = queue.getDeliverableNotifications(maxPerDay: 10)

        // Crisis should be delivered separately, rest bundled
        XCTAssertEqual(deliverables.count, 2, "Should have crisis + bundle")

        var hasCrisis = false
        var hasBundle = false

        for item in deliverables {
            switch item {
            case .single(let notification):
                if notification.priority == .crisis {
                    hasCrisis = true
                }
            case .bundle:
                hasBundle = true
            }
        }

        XCTAssertTrue(hasCrisis, "Crisis notification should be delivered separately")
        XCTAssertTrue(hasBundle, "Normal notifications should be bundled")
    }

    @MainActor
    func testQueueDailyLimitEnforced() async throws {
        let queue = NotificationQueue()

        // Add 5 notifications
        for _ in 0..<5 {
            queue.enqueue(makeQueuedNotification(type: .quest, priority: .normal))
        }

        // Get with limit of 3
        let deliverables = queue.getDeliverableNotifications(maxPerDay: 3)

        // Should bundle all 5 into 1 (bundling counts as 1 toward limit)
        // Actually since 5 >= 3 and slots = 3, should still bundle
        XCTAssertEqual(deliverables.count, 1, "Should bundle within daily limit")
    }

    @MainActor
    func testQueueExpiredNotificationsRemoved() async throws {
        let queue = NotificationQueue()

        // Add an expired notification (25 hours old)
        let expiredNotification = QueuedNotification(
            id: UUID(),
            type: .quest,
            title: "Expired",
            body: "Body",
            deepLink: nil,
            priority: .normal,
            engagementScore: 0.7,
            scheduledFor: nil,
            context: nil,
            createdAt: Date(timeIntervalSinceNow: -25 * 60 * 60)
        )
        queue.enqueue(expiredNotification)

        let expiredIds = queue.expireOldNotifications()

        XCTAssertEqual(expiredIds.count, 1, "Should expire 1 notification")
        XCTAssertEqual(queue.queue.count, 0, "Queue should be empty after expiration")
    }

    // MARK: - EngagementOutcome Tests

    func testEngagementOutcomePositiveClassification() {
        XCTAssertTrue(EngagementOutcome.opened.isPositive)
        XCTAssertTrue(EngagementOutcome.completed.isPositive)
        XCTAssertFalse(EngagementOutcome.dismissed.isPositive)
        XCTAssertFalse(EngagementOutcome.expired.isPositive)
        XCTAssertFalse(EngagementOutcome.suppressed.isPositive)
    }

    // MARK: - NotificationPriority Tests

    func testCrisisAndUrgentBypassSuppression() {
        XCTAssertTrue(NotificationPriority.crisis.bypassesSuppression)
        XCTAssertFalse(NotificationPriority.urgent.bypassesSuppression)
        XCTAssertFalse(NotificationPriority.high.bypassesSuppression)
        XCTAssertFalse(NotificationPriority.normal.bypassesSuppression)
        XCTAssertFalse(NotificationPriority.low.bypassesSuppression)
    }

    func testPriorityComparison() {
        XCTAssertTrue(NotificationPriority.crisis > NotificationPriority.urgent)
        XCTAssertTrue(NotificationPriority.urgent > NotificationPriority.high)
        XCTAssertTrue(NotificationPriority.high > NotificationPriority.normal)
        XCTAssertTrue(NotificationPriority.normal > NotificationPriority.low)
    }

    // MARK: - Context Tests

    func testUnifiedContextSuppression() {
        // Focus mode suppresses
        var context = UnifiedContext(
            calendar: CalendarContext(isBusy: false, nextEventInMinutes: nil, eventType: nil),
            location: LocationContext(type: .home, isStale: false, lastUpdated: Date()),
            biometric: BiometricContext(heartRate: 70, hrv: 50, isStressed: false, sleepState: nil, lastUpdated: Date()),
            focusMode: FocusModeContext(mode: .sleep, shouldSuppress: true),
            timestamp: Date()
        )

        XCTAssertTrue(context.shouldSuppressNotification, "Sleep Focus should suppress")

        // No suppression when Focus mode is off
        context = UnifiedContext(
            calendar: CalendarContext(isBusy: false, nextEventInMinutes: nil, eventType: nil),
            location: LocationContext(type: .home, isStale: false, lastUpdated: Date()),
            biometric: BiometricContext(heartRate: 70, hrv: 50, isStressed: false, sleepState: nil, lastUpdated: Date()),
            focusMode: FocusModeContext(mode: .none, shouldSuppress: false),
            timestamp: Date()
        )

        XCTAssertFalse(context.shouldSuppressNotification, "No Focus mode should not suppress")
    }

    // MARK: - Helper Methods

    private func makeMockFeatures() -> PredictionFeatures {
        PredictionFeatures(
            hourOfDay: 12,
            dayOfWeek: 3,
            isWeekend: false,
            avgEngagementAtHour: 0.5,
            recentEngagementRate: 0.5,
            daysSinceLastOpen: 0,
            hasCalendarEvent: false,
            locationContext: "home",
            biometricStress: 0.3,
            focusModeActive: false,
            notificationType: SmartNotificationType.quest.rawValue,
            notificationPriority: NotificationPriority.normal.rawValue
        )
    }

    private func makeQueuedNotification(type: SmartNotificationType, priority: NotificationPriority) -> QueuedNotification {
        QueuedNotification(
            id: UUID(),
            type: type,
            title: "Test",
            body: "Body",
            deepLink: nil,
            priority: priority,
            engagementScore: 0.7,
            scheduledFor: nil,
            context: nil,
            createdAt: Date()
        )
    }
}
