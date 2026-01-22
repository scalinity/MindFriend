//
//  AudioSoundscapeService.swift
//  MindFriendApp
//
//  Created by Claude Code on 2026-01-20.
//  AVAudioPlayer wrapper for audio soundscape playback
//

import Foundation
import AVFoundation
import Combine

@MainActor
final class AudioSoundscapeService: NSObject, ObservableObject {
    // MARK: - Published Properties

    @Published var isPlaying: Bool = false
    @Published var currentSoundscape: AudioSoundscape?
    @Published var error: SensoryError?

    // MARK: - Private Properties

    private var audioPlayer: AVAudioPlayer?
    private var audioSession: AVAudioSession = .sharedInstance()

    // MARK: - Initialization

    override init() {
        super.init()
        configureAudioSession()
    }

    // MARK: - Public Methods

    /// Load soundscape from library
    func loadSoundscape(id: String) async throws -> AudioSoundscape {
        guard let soundscape = AudioSoundscape.library.first(where: { $0.id == id }) else {
            throw SensoryError.patternNotFound
        }

        // Validate audio file exists
        guard soundscape.audioURL != nil else {
            throw SensoryError.ahapFileNotFound(soundscape.filename)
        }

        return soundscape
    }

    /// Start playing soundscape
    func playSound(id: String, loop: Bool) async throws {
        // Load soundscape
        let soundscape = try await loadSoundscape(id: id)

        // Stop any currently playing sound
        await stopSound()

        // Load audio file from bundle
        guard let audioURL = soundscape.audioURL else {
            throw SensoryError.ahapFileNotFound(soundscape.filename)
        }

        do {
            // Configure audio player
            let player = try AVAudioPlayer(contentsOf: audioURL)
            player.delegate = self
            player.numberOfLoops = loop ? -1 : 0  // -1 = infinite loop
            player.prepareToPlay()

            // Start playback
            guard player.play() else {
                throw SensoryError.renderFailure
            }

            audioPlayer = player
            currentSoundscape = soundscape
            isPlaying = true

        } catch {
            throw SensoryError.renderFailure
        }
    }

    /// Stop currently playing sound
    func stopSound() async {
        guard isPlaying else { return }

        // Stop player
        audioPlayer?.stop()

        // Release resources
        audioPlayer = nil
        currentSoundscape = nil
        isPlaying = false
    }

    /// Adjust playback volume
    func setVolume(_ volume: Float) {
        let clampedVolume = max(0.0, min(1.0, volume))
        audioPlayer?.volume = clampedVolume
    }

    // MARK: - Private Methods

    private func configureAudioSession() {
        do {
            // Use ambient mode for background compatibility
            // This allows audio to mix with other apps and doesn't silence music
            try audioSession.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try audioSession.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error.localizedDescription)")
            self.error = .renderFailure
        }
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioSoundscapeService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // Only update state if not looping
        if player.numberOfLoops == 0 {
            Task { @MainActor in
                self.isPlaying = false
                self.currentSoundscape = nil
            }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        print("Audio player decode error: \(error?.localizedDescription ?? "unknown")")
        Task { @MainActor in
            self.error = .renderFailure
            self.isPlaying = false
            self.currentSoundscape = nil
        }
    }
}
