import Foundation

/// Single source of truth for mood emoji mappings
/// Matches iOS MoodCheckInView emojis: ["😔", "😕", "😐", "🙂", "😁"] for scores 1-5
public enum MoodEmojiMapper {

    /// All moods in order from lowest (1) to highest (5) score
    public static let moodsLowToHigh: [(name: String, emoji: String, score: Int)] = [
        ("stressed", "😔", 1),
        ("low", "😕", 2),
        ("okay", "😐", 3),
        ("good", "🙂", 4),
        ("great", "😁", 5)
    ]

    /// All moods in order from highest (5) to lowest (1) score
    public static let moodsHighToLow: [(name: String, emoji: String, score: Int)] = moodsLowToHigh.reversed()

    /// Get emoji for a mood name
    /// - Parameter mood: The mood name (e.g., "great", "good", "okay", "low", "stressed")
    /// - Returns: The corresponding emoji, or "🙂" for unknown moods
    public static func emoji(for mood: String?) -> String {
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

    /// Get emoji for a mood score (1-5)
    /// - Parameter score: The mood score (1=stressed, 5=great)
    /// - Returns: The corresponding emoji
    public static func emoji(forScore score: Int) -> String {
        switch score {
        case 1: return "😔"
        case 2: return "😕"
        case 3: return "😐"
        case 4: return "🙂"
        case 5: return "😁"
        default: return "🙂"
        }
    }

    /// Get score for a mood name
    /// - Parameter mood: The mood name
    /// - Returns: The score (1-5), or 3 for unknown moods
    public static func score(for mood: String) -> Int {
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
