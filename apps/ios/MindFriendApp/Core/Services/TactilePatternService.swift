//
//  TactilePatternService.swift
//  MindFriendApp
//
//  Created by Claude Code on 2026-01-20.
//  Core Haptics engine wrapper for tactile pattern playback
//

import Foundation
import CoreHaptics
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

    // MARK: - Initialization

    init() {
        setupHapticEngine()
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
        guard pattern.loadAHAPPattern() != nil else {
            throw SensoryError.ahapFileNotFound(pattern.ahapFilename)
        }

        return pattern
    }

    /// Start playing a tactile pattern
    func playPattern(id: String, speed: SpeedPreset, loop: Bool) async throws {
        guard isHapticsSupported() else {
            throw SensoryError.hapticsNotSupported
        }

        // Load pattern
        let pattern = try await loadPattern(id: id)

        // Stop any currently playing pattern
        await stopPattern()

        // Start engine if needed
        try await startEngine()

        // Load AHAP dictionary
        guard var ahapDict = pattern.loadAHAPPattern() else {
            throw SensoryError.ahapFileNotFound(pattern.ahapFilename)
        }

        // Apply speed multiplier to pattern timing
        ahapDict = applySpeedMultiplier(ahapDict, multiplier: speed.speedMultiplier)

        // Apply intensity multiplier
        ahapDict = applyIntensityMultiplier(ahapDict, intensity: intensity)

        // Create CHHapticPattern
        guard let hapticPattern = try? CHHapticPattern(dictionary: ahapDict) else {
            throw SensoryError.engineFailure
        }

        // Create CHHapticPatternPlayer
        do {
            let player = try hapticEngine?.makePlayer(with: hapticPattern)
            currentPlayer = player
            currentPatternId = id

            // Start playback
            try await Task.detached { [player] in
                try player?.start(atTime: CHHapticTimeImmediate)
            }.value

            isPlaying = true

            // Handle looping
            if loop {
                loopingTask = Task { [weak self] in
                    await self?.handlePatternLoop(duration: TimeInterval(pattern.durationSeconds))
                }
            }

        } catch {
            throw SensoryError.engineFailure
        }
    }

    /// Stop currently playing pattern
    func stopPattern() async {
        guard isPlaying else { return }

        // Cancel looping task
        loopingTask?.cancel()
        loopingTask = nil

        // Stop current player
        do {
            try await Task.detached { [currentPlayer] in
                try currentPlayer?.stop(atTime: CHHapticTimeImmediate)
            }.value
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

        // Send to current player using sendParameters(_:atTime:)
        do {
            try await Task.detached {
                try player.sendParameters([intensityParam], atTime: CHHapticTimeImmediate)
            }.value
        } catch {
            print("Error adjusting intensity: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Methods

    private func setupHapticEngine() {
        guard isHapticsSupported() else { return }

        do {
            hapticEngine = try CHHapticEngine()

            // Configure engine reset handler
            hapticEngine?.resetHandler = { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    print("Haptic engine reset")
                    do {
                        try await self.startEngine()
                        // Restart pattern if was playing
                        if self.isPlaying, let patternId = self.currentPatternId {
                            // Simple restart without looping
                            try await self.playPattern(id: patternId, speed: .medium, loop: false)
                        }
                    } catch {
                        self.error = .engineFailure
                    }
                }
            }

            // Configure engine stopped handler
            hapticEngine?.stoppedHandler = { [weak self] reason in
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    print("Haptic engine stopped: \(reason.rawValue)")
                    self.isEngineRunning = false
                    if reason == .audioSessionInterrupt || reason == .applicationSuspended {
                        // Engine will auto-restart when app returns
                    } else if reason == .systemError {
                        self.error = .engineFailure
                    }
                }
            }

            isEngineRunning = false
        } catch {
            print("Haptic engine creation failed: \(error.localizedDescription)")
            self.error = .engineFailure
        }
    }

    private func startEngine() async throws {
        guard let engine = hapticEngine, !isEngineRunning else { return }

        try await Task.detached {
            try engine.start()
        }.value
        isEngineRunning = true
    }

    private func stopEngine() async {
        guard let engine = hapticEngine, isEngineRunning else { return }

        await Task.detached {
            engine.stop()
        }.value
        isEngineRunning = false
    }

    private func handlePatternLoop(duration: TimeInterval) async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            
            guard !Task.isCancelled, isPlaying, let player = currentPlayer else {
                break
            }

            // Restart pattern
            do {
                try await Task.detached {
                    try player.start(atTime: CHHapticTimeImmediate)
                }.value
            } catch {
                print("Error restarting pattern: \(error.localizedDescription)")
                break
            }
        }
    }
}

// MARK: - AHAP Pattern Utilities

extension TactilePatternService {
    /// Apply speed multiplier to AHAP pattern dictionary
    private func applySpeedMultiplier(_ pattern: [CHHapticPattern.Key: Any], multiplier: Double) -> [CHHapticPattern.Key: Any] {
        var modifiedPattern = pattern
        
        // Multiply all "Time" and "EventDuration" values by (1 / multiplier)
        // Example: 2x speed = 0.5 time multiplier
        let timeScale = 1.0 / multiplier
        
        if var events = modifiedPattern[.pattern] as? [[String: Any]] {
            events = events.map { event in
                var modifiedEvent = event
                
                // Scale event time
                if let time = event["Time"] as? Double {
                    modifiedEvent["Time"] = time * timeScale
                }
                
                // Scale event duration
                if let duration = event["EventDuration"] as? Double {
                    modifiedEvent["EventDuration"] = duration * timeScale
                }
                
                // Scale parameter curve control points
                if var parameters = event["ParameterCurve"] as? [[String: Any]] {
                    parameters = parameters.map { param in
                        var modifiedParam = param
                        if let paramTime = param["Time"] as? Double {
                            modifiedParam["Time"] = paramTime * timeScale
                        }
                        return modifiedParam
                    }
                    modifiedEvent["ParameterCurve"] = parameters
                }
                
                return modifiedEvent
            }
            modifiedPattern[.pattern] = events
        }
        
        return modifiedPattern
    }

    /// Apply intensity multiplier to AHAP pattern dictionary
    private func applyIntensityMultiplier(_ pattern: [CHHapticPattern.Key: Any], intensity: Float) -> [CHHapticPattern.Key: Any] {
        var modifiedPattern = pattern
        
        // Multiply all "HapticIntensity" parameter values by intensity
        if var events = modifiedPattern[.pattern] as? [[String: Any]] {
            events = events.map { event in
                var modifiedEvent = event
                
                // Scale event parameters
                if var parameters = event["EventParameters"] as? [[String: Any]] {
                    parameters = parameters.map { param in
                        var modifiedParam = param
                        if let parameterID = param["ParameterID"] as? String,
                           parameterID == "HapticIntensity",
                           let value = param["ParameterValue"] as? Double {
                            modifiedParam["ParameterValue"] = value * Double(intensity)
                        }
                        return modifiedParam
                    }
                    modifiedEvent["EventParameters"] = parameters
                }
                
                // Scale parameter curve values
                if var curve = event["ParameterCurve"] as? [[String: Any]] {
                    curve = curve.map { point in
                        var modifiedPoint = point
                        if let value = point["ParameterValue"] as? Double {
                            modifiedPoint["ParameterValue"] = value * Double(intensity)
                        }
                        return modifiedPoint
                    }
                    modifiedEvent["ParameterCurve"] = curve
                }
                
                return modifiedEvent
            }
            modifiedPattern[.pattern] = events
        }
        
        return modifiedPattern
    }
}
