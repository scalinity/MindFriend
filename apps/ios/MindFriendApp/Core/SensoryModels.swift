//
//  SensoryModels.swift
//  MindFriendApp
//
//  Created by Claude Code on 2026-01-20.
//  Sensory Regulation Toolkit: Core data models for tactile/visual/audio patterns
//

import Foundation
import CoreHaptics

// MARK: - Sensory Modality

enum SensoryModality: String, Codable, CaseIterable, Identifiable {
    case tactile
    case visual
    case audio

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tactile: return "Tactile"
        case .visual: return "Visual"
        case .audio: return "Audio"
        }
    }

    var icon: String {
        switch self {
        case .tactile: return "hand.tap.fill"
        case .visual: return "eye.fill"
        case .audio: return "speaker.wave.3.fill"
        }
    }
}

// MARK: - Speed Preset

enum SpeedPreset: String, Codable, CaseIterable {
    case slow = "slow"
    case medium = "medium"
    case fast = "fast"

    var displayName: String {
        switch self {
        case .slow: return "Slow"
        case .medium: return "Medium"
        case .fast: return "Fast"
        }
    }

    /// Breaths per minute for breathing patterns
    var breathsPerMinute: Double {
        switch self {
        case .slow: return 5.0    // Inhale 6s, Exhale 6s
        case .medium: return 9.0  // Inhale 3.5s, Exhale 3s
        case .fast: return 13.0   // Inhale 2.5s, Exhale 2s
        }
    }

    /// Speed multiplier for animations/haptics
    var speedMultiplier: Double {
        switch self {
        case .slow: return 0.75
        case .medium: return 1.0
        case .fast: return 1.25
        }
    }
}

// MARK: - Tactile Pattern

struct TactilePattern: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let category: PatternCategory
    let durationSeconds: Int
    let isPremium: Bool
    let ahapFilename: String
    let thumbnailName: String?

    enum PatternCategory: String, Codable, CaseIterable {
        case grounding
        case calming
        case energizing
        case focus

        var displayName: String {
            switch self {
            case .grounding: return "Grounding"
            case .calming: return "Calming"
            case .energizing: return "Energizing"
            case .focus: return "Focus"
            }
        }
    }

    /// Load AHAP pattern dictionary from bundle
    func loadAHAPPattern() -> [CHHapticPattern.Key: Any]? {
        guard let url = Bundle.main.url(forResource: ahapFilename, withExtension: "ahap"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [CHHapticPattern.Key: Any] else {
            return nil
        }
        return json
    }
}

// MARK: - Visual Animation

struct VisualAnimation: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let type: AnimationType
    let isPremium: Bool
    let defaultSpeed: SpeedPreset
    let colors: [String]  // Hex color codes

    enum AnimationType: String, Codable {
        case expandingCircle = "expanding_circle"
        case pulsingSquare = "pulsing_square"
        case wave = "wave"
        case bouncingDot = "bouncing_dot"
        case spiral = "spiral"
        case flowerBloom = "flower_bloom"
        case dotGrid = "dot_grid"
        case ribbonFlow = "ribbon_flow"

        var displayName: String {
            switch self {
            case .expandingCircle: return "Expanding Circle"
            case .pulsingSquare: return "Pulsing Square"
            case .wave: return "Wave"
            case .bouncingDot: return "Bouncing Dot"
            case .spiral: return "Spiral"
            case .flowerBloom: return "Flower Bloom"
            case .dotGrid: return "Dot Grid"
            case .ribbonFlow: return "Ribbon Flow"
            }
        }
    }
}

// MARK: - Audio Soundscape

struct AudioSoundscape: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let filename: String
    let durationSeconds: Int
    let isPremium: Bool
    let loopable: Bool
    let tags: [String]?

    var audioURL: URL? {
        Bundle.main.url(forResource: filename, withExtension: "m4a")
    }
}

// MARK: - Sensory Session

struct SensorySession: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let modality: SensoryModality
    let patternId: String
    let startedAt: Date
    var completedAt: Date?
    var durationSeconds: Int?
    var interrupted: Bool
    var status: SessionStatus
    let createdAt: Date
    var updatedAt: Date

    enum SessionStatus: String, Codable {
        case active
        case paused
        case completed
    }

    /// Computed property: is session currently active
    var isActive: Bool {
        status == .active
    }

    /// Computed property: formatted duration
    var formattedDuration: String {
        guard let duration = durationSeconds else { return "00:00" }
        let minutes = duration / 60
        let seconds = duration % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Sensory Favorite

struct SensoryFavorite: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let modality: SensoryModality
    let patternId: String
    let createdAt: Date
}

// MARK: - Sensory Settings

struct SensorySettings: Codable {
    var defaultSpeed: SpeedPreset
    var hapticIntensity: Float  // 0.0 - 1.0
    var enableAutoPause: Bool
    var defaultSessionDuration: Int  // Seconds, max 1800 (30 min)

    /// Default settings for new users
    static let `default` = SensorySettings(
        defaultSpeed: .medium,
        hapticIntensity: 1.0,
        enableAutoPause: true,
        defaultSessionDuration: 600  // 10 minutes
    )

    /// Validate settings
    func isValid() -> Bool {
        hapticIntensity >= 0.0 && hapticIntensity <= 1.0 &&
        defaultSessionDuration >= 60 && defaultSessionDuration <= 1800
    }
}

// MARK: - Pattern Libraries

extension TactilePattern {
    /// All available tactile patterns (hardcoded, database is optional metadata layer)
    static let library: [TactilePattern] = [
        // Grounding patterns
        TactilePattern(
            id: "tactile-heartbeat",
            name: "Heartbeat",
            description: "60 BPM pulse pattern for grounding",
            category: .grounding,
            durationSeconds: 300,
            isPremium: false,
            ahapFilename: "heartbeat",
            thumbnailName: "heartbeat_thumb"
        ),
        TactilePattern(
            id: "tactile-earth-pulse",
            name: "Earth Pulse",
            description: "Deep, slow rhythm like the earth's heartbeat",
            category: .grounding,
            durationSeconds: 300,
            isPremium: true,
            ahapFilename: "earth_pulse",
            thumbnailName: "earth_pulse_thumb"
        ),

        // Calming patterns
        TactilePattern(
            id: "tactile-wave",
            name: "Wave",
            description: "Rising and falling intensity like ocean waves",
            category: .calming,
            durationSeconds: 300,
            isPremium: false,
            ahapFilename: "wave",
            thumbnailName: "wave_thumb"
        ),
        TactilePattern(
            id: "tactile-breath-cue",
            name: "Breath Cue",
            description: "Tactile inhale/exhale timing cues",
            category: .calming,
            durationSeconds: 300,
            isPremium: false,
            ahapFilename: "breath_cue",
            thumbnailName: "breath_cue_thumb"
        ),

        // Focus patterns
        TactilePattern(
            id: "tactile-counting",
            name: "Counting",
            description: "Numbered taps for pacing and focus",
            category: .focus,
            durationSeconds: 240,
            isPremium: false,
            ahapFilename: "counting",
            thumbnailName: "counting_thumb"
        ),

        // Emergency pattern
        TactilePattern(
            id: "tactile-sos",
            name: "SOS",
            description: "Emergency grounding pattern (... --- ...)",
            category: .grounding,
            durationSeconds: 120,
            isPremium: false,
            ahapFilename: "sos",
            thumbnailName: "sos_thumb"
        )
    ]
}

extension VisualAnimation {
    /// All available visual animations
    static let library: [VisualAnimation] = [
        VisualAnimation(
            id: "visual-expanding-circle",
            name: "Expanding Circle",
            description: "Circle expands and contracts with breathing",
            type: .expandingCircle,
            isPremium: false,
            defaultSpeed: .medium,
            colors: ["#4A90E2", "#5BA3F5"]
        ),
        VisualAnimation(
            id: "visual-pulsing-square",
            name: "Pulsing Square",
            description: "Square pulses gently",
            type: .pulsingSquare,
            isPremium: false,
            defaultSpeed: .medium,
            colors: ["#7B68EE", "#9370DB"]
        ),
        VisualAnimation(
            id: "visual-wave",
            name: "Wave",
            description: "Flowing wave animation",
            type: .wave,
            isPremium: false,
            defaultSpeed: .medium,
            colors: ["#20B2AA", "#48D1CC"]
        ),
        VisualAnimation(
            id: "visual-bouncing-dot",
            name: "Bouncing Dot",
            description: "Dot bounces rhythmically",
            type: .bouncingDot,
            isPremium: false,
            defaultSpeed: .medium,
            colors: ["#FF6B6B", "#FF8787"]
        ),
        VisualAnimation(
            id: "visual-spiral",
            name: "Spiral",
            description: "Hypnotic spiral motion",
            type: .spiral,
            isPremium: true,
            defaultSpeed: .slow,
            colors: ["#9B59B6", "#BB8FCE"]
        ),
        VisualAnimation(
            id: "visual-flower-bloom",
            name: "Flower Bloom",
            description: "Petals bloom and close gently",
            type: .flowerBloom,
            isPremium: true,
            defaultSpeed: .slow,
            colors: ["#FFB6C1", "#FFC0CB"]
        ),
        VisualAnimation(
            id: "visual-dot-grid",
            name: "Dot Grid",
            description: "Grid of dots expands in sync",
            type: .dotGrid,
            isPremium: true,
            defaultSpeed: .medium,
            colors: ["#87CEEB", "#ADD8E6"]
        ),
        VisualAnimation(
            id: "visual-ribbon-flow",
            name: "Ribbon Flow",
            description: "Flowing ribbons move gracefully",
            type: .ribbonFlow,
            isPremium: false,
            defaultSpeed: .medium,
            colors: ["#98D8C8", "#B4E7CE"]
        )
    ]
}

extension AudioSoundscape {
    /// All available audio soundscapes
    static let library: [AudioSoundscape] = [
        AudioSoundscape(
            id: "audio-rain",
            name: "Rain",
            description: "Gentle rainfall sounds",
            filename: "rain",
            durationSeconds: 600,
            isPremium: false,
            loopable: true,
            tags: ["nature", "calming"]
        ),
        AudioSoundscape(
            id: "audio-ocean-waves",
            name: "Ocean Waves",
            description: "Calming ocean wave sounds",
            filename: "ocean_waves",
            durationSeconds: 600,
            isPremium: false,
            loopable: true,
            tags: ["nature", "calming"]
        )
    ]
}

// MARK: - Error Types

enum SensoryError: LocalizedError {
    case premiumRequired
    case sessionInProgress
    case maxDurationExceeded
    case patternNotFound
    case hapticsNotSupported
    case ahapFileNotFound(String)
    case engineFailure
    case animationNotFound
    case renderFailure
    case networkError

    var errorDescription: String? {
        switch self {
        case .premiumRequired:
            return "This pattern is premium. Upgrade to unlock."
        case .sessionInProgress:
            return "End current session first"
        case .maxDurationExceeded:
            return "Session ended (30 min limit)"
        case .patternNotFound:
            return "Pattern not found"
        case .hapticsNotSupported:
            return "Haptics not supported on this device"
        case .ahapFileNotFound(let filename):
            return "Pattern file '\(filename)' not found"
        case .engineFailure:
            return "Haptic engine failure"
        case .animationNotFound:
            return "Animation not found"
        case .renderFailure:
            return "Visual effect unavailable"
        case .networkError:
            return "Session saved locally"
        }
    }
}
