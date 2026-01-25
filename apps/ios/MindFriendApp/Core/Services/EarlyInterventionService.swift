import Foundation
import UserNotifications

/// Service for delivering early interventions when patterns emerge
@MainActor
final class EarlyInterventionService: ObservableObject {
    private let supabaseDataService: SupabaseDataService

    @Published private(set) var pendingIntervention: PendingIntervention?
    @Published private(set) var lastDeliveredAt: Date?

    init(supabaseDataService: SupabaseDataService) {
        self.supabaseDataService = supabaseDataService
    }

    /// Trigger an intervention based on alert severity
    func triggerIntervention(
        for alert: PatternAlert,
        signature: WarningSignature
    ) async throws {
        // Generate personalized message
        let message = generateAlertMessage(
            activeComponents: alert.activeComponents,
            severity: alert.severity
        )

        // Select appropriate intervention
        let intervention = selectIntervention(
            tier: alert.interventionTier,
            activeComponents: alert.activeComponents
        )

        // Create pending intervention
        let pending = PendingIntervention(
            alertId: alert.id,
            message: message,
            tier: alert.interventionTier,
            suggestedInterventions: intervention.suggestions,
            estimatedHours: alert.predictedHours
        )

        pendingIntervention = pending

        // Deliver based on tier
        switch alert.interventionTier {
        case .gentle:
            // In-app only - no push notification
            break

        case .moderate:
            // Send push notification
            try await sendPushNotification(
                title: "Pattern Noticed",
                body: message,
                alertId: alert.id
            )

        case .immediate:
            // Persistent notification with higher priority
            try await sendPushNotification(
                title: "Let's Check In",
                body: message,
                alertId: alert.id,
                priority: .high
            )
        }

        // Mark as delivered
        try await supabaseDataService.markAlertDelivered(alertId: alert.id)
        lastDeliveredAt = Date()
    }

    /// Generate a personalized alert message based on active components
    private func generateAlertMessage(
        activeComponents: [ActiveSignal],
        severity: AlertSeverity
    ) -> String {
        let signals = activeComponents.map { $0.signal }

        // Specific patterns
        if signals.contains("isolation") && signals.contains("insomnia_wired") {
            return "I've noticed you've been quieter lately and sleep has been tough. This is a pattern we've seen before. Want to talk about it?"
        }

        if signals.contains("catastrophizing") || signals.contains("rumination") {
            return "It seems like worries have been building up. Let's take a moment to get grounded."
        }

        if signals.contains("numbness") || signals.contains("oversleeping") {
            return "I'm noticing some familiar patterns. How are you really doing?"
        }

        if signals.contains("low_energy") && signals.contains("procrastination") {
            return "Energy has felt low lately. Small steps today can help break the cycle."
        }

        if signals.contains("tearfulness") || signals.contains("irritability") {
            return "Emotions have been running high. That's okay. Let's check in together."
        }

        if signals.contains("tension") || signals.contains("appetite_change") {
            return "Your body might be telling you something. Let's pause and check in."
        }

        // Generic by severity
        switch severity {
        case .severe:
            return "I'm noticing several warning signs coming together. This is a good time to reach out for support."
        case .moderate:
            return "Some patterns are emerging that we've tracked before. Let's check in and see how you're really doing."
        case .mild:
            return "I'm noticing a few familiar signs. How are you feeling today?"
        }
    }

    /// Select appropriate interventions based on tier and components
    private func selectIntervention(
        tier: InterventionTier,
        activeComponents: [ActiveSignal]
    ) -> InterventionSelection {
        var suggestions: [SuggestedIntervention] = []
        let signals = Set(activeComponents.map { $0.signal })

        // Sleep issues
        if signals.contains("insomnia_wired") || signals.contains("oversleeping") || signals.contains("early_waking") {
            suggestions.append(SuggestedIntervention(
                type: .exercise,
                name: "Sleep Wind-Down",
                description: "A calming routine to prepare for restful sleep",
                exerciseId: nil
            ))
        }

        // Cognitive issues
        if signals.contains("catastrophizing") || signals.contains("rumination") || signals.contains("indecision") {
            suggestions.append(SuggestedIntervention(
                type: .exercise,
                name: "Thought Defusion",
                description: "Step back from anxious thoughts",
                exerciseId: nil
            ))
            suggestions.append(SuggestedIntervention(
                type: .exercise,
                name: "Grounding Exercise",
                description: "Connect with the present moment",
                exerciseId: nil
            ))
        }

        // Emotional issues
        if signals.contains("numbness") || signals.contains("tearfulness") {
            suggestions.append(SuggestedIntervention(
                type: .chat,
                name: "Talk It Through",
                description: "Express what you're feeling",
                exerciseId: nil
            ))
        }

        // Social issues
        if signals.contains("isolation") || signals.contains("irritability") {
            suggestions.append(SuggestedIntervention(
                type: .socialConnection,
                name: "Reach Out",
                description: "Connect with someone who cares",
                exerciseId: nil
            ))
        }

        // Physical issues
        if signals.contains("tension") || signals.contains("low_energy") {
            suggestions.append(SuggestedIntervention(
                type: .exercise,
                name: "Body Scan",
                description: "Release physical tension",
                exerciseId: nil
            ))
        }

        // Always include a breathing exercise for moderate+
        if tier != .gentle {
            suggestions.insert(SuggestedIntervention(
                type: .exercise,
                name: "Deep Breathing",
                description: "Calm your nervous system in 2 minutes",
                exerciseId: nil
            ), at: 0)
        }

        // For immediate tier, add crisis resources
        if tier == .immediate {
            suggestions.append(SuggestedIntervention(
                type: .crisisResources,
                name: "Support Resources",
                description: "Professional help is available",
                exerciseId: nil
            ))
        }

        return InterventionSelection(suggestions: suggestions)
    }

    /// Send a push notification
    private func sendPushNotification(
        title: String,
        body: String,
        alertId: UUID,
        priority: InterventionNotificationPriority = .normal
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = priority == .high ? .default : .none
        content.userInfo = [
            "type": "pattern_alert",
            "alert_id": alertId.uuidString
        ]
        content.categoryIdentifier = "PATTERN_ALERT"

        // Set thread identifier for grouping
        content.threadIdentifier = "stress_signature"

        // Configure for immediate delivery
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)

        let request = UNNotificationRequest(
            identifier: "pattern_alert_\(alertId.uuidString)",
            content: content,
            trigger: trigger
        )

        try await UNUserNotificationCenter.current().add(request)
    }

    /// Dismiss the current pending intervention
    func dismissIntervention() {
        pendingIntervention = nil
    }

    /// Handle user completing a suggested intervention
    func completeIntervention(_ intervention: SuggestedIntervention) async {
        // Log completion for analytics
        // Could track engagement with interventions here
    }

    /// Configure notification categories for pattern alerts
    static func configureNotificationCategories() {
        let viewAction = UNNotificationAction(
            identifier: "VIEW_ALERT",
            title: "View Details",
            options: [.foreground]
        )

        let dismissAction = UNNotificationAction(
            identifier: "DISMISS_ALERT",
            title: "Dismiss",
            options: []
        )

        let category = UNNotificationCategory(
            identifier: "PATTERN_ALERT",
            actions: [viewAction, dismissAction],
            intentIdentifiers: [],
            options: [.hiddenPreviewsShowTitle]
        )

        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}

// MARK: - Supporting Types

struct PendingIntervention: Identifiable, Sendable {
    let id = UUID()
    let alertId: UUID
    let message: String
    let tier: InterventionTier
    let suggestedInterventions: [SuggestedIntervention]
    let estimatedHours: Int?
}

struct SuggestedIntervention: Identifiable, Sendable {
    let id = UUID()
    let type: InterventionType
    let name: String
    let description: String
    let exerciseId: UUID?

    enum InterventionType: String, Sendable {
        case exercise
        case chat
        case socialConnection
        case crisisResources
        case journal
    }
}

struct InterventionSelection {
    let suggestions: [SuggestedIntervention]
}

enum InterventionNotificationPriority {
    case normal
    case high
}

// MARK: - SupabaseDataService Extension

extension SupabaseDataService {
    func markAlertDelivered(alertId: UUID) async throws {
        struct DeliveredUpdate: Encodable {
            let interventionDelivered: Bool
            let interventionDeliveredAt: String

            enum CodingKeys: String, CodingKey {
                case interventionDelivered = "intervention_delivered"
                case interventionDeliveredAt = "intervention_delivered_at"
            }
        }

        let update = DeliveredUpdate(
            interventionDelivered: true,
            interventionDeliveredAt: ISO8601DateFormatter().string(from: Date())
        )

        _ = try await supabase
            .from("pattern_alerts")
            .update(update)
            .eq("id", value: alertId.uuidString)
            .execute()
    }
}
