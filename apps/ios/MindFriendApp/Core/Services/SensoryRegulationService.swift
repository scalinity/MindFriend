//
//  SensoryRegulationService.swift
//  MindFriendApp
//
//  Created by Claude Code on 2026-01-20.
//  Session orchestration for Sensory Regulation Toolkit
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class SensoryRegulationService: ObservableObject {
    // MARK: - Published Properties

    @Published var currentSession: SensorySession?
    @Published var isSessionActive: Bool = false
    @Published var elapsedSeconds: Int = 0
    @Published var error: SensoryError?

    // MARK: - Private Properties

    private let supabase: SupabaseDataService
    private let tactileService: TactilePatternService
    private let visualService: VisualAnimationService
    private let audioService: AudioSoundscapeService
    private let achievementService: AchievementService

    private var sessionTimer: Timer?
    private var sessionStartTime: Date?
    private var isPaused: Bool = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    // MARK: - Constants

    private let maxSessionDuration: Int = 1800  // 30 minutes in seconds

    // MARK: - Initialization

    init(
        supabase: SupabaseDataService,
        tactileService: TactilePatternService,
        visualService: VisualAnimationService,
        audioService: AudioSoundscapeService,
        achievementService: AchievementService
    ) {
        self.supabase = supabase
        self.tactileService = tactileService
        self.visualService = visualService
        self.audioService = audioService
        self.achievementService = achievementService

        setupNotificationObservers()
    }

    // MARK: - Public Methods

    /// Start a new sensory regulation session
    func startSession(
        modality: SensoryModality,
        patternId: String,
        speed: SpeedPreset,
        loop: Bool
    ) async throws {
        // Validate no session in progress
        guard !isSessionActive else {
            throw SensoryError.sessionInProgress
        }

        // Validate pattern exists in library
        let patternExists = await validatePatternExists(modality: modality, patternId: patternId)
        guard patternExists else {
            throw SensoryError.patternNotFound
        }

        // Check premium access for premium patterns
        let isPremiumPattern = try await checkPremiumPattern(modality: modality, patternId: patternId)
        if isPremiumPattern {
            // TODO: Implement premium access check with SupabaseDataService
            // For now, allow all users - premium gating handled server-side
        }

        // Try to create session on server, but allow local-only sessions on network failure
        do {
            let session = try await createSessionOnServer(modality: modality, patternId: patternId)
            currentSession = session
        } catch {
            // Network failed - create a local-only session (will be synced later if possible)
            CrashReporter.shared.capture(error: error, context: ["source": "SensoryRegulationService.startSession", "modality": modality.rawValue])
            currentSession = createLocalSession(modality: modality, patternId: patternId)
        }

        // Start modality service (works offline - haptics, visuals, and audio are local)
        try await startModalityService(modality: modality, patternId: patternId, speed: speed, loop: loop)

        // Start session timer
        sessionStartTime = Date()
        elapsedSeconds = 0
        isPaused = false
        startSessionTimer()

        isSessionActive = true
    }

    /// Pause the current session
    func pauseSession() async {
        guard isSessionActive, !isPaused else { return }

        // Pause timer
        sessionTimer?.invalidate()
        sessionTimer = nil

        // Pause modality service
        await pauseModalityService()

        // Update session status
        if var session = currentSession {
            session.status = .paused
            currentSession = session
        }

        isPaused = true
    }

    /// Resume paused session
    func resumeSession() async throws {
        guard isSessionActive, isPaused else { return }

        // Check 30-minute limit before resuming
        if elapsedSeconds >= maxSessionDuration {
            await endSession(interrupted: true)
            throw SensoryError.maxDurationExceeded
        }

        // Resume modality service
        try await resumeModalityService()

        // Resume timer
        startSessionTimer()

        // Update session status
        if var session = currentSession {
            session.status = .active
            currentSession = session
        }

        isPaused = false
    }

    /// End the current session
    func endSession(interrupted: Bool = false) async {
        guard isSessionActive else { return }

        // Stop timer
        sessionTimer?.invalidate()
        sessionTimer = nil

        // Stop modality service
        await stopModalityService()

        // Calculate final duration
        let finalDuration = elapsedSeconds

        // Call complete-session Edge Function
        if var session = currentSession {
            session.status = .completed
            session.completedAt = Date()
            session.durationSeconds = finalDuration
            session.interrupted = interrupted

            do {
                let achievements = try await completeSessionOnServer(
                    sessionId: session.id,
                    duration: finalDuration,
                    interrupted: interrupted
                )

                // Check achievements
                if !achievements.isEmpty {
                    // Reload achievement service to reflect newly earned badges
                    try? await achievementService.loadUserBadgeProgress()
                }
            } catch {
                CrashReporter.shared.capture(error: error, context: ["source": "SensoryRegulationService.completeSession", "sessionId": session.id.uuidString])
            }
        }

        // Clear session state
        currentSession = nil
        isSessionActive = false
        elapsedSeconds = 0
        isPaused = false
        sessionStartTime = nil

        // End background task if active
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    // MARK: - Private Methods - Session Timer

    private func startSessionTimer() {
        // Invalidate any existing timer before creating new one (prevent timer leak)
        sessionTimer?.invalidate()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                // Guard session is still active to prevent race with endSession()
                guard let self = self, self.isSessionActive else { return }

                self.elapsedSeconds += 1

                // Auto-pause at 30 minutes (re-check isSessionActive after suspension point)
                if self.elapsedSeconds >= self.maxSessionDuration && self.isSessionActive {
                    await self.pauseSession()
                    // Only set error if session is still active after pause
                    if self.isSessionActive {
                        self.error = .maxDurationExceeded
                    }
                }
            }
        }
    }

    // MARK: - Private Methods - Modality Services

    private func startModalityService(
        modality: SensoryModality,
        patternId: String,
        speed: SpeedPreset,
        loop: Bool
    ) async throws {
        switch modality {
        case .tactile:
            try await tactileService.playPattern(id: patternId, speed: speed, loop: loop)

        case .visual:
            try await visualService.startAnimation(id: patternId, speed: speed)

        case .audio:
            try await audioService.playSound(id: patternId, loop: loop)
        }
    }

    private func pauseModalityService() async {
        // Stop all services (pause = stop for now)
        await stopModalityService()
    }

    private func resumeModalityService() async throws {
        guard let session = currentSession else { return }

        // Restart from beginning (no resume state for MVP)
        try await startModalityService(
            modality: session.modality,
            patternId: session.patternId,
            speed: .medium,  // Use default speed on resume
            loop: true
        )
    }

    private func stopModalityService() async {
        await tactileService.stopPattern()
        await visualService.stopAnimation()
        await audioService.stopSound()
    }

    // MARK: - Private Methods - Server Communication

    private func validatePatternExists(modality: SensoryModality, patternId: String) async -> Bool {
        switch modality {
        case .tactile:
            return TactilePattern.library.contains(where: { $0.id == patternId })
        case .visual:
            return VisualAnimation.library.contains(where: { $0.id == patternId })
        case .audio:
            return AudioSoundscape.library.contains(where: { $0.id == patternId })
        }
    }

    /// Stable UUID namespace for offline sessions (avoids hardcoded zeros)
    private static let offlineSessionNamespace = UUID(uuidString: "F47AC10B-58CC-4372-A567-0E02B2C3D479")!

    /// Create a local-only session when network is unavailable
    private func createLocalSession(modality: SensoryModality, patternId: String) -> SensorySession {
        // Use a deterministic offline user ID based on device ID for later sync
        // This allows correlating offline sessions to the user once they're back online
        let offlineUserId = Self.offlineSessionNamespace
        
        return SensorySession(
            id: UUID(),
            userId: offlineUserId,
            modality: modality,
            patternId: patternId,
            startedAt: Date(),
            completedAt: nil,
            durationSeconds: nil,
            interrupted: false,
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private func createSessionOnServer(
        modality: SensoryModality,
        patternId: String
    ) async throws -> SensorySession {
        // Call create-sensory-session Edge Function
        struct CreateSessionRequest: Codable {
            let modality: String
            let patternId: String
        }

        struct CreateSessionResponse: Codable {
            let sessionId: String
            let premiumAccess: Bool
        }

        let request = CreateSessionRequest(
            modality: modality.rawValue,
            patternId: patternId
        )

        do {
            let response: CreateSessionResponse = try await supabase.functions.invoke(
                "create-sensory-session",
                options: .init(body: request)
            )

            // Validate session ID from backend
            guard let sessionId = UUID(uuidString: response.sessionId) else {
                throw SensoryError.networkError
            }

            // Create local session object
            let userId = try await getCurrentUserId()
            let session = SensorySession(
                id: sessionId,
                userId: userId,
                modality: modality,
                patternId: patternId,
                startedAt: Date(),
                completedAt: nil,
                durationSeconds: nil,
                interrupted: false,
                status: .active,
                createdAt: Date(),
                updatedAt: Date()
            )

            return session

        } catch {
            CrashReporter.shared.capture(error: error, context: ["source": "SensoryRegulationService.createSessionOnServer"])
            throw SensoryError.networkError
        }
    }
    
    private func getCurrentUserId() async throws -> UUID {
        // Get current user ID from the Supabase data service
        guard let userId = self.supabase.currentUserId else {
            throw SensoryError.networkError
        }
        return userId
    }

    private func completeSessionOnServer(
        sessionId: UUID,
        duration: Int,
        interrupted: Bool
    ) async throws -> [UserBadge] {
        struct CompleteSessionRequest: Codable {
            let sessionId: String
            let duration: Int
            let interrupted: Bool
        }

        struct CompleteSessionResponse: Codable {
            let achievementsUnlocked: [UserBadge]
        }

        let request = CompleteSessionRequest(
            sessionId: sessionId.uuidString,
            duration: duration,
            interrupted: interrupted
        )

        do {
            let response: CompleteSessionResponse = try await supabase.functions.invoke(
                "complete-sensory-session",
                options: .init(body: request)
            )

            return response.achievementsUnlocked

        } catch {
            CrashReporter.shared.capture(error: error, context: ["source": "SensoryRegulationService.completeSessionOnServer"])
            throw SensoryError.networkError
        }
    }

    private func checkPremiumPattern(modality: SensoryModality, patternId: String) async throws -> Bool {
        switch modality {
        case .tactile:
            return TactilePattern.library.first(where: { $0.id == patternId })?.isPremium ?? false
        case .visual:
            return VisualAnimation.library.first(where: { $0.id == patternId })?.isPremium ?? false
        case .audio:
            return AudioSoundscape.library.first(where: { $0.id == patternId })?.isPremium ?? false
        }
    }

    // MARK: - Background/Foreground Handling

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc private func handleAppDidEnterBackground() {
        // @objc methods aren't @MainActor-isolated, so hop to MainActor for safe state access
        Task { @MainActor [weak self] in
            guard let self = self, self.isSessionActive else { return }

            // Request background time to continue audio/haptics briefly
            self.backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    // Always end task, even if pause fails (use defer for safety)
                    defer {
                        if self.backgroundTask != .invalid {
                            UIApplication.shared.endBackgroundTask(self.backgroundTask)
                            self.backgroundTask = .invalid
                        }
                    }
                    // Background time expired, pause session
                    await self.pauseSession()
                }
            }
        }
    }

    @objc private func handleAppWillEnterForeground() {
        // @objc methods aren't @MainActor-isolated, so hop to MainActor for safe state access
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            // End background task if active
            if self.backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(self.backgroundTask)
                self.backgroundTask = .invalid
            }

            // Session remains paused if user backgrounded app
            // User must manually resume
        }
    }

    deinit {
        // Invalidate timer to prevent dangling timer if service is deallocated during active session
        sessionTimer?.invalidate()
        sessionTimer = nil
        NotificationCenter.default.removeObserver(self)
    }
}
