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

        // Check rate limits atomically - reserve a slot before processing
        guard rateLimiter.canShowPrompt() else {
            print("DistortionEngine: Rate limit exceeded")
            return false
        }

        // Validate input size (max 5000 characters)
        guard text.count <= 5000 else {
            print("DistortionEngine: Input text too long (\(text.count) chars, max 5000)")
            return false
        }

        isDetecting = true
        defer { isDetecting = false } // Ensures cleanup on all exit paths
        lastError = nil

        do {
            // Reserve rate limit slot atomically to prevent TOCTOU race condition
            rateLimiter.reservePromptSlot()
            
            // Call Edge Function for detection
            let result = try await detectViaEdgeFunction(text: text, sessionId: sessionId)

            if let distortion = result.distortion, result.detected {
                // Create and show prompt
                await showPrompt(for: distortion, sessionId: sessionId, transcriptText: text)
                return true
            } else {
                // No distortion detected, release the reserved slot
                rateLimiter.releaseLastReservation()
            }

            return false
        } catch {
            // On error, release the reserved slot
            rateLimiter.releaseLastReservation()
            lastError = error
            print("DistortionEngine: Detection failed - \(error.localizedDescription)")
            return false
        }
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

    /// Detects distortion via Edge Function with timeout
    private func detectViaEdgeFunction(text: String, sessionId: String) async throws -> DetectDistortionResponse {
        struct DetectRequest: Encodable {
            let text: String
            let sessionId: String
        }

        let request = DetectRequest(text: text, sessionId: sessionId)

        // Implement timeout (15 seconds) to prevent indefinite blocking
        return try await withThrowingTaskGroup(of: DetectDistortionResponse.self) { group in
            group.addTask {
                let response: DetectDistortionResponse = try await self.supabase.functions
                    .invoke("detect-distortion", options: FunctionInvokeOptions(body: request))
                
                return response
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: 15_000_000_000) // 15 seconds
                throw DistortionError.timeout
            }
            
            guard let result = try await group.next() else {
                throw DistortionError.unknown
            }
            
            group.cancelAll()
            return result
        }
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

        // Update the reserved slot with the actual distortion type
        rateLimiter.updateLastReservation(distortionType: distortion.type)

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
            print("DistortionEngine: Prompt shown for distortion type: \(distortion.type)")
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

// MARK: - Error Types

enum DistortionError: Error, LocalizedError {
    case timeout
    case unknown
    case invalidInput
    
    var errorDescription: String? {
        switch self {
        case .timeout:
            return "Detection timed out after 15 seconds"
        case .unknown:
            return "An unknown error occurred during detection"
        case .invalidInput:
            return "Invalid input provided for detection"
        }
    }
}
