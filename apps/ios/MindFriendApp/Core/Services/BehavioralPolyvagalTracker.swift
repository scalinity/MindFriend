import Foundation

/// Tracks app interaction patterns as polyvagal behavioral signals
@MainActor
final class BehavioralPolyvagalTracker: ObservableObject {
    // MARK: - Properties

    private var interactions: [AppInteraction] = []
    private let windowDuration: TimeInterval = 300 // 5 minutes
    private var sessionStartTime: Date?

    // MARK: - Public Interface

    /// Track an app interaction
    func trackInteraction(_ interaction: AppInteraction) {
        interactions.append(interaction)
        cleanOldInteractions()

        // Track session start/end
        switch interaction {
        case .appForegrounded, .voiceSessionStarted:
            if sessionStartTime == nil {
                sessionStartTime = Date()
            }
        case .appBackgrounded:
            sessionStartTime = nil
        default:
            break
        }
    }

    /// Get current behavioral features for polyvagal classification
    func getCurrentBehavioralFeatures() -> PolyvagalBehavioralFeatures {
        cleanOldInteractions()

        let now = Date()
        let recentInteractions = interactions.filter {
            now.timeIntervalSince($0.timestamp) < windowDuration
        }

        // Calculate activity level (interactions per minute)
        let interactionCount = Double(recentInteractions.count)
        let recentActivityLevel = min(1.0, interactionCount / (windowDuration / 60.0) / 5.0) // Normalize to 5 interactions/min = 1.0

        // Calculate social engagement (circles, chat)
        let socialInteractions = recentInteractions.filter {
            if case .circlePostCreated = $0 { return true }
            if case .chatMessageSent = $0 { return true }
            return false
        }
        let socialEngagementLevel = min(1.0, Double(socialInteractions.count) / 5.0) // 5 social interactions = 1.0

        // Calculate self-care level (quests, exercises, moods)
        let selfCareInteractions = recentInteractions.filter {
            if case .questCompleted = $0 { return true }
            if case .exerciseCompleted = $0 { return true }
            if case .moodLogged = $0 { return true }
            return false
        }
        let selfCareLevel = min(1.0, Double(selfCareInteractions.count) / 3.0) // 3 self-care activities = 1.0

        // Session duration
        let sessionDuration: TimeInterval = sessionStartTime.map { now.timeIntervalSince($0) } ?? 0

        // Time since last interaction
        let timeSinceLastInteraction: TimeInterval = interactions.last.map { now.timeIntervalSince($0.timestamp) } ?? 0

        // Consecutive backgrounding sessions
        let consecutiveBackgroundingSessions = countConsecutiveBackgrounding()

        return PolyvagalBehavioralFeatures(
            recentActivityLevel: recentActivityLevel,
            socialEngagementLevel: socialEngagementLevel,
            selfCareLevel: selfCareLevel,
            sessionDuration: sessionDuration,
            timeSinceLastInteraction: timeSinceLastInteraction,
            consecutiveBackgroundingSessions: consecutiveBackgroundingSessions
        )
    }

    /// Reset tracking (for testing)
    func reset() {
        interactions = []
        sessionStartTime = nil
    }

    // MARK: - Private Methods

    private func cleanOldInteractions() {
        let cutoff = Date().addingTimeInterval(-windowDuration)
        interactions.removeAll { $0.timestamp < cutoff }
    }

    private func countConsecutiveBackgrounding() -> Int {
        var count = 0
        for interaction in interactions.reversed() {
            if case .appBackgrounded = interaction {
                count += 1
            } else if case .appForegrounded = interaction {
                break
            }
        }
        return count
    }
}

// MARK: - App Interaction Model

/// Types of app interactions tracked for behavioral signals
enum AppInteraction {
    case questCompleted(duration: TimeInterval)
    case exerciseCompleted(type: String, duration: TimeInterval)
    case circlePostCreated
    case chatMessageSent(length: Int)
    case moodLogged(mood: String)
    case appBackgrounded
    case appForegrounded
    case voiceSessionStarted
    case voiceSessionEnded(duration: TimeInterval)

    var timestamp: Date {
        // In real implementation, each interaction would carry its own timestamp
        // For MVP, we use Date() as they're tracked immediately
        return Date()
    }
}
