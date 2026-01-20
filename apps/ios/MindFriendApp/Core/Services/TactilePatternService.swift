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
import SensoryModels

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

        // TODO: Implement pattern playback
        // 1. Load AHAP dictionary
        // 2. Apply speed multiplier to pattern timing
        // 3. Apply intensity multiplier
        // 4. Create CHHapticPattern
        // 5. Create CHHapticPatternPlayer
        // 6. Start playback
        // 7. If loop=true, repeat on completion

        isPlaying = true
        print("TODO: TactilePatternService.playPattern - implement Core Haptics playback")
    }

    /// Stop currently playing pattern
    func stopPattern() async {
        guard isPlaying else { return }

        // TODO: Implement pattern stop
        // 1. Stop current player
        // 2. Clear currentPlayer reference
        // 3. Update isPlaying state

        isPlaying = false
        print("TODO: TactilePatternService.stopPattern - implement")
    }

    /// Adjust intensity of currently playing pattern
    func setIntensity(_ value: Float) async {
        intensity = max(0.0, min(1.0, value))

        // TODO: Implement dynamic intensity adjustment
        // 1. Create intensity parameter
        // 2. Send to current player using sendParameters(_:atTime:)
        print("TODO: TactilePatternService.setIntensity - implement dynamic intensity")
    }

    // MARK: - Private Methods

    private func setupHapticEngine() {
        guard isHapticsSupported() else { return }

        do {
            hapticEngine = try CHHapticEngine()

            // TODO: Configure engine reset handler
            // TODO: Configure engine stopped handler

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
}

// MARK: - AHAP Pattern Utilities

extension TactilePatternService {
    /// Apply speed multiplier to AHAP pattern dictionary
    private func applySpeedMultiplier(_ pattern: [CHHapticPattern.Key: Any], multiplier: Double) -> [CHHapticPattern.Key: Any] {
        // TODO: Implement pattern timing transformation
        // Multiply all "Time" and "EventDuration" values by (1 / multiplier)
        // Example: 2x speed = 0.5 time multiplier
        return pattern
    }

    /// Apply intensity multiplier to AHAP pattern dictionary
    private func applyIntensityMultiplier(_ pattern: [CHHapticPattern.Key: Any], intensity: Float) -> [CHHapticPattern.Key: Any] {
        // TODO: Implement intensity transformation
        // Multiply all "HapticIntensity" parameter values by intensity
        return pattern
    }
}
