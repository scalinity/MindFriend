//
//  SessionViewModel.swift
//  MindFriendApp
//
//  Created by Claude Code on 2026-01-20.
//  UI state management for active sensory regulation sessions
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class SessionViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var isPlaying: Bool = false
    @Published var elapsedTime: String = "00:00"
    @Published var progressPercentage: Double = 0.0
    @Published var currentSpeed: SpeedPreset = .medium
    @Published var simulatedHeartRate: Int = 80
    @Published var showPremiumPaywall: Bool = false
    @Published var errorMessage: String?

    // MARK: - Private Properties

    private let sensoryService: SensoryRegulationService
    private let tactileService: TactilePatternService
    private let visualService: VisualAnimationService
    private let audioService: AudioSoundscapeService

    private var cancellables = Set<AnyCancellable>()
    private var heartRateTimer: Timer?

    // Session configuration
    private let modality: SensoryModality
    private let patternId: String
    private let maxDuration: Int = 1800  // 30 minutes

    // MARK: - Initialization

    init(
        modality: SensoryModality,
        patternId: String,
        sensoryService: SensoryRegulationService,
        tactileService: TactilePatternService,
        visualService: VisualAnimationService,
        audioService: AudioSoundscapeService
    ) {
        self.modality = modality
        self.patternId = patternId
        self.sensoryService = sensoryService
        self.tactileService = tactileService
        self.visualService = visualService
        self.audioService = audioService

        setupBindings()
        startSimulatedHeartRate()
    }

    // MARK: - Public Methods

    /// Start the session
    func startSession() async {
        do {
            try await sensoryService.startSession(
                modality: modality,
                patternId: patternId,
                speed: currentSpeed,
                loop: true
            )
            isPlaying = true
        } catch SensoryError.premiumRequired {
            showPremiumPaywall = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Toggle play/pause
    func togglePlayPause() async {
        if isPlaying {
            await sensoryService.pauseSession()
            isPlaying = false
        } else {
            do {
                try await sensoryService.resumeSession()
                isPlaying = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// End the session
    func endSession() async {
        await sensoryService.endSession(interrupted: false)
        isPlaying = false
    }

    /// Change playback speed
    func changeSpeed(_ speed: SpeedPreset) {
        currentSpeed = speed

        // Update modality-specific service
        switch modality {
        case .tactile:
            // Tactile speed change requires restart
            break
        case .visual:
            visualService.changeSpeed(speed)
        case .audio:
            // Audio doesn't support speed change
            break
        }
    }

    // MARK: - Private Methods

    private func setupBindings() {
        // Bind elapsed time from service
        sensoryService.$elapsedSeconds
            .map { elapsed in
                let minutes = elapsed / 60
                let seconds = elapsed % 60
                return String(format: "%02d:%02d", minutes, seconds)
            }
            .assign(to: &$elapsedTime)

        // Calculate progress percentage
        sensoryService.$elapsedSeconds
            .map { elapsed in
                Double(elapsed) / Double(self.maxDuration)
            }
            .assign(to: &$progressPercentage)

        // Bind session state
        sensoryService.$isSessionActive
            .assign(to: &$isPlaying)

        // Bind errors
        sensoryService.$error
            .compactMap { $0?.errorDescription }
            .assign(to: &$errorMessage)
    }

    private func startSimulatedHeartRate() {
        // Simulate heart rate decreasing from 80 to 60 over time
        simulatedHeartRate = 80

        heartRateTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            MainActor.assumeIsolated {
                if self.isPlaying {
                    // Gradually decrease heart rate during session (max reduction: 20 BPM)
                    let elapsed = self.sensoryService.elapsedSeconds
                    let targetReduction = min(20.0, Double(elapsed) / 90.0)  // 1 BPM per 4.5 seconds
                    self.simulatedHeartRate = max(60, 80 - Int(targetReduction))

                    // Add slight random variation (+/-2 BPM)
                    self.simulatedHeartRate += Int.random(in: -2...2)
                    self.simulatedHeartRate = max(58, min(82, self.simulatedHeartRate))
                } else {
                    // Heart rate returns to baseline when paused
                    if self.simulatedHeartRate < 80 {
                        self.simulatedHeartRate = min(80, self.simulatedHeartRate + 2)
                    }
                }
            }
        }
    }

    deinit {
        heartRateTimer?.invalidate()
    }
}
