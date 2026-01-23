//
//  CognitiveDistortionEngine.swift
//  MindFriendApp
//
//  Created by dev-pipeline
//  Main orchestrator for cognitive distortion detection
//

import Foundation
import Supabase

/// Main engine for detecting and managing cognitive distortions
/// Orchestrates pattern matching, API calls, and rate limiting
@MainActor
final class CognitiveDistortionEngine: ObservableObject {

    // MARK: - Dependencies

    private let supabase: SupabaseClient
    private let patternMatcher: DistortionPatternMatcher
    private let rateLimiter: DistortionRateLimiter

    // MARK: - State

    /// Currently pending prompt (if any)
    @Published private(set) var pendingPrompt: DistortionPrompt?

    /// Detection in progress
    @Published private(set) var isDetecting = false

    /// Last detection error
    @Published private(set) var lastError: Error?

    // MARK: - Configuration

    /// Minimum confidence threshold for showing prompts
    private let confidenceThreshold: Double = 0.70

    /// Session ID for current voice journal session
    private var currentSessionId: String?

    // MARK: - Initialization

    init(
        supabase: SupabaseClient,
        patternMatcher: DistortionPatternMatcher = DistortionPatternMatcher(),
        rateLimiter: DistortionRateLimiter = DistortionRateLimiter()
    ) {
        self.supabase = supabase
        self.patternMatcher = patternMatcher
        self.rateLimiter = rateLimiter
    }

    // MARK: - Public Interface

    /// Starts a new detection session
    /// - Parameter sessionId: Voice journal session ID
    func startSession(sessionId: String) {
        self.currentSessionId = sessionId
        rateLimiter.resetSession()
        pendingPrompt = nil
        lastError = nil
    }

    /// Ends the current detection session
    func endSession() {
        currentSessionId = nil
        pendingPrompt = nil
        rateLimiter.resetSession()
    }

    /// Analyzes transcript text for cognitive distortions
    /// - Parameter text: Transcript text from voice journal
    /// - Returns: True if distortion detected and prompt shown
    @discardableResult
    func analyzeText(_ text: String) async -> Bool {
        guard let sessionId = currentSessionId else {
            print("DistortionEngine: No active session")
            return false
        }

        // Check rate limits
        guard rateLimiter.canShowPrompt() else {
            print("DistortionEngine: Rate limit exceeded")
            return false
        }

        isDetecting = true
        lastError = nil

        do {
            // Call Edge Function for detection
            let result = try await detectViaEdgeFunction(text: text, sessionId: sessionId)

            if let distortion = result.distortion, result.detected {
                // Create and show prompt
                await showPrompt(for: distortion, sessionId: sessionId, transcriptText: text)
                return true
            }

            return false
        } catch {
            lastError = error
            print("DistortionEngine: Detection failed - \(error.localizedDescription)")
            return false
        }

        isDetecting = false
    }

    /// Dismisses the current prompt
    func dismissPrompt() {
        pendingPrompt = nil
        rateLimiter.recordPromptDismissed()
    }

    /// Acknowledges the current prompt (user engaged with reframing)
    func acknowledgePrompt() async {
        guard let prompt = pendingPrompt else { return }

        do {
            // Update distortion event as acknowledged
            try await supabase
                .from("distortion_events")
                .update(["user_acknowledged": true])
                .eq("id", value: prompt.distortionEvent.id.uuidString)
                .execute()

            // Update prompt record
            try await supabase
                .from("distortion_prompts")
                .update(["acknowledged": true])
                .eq("id", value: prompt.id.uuidString)
                .execute()

            pendingPrompt = nil
            rateLimiter.recordPromptDismissed()
        } catch {
            lastError = error
            print("DistortionEngine: Failed to acknowledge prompt - \(error.localizedDescription)")
        }
    }

    // MARK: - Private Helpers

    /// Detects distortion via Edge Function
    private func detectViaEdgeFunction(text: String, sessionId: String) async throws -> DetectDistortionResponse {
        struct DetectRequest: Encodable {
            let text: String
            let sessionId: String
        }

        let request = DetectRequest(text: text, sessionId: sessionId)

        let response: DetectDistortionResponse = try await supabase.functions
            .invoke("detect-distortion", options: FunctionInvokeOptions(body: request))

        return response
    }

    /// Shows a prompt for detected distortion
    private func showPrompt(
        for distortion: DetectedDistortion,
        sessionId: String,
        transcriptText: String
    ) async {
        guard let userId = try? await supabase.auth.session.user.id else {
            print("DistortionEngine: No authenticated user")
            return
        }

        // Create distortion event (already stored by Edge Function)
        let event = DistortionEvent(
            userId: userId,
            sessionId: sessionId,
            distortionType: distortion.type,
            transcriptText: transcriptText,
            confidence: distortion.confidence,
            detectionMethod: .llm, // Assuming Edge Function result
            userAcknowledged: false,
            createdAt: Date()
        )

        // Create prompt record
        let prompt = DistortionPrompt(
            distortionEvent: event,
            shownAt: Date(),
            dismissed: false,
            acknowledged: false
        )

        // Record in rate limiter
        rateLimiter.recordPromptShown(for: distortion.type)

        // Store prompt in database
        do {
            let promptRecord = DistortionPromptRecord(
                userId: userId,
                sessionId: sessionId,
                distortionEventId: event.id,
                shownAt: Date(),
                dismissed: false,
                acknowledged: false
            )

            try await supabase
                .from("distortion_prompts")
                .insert(promptRecord)
                .execute()

            // Show prompt to user
            pendingPrompt = prompt
        } catch {
            lastError = error
            print("DistortionEngine: Failed to store prompt - \(error.localizedDescription)")
        }
    }
}

// MARK: - API Response Models

private struct DetectDistortionResponse: Decodable {
    let detected: Bool
    let distortion: DetectedDistortion?
    let detectionMethod: String
}

private struct DetectedDistortion: Decodable {
    let type: DistortionType
    let confidence: Double
    let reasoning: String?
}
