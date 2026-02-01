//
//  TactilePatternService.swift
//  MindFriendApp
//
//  Created by Claude Code on 2026-01-20.
//  Core Haptics engine wrapper for tactile pattern playback
//

import Foundation
import CoreHaptics
import AVFoundation
import UIKit
import Combine

@MainActor
final class TactilePatternService: ObservableObject {
    // MARK: - Published Properties

    @Published var isPlaying: Bool = false
    @Published var intensity: Float = 1.0  // 0.0 - 1.0
    @Published var error: SensoryError?

    // MARK: - Private Properties

    private var hapticEngine: CHHapticEngine?
    private var currentPlayer: CHHapticPatternPlayer?
    private var isEngineRunning: Bool = false
    private var loopingTask: Task<Void, Never>?
    private var currentPatternId: String?
    private var currentSpeed: SpeedPreset = .medium
    private var needsEngineRestart: Bool = false

    // MARK: - Initialization

    init() {
        setupNotifications()
        createHapticEngine()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public Methods

    /// Check if haptics are supported on this device
    func isHapticsSupported() -> Bool {
        return CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    /// Load AHAP pattern from bundle
    func loadPattern(id: String) async throws -> TactilePattern {
        guard let pattern = TactilePattern.library.first(where: { $0.id == id }) else {
            throw SensoryError.patternNotFound
        }

        // Validate AHAP file exists
        guard pattern.ahapURL() != nil else {
            throw SensoryError.ahapFileNotFound(pattern.ahapFilename)
        }

        return pattern
    }

    /// Start playing a tactile pattern
    func playPattern(id: String, speed: SpeedPreset, loop: Bool) async throws {
        print("[Haptics] playPattern called: id=\(id), speed=\(speed), loop=\(loop)")
        
        guard isHapticsSupported() else {
            print("[Haptics] Device does not support haptics")
            throw SensoryError.hapticsNotSupported
        }

        // Load pattern metadata
        let pattern = try await loadPattern(id: id)
        print("[Haptics] Pattern loaded: \(pattern.name), loopDuration=\(pattern.loopDurationSeconds)s")

        // Stop any currently playing pattern
        await stopPattern()

        // Ensure engine exists
        if hapticEngine == nil {
            print("[Haptics] Engine is nil, creating new engine")
            createHapticEngine()
        }
        
        // Start engine if needed
        try await startEngine()

        // Get AHAP file URL
        guard let ahapURL = pattern.ahapURL() else {
            print("[Haptics] AHAP file not found: \(pattern.ahapFilename)")
            throw SensoryError.ahapFileNotFound(pattern.ahapFilename)
        }
        print("[Haptics] AHAP URL: \(ahapURL.lastPathComponent)")

        // Create CHHapticPattern directly from AHAP file (Apple's recommended approach)
        let hapticPattern: CHHapticPattern
        do {
            hapticPattern = try CHHapticPattern(contentsOf: ahapURL)
            print("[Haptics] CHHapticPattern created successfully")
        } catch {
            print("[Haptics] Failed to load AHAP pattern: \(error.localizedDescription)")
            throw SensoryError.engineFailure
        }

        // Create CHHapticPatternPlayer
        do {
            guard let engine = hapticEngine else {
                print("[Haptics] Engine is nil after start")
                throw SensoryError.engineFailure
            }
            
            let player = try engine.makePlayer(with: hapticPattern)
            currentPlayer = player
            currentPatternId = id
            currentSpeed = speed
            print("[Haptics] Player created successfully")

            // Apply initial intensity via dynamic parameter
            if intensity < 1.0 {
                let intensityParam = CHHapticDynamicParameter(
                    parameterID: .hapticIntensityControl,
                    value: intensity,
                    relativeTime: 0
                )
                try player.sendParameters([intensityParam], atTime: CHHapticTimeImmediate)
                print("[Haptics] Intensity set to \(intensity)")
            }

            // Start playback
            try player.start(atTime: CHHapticTimeImmediate)
            print("[Haptics] Pattern playback started!")

            isPlaying = true
            needsEngineRestart = false

            // Handle looping - use the actual AHAP pattern duration, adjusted for speed
            if loop {
                let adjustedDuration = TimeInterval(pattern.loopDurationSeconds) / speed.speedMultiplier
                print("[Haptics] Starting loop with duration \(adjustedDuration)s")
                loopingTask = Task { [weak self] in
                    await self?.handlePatternLoop(duration: adjustedDuration)
                }
            }

        } catch {
            print("[Haptics] Failed to create/start haptic player: \(error.localizedDescription)")
            throw SensoryError.engineFailure
        }
    }

    /// Stop currently playing pattern
    func stopPattern() async {
        guard isPlaying else { return }

        // Cancel looping task
        loopingTask?.cancel()
        loopingTask = nil

        // Stop current player on main thread for thread safety
        do {
            try currentPlayer?.stop(atTime: CHHapticTimeImmediate)
        } catch {
            print("Error stopping pattern: \(error.localizedDescription)")
        }

        // Clear currentPlayer reference
        currentPlayer = nil
        currentPatternId = nil

        // Update isPlaying state
        isPlaying = false
    }

    /// Adjust intensity of currently playing pattern
    func setIntensity(_ value: Float) async {
        intensity = max(0.0, min(1.0, value))

        guard isPlaying, let player = currentPlayer else { return }

        // Create intensity parameter
        let intensityParam = CHHapticDynamicParameter(
            parameterID: .hapticIntensityControl,
            value: intensity,
            relativeTime: 0
        )

        // Send to current player on main thread for thread safety
        do {
            try player.sendParameters([intensityParam], atTime: CHHapticTimeImmediate)
        } catch {
            print("Error adjusting intensity: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Methods - Engine Setup

    private func setupNotifications() {
        // Listen for audio session interruptions
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        
        // Listen for app becoming active (to restart engine if needed)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        Task { @MainActor in
            switch type {
            case .began:
                print("[Haptics] Audio session interruption began")
                needsEngineRestart = isPlaying
                
            case .ended:
                print("[Haptics] Audio session interruption ended")
                if needsEngineRestart, let patternId = currentPatternId {
                    print("[Haptics] Restarting pattern after interruption")
                    // Small delay to let audio session settle
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                    do {
                        try await restartEngineAndPattern(patternId: patternId)
                    } catch {
                        print("[Haptics] Failed to restart after interruption: \(error)")
                    }
                }
                needsEngineRestart = false
                
            @unknown default:
                break
            }
        }
    }
    
    @objc private func handleAppDidBecomeActive() {
        Task { @MainActor in
            if needsEngineRestart, let patternId = currentPatternId {
                print("[Haptics] Restarting pattern after app became active")
                do {
                    try await restartEngineAndPattern(patternId: patternId)
                } catch {
                    print("[Haptics] Failed to restart after becoming active: \(error)")
                }
                needsEngineRestart = false
            }
        }
    }

    private func createHapticEngine() {
        guard isHapticsSupported() else {
            print("[Haptics] Device does not support haptics")
            return
        }

        do {
            hapticEngine = try CHHapticEngine()
            
            // CRITICAL: Disable auto-shutdown to keep engine alive during session
            hapticEngine?.isAutoShutdownEnabled = false
            
            // Use haptics-only mode (no audio component needed)
            hapticEngine?.playsHapticsOnly = true

            // Configure engine reset handler - engine needs restart after reset
            hapticEngine?.resetHandler = { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    print("[Haptics] Engine reset triggered")
                    self.isEngineRunning = false
                    
                    // Restart engine and pattern if we were playing
                    if let patternId = self.currentPatternId {
                        do {
                            try await self.restartEngineAndPattern(patternId: patternId)
                        } catch {
                            print("[Haptics] Failed to restart after reset: \(error)")
                            self.error = .engineFailure
                        }
                    }
                }
            }

            // Configure engine stopped handler
            hapticEngine?.stoppedHandler = { [weak self] reason in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    print("[Haptics] Engine stopped with reason: \(reason.rawValue)")
                    self.isEngineRunning = false
                    
                    switch reason {
                    case .audioSessionInterrupt:
                        // Mark for restart when interrupt ends
                        self.needsEngineRestart = self.isPlaying
                        print("[Haptics] Will restart after audio session interrupt")
                        
                    case .applicationSuspended:
                        // Mark for restart when app becomes active
                        self.needsEngineRestart = self.isPlaying
                        print("[Haptics] Will restart after app resumes")
                        
                    case .idleTimeout:
                        // Engine timed out, restart if we need it
                        if self.isPlaying {
                            print("[Haptics] Engine idle timeout, restarting...")
                            if let patternId = self.currentPatternId {
                                do {
                                    try await self.restartEngineAndPattern(patternId: patternId)
                                } catch {
                                    print("[Haptics] Failed to restart after idle: \(error)")
                                }
                            }
                        }
                        
                    case .notifyWhenFinished:
                        // Pattern completed naturally
                        print("[Haptics] Pattern finished")
                        
                    case .systemError:
                        print("[Haptics] System error, recreating engine")
                        self.error = .engineFailure
                        // Try to recreate the engine
                        self.hapticEngine = nil
                        self.createHapticEngine()
                        
                    case .engineDestroyed:
                        print("[Haptics] Engine destroyed, recreating")
                        self.hapticEngine = nil
                        self.createHapticEngine()
                        
                    case .gameControllerDisconnect:
                        // Not applicable
                        break
                        
                    @unknown default:
                        print("[Haptics] Unknown stop reason: \(reason.rawValue)")
                    }
                }
            }

            isEngineRunning = false
            print("[Haptics] Engine created successfully")
            
        } catch {
            print("[Haptics] Engine creation failed: \(error.localizedDescription)")
            self.error = .engineFailure
        }
    }
    
    private func restartEngineAndPattern(patternId: String) async throws {
        // Recreate engine if needed
        if hapticEngine == nil {
            createHapticEngine()
        }
        
        // Start the engine
        try await startEngine()
        
        // Reload and play the pattern
        guard let pattern = TactilePattern.library.first(where: { $0.id == patternId }),
              let ahapURL = pattern.ahapURL() else {
            return
        }
        
        let hapticPattern = try CHHapticPattern(contentsOf: ahapURL)
        let player = try hapticEngine?.makePlayer(with: hapticPattern)
        currentPlayer = player
        
        try player?.start(atTime: CHHapticTimeImmediate)
        print("[Haptics] Pattern restarted successfully")
    }

    private func startEngine() async throws {
        guard let engine = hapticEngine else {
            throw SensoryError.engineFailure
        }

        guard !isEngineRunning else {
            print("[Haptics] Engine already running")
            return
        }

        do {
            // IMPORTANT: Start the engine and await completion
            // This ensures the engine is ready before we try to play patterns
            try await engine.start()
            isEngineRunning = true
            print("[Haptics] Engine started successfully")
        } catch {
            print("[Haptics] Failed to start engine: \(error.localizedDescription)")
            throw SensoryError.engineFailure
        }
    }

    private func stopEngine() async {
        guard let engine = hapticEngine, isEngineRunning else { return }

        // Stop the engine and await completion
        try? await engine.stop()
        isEngineRunning = false
        print("[Haptics] Engine stopped")
    }

    private func handlePatternLoop(duration: TimeInterval) async {
        print("[Haptics] Loop started, duration: \(duration)s")
        
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            
            guard !Task.isCancelled, isPlaying else {
                print("[Haptics] Loop cancelled or stopped")
                break
            }
            
            // Check if engine needs restart
            if !isEngineRunning {
                print("[Haptics] Engine not running in loop, attempting restart")
                do {
                    try await startEngine()
                } catch {
                    print("[Haptics] Failed to restart engine in loop: \(error)")
                    break
                }
            }
            
            guard let player = currentPlayer else {
                print("[Haptics] No player in loop")
                break
            }

            // Restart pattern on main thread for thread safety
            do {
                try player.start(atTime: CHHapticTimeImmediate)
                print("[Haptics] Loop iteration completed")
            } catch {
                print("[Haptics] Error restarting pattern in loop: \(error.localizedDescription)")
                // Try to recreate player
                if let patternId = currentPatternId {
                    do {
                        try await restartEngineAndPattern(patternId: patternId)
                    } catch {
                        print("[Haptics] Failed to recover in loop: \(error)")
                        break
                    }
                } else {
                    break
                }
            }
        }
    }
}

