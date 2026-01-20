import Foundation

// MARK: - Sleep Content Type

/// The type of sleep content
enum SleepContentType: String, Codable, CaseIterable, Identifiable {
    case story
    case soundscape
    case routine

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .story: return "Stories"
        case .soundscape: return "Soundscapes"
        case .routine: return "Routines"
        }
    }

    var icon: String {
        switch self {
        case .story: return "book.fill"
        case .soundscape: return "waveform"
        case .routine: return "moon.stars.fill"
        }
    }

    var description: String {
        switch self {
        case .story: return "Calming stories to drift off to"
        case .soundscape: return "Ambient sounds for deep sleep"
        case .routine: return "Guided wind-down routines"
        }
    }
}

// MARK: - Sleep Category

/// The category of sleep content within a type
enum SleepCategory: String, Codable, CaseIterable, Identifiable {
    case nature
    case fiction
    case nonfiction
    case asmr
    case ambient
    case whiteNoise = "white_noise"
    case binaural
    case routine

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nature: return "Nature"
        case .fiction: return "Fiction"
        case .nonfiction: return "Non-Fiction"
        case .asmr: return "ASMR"
        case .ambient: return "Ambient"
        case .whiteNoise: return "White Noise"
        case .binaural: return "Binaural Beats"
        case .routine: return "Routines"
        }
    }

    var icon: String {
        switch self {
        case .nature: return "leaf.fill"
        case .fiction: return "sparkles"
        case .nonfiction: return "globe"
        case .asmr: return "ear.fill"
        case .ambient: return "cloud.fill"
        case .whiteNoise: return "waveform.circle.fill"
        case .binaural: return "headphones"
        case .routine: return "moon.stars.fill"
        }
    }

    /// Valid categories for each content type
    static func validCategories(for contentType: SleepContentType) -> [SleepCategory] {
        switch contentType {
        case .story:
            return [.nature, .fiction, .nonfiction, .asmr]
        case .soundscape:
            return [.nature, .ambient, .whiteNoise, .binaural]
        case .routine:
            return [.routine]
        }
    }
}

// MARK: - Sleep Content

/// Represents a piece of sleep content (story, soundscape, or routine)
struct SleepContent: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let title: String
    let description: String?
    let contentType: SleepContentType
    let category: SleepCategory
    let durationSeconds: Int
    let narrator: String?
    let isPremium: Bool
    let isKids: Bool
    let audioUrl: String
    let thumbnailUrl: String?
    let isLoopable: Bool
    let isFeatured: Bool
    let sortOrder: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case contentType = "content_type"
        case category
        case durationSeconds = "duration_seconds"
        case narrator
        case isPremium = "is_premium"
        case isKids = "is_kids"
        case audioUrl = "audio_url"
        case thumbnailUrl = "thumbnail_url"
        case isLoopable = "is_loopable"
        case isFeatured = "is_featured"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
    }

    // MARK: - Computed Properties

    /// Formatted duration string (e.g., "30 min" or "1 hr 15 min")
    var formattedDuration: String {
        let minutes = durationSeconds / 60
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return "\(hours) hr"
            }
            return "\(hours) hr \(remainingMinutes) min"
        }
        return "\(minutes) min"
    }

    /// URL for the thumbnail image, if available
    var thumbnailURL: URL? {
        guard let thumbnailUrl else { return nil }
        return URL(string: thumbnailUrl)
    }

    /// URL for the audio file
    var audioURL: URL? {
        URL(string: audioUrl)
    }

    /// Whether this content should be looped (true for soundscapes)
    var shouldLoop: Bool {
        isLoopable || contentType == .soundscape
    }
}

// MARK: - Sleep Session

/// Represents a user's playback session for sleep content
struct SleepSession: Identifiable, Codable, Equatable {
    let id: String
    let userId: String
    let contentId: String
    let startedAt: Date
    var endedAt: Date?
    var durationListenedSeconds: Int
    var completed: Bool
    var sleepTimerUsed: Bool
    var timerDurationMinutes: Int?
    var lastPositionSeconds: Int

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case contentId = "content_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationListenedSeconds = "duration_listened_seconds"
        case completed
        case sleepTimerUsed = "sleep_timer_used"
        case timerDurationMinutes = "timer_duration_minutes"
        case lastPositionSeconds = "last_position_seconds"
    }

    // MARK: - Computed Properties

    /// Whether there's a resume position available
    var hasResumePosition: Bool {
        !completed && lastPositionSeconds > 30
    }

    /// Formatted resume position (e.g., "Resume from 12:45")
    var formattedResumePosition: String {
        let minutes = lastPositionSeconds / 60
        let seconds = lastPositionSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Sleep Session Create DTO

/// Data transfer object for creating a new sleep session
struct CreateSleepSessionDTO: Encodable {
    let userId: String
    let contentId: String
    let sleepTimerUsed: Bool
    let timerDurationMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case contentId = "content_id"
        case sleepTimerUsed = "sleep_timer_used"
        case timerDurationMinutes = "timer_duration_minutes"
    }
}

// MARK: - Sleep Session Update DTO

/// Data transfer object for updating a sleep session
struct UpdateSleepSessionDTO: Encodable {
    let endedAt: Date?
    let durationListenedSeconds: Int?
    let completed: Bool?
    let lastPositionSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case endedAt = "ended_at"
        case durationListenedSeconds = "duration_listened_seconds"
        case completed
        case lastPositionSeconds = "last_position_seconds"
    }
}

// MARK: - Sleep Timer Duration Extension

/// Extension to add seconds conversion for sleep timer (base enum is in AudioModels.swift)
extension SleepTimerDuration {
    /// Returns duration in seconds, or nil for endOfTrack
    var seconds: Int? {
        switch self {
        case .endOfTrack: return nil
        default: return rawValue * 60
        }
    }
}

// MARK: - Sleep Content Filter

/// Filter options for browsing sleep content
struct SleepContentFilter {
    var contentType: SleepContentType?
    var category: SleepCategory?
    var isPremiumOnly: Bool = false
    var isKidsOnly: Bool = false
    var isFeaturedOnly: Bool = false

    static let all = SleepContentFilter()

    static func stories(category: SleepCategory? = nil) -> SleepContentFilter {
        SleepContentFilter(contentType: .story, category: category)
    }

    static func soundscapes(category: SleepCategory? = nil) -> SleepContentFilter {
        SleepContentFilter(contentType: .soundscape, category: category)
    }

    static func featured() -> SleepContentFilter {
        SleepContentFilter(isFeaturedOnly: true)
    }

    static func kids() -> SleepContentFilter {
        SleepContentFilter(isKidsOnly: true)
    }
}

// MARK: - Sleep Player State

/// Current state of the sleep player
struct SleepPlayerState {
    var currentContent: SleepContent?
    var currentSession: SleepSession?
    var isPlaying: Bool = false
    var isBuffering: Bool = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var sleepTimerDuration: SleepTimerDuration?
    var sleepTimerRemaining: TimeInterval?
    var isFading: Bool = false

    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    var formattedCurrentTime: String {
        formatTime(currentTime)
    }

    var formattedDuration: String {
        formatTime(duration)
    }

    var formattedTimeRemaining: String {
        let remaining = max(0, duration - currentTime)
        return "-" + formatTime(remaining)
    }

    var formattedSleepTimerRemaining: String? {
        guard let remaining = sleepTimerRemaining else { return nil }
        return formatTime(remaining)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
