// Spec 14: Accessibility Models
// Database models (DB* prefix with snake_case CodingKeys) and domain models

import Foundation

// MARK: - Enumerations

enum FontSizePreference: String, Codable, CaseIterable {
    case system
    case small
    case medium
    case large
    case xlarge

    var displayName: String {
        switch self {
        case .system: return "System Default"
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .xlarge: return "Extra Large"
        }
    }

    var scaleFactor: CGFloat {
        switch self {
        case .system: return 1.0
        case .small: return 0.85
        case .medium: return 1.0
        case .large: return 1.2
        case .xlarge: return 1.4
        }
    }
}

enum ColorBlindMode: String, Codable, CaseIterable {
    case none
    case protanopia // Red-blind
    case deuteranopia // Green-blind
    case tritanopia // Blue-blind
    case achromasia // Complete color blindness

    var displayName: String {
        switch self {
        case .none: return "None"
        case .protanopia: return "Protanopia (Red-Blind)"
        case .deuteranopia: return "Deuteranopia (Green-Blind)"
        case .tritanopia: return "Tritanopia (Blue-Blind)"
        case .achromasia: return "Achromasia (Complete)"
        }
    }
}

enum DateFormatPreference: String, Codable, CaseIterable {
    case system
    case mdy // MM/DD/YYYY
    case dmy // DD/MM/YYYY
    case ymd // YYYY-MM-DD

    var displayName: String {
        switch self {
        case .system: return "System Default"
        case .mdy: return "MM/DD/YYYY"
        case .dmy: return "DD/MM/YYYY"
        case .ymd: return "YYYY-MM-DD"
        }
    }
}

enum TimeFormatPreference: String, Codable, CaseIterable {
    case system
    case twelveHour = "12h"
    case twentyFourHour = "24h"

    var displayName: String {
        switch self {
        case .system: return "System Default"
        case .twelveHour: return "12-Hour (AM/PM)"
        case .twentyFourHour: return "24-Hour"
        }
    }
}

enum AccessibilityCategory: String, Codable, CaseIterable {
    case voiceover
    case visual
    case motor
    case cognitive
    case audio
    case localization

    var displayName: String {
        switch self {
        case .voiceover: return "VoiceOver & Screen Readers"
        case .visual: return "Visual Accessibility"
        case .motor: return "Motor & Mobility"
        case .cognitive: return "Cognitive Accessibility"
        case .audio: return "Audio & Hearing"
        case .localization: return "Language & Localization"
        }
    }
}

enum FeedbackIssueType: String, Codable, CaseIterable {
    case bug
    case improvement
    case missingLabel = "missing_label"
    case translation

    var displayName: String {
        switch self {
        case .bug: return "Something doesn't work"
        case .improvement: return "Suggestion for improvement"
        case .missingLabel: return "Missing or unclear label"
        case .translation: return "Translation issue"
        }
    }
}

enum AssistiveTechnology: String, Codable, CaseIterable {
    case voiceover
    case switchControl = "switch_control"
    case voiceControl = "voice_control"
    case zoomMagnifier = "zoom"
    case dynamicType = "dynamic_type"
    case reduceMotion = "reduce_motion"
    case increaseContrast = "increase_contrast"
    case brailleDisplay = "braille"
    case hearingAids = "hearing_aids"
    case closedCaptions = "closed_captions"

    var displayName: String {
        switch self {
        case .voiceover: return "VoiceOver"
        case .switchControl: return "Switch Control"
        case .voiceControl: return "Voice Control"
        case .zoomMagnifier: return "Zoom/Magnifier"
        case .dynamicType: return "Dynamic Type"
        case .reduceMotion: return "Reduce Motion"
        case .increaseContrast: return "Increase Contrast"
        case .brailleDisplay: return "Braille Display"
        case .hearingAids: return "Hearing Aids"
        case .closedCaptions: return "Closed Captions"
        }
    }
}

enum SignLanguageType: String, Codable, CaseIterable {
    case asl = "ASL" // American Sign Language
    case bsl = "BSL" // British Sign Language
    case auslan = "Auslan" // Australian Sign Language
    case lsf = "LSF" // French Sign Language
    case dgs = "DGS" // German Sign Language

    var displayName: String {
        switch self {
        case .asl: return "American Sign Language (ASL)"
        case .bsl: return "British Sign Language (BSL)"
        case .auslan: return "Australian Sign Language (Auslan)"
        case .lsf: return "French Sign Language (LSF)"
        case .dgs: return "German Sign Language (DGS)"
        }
    }
}

// MARK: - Domain Models

struct AccessibilityPreferences: Codable, Equatable {
    var id: UUID
    var userId: UUID

    // Visual
    var preferredFontSize: FontSizePreference
    var highContrastEnabled: Bool
    var reducedTransparencyEnabled: Bool
    var colorBlindMode: ColorBlindMode?

    // Motion
    var reduceMotionEnabled: Bool
    var autoPlayVideos: Bool
    var animationSpeed: Double

    // Cognitive
    var simplifiedModeEnabled: Bool
    var focusModeEnabled: Bool
    var dyslexiaFontEnabled: Bool
    var readingGuideEnabled: Bool
    var extendedTimeLimits: Bool

    // Audio
    var captionsEnabled: Bool
    var audioDescriptionsEnabled: Bool
    var hapticFeedbackEnabled: Bool
    var visualAlertsEnabled: Bool

    // Localization
    var preferredLanguage: String
    var preferredRegion: String?
    var dateFormat: DateFormatPreference
    var timeFormat: TimeFormatPreference

    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case preferredFontSize = "preferred_font_size"
        case highContrastEnabled = "high_contrast_enabled"
        case reducedTransparencyEnabled = "reduced_transparency_enabled"
        case colorBlindMode = "color_blind_mode"
        case reduceMotionEnabled = "reduce_motion_enabled"
        case autoPlayVideos = "auto_play_videos"
        case animationSpeed = "animation_speed"
        case simplifiedModeEnabled = "simplified_mode_enabled"
        case focusModeEnabled = "focus_mode_enabled"
        case dyslexiaFontEnabled = "dyslexia_font_enabled"
        case readingGuideEnabled = "reading_guide_enabled"
        case extendedTimeLimits = "extended_time_limits"
        case captionsEnabled = "captions_enabled"
        case audioDescriptionsEnabled = "audio_descriptions_enabled"
        case hapticFeedbackEnabled = "haptic_feedback_enabled"
        case visualAlertsEnabled = "visual_alerts_enabled"
        case preferredLanguage = "preferred_language"
        case preferredRegion = "preferred_region"
        case dateFormat = "date_format"
        case timeFormat = "time_format"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    static var `default`: AccessibilityPreferences {
        AccessibilityPreferences(
            id: UUID(),
            userId: UUID(),
            preferredFontSize: FontSizePreference.system,
            highContrastEnabled: false,
            reducedTransparencyEnabled: false,
            colorBlindMode: ColorBlindMode.none,
            reduceMotionEnabled: false,
            autoPlayVideos: true,
            animationSpeed: 1.0,
            simplifiedModeEnabled: false,
            focusModeEnabled: false,
            dyslexiaFontEnabled: false,
            readingGuideEnabled: false,
            extendedTimeLimits: false,
            captionsEnabled: true,
            audioDescriptionsEnabled: false,
            hapticFeedbackEnabled: true,
            visualAlertsEnabled: false,
            preferredLanguage: "en",
            preferredRegion: nil,
            dateFormat: DateFormatPreference.system,
            timeFormat: TimeFormatPreference.system,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

// MARK: - Captions

struct AudioCaptions: Codable, Equatable {
    let available: Bool
    let language: String?
    let format: CaptionFormat?
    let captionsUrl: String?
    let captions: [CaptionCue]?
    let transcript: String?
    let duration: Int?

    enum CaptionFormat: String, Codable {
        case vtt
        case srt
    }

    enum CodingKeys: String, CodingKey {
        case available
        case language
        case format
        case captionsUrl = "captionsUrl"
        case captions
        case transcript
        case duration
    }
}

struct CaptionCue: Codable, Identifiable, Equatable {
    let id: Int
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String

    enum CodingKeys: String, CodingKey {
        case id
        case startTime = "start_time"
        case endTime = "end_time"
        case text
    }
}

// MARK: - Localization

struct LocalizedStringBundle: Codable, Equatable {
    let language: String
    let region: String?
    let strings: [String: LocalizedStringValue]
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case language
        case region
        case strings
        case updatedAt = "updated_at"
    }
}

struct LocalizedStringValue: Codable, Equatable {
    let value: String
    let plurals: [String: String]?
}

// MARK: - Sign Language

struct SignLanguageVideo: Codable, Identifiable, Equatable {
    let id: UUID
    let contentType: String
    let contentId: UUID
    let signLanguage: SignLanguageType
    let videoUrl: String
    let thumbnailUrl: String?
    let durationSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case contentType = "content_type"
        case contentId = "content_id"
        case signLanguage = "sign_language"
        case videoUrl = "video_url"
        case thumbnailUrl = "thumbnail_url"
        case durationSeconds = "duration_seconds"
    }
}

// MARK: - Feedback

struct AccessibilityFeedback: Codable, Equatable {
    let category: AccessibilityCategory
    let screenName: String?
    let elementIdentifier: String?
    let issueType: FeedbackIssueType
    let description: String
    let assistiveTechUsed: [AssistiveTechnology]

    enum CodingKeys: String, CodingKey {
        case category
        case screenName = "screen_name"
        case elementIdentifier = "element_identifier"
        case issueType = "issue_type"
        case description
        case assistiveTechUsed = "assistive_tech_used"
    }
}
