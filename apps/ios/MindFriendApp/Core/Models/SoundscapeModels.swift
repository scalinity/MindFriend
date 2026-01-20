import Foundation

// MARK: - Soundscape Constants

/// Constants shared between models and service
enum SoundscapeConstants {
    static let maxLayers = 5
    static let defaultVolume: Float = 0.7
}

// MARK: - DateFormatter Cache

private enum DateFormatterCache {
    static let mediumDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}

// MARK: - Soundscape Category

/// Categories for soundscape sounds in the mixer
enum SoundscapeCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case binaural = "binaural"
    case nature = "nature"
    case ambient = "ambient"
    case lofi = "lofi"
    case whiteNoise = "white_noise"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .binaural: return "Binaural Beats"
        case .nature: return "Nature Sounds"
        case .ambient: return "Ambient Music"
        case .lofi: return "Lo-fi"
        case .whiteNoise: return "White Noise"
        }
    }

    var icon: String {
        switch self {
        case .binaural: return "headphones"
        case .nature: return "leaf.fill"
        case .ambient: return "cloud.fill"
        case .lofi: return "music.note"
        case .whiteNoise: return "waveform.circle.fill"
        }
    }

    var description: String {
        switch self {
        case .binaural: return "Brainwave entrainment for focus & relaxation"
        case .nature: return "Calming sounds from the natural world"
        case .ambient: return "Atmospheric soundscapes for any mood"
        case .lofi: return "Chill beats for studying or relaxing"
        case .whiteNoise: return "Consistent noise to mask distractions"
        }
    }
}

// MARK: - Soundscape Sound

/// A single sound that can be added to a soundscape mix
struct SoundscapeSound: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: String
    let title: String
    let category: SoundscapeCategory
    let audioUrl: String
    let thumbnailUrl: String?
    let iconName: String
    let isPremium: Bool
    let durationSeconds: Int? // nil for infinite loops
    let sortOrder: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, category
        case audioUrl = "audio_url"
        case thumbnailUrl = "thumbnail_url"
        case iconName = "icon_name"
        case isPremium = "is_premium"
        case durationSeconds = "duration_seconds"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
    }

    // MARK: - Computed Properties

    /// URL for the audio file
    var audioURL: URL? {
        URL(string: audioUrl)
    }

    /// URL for the thumbnail image
    var thumbnailURL: URL? {
        guard let thumbnailUrl else { return nil }
        return URL(string: thumbnailUrl)
    }

    /// SF Symbol name for the sound
    var sfSymbol: String {
        iconName
    }
}

// MARK: - Sound Layer State

/// State for a single layer in the soundscape mixer
struct SoundLayerState: Identifiable, Equatable, Sendable {
    let id: UUID
    let sound: SoundscapeSound
    var volume: Float // 0.0 to 1.0
    var pan: Float // -1.0 (left) to 1.0 (right)
    var isLoaded: Bool
    var isPlaying: Bool
    var loadError: String?

    init(id: UUID = UUID(), sound: SoundscapeSound, volume: Float = SoundscapeConstants.defaultVolume, pan: Float = 0.0) {
        self.id = id
        self.sound = sound
        self.volume = volume
        self.pan = pan
        self.isLoaded = false
        self.isPlaying = false
        self.loadError = nil
    }

    init(id: UUID, sound: SoundscapeSound, volume: Float, pan: Float, isLoaded: Bool, isPlaying: Bool, loadError: String?) {
        self.id = id
        self.sound = sound
        self.volume = volume
        self.pan = pan
        self.isLoaded = isLoaded
        self.isPlaying = isPlaying
        self.loadError = loadError
    }

    /// Formatted volume percentage
    var volumePercentage: Int {
        Int(volume * 100)
    }

    /// Pan position description
    var panDescription: String {
        if pan < -0.3 {
            return "Left"
        } else if pan > 0.3 {
            return "Right"
        } else {
            return "Center"
        }
    }
}

// MARK: - Soundscape Mixer State

/// Overall state of the soundscape mixer
struct SoundscapeMixerState: Equatable {
    var layers: [SoundLayerState] = []
    var isPlaying: Bool = false
    var isPreparing: Bool = false
    var masterVolume: Float = 1.0
    var sleepTimerDuration: SleepTimerDuration?
    var sleepTimerRemaining: TimeInterval?
    var isFading: Bool = false
    var error: String?

    // MARK: - Computed Properties

    /// Whether more layers can be added
    var canAddLayer: Bool {
        layers.count < SoundscapeConstants.maxLayers
    }

    /// Whether the mixer has any active layers
    var hasActiveLayers: Bool {
        !layers.isEmpty
    }

    /// Number of layers currently in the mix
    var layerCount: Int {
        layers.count
    }

    /// Number of remaining layer slots
    var remainingSlots: Int {
        max(0, SoundscapeConstants.maxLayers - layers.count)
    }

    /// Master volume as a percentage
    var masterVolumePercentage: Int {
        Int(masterVolume * 100)
    }

    /// Whether all layers are loaded and ready
    var allLayersLoaded: Bool {
        layers.allSatisfy { $0.isLoaded }
    }

    /// Formatted sleep timer remaining
    var formattedSleepTimerRemaining: String? {
        guard let remaining = sleepTimerRemaining else { return nil }
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Saved Mix

/// A user-saved soundscape mix configuration
struct SavedMix: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let userId: String
    let name: String
    let layers: [SavedMixLayer]
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, layers
        case userId = "user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Number of sounds in this mix
    var soundCount: Int {
        layers.count
    }

    /// Formatted creation date
    var formattedDate: String {
        DateFormatterCache.mediumDate.string(from: createdAt)
    }
}

// MARK: - Saved Mix Layer

/// Configuration for a single layer in a saved mix
struct SavedMixLayer: Codable, Equatable, Sendable {
    let soundId: String
    let volume: Float
    let pan: Float

    enum CodingKeys: String, CodingKey {
        case soundId = "sound_id"
        case volume, pan
    }

    init(soundId: String, volume: Float, pan: Float = 0.0) {
        self.soundId = soundId
        self.volume = volume
        self.pan = pan
    }
}

// MARK: - Create Saved Mix DTO

/// Data transfer object for creating a new saved mix
struct CreateSavedMixDTO: Encodable {
    let userId: String
    let name: String
    let layers: [SavedMixLayer]

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name, layers
    }
}

// MARK: - Update Saved Mix DTO

/// Data transfer object for updating a saved mix
struct UpdateSavedMixDTO: Encodable {
    let name: String?
    let layers: [SavedMixLayer]?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case name, layers
        case updatedAt = "updated_at"
    }
}

// MARK: - Soundscape Mixer Error

/// Errors that can occur in the soundscape mixer
enum SoundscapeMixerError: LocalizedError, Sendable {
    case maxLayersReached
    case soundNotFound
    case audioLoadFailed(String)
    case engineStartFailed(String)
    case notAuthenticated
    case mixNotFound
    case invalidMixName(String)
    case saveFailed(String)
    case deleteFailed(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .maxLayersReached:
            return "Maximum of 5 layers allowed"
        case .soundNotFound:
            return "Sound not found"
        case .audioLoadFailed(let reason):
            return "Failed to load audio: \(reason)"
        case .engineStartFailed(let reason):
            return "Audio engine failed to start: \(reason)"
        case .notAuthenticated:
            return "Sign in to save mixes"
        case .mixNotFound:
            return "Mix not found"
        case .invalidMixName(let reason):
            return "Invalid mix name: \(reason)"
        case .saveFailed(let reason):
            return "Failed to save mix: \(reason)"
        case .deleteFailed(let reason):
            return "Failed to delete mix: \(reason)"
        case .networkError(let reason):
            return "Network error: \(reason)"
        }
    }
}

// MARK: - Soundscape Content Filter

/// Filter options for browsing soundscape sounds
struct SoundscapeContentFilter: Equatable, Sendable {
    var category: SoundscapeCategory?
    var isPremiumOnly: Bool = false
    var searchQuery: String?

    static let all = SoundscapeContentFilter()

    static func category(_ category: SoundscapeCategory) -> SoundscapeContentFilter {
        SoundscapeContentFilter(category: category)
    }

    static func premium() -> SoundscapeContentFilter {
        SoundscapeContentFilter(isPremiumOnly: true)
    }
}

// MARK: - Mixer Preset

/// Predefined mixer configurations for quick setup
struct MixerPreset: Identifiable, Sendable {
    let id: String
    let name: String
    let description: String
    let iconName: String
    let soundConfigs: [(soundId: String, volume: Float)]

    static let presets: [MixerPreset] = [
        MixerPreset(
            id: "focus",
            name: "Deep Focus",
            description: "Brown noise with subtle rain for concentration",
            iconName: "brain.head.profile",
            soundConfigs: [
                ("brown-noise", 0.6),
                ("rain", 0.3)
            ]
        ),
        MixerPreset(
            id: "sleep",
            name: "Sleep Sanctuary",
            description: "Ocean waves with gentle wind for restful sleep",
            iconName: "moon.stars.fill",
            soundConfigs: [
                ("ocean", 0.7),
                ("wind", 0.4)
            ]
        ),
        MixerPreset(
            id: "cafe",
            name: "Cozy Cafe",
            description: "Coffee shop ambiance with lo-fi beats",
            iconName: "cup.and.saucer.fill",
            soundConfigs: [
                ("cafe", 0.5),
                ("lofi-beats", 0.6)
            ]
        ),
        MixerPreset(
            id: "nature",
            name: "Forest Retreat",
            description: "Birds, creek, and gentle wind in nature",
            iconName: "leaf.fill",
            soundConfigs: [
                ("birds", 0.5),
                ("creek", 0.6),
                ("wind", 0.3)
            ]
        ),
        MixerPreset(
            id: "meditation",
            name: "Meditation Space",
            description: "Theta waves with ambient tones",
            iconName: "sparkles",
            soundConfigs: [
                ("theta", 0.7),
                ("ambient", 0.4)
            ]
        )
    ]
}
