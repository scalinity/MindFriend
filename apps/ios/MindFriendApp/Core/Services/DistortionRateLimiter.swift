//
//  DistortionRateLimiter.swift
//  MindFriendApp
//
//  Created by dev-pipeline
//  Rate limiting for cognitive distortion prompts
//

import Foundation

/// Rate limiter for distortion prompts
/// Enforces: < 3 prompts per 5-minute session, 60s cooldown after dismiss
@MainActor
final class DistortionRateLimiter: ObservableObject {

    // MARK: - Configuration

    /// Maximum prompts allowed per session
    private let maxPromptsPerSession = 3

    /// Session window duration (5 minutes)
    private let sessionWindow: TimeInterval = 5 * 60 // 300 seconds

    /// Cooldown period after dismissing a prompt (60 seconds)
    private let dismissCooldown: TimeInterval = 60

    // MARK: - State

    /// Session identifier (changes when session resets)
    @Published private(set) var currentSessionId: String = UUID().uuidString

    /// Timestamp when current session started
    private var sessionStartTime: Date = Date()

    /// Prompts shown in current session
    private var promptsShown: [PromptRecord] = []

    /// Timestamp of last dismissed prompt
    private var lastDismissedAt: Date?

    // MARK: - Models

    private struct PromptRecord {
        let distortionType: DistortionType
        let shownAt: Date
        var dismissedAt: Date?
    }

    // MARK: - Public Interface

    /// Checks if a prompt can be shown based on rate limits
    /// - Returns: True if prompt can be shown, false otherwise
    func canShowPrompt() -> Bool {
        cleanupExpiredSession()

        // Check session limit (max 3 prompts per 5-minute session)
        if promptsShown.count >= maxPromptsPerSession {
            return false
        }

        // Check dismiss cooldown (60 seconds after last dismiss)
        if let lastDismiss = lastDismissedAt {
            let timeSinceDismiss = Date().timeIntervalSince(lastDismiss)
            if timeSinceDismiss < dismissCooldown {
                return false
            }
        }

        return true
    }

    /// Records that a prompt was shown
    /// - Parameter distortionType: Type of distortion detected
    func recordPromptShown(for distortionType: DistortionType) {
        let record = PromptRecord(
            distortionType: distortionType,
            shownAt: Date(),
            dismissedAt: nil
        )
        promptsShown.append(record)
    }

    /// Records that a prompt was dismissed
    func recordPromptDismissed() {
        lastDismissedAt = Date()

        // Mark last prompt as dismissed
        if !promptsShown.isEmpty {
            promptsShown[promptsShown.count - 1].dismissedAt = Date()
        }
    }

    /// Gets remaining prompts for current session
    /// - Returns: Number of prompts remaining (0-3)
    func remainingPrompts() -> Int {
        cleanupExpiredSession()
        return max(0, maxPromptsPerSession - promptsShown.count)
    }

    /// Gets time remaining in dismiss cooldown
    /// - Returns: Seconds remaining in cooldown, or 0 if no cooldown active
    func remainingCooldown() -> TimeInterval {
        guard let lastDismiss = lastDismissedAt else {
            return 0
        }

        let elapsed = Date().timeIntervalSince(lastDismiss)
        let remaining = dismissCooldown - elapsed

        return max(0, remaining)
    }

    /// Manually resets the session (called when voice journal session ends)
    func resetSession() {
        currentSessionId = UUID().uuidString
        sessionStartTime = Date()
        promptsShown.removeAll()
        lastDismissedAt = nil
    }

    /// Gets statistics for current session
    /// - Returns: Tuple with prompts shown count and session age
    func getSessionStats() -> (promptsShown: Int, sessionAge: TimeInterval) {
        cleanupExpiredSession()
        let age = Date().timeIntervalSince(sessionStartTime)
        return (promptsShown: promptsShown.count, sessionAge: age)
    }

    // MARK: - Private Helpers

    /// Cleans up expired session and resets if needed
    private func cleanupExpiredSession() {
        let sessionAge = Date().timeIntervalSince(sessionStartTime)

        // If session window expired, reset
        if sessionAge >= sessionWindow {
            resetSession()
        }
    }
}
