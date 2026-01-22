import Foundation
import SwiftUI

// MARK: - Emotion Snapshot

/// Timestamped record of a single emotion detection event during a Voice Mode session
/// Used for storing emotion history with voice journal entries
struct EmotionSnapshot: Codable, Identifiable, Equatable, Hashable {

    // MARK: - Valid Emotions (Allowlist for XSS Prevention)

    /// Set of valid emotion strings from the ML model
    /// Used to validate inputs and prevent XSS attacks
    static let validEmotions: Set<String> = [
        "angry", "calm", "disgust", "fearful", "happy", "neutral", "sad", "surprised"
    ]

    /// Maximum allowed transcript segment length
    static let maxTranscriptLength = 500

    // MARK: - Shared UI Helpers (Single Source of Truth)

    /// Get SF Symbol icon for an emotion string
    static func icon(for emotion: String) -> String {
        switch emotion {
        case "angry": return "exclamationmark.triangle.fill"
        case "fearful": return "eye.fill"
        case "sad": return "drop.fill"
        case "happy": return "face.smiling.fill"
        case "surprised": return "star.fill"
        case "disgust": return "hand.raised.fill"
        case "calm": return "wind"
        default: return "circle.fill" // neutral
        }
    }

    /// Get emoji for an emotion string
    static func emoji(for emotion: String) -> String {
        switch emotion {
        case "angry": return "😠"
        case "fearful": return "😨"
        case "sad": return "😢"
        case "happy": return "😊"
        case "surprised": return "😲"
        case "disgust": return "🤢"
        case "calm": return "😌"
        default: return "😐" // neutral
        }
    }

    /// Get hex color string for an emotion
    static func colorHex(for emotion: String) -> String {
        switch emotion {
        case "angry": return "#FF3B30"     // Red
        case "fearful": return "#FF9500"   // Orange
        case "sad": return "#5856D6"       // Purple
        case "happy": return "#34C759"     // Green
        case "surprised": return "#FFCC00" // Yellow
        case "disgust": return "#AF52DE"   // Dark purple
        case "calm": return "#007AFF"      // Blue
        default: return "#8E8E93"          // Gray (neutral)
        }
    }

    /// Get SwiftUI Color for an emotion
    static func color(for emotion: String) -> Color {
        switch emotion {
        case "angry": return Color(red: 1.0, green: 0.23, blue: 0.19)
        case "fearful": return Color(red: 1.0, green: 0.58, blue: 0.0)
        case "sad": return Color(red: 0.35, green: 0.34, blue: 0.84)
        case "happy": return Color(red: 0.20, green: 0.78, blue: 0.35)
        case "surprised": return Color(red: 1.0, green: 0.80, blue: 0.0)
        case "disgust": return Color(red: 0.69, green: 0.32, blue: 0.87)
        case "calm": return Color(red: 0.0, green: 0.48, blue: 1.0)
        default: return Color(red: 0.56, green: 0.56, blue: 0.58) // neutral
        }
    }

    // MARK: - Properties

    /// Unique identifier for this snapshot
    let id: UUID

    /// The detected emotion (one of 8: angry, calm, disgust, fearful, happy, neutral, sad, surprised)
    let emotion: String

    /// Confidence score for the detected emotion (0.0 - 1.0)
    let confidence: Double

    /// Probability distribution across all 8 emotions
    let allProbabilities: [String: Double]

    /// Timestamp relative to session start (in seconds)
    let timestamp: TimeInterval

    /// Optional associated transcript segment (max 500 chars)
    let transcriptSegment: String?

    // MARK: - Initialization

    /// Initialize from an EmotionAnalyzer result
    /// - Parameters:
    ///   - result: The emotion analysis result
    ///   - sessionStartTime: When the voice session started
    ///   - transcript: Optional associated transcript text
    init(
        from result: EmotionAnalyzer.EmotionResult,
        sessionStartTime: Date,
        transcript: String? = nil
    ) {
        self.id = UUID()
        // Validate emotion string - fallback to neutral for unknown emotions
        self.emotion = Self.validEmotions.contains(result.emotion) ? result.emotion : "neutral"
        // Validate confidence - clamp to 0.0-1.0 and handle NaN/Infinity
        self.confidence = Self.sanitizeConfidence(result.confidence)
        // Filter and validate probabilities - only keep valid emotions
        self.allProbabilities = Self.sanitizeProbabilities(result.allProbabilities)
        // Ensure timestamp is positive
        self.timestamp = max(0, Date().timeIntervalSince(sessionStartTime))
        // Sanitize and truncate transcript
        self.transcriptSegment = Self.sanitizeTranscript(transcript)
    }

    /// Initialize with explicit values (for testing and decoding)
    init(
        id: UUID = UUID(),
        emotion: String,
        confidence: Double,
        allProbabilities: [String: Double] = [:],
        timestamp: TimeInterval,
        transcriptSegment: String? = nil
    ) {
        self.id = id
        // Validate emotion string
        self.emotion = Self.validEmotions.contains(emotion) ? emotion : "neutral"
        // Validate confidence
        self.confidence = Self.sanitizeConfidence(confidence)
        // Validate probabilities
        self.allProbabilities = Self.sanitizeProbabilities(allProbabilities)
        // Ensure timestamp is non-negative
        self.timestamp = max(0, timestamp)
        // Sanitize transcript
        self.transcriptSegment = Self.sanitizeTranscript(transcriptSegment)
    }

    // MARK: - Validation Helpers

    /// Sanitize confidence to valid range, handling NaN/Infinity
    private static func sanitizeConfidence(_ value: Double) -> Double {
        guard value.isFinite else { return 0.0 }
        return max(0.0, min(1.0, value))
    }

    /// Sanitize probabilities - filter to valid emotions, validate values
    private static func sanitizeProbabilities(_ probs: [String: Double]) -> [String: Double] {
        var result: [String: Double] = [:]
        for (emotion, value) in probs {
            // Only include valid emotions
            guard validEmotions.contains(emotion) else { continue }
            // Validate the probability value
            guard value.isFinite else { continue }
            result[emotion] = max(0.0, min(1.0, value))
        }
        return result
    }

    /// Sanitize transcript - truncate to max length
    private static func sanitizeTranscript(_ text: String?) -> String? {
        guard let text = text, !text.isEmpty else { return nil }
        // Truncate to max length
        let truncated = String(text.prefix(maxTranscriptLength))
        return truncated.isEmpty ? nil : truncated
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id
        case emotion
        case confidence
        case allProbabilities = "all_probabilities"
        case timestamp
        case transcriptSegment = "transcript_segment"
    }

    /// Custom decoder to validate data from database/network
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decode and validate each field
        self.id = try container.decode(UUID.self, forKey: .id)

        // Validate emotion string - reject unknown emotions, fallback to neutral
        let rawEmotion = try container.decode(String.self, forKey: .emotion)
        self.emotion = Self.validEmotions.contains(rawEmotion) ? rawEmotion : "neutral"

        // Validate confidence - clamp to 0-1 range, handle NaN/Infinity
        let rawConfidence = try container.decode(Double.self, forKey: .confidence)
        self.confidence = Self.sanitizeConfidence(rawConfidence)

        // Validate probabilities - filter to valid emotions only
        let rawProbabilities = try container.decodeIfPresent([String: Double].self, forKey: .allProbabilities) ?? [:]
        self.allProbabilities = Self.sanitizeProbabilities(rawProbabilities)

        // Validate timestamp - ensure non-negative
        let rawTimestamp = try container.decode(TimeInterval.self, forKey: .timestamp)
        self.timestamp = max(0, rawTimestamp)

        // Validate transcript - truncate to max length
        let rawTranscript = try container.decodeIfPresent(String.self, forKey: .transcriptSegment)
        self.transcriptSegment = Self.sanitizeTranscript(rawTranscript)
    }
}

// MARK: - Emotion Summary

/// Summary of emotions detected during a voice session
struct EmotionSummary: Codable, Equatable {

    /// The dominant (most frequent or highest average confidence) emotion
    let dominantEmotion: String

    /// Average confidence across all detections
    let averageConfidence: Double

    /// Distribution of emotions by count
    let emotionDistribution: [String: Int]

    /// Total number of emotion detections in the session
    let totalDetections: Int

    // MARK: - Initialization

    /// Compute summary from emotion history
    /// - Parameter history: Array of emotion snapshots
    init(from history: [EmotionSnapshot]) {
        guard !history.isEmpty else {
            self.dominantEmotion = "neutral"
            self.averageConfidence = 0
            self.emotionDistribution = [:]
            self.totalDetections = 0
            return
        }

        // Calculate emotion counts
        var counts: [String: Int] = [:]
        var totalConfidence: Double = 0

        for snapshot in history {
            counts[snapshot.emotion, default: 0] += 1
            totalConfidence += snapshot.confidence
        }

        // Find dominant emotion
        let dominant = counts.max(by: { $0.value < $1.value })?.key ?? "neutral"

        self.dominantEmotion = dominant
        self.averageConfidence = totalConfidence / Double(history.count)
        self.emotionDistribution = counts
        self.totalDetections = history.count
    }

    /// Initialize with explicit values
    init(
        dominantEmotion: String,
        averageConfidence: Double,
        emotionDistribution: [String: Int],
        totalDetections: Int
    ) {
        self.dominantEmotion = dominantEmotion
        self.averageConfidence = averageConfidence
        self.emotionDistribution = emotionDistribution
        self.totalDetections = totalDetections
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case dominantEmotion = "dominant_emotion"
        case averageConfidence = "average_confidence"
        case emotionDistribution = "emotion_distribution"
        case totalDetections = "total_detections"
    }
}

// MARK: - Emotion Settings

/// User preferences for emotion detection during voice mode
struct EmotionSettings: Codable, Equatable {

    /// Whether emotion detection is enabled
    var isEnabled: Bool

    /// Confidence threshold for displaying emotions (0.4 - 0.8, default: 0.6)
    var sensitivityThreshold: Double

    /// Whether to show emotion badges in the UI
    var showBadges: Bool

    /// Whether to include emotion context in AI prompts
    var includeInPrompts: Bool

    /// Whether to save emotion history with journal entries (premium only)
    var saveHistory: Bool

    // MARK: - Defaults

    /// Default emotion settings (disabled by default for privacy)
    static let defaults = EmotionSettings(
        isEnabled: false,
        sensitivityThreshold: 0.6,
        showBadges: true,
        includeInPrompts: true,
        saveHistory: true
    )

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case isEnabled = "emotion_analysis_enabled"
        case sensitivityThreshold = "emotion_sensitivity"
        case showBadges = "show_emotion_badges"
        case includeInPrompts = "include_emotion_in_prompts"
        case saveHistory = "save_emotion_history"
    }
}

// MARK: - Emotion UI Helpers

extension EmotionSnapshot {

    /// SF Symbol icon for the emotion
    var icon: String {
        Self.icon(for: emotion)
    }

    /// Emoji representation
    var emoji: String {
        Self.emoji(for: emotion)
    }

    /// Display color for the emotion (hex values from spec)
    var colorHex: String {
        Self.colorHex(for: emotion)
    }

    /// SwiftUI Color for the emotion
    var color: Color {
        Self.color(for: emotion)
    }

    /// Confidence level description
    var confidenceLevel: String {
        if confidence >= 0.8 { return "high" }
        if confidence >= 0.6 { return "medium" }
        return "low"
    }

    /// Format timestamp as relative time string
    func formattedTimestamp() -> String {
        let minutes = Int(timestamp / 60)
        let seconds = Int(timestamp.truncatingRemainder(dividingBy: 60))

        if minutes == 0 {
            return "\(seconds)s"
        }
        return "\(minutes)m \(seconds)s"
    }
}
