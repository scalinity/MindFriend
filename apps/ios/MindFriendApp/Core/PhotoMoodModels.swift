import Foundation
import SwiftUI

// MARK: - PhotoMood Model

/// Represents a photo-based mood log entry
struct PhotoMood: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let moodScore: Int // 1-5
    let caption: String?
    let emotionTags: [String]? // Max 5 emotions
    let locationName: String?
    let photoStoragePath: String // {user_id}/{timestamp}.jpg
    let photoThumbnailPath: String? // {user_id}/thumb_{timestamp}.jpg

    // Future AI features
    let aiMoodSuggestion: Int? // 1-5
    let aiEmotionsDetected: [String]?
    let aiAnalyzedAt: Date?

    // Future sharing feature
    let sharedToCircleId: UUID?

    // Timestamps
    let loggedAt: Date
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, caption
        case userId = "user_id"
        case moodScore = "mood_score"
        case emotionTags = "emotion_tags"
        case locationName = "location_name"
        case photoStoragePath = "photo_storage_path"
        case photoThumbnailPath = "photo_thumbnail_path"
        case aiMoodSuggestion = "ai_mood_suggestion"
        case aiEmotionsDetected = "ai_emotions_detected"
        case aiAnalyzedAt = "ai_analyzed_at"
        case sharedToCircleId = "shared_to_circle_id"
        case loggedAt = "logged_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Convenience computed property for mood emoji
    var moodEmoji: String {
        switch moodScore {
        case 1: return "😢"
        case 2: return "😕"
        case 3: return "😐"
        case 4: return "🙂"
        case 5: return "😊"
        default: return "😐"
        }
    }

    /// Convenience computed property for mood description
    var moodDescription: String {
        switch moodScore {
        case 1: return "Very Bad"
        case 2: return "Bad"
        case 3: return "Okay"
        case 4: return "Good"
        case 5: return "Great"
        default: return "Okay"
        }
    }
}

// MARK: - MoodEmotion Enum

/// Predefined emotion tags for photo moods
enum MoodEmotion: String, CaseIterable, Codable {
    case happy
    case peaceful
    case excited
    case grateful
    case loved
    case content
    case anxious
    case sad
    case stressed
    case tired
    case frustrated
    case lonely

    /// Emoji representation of emotion
    var emoji: String {
        switch self {
        case .happy: return "😊"
        case .peaceful: return "😌"
        case .excited: return "🤩"
        case .grateful: return "🙏"
        case .loved: return "🥰"
        case .content: return "😊"
        case .anxious: return "😰"
        case .sad: return "😢"
        case .stressed: return "😫"
        case .tired: return "😴"
        case .frustrated: return "😤"
        case .lonely: return "🥺"
        }
    }

    /// Display name for UI
    var displayName: String {
        rawValue.capitalized
    }

    /// Color theme for emotion chip
    var color: Color {
        switch self {
        case .happy, .excited, .grateful, .loved, .content:
            return .green
        case .peaceful:
            return .blue
        case .anxious, .stressed:
            return .orange
        case .sad, .frustrated, .lonely:
            return .red
        case .tired:
            return .gray
        }
    }
}

// MARK: - PhotoMoodError Enum

/// Errors that can occur during photo mood operations
enum PhotoMoodError: LocalizedError {
    case compressionFailed
    case exifStripFailed
    case uploadFailed(String)
    case fetchFailed(String)
    case deleteFailed(String)
    case urlGenerationFailed(String)
    case permissionDenied(String)
    case invalidMoodScore
    case captionTooLong
    case tooManyEmotions
    case networkRequired
    case photoTooLarge
    case invalidPhotoFormat

    var errorDescription: String? {
        switch self {
        case .compressionFailed:
            return "Unable to process photo. Try a different photo."
        case .exifStripFailed:
            return "Failed to remove photo metadata."
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        case .fetchFailed(let message):
            return "Failed to load photo moods: \(message)"
        case .deleteFailed(let message):
            return "Delete failed: \(message)"
        case .urlGenerationFailed(let message):
            return "Failed to load photo: \(message)"
        case .permissionDenied(let type):
            return "\(type) access denied. Go to Settings to enable."
        case .invalidMoodScore:
            return "Please select how you're feeling (1-5)."
        case .captionTooLong:
            return "Caption must be 500 characters or less."
        case .tooManyEmotions:
            return "Maximum 5 emotions per mood."
        case .networkRequired:
            return "Internet connection required to save photo moods."
        case .photoTooLarge:
            return "Photo too large. Try a different photo."
        case .invalidPhotoFormat:
            return "Invalid photo format. Please use JPEG or PNG."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .uploadFailed, .deleteFailed:
            return "Please try again."
        case .permissionDenied:
            return "Open Settings > Privacy to enable access."
        case .networkRequired:
            return "Check your internet connection."
        case .photoTooLarge:
            return "Try selecting a smaller photo or taking a new one."
        default:
            return nil
        }
    }
}
