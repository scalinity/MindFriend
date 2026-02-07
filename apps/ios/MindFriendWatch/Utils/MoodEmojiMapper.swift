import Foundation

/// Single source of truth for mood emoji mappings (Watch version)
/// Matches iOS MoodCheckInView emojis: ["😔", "😕", "😐", "🙂", "😁"] for scores 1-5
enum MoodEmojiMapper {

    /// All moods in order from lowest (1) to highest (5) score
    static let moodsLowToHigh: [(name: String, emoji: String, score: Int)] = [
        ("stressed", "😔", 1),
        ("low", "😕", 2),
        ("okay", "😐", 3),
        ("good", "🙂", 4),
        ("great", "😁", 5)
    ]

    /// Get emoji for a mood name
    /// - Parameter mood: The mood name (e.g., "great", "good", "okay", "low", "stressed")
    /// - Returns: The corresponding emoji, or "🙂" for unknown moods
    static func emoji(for mood: String?) -> String {
        guard let mood = mood?.lowercased() else { return "🙂" }

        switch mood {
        case "great": return "😁"
        case "good": return "🙂"
        case "okay": return "😐"
        case "low": return "😕"
        case "stressed": return "😔"
        default: return "🙂"
        }
    }

    /// Get score for a mood name
    /// - Parameter mood: The mood name
    /// - Returns: The score (1-5), or 3 for unknown moods
    static func score(for mood: String) -> Int {
        switch mood.lowercased() {
        case "great": return 5
        case "good": return 4
        case "okay": return 3
        case "low": return 2
        case "stressed": return 1
        default: return 3
        }
    }
}
