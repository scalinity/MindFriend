import Foundation
import UserNotifications
import OSLog
import BackgroundTasks
import Combine

/// Main orchestrator for smart notifications
/// Coordinates ML prediction, context awareness, queue management, and engagement tracking
@MainActor
final class SmartNotificationService: ObservableObject {
    // MARK: - Dependencies

    private let contextEngine: ContextEngine
    private let predictionEngine: MLPredictionEngine
    private let notificationQueue: NotificationQueue
    private let engagementTracker: EngagementTracker
    private let notificationManager: NotificationManager
    private let supabaseDataService: SupabaseDataService

    // MARK: - Published State

    @Published private(set) var isEnabled: Bool = true
    @Published private(set) var lastProcessedAt: Date?
    @Published private(set) var weeklyEngagementRate: Double = 0.0

    // MARK: - Settings

    private var maxNotificationsPerDay: Int = SmartNotificationDefaults.maxPerDay
    private var engagementThreshold: Double = 0.60

    // MARK: - Background Processing

    private var foregroundTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    /// Background task identifier
    static let backgroundTaskIdentifier = "com.mindfriend.smart-notifications.process"

    // MARK: - Initialization

    init(
        contextEngine: ContextEngine,
        predictionEngine: MLPredictionEngine,
        notificationQueue: NotificationQueue,
        engagementTracker: EngagementTracker,
        notificationManager: NotificationManager,
        supabaseDataService: SupabaseDataService
    ) {
        self.contextEngine = contextEngine
        self.predictionEngine = predictionEngine
        self.notificationQueue = notificationQueue
        self.engagementTracker = engagementTracker
        self.notificationManager = notificationManager
        self.supabaseDataService = supabaseDataService

        setupObservers()
    }

    // MARK: - Configuration

    /// Configure the service with user settings
    func configure(settings: UserSettings) {
        isEnabled = settings.smartNotificationsEnabled ?? true
        maxNotificationsPerDay = settings.notificationMaxPerDay ?? SmartNotificationDefaults.maxPerDay

        // Adjust threshold based on frequency preference
        if let frequencyStr = settings.notificationFrequency,
           let frequency = NotificationFrequency(rawValue: frequencyStr) {
            switch frequency {
            case .minimal:
                engagementThreshold = 0.70 // Higher threshold = fewer notifications
            case .moderate:
                engagementThreshold = 0.60
            case .frequent:
                engagementThreshold = 0.50 // Lower threshold = more notifications
            }
        }

        Log.notifications.debug("[SmartNotifications] Configured - enabled: \(self.isEnabled), maxPerDay: \(self.maxNotificationsPerDay), threshold: \(self.engagementThreshold)")
    }

    /// Initialize ML model with user's account creation date
    func initializeModel(accountCreatedAt: Date) {
        predictionEngine.initialize(accountCreatedAt: accountCreatedAt)
    }

    // MARK: - Schedule Notification

    /// Schedule a smart notification
    /// Returns the notification ID if scheduled, nil if suppressed
    @discardableResult
    func scheduleNotification(
        type: SmartNotificationType,
        title: String,
        body: String,
        deepLink: String? = nil,
        priority: NotificationPriority = .normal
    ) async throws -> UUID? {
        guard isEnabled || priority.bypassesSuppression else {
            Log.notifications.debug("[SmartNotifications] Service disabled, skipping \(type.rawValue)")
            return nil
        }

        let notificationId = UUID()

        // Crisis notifications bypass ALL checks
        if priority.bypassesSuppression {
            return try await deliverImmediately(
                id: notificationId,
                type: type,
                title: title,
                body: body,
                deepLink: deepLink,
                priority: priority
            )
        }

        // Get current context
        let context = await contextEngine.getCurrentContext()

        // Check for context-based suppression
        if context.shouldSuppressNotification {
            await engagementTracker.logSuppressed(
                notificationId: notificationId,
                type: type,
                prediction: nil,
                context: context,
                reason: context.suppressionReason ?? "Context suppression"
            )
            Log.notifications.debug("[SmartNotifications] Suppressed by context: \(context.suppressionReason ?? "unknown")")
            return nil
        }

        // Build prediction features
        let features = await buildPredictionFeatures(type: type, priority: priority, context: context)

        // Get engagement prediction
        let prediction = predictionEngine.predict(features: features)

        // Check if prediction meets threshold
        if !predictionEngine.meetsThreshold(prediction) {
            // Queue for later delivery at next optimal window
            let scheduledFor = calculateNextOptimalWindow(for: features.hourOfDay)

            let notification = QueuedNotification(
                id: notificationId,
                type: type,
                title: title,
                body: body,
                deepLink: deepLink,
                priority: priority,
                engagementScore: prediction.probability,
                scheduledFor: scheduledFor,
                context: context,
                createdAt: Date()
            )

            notificationQueue.enqueue(notification)

            await engagementTracker.logScheduled(
                notificationId: notificationId,
                type: type,
                prediction: prediction,
                context: context
            )

            Log.notifications.debug("[SmartNotifications] Queued for later: \(type.rawValue), score: \(prediction.probability), threshold: \(self.engagementThreshold)")
            return notificationId
        }

        // Add to queue for immediate delivery
        let notification = QueuedNotification(
            id: notificationId,
            type: type,
            title: title,
            body: body,
            deepLink: deepLink,
            priority: priority,
            engagementScore: prediction.probability,
            scheduledFor: nil, // Deliver now
            context: context,
            createdAt: Date()
        )

        notificationQueue.enqueue(notification)

        await engagementTracker.logScheduled(
            notificationId: notificationId,
            type: type,
            prediction: prediction,
            context: context
        )

        // Process queue immediately
        await processQueue()

        return notificationId
    }

    // MARK: - Queue Processing

    /// Process the notification queue and deliver eligible notifications
    func processQueue() async {
        guard isEnabled else { return }

        // Get deliverable notifications
        let deliverables = notificationQueue.getDeliverableNotifications(maxPerDay: maxNotificationsPerDay)

        guard !deliverables.isEmpty else {
            Log.notifications.debug("[SmartNotifications] No deliverable notifications")
            return
        }

        // Deliver each item
        for item in deliverables {
            switch item {
            case .single(let notification):
                await deliverSingleNotification(notification)
            case .bundle(let bundle):
                await deliverBundledNotifications(bundle)
            }
        }

        // Expire old notifications
        let expiredIds = notificationQueue.expireOldNotifications()
        for id in expiredIds {
            // We don't have the type info for expired notifications, use a default
            await engagementTracker.logExpired(notificationId: id, type: .quest)
        }

        lastProcessedAt = Date()
        Log.notifications.debug("[SmartNotifications] Queue processed, delivered: \(deliverables.count)")
    }

    // MARK: - Engagement Tracking

    /// Track that a notification was opened
    func trackNotificationOpened(notificationId: UUID, type: SmartNotificationType) async {
        await engagementTracker.logOpened(notificationId: notificationId, type: type)
        engagementTracker.invalidateStatsCache()
    }

    /// Track that a notification action was completed
    func trackNotificationCompleted(notificationId: UUID, type: SmartNotificationType) async {
        await engagementTracker.logCompleted(notificationId: notificationId, type: type)
        engagementTracker.invalidateStatsCache()
    }

    /// Track that a notification was dismissed
    func trackNotificationDismissed(notificationId: UUID, type: SmartNotificationType) async {
        await engagementTracker.logDismissed(notificationId: notificationId, type: type)
        engagementTracker.invalidateStatsCache()
    }

    // MARK: - Model Retraining

    /// Retrain the ML model with recent engagement data
    /// Should be called weekly (e.g., Sunday 2am local)
    func retrainModel() async {
        do {
            let trainingData = try await engagementTracker.fetchTrainingData()

            guard trainingData.count >= 10 else {
                Log.notifications.debug("[SmartNotifications] Not enough training data (\(trainingData.count))")
                return
            }

            try await predictionEngine.retrain(data: trainingData)
            Log.notifications.debug("[SmartNotifications] Model retrained with \(trainingData.count) samples")
        } catch {
            Log.notifications.error("[SmartNotifications] Model retrain failed: \(error)")
        }
    }

    /// Update weekly engagement stats
    func updateWeeklyStats() async {
        do {
            let stats = try await engagementTracker.getWeeklyStats()
            weeklyEngagementRate = stats.rate
        } catch {
            Log.notifications.error("[SmartNotifications] Failed to get weekly stats: \(error)")
        }
    }

    // MARK: - Background Processing

    /// Start foreground timer for queue processing
    func startForegroundProcessing() {
        stopForegroundProcessing()

        foregroundTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.processQueue()
            }
        }

        Log.notifications.debug("[SmartNotifications] Foreground processing started")
    }

    /// Stop foreground timer
    func stopForegroundProcessing() {
        foregroundTimer?.invalidate()
        foregroundTimer = nil
    }

    /// Register background task
    static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            handleBackgroundTask(refreshTask)
        }
    }

    /// Schedule next background task
    static func scheduleBackgroundTask() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 60 * 60) // 6 hours

        do {
            try BGTaskScheduler.shared.submit(request)
            Log.notifications.debug("[SmartNotifications] Background task scheduled")
        } catch {
            Log.notifications.error("[SmartNotifications] Failed to schedule background task: \(error)")
        }
    }

    /// Handle background task execution
    private static func handleBackgroundTask(_ task: BGAppRefreshTask) {
        // Schedule next task
        scheduleBackgroundTask()

        // Create a task to process the queue
        let processingTask = Task { @MainActor in
            // Access the shared container's smart notification service
            let service = DependencyContainer.shared.smartNotificationService
            await service.processQueue()
            Log.notifications.debug("[SmartNotifications] Background task executed")
        }

        task.expirationHandler = {
            processingTask.cancel()
        }

        Task {
            await processingTask.value
            task.setTaskCompleted(success: true)
        }
    }

    // MARK: - Private Methods

    private func setupObservers() {
        // Observe context engine changes
        contextEngine.$shouldSuppressNotifications
            .sink { [weak self] shouldSuppress in
                if shouldSuppress {
                    Log.notifications.debug("[SmartNotifications] Context changed to suppression")
                }
            }
            .store(in: &cancellables)
    }

    private func buildPredictionFeatures(
        type: SmartNotificationType,
        priority: NotificationPriority,
        context: UnifiedContext
    ) async -> PredictionFeatures {
        let now = Date()
        let calendar = Calendar.current

        let hour = calendar.component(.hour, from: now)
        let weekday = calendar.component(.weekday, from: now)

        // Get historical engagement rate for this hour
        let avgEngagementAtHour = predictionEngine.getHourlyEngagementRate(hour: hour)

        // Get recent engagement rate from tracker
        var recentEngagementRate: Double = 0.5
        if let stats = engagementTracker.weeklyStats {
            recentEngagementRate = stats.rate
        }

        // Calculate days since last app open (approximation)
        let daysSinceLastOpen = 0 // Would need to track this separately

        return PredictionFeatures(
            hourOfDay: hour,
            dayOfWeek: weekday,
            isWeekend: calendar.isDateInWeekend(now),
            avgEngagementAtHour: avgEngagementAtHour,
            recentEngagementRate: recentEngagementRate,
            daysSinceLastOpen: daysSinceLastOpen,
            hasCalendarEvent: context.calendar.isBusy,
            locationContext: context.location.type.rawValue,
            biometricStress: context.biometric.isStressed ? 0.8 : 0.2,
            focusModeActive: context.focusMode.shouldSuppress,
            notificationType: type.rawValue,
            notificationPriority: priority.rawValue
        )
    }

    private func calculateNextOptimalWindow(for currentHour: Int) -> Date {
        // Calculate next optimal time window (max 4 hours from now)
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day, .hour], from: Date())

        // Find next good hour
        let optimalHours = [9, 12, 18, 20] // Morning, lunch, evening, night
        let nextHour = optimalHours.first { $0 > currentHour } ?? optimalHours.first!

        if nextHour > currentHour {
            components.hour = nextHour
        } else {
            // Next day
            components.day! += 1
            components.hour = nextHour
        }

        return calendar.date(from: components) ?? Date(timeIntervalSinceNow: 4 * 60 * 60)
    }

    private func deliverImmediately(
        id: UUID,
        type: SmartNotificationType,
        title: String,
        body: String,
        deepLink: String?,
        priority: NotificationPriority
    ) async throws -> UUID {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = [
            "notification_id": id.uuidString,
            "type": type.rawValue,
            "smart_notification": true
        ]

        if let deepLink = deepLink {
            content.userInfo["deep_link"] = deepLink
        }

        let request = UNNotificationRequest(
            identifier: id.uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )

        try await UNUserNotificationCenter.current().add(request)

        await engagementTracker.logDelivered(notificationId: id, type: type)
        Log.notifications.debug("[SmartNotifications] Delivered immediately: \(type.rawValue) (crisis/urgent)")

        return id
    }

    private func deliverSingleNotification(_ notification: QueuedNotification) async {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.userInfo = [
            "notification_id": notification.id.uuidString,
            "type": notification.type.rawValue,
            "smart_notification": true
        ]

        if let deepLink = notification.deepLink {
            content.userInfo["deep_link"] = deepLink
        }

        let request = UNNotificationRequest(
            identifier: notification.id.uuidString,
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            notificationQueue.markDelivered(ids: [notification.id])
            await engagementTracker.logDelivered(notificationId: notification.id, type: notification.type)
            Log.notifications.debug("[SmartNotifications] Delivered: \(notification.type.rawValue)")
        } catch {
            Log.notifications.error("[SmartNotifications] Delivery failed: \(error)")
        }
    }

    private func deliverBundledNotifications(_ bundle: NotificationBundle) async {
        let content = UNMutableNotificationContent()
        content.title = bundle.title
        content.body = bundle.body
        content.sound = .default

        let ids = bundle.notifications.map { $0.id.uuidString }
        content.userInfo = [
            "notification_ids": ids,
            "type": "bundle",
            "smart_notification": true,
            "deep_link": bundle.deepLink
        ]

        let bundleId = UUID()
        let request = UNNotificationRequest(
            identifier: bundleId.uuidString,
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            let notificationIds = bundle.notifications.map { $0.id }
            notificationQueue.markDelivered(ids: notificationIds)

            for notification in bundle.notifications {
                await engagementTracker.logDelivered(notificationId: notification.id, type: notification.type)
            }

            Log.notifications.debug("[SmartNotifications] Delivered bundle: \(bundle.notifications.count) notifications")
        } catch {
            Log.notifications.error("[SmartNotifications] Bundle delivery failed: \(error)")
        }
    }
}
