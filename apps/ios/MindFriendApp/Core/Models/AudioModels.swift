// MARK: - Audio Content Models
// Models for audio tracks, narrators, playback state, and related entities

import Foundation
import AVFoundation

// MARK: - Enums

enum AudioCategory: String, Codable, CaseIterable {
    case meditation
    case sleepStory = "sleep_story"
    case sleepMeditation = "sleep_meditation"
    case soundscape
    case breathing
    case music
    case courseLesson = "course_lesson"

    var displayName: String {
        switch self {
        case .meditation: return "Meditation"
        case .sleepStory: return "Sleep Story"
        case .sleepMeditation: return "Sleep Meditation"
        case .soundscape: return "Soundscape"
        case .breathing: return "Breathing"
        case .music: return "Music"
        case .courseLesson: return "Course"
        }
    }

    var icon: String {
        switch self {
        case .meditation: return "brain.head.profile"
        case .sleepStory: return "moon.stars"
        case .sleepMeditation: return "moon.zzz"
        case .soundscape: return "waveform"
        case .breathing: return "wind"
        case .music: return "music.note"
        case .courseLesson: return "book"
        }
    }
}

enum EnergyLevel: String, Codable {
    case calming
    case neutral
    case energizing
}

enum CreatorType: String, Codable {
    case professional
    case community
    case aiGenerated = "ai_generated"
}

enum SleepTimerDuration: Int, CaseIterable, Equatable {
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case fortyFiveMinutes = 45
    case oneHour = 60
    case endOfTrack = 0

    var displayName: String {
        switch self {
        case .fifteenMinutes: return "15 minutes"
        case .thirtyMinutes: return "30 minutes"
        case .fortyFiveMinutes: return "45 minutes"
        case .oneHour: return "1 hour"
        case .endOfTrack: return "End of track"
        }
    }

    var minutes: Int {
        switch self {
        case .endOfTrack: return 0
        default: return self.rawValue
        }
    }
}

// MARK: - Database Row Types (DB prefix for snake_case mapping)

struct DBAudioTrack: Codable {
    let id: String
    let title: String
    let slug: String
    let description: String?
    let category: String
    let subcategory: String?
    let tags: [String]?
    let audioUrl: String
    let audioDurationSeconds: Int
    let audioFormat: String?
    let audioQuality: String?
    let fileSizeBytes: Int?
    let previewUrl: String?
    let previewDurationSeconds: Int?
    let coverImageUrl: String?
    let backgroundImageUrl: String?
    let colorScheme: ColorScheme?
    let narratorId: String?
    let creatorType: String?
    let language: String?
    let isLoopable: Bool
    let hasBackgroundMusic: Bool
    let energyLevel: String?
    let isPremium: Bool
    let isFeatured: Bool
    let isActive: Bool
    let releasedAt: String?
    let courseId: String?
    let courseOrder: Int?
    let playCount: Int
    let completionCount: Int
    let averageRating: Double?
    let ratingCount: Int
    let createdAt: String
    let updatedAt: String
    let narrator: DBNarrator?

    enum CodingKeys: String, CodingKey {
        case id, title, slug, description, category, subcategory, tags
        case audioUrl = "audio_url"
        case audioDurationSeconds = "audio_duration_seconds"
        case audioFormat = "audio_format"
        case audioQuality = "audio_quality"
        case fileSizeBytes = "file_size_bytes"
        case previewUrl = "preview_url"
        case previewDurationSeconds = "preview_duration_seconds"
        case coverImageUrl = "cover_image_url"
        case backgroundImageUrl = "background_image_url"
        case colorScheme = "color_scheme"
        case narratorId = "narrator_id"
        case creatorType = "creator_type"
        case language
        case isLoopable = "is_loopable"
        case hasBackgroundMusic = "has_background_music"
        case energyLevel = "energy_level"
        case isPremium = "is_premium"
        case isFeatured = "is_featured"
        case isActive = "is_active"
        case releasedAt = "released_at"
        case courseId = "course_id"
        case courseOrder = "course_order"
        case playCount = "play_count"
        case completionCount = "completion_count"
        case averageRating = "average_rating"
        case ratingCount = "rating_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case narrator
    }
}

struct ColorScheme: Codable {
    let primary: String?
    let secondary: String?
}

struct DBNarrator: Codable {
    let id: String
    let name: String
    let slug: String
    let bio: String?
    let avatarUrl: String?
    let voiceType: String?
    let voiceGender: String?
    let voiceStyle: String?
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, slug, bio
        case avatarUrl = "avatar_url"
        case voiceType = "voice_type"
        case voiceGender = "voice_gender"
        case voiceStyle = "voice_style"
        case isActive = "is_active"
    }
}

struct DBPlaybackSession: Codable {
    let id: String
    let userId: String
    let trackId: String
    let startedAt: String
    let endedAt: String?
    let durationPlayedSeconds: Int?
    let completed: Bool
    let lastPositionSeconds: Int
    let source: String?
    let contextId: String?
    let skipped: Bool
    let skipPositionSeconds: Int?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case trackId = "track_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationPlayedSeconds = "duration_played_seconds"
        case completed
        case lastPositionSeconds = "last_position_seconds"
        case source
        case contextId = "context_id"
        case skipped
        case skipPositionSeconds = "skip_position_seconds"
        case createdAt = "created_at"
    }
}

// MARK: - Domain Models

struct AudioTrack: Identifiable, Equatable {
    let id: String
    let title: String
    let slug: String
    let description: String?
    let category: AudioCategory
    let subcategory: String?
    let tags: [String]
    let audioUrl: URL
    let duration: TimeInterval
    let audioFormat: String
    let audioQuality: String
    let fileSizeBytes: Int?
    let previewUrl: URL?
    let coverImageUrl: URL?
    let backgroundImageUrl: URL?
    let primaryColor: String?
    let secondaryColor: String?
    let narrator: Narrator?
    let creatorType: CreatorType
    let language: String
    let isLoopable: Bool
    let hasBackgroundMusic: Bool
    let energyLevel: EnergyLevel?
    let isPremium: Bool
    let isFeatured: Bool
    let playCount: Int
    let completionCount: Int
    let averageRating: Double?
    let ratingCount: Int

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes < 60 {
            return "\(minutes):\(String(format: "%02d", seconds))"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours):\(String(format: "%02d", remainingMinutes)):\(String(format: "%02d", seconds))"
        }
    }

    var shortDuration: String {
        let minutes = Int(duration) / 60
        if minutes < 60 {
            return "\(minutes) min"
        } else {
            return "\(minutes / 60) hr \(minutes % 60) min"
        }
    }

    init(from db: DBAudioTrack) {
        self.id = db.id
        self.title = db.title
        self.slug = db.slug
        self.description = db.description
        self.category = AudioCategory(rawValue: db.category) ?? .meditation
        self.subcategory = db.subcategory
        self.tags = db.tags ?? []
        self.audioUrl = URL(string: db.audioUrl) ?? URL(fileURLWithPath: "")
        self.duration = TimeInterval(db.audioDurationSeconds)
        self.audioFormat = db.audioFormat ?? "mp3"
        self.audioQuality = db.audioQuality ?? "high"
        self.fileSizeBytes = db.fileSizeBytes
        self.previewUrl = db.previewUrl.flatMap { URL(string: $0) }
        self.coverImageUrl = db.coverImageUrl.flatMap { URL(string: $0) }
        self.backgroundImageUrl = db.backgroundImageUrl.flatMap { URL(string: $0) }
        self.primaryColor = db.colorScheme?.primary
        self.secondaryColor = db.colorScheme?.secondary
        self.narrator = db.narrator.map { Narrator(from: $0) }
        self.creatorType = CreatorType(rawValue: db.creatorType ?? "professional") ?? .professional
        self.language = db.language ?? "en"
        self.isLoopable = db.isLoopable
        self.hasBackgroundMusic = db.hasBackgroundMusic
        self.energyLevel = db.energyLevel.flatMap { EnergyLevel(rawValue: $0) }
        self.isPremium = db.isPremium
        self.isFeatured = db.isFeatured
        self.playCount = db.playCount
        self.completionCount = db.completionCount
        self.averageRating = db.averageRating
        self.ratingCount = db.ratingCount
    }

    static func == (lhs: AudioTrack, rhs: AudioTrack) -> Bool {
        lhs.id == rhs.id
    }
}

struct Narrator: Identifiable, Equatable {
    let id: String
    let name: String
    let slug: String
    let bio: String?
    let avatarUrl: URL?
    let voiceType: String?
    let voiceGender: String?
    let voiceStyle: String?

    init(from db: DBNarrator) {
        self.id = db.id
        self.name = db.name
        self.slug = db.slug
        self.bio = db.bio
        self.avatarUrl = db.avatarUrl.flatMap { URL(string: $0) }
        self.voiceType = db.voiceType
        self.voiceGender = db.voiceGender
        self.voiceStyle = db.voiceStyle
    }

    static func == (lhs: Narrator, rhs: Narrator) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Playback State

struct PlaybackState: Equatable {
    var track: AudioTrack?
    var isPlaying: Bool = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var isLoading: Bool = false
    var error: PlaybackError?

    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    var remainingTime: TimeInterval {
        max(0, duration - currentTime)
    }

    var formattedCurrentTime: String {
        formatTime(currentTime)
    }

    var formattedRemainingTime: String {
        "-" + formatTime(remainingTime)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}

enum PlaybackError: Error, Equatable {
    case networkError
    case invalidURL
    case decodingError
    case unknown(String)

    static func == (lhs: PlaybackError, rhs: PlaybackError) -> Bool {
        switch (lhs, rhs) {
        case (.networkError, .networkError): return true
        case (.invalidURL, .invalidURL): return true
        case (.decodingError, .decodingError): return true
        case let (.unknown(a), .unknown(b)): return a == b
        default: return false
        }
    }
}

// MARK: - Playback Session

struct PlaybackSession {
    let id: String
    let trackId: String
    let startedAt: Date
    var lastPositionSeconds: Int = 0
    var durationPlayedSeconds: Int?
    var completed: Bool = false
    let source: String?

    init(from db: DBPlaybackSession) {
        self.id = db.id
        self.trackId = db.trackId
        self.startedAt = ISO8601DateFormatter().date(from: db.startedAt) ?? Date()
        self.lastPositionSeconds = db.lastPositionSeconds
        self.durationPlayedSeconds = db.durationPlayedSeconds
        self.completed = db.completed
        self.source = db.source
    }
}
