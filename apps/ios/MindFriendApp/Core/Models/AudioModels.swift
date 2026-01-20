import Foundation

// MARK: - Audio Models

enum AudioCategory: String, Codable, CaseIterable, Identifiable {
    case meditation
    case sleep
    case focus
    case sounds
    case breathing
    case music
    case story

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .meditation: return "Meditation"
        case .sleep: return "Sleep"
        case .focus: return "Focus"
        case .sounds: return "Sounds"
        case .breathing: return "Breathing"
        case .music: return "Music"
        case .story: return "Story"
        }
    }
}

struct AudioTrack: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let slug: String
    let description: String?
    let authorName: String?
    let imageUrl: String?
    let audioUrl: String
    let category: AudioCategory
    let duration: TimeInterval
    let isFeatured: Bool
    let playCount: Int
    let createdAt: Date

    init(from dbTrack: DBAudioTrack) {
        self.id = dbTrack.id
        self.title = dbTrack.title
        self.slug = dbTrack.slug
        self.description = dbTrack.description
        self.authorName = dbTrack.authorName
        self.imageUrl = dbTrack.imageUrl
        self.audioUrl = dbTrack.audioUrl
        self.category = AudioCategory(rawValue: dbTrack.category) ?? .meditation
        self.duration = TimeInterval(dbTrack.audioDurationSeconds)
        self.isFeatured = dbTrack.isFeatured
        self.playCount = dbTrack.playCount
        self.createdAt = dbTrack.createdAt
    }

    // Manual init for previews/mocking
    init(id: String, title: String, slug: String, description: String? = nil, authorName: String? = nil, imageUrl: String? = nil, audioUrl: String, category: AudioCategory, duration: TimeInterval, isFeatured: Bool = false, playCount: Int = 0, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.slug = slug
        self.description = description
        self.authorName = authorName
        self.imageUrl = imageUrl
        self.audioUrl = audioUrl
        self.category = category
        self.duration = duration
        self.isFeatured = isFeatured
        self.playCount = playCount
        self.createdAt = createdAt
    }
    
    // Derived properties to match existing usage
    var coverImageUrl: URL? {
        guard let url = imageUrl else { return nil }
        return URL(string: url)
    }
    
    var narrator: String? { authorName }
    var audioFormat: String { "mp3" } // Default
    var fileSizeBytes: Int? { nil } // Placeholder
    var shortDuration: String {
        let minutes = Int(duration) / 60
        return "\(minutes) min"
    }
}

struct DBAudioTrack: Codable, Identifiable {
    let id: String
    let title: String
    let slug: String
    let description: String?
    let authorName: String?
    let imageUrl: String?
    let audioUrl: String
    let category: String
    let audioDurationSeconds: Int
    let isFeatured: Bool
    let playCount: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, slug, description, category
        case authorName = "author_name"
        case imageUrl = "image_url"
        case audioUrl = "audio_url"
        case audioDurationSeconds = "audio_duration_seconds"
        case isFeatured = "is_featured"
        case playCount = "play_count"
        case createdAt = "created_at"
    }
}

// MARK: - Player Types

struct PlaybackState: Equatable {
    var isPlaying: Bool = false
    var currentTrack: AudioTrack?
    var progress: Double = 0 // 0 to 1
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var isBuffering: Bool = false
    var error: String?
    
    // Alias for compatibility
    var track: AudioTrack? { currentTrack }
    var isLoading: Bool { isBuffering }
    
    var formattedCurrentTime: String {
        let minutes = Int(currentTime) / 60
        let seconds = Int(currentTime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var formattedRemainingTime: String {
        let remaining = max(0, duration - currentTime)
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return String(format: "-%d:%02d", minutes, seconds)
    }
}

enum SleepTimerDuration: Int, CaseIterable, Identifiable {
    case minutes15 = 15
    case minutes30 = 30
    case minutes45 = 45
    case minutes60 = 60
    case endOfTrack = -1

    var id: Int { rawValue }

    var displayName: String {
        if self == .endOfTrack {
            return "End of Track"
        }
        return "\(rawValue) min"
    }
    
    var minutes: Int? {
        self == .endOfTrack ? nil : rawValue
    }
}

struct DBPlaybackSession: Decodable {
    let trackId: String
    let track: DBAudioTrack?
    
    enum CodingKeys: String, CodingKey {
        case trackId = "track_id"
        case track = "audio_tracks"
    }
}
