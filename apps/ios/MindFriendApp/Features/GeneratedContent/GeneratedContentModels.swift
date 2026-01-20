import Foundation

// MARK: - Content Types

/// Types of AI-generated wellness content
enum GeneratedContentType: String, Codable, CaseIterable, Identifiable {
    case sleepStory = "sleep_story"
    case meditation = "meditation"
    case breathing = "breathing"
    case grounding = "grounding"
    case mindfulness = "mindfulness"
    case cbt = "cbt"
    case journaling = "journaling"
    case affirmation = "affirmation"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sleepStory: return "Sleep Story"
        case .meditation: return "Meditation"
        case .breathing: return "Breathing Exercise"
        case .grounding: return "Grounding Exercise"
        case .mindfulness: return "Mindfulness"
        case .cbt: return "CBT Exercise"
        case .journaling: return "Journaling Prompt"
        case .affirmation: return "Affirmation"
        }
    }

    var icon: String {
        switch self {
        case .sleepStory: return "moon.stars.fill"
        case .meditation: return "brain.head.profile"
        case .breathing: return "wind"
        case .grounding: return "leaf.fill"
        case .mindfulness: return "sparkles"
        case .cbt: return "lightbulb.fill"
        case .journaling: return "pencil.and.scribble"
        case .affirmation: return "heart.text.square.fill"
        }
    }

    var description: String {
        switch self {
        case .sleepStory:
            return "Calming stories to help you drift off to sleep"
        case .meditation:
            return "Guided meditations for relaxation and focus"
        case .breathing:
            return "Structured breathing exercises for calm"
        case .grounding:
            return "Techniques to center yourself in the present"
        case .mindfulness:
            return "Mindful awareness practices"
        case .cbt:
            return "Cognitive exercises for thought patterns"
        case .journaling:
            return "Reflective writing prompts"
        case .affirmation:
            return "Positive affirmations for wellbeing"
        }
    }

    var supportsAudio: Bool {
        switch self {
        case .sleepStory, .meditation, .breathing, .grounding, .mindfulness,
             .affirmation, .cbt, .journaling:
            return true
        }
    }

    var audioStyle: AudioPlaybackStyle {
        switch self {
        case .sleepStory:
            return .continuous(narrative: true)
        case .meditation, .mindfulness:
            return .pausable
        case .breathing:
            return .paced(interval: 4)
        case .grounding:
            return .pausable
        case .cbt:
            return .interactive
        case .journaling:
            return .interactive
        case .affirmation:
            return .continuous(narrative: false)
        }
    }

    var defaultDuration: Int {
        switch self {
        case .sleepStory: return 20
        case .meditation: return 10
        case .breathing: return 5
        case .grounding: return 5
        case .mindfulness: return 10
        case .cbt: return 15
        case .journaling: return 10
        case .affirmation: return 3
        }
    }
}

/// Audio playback style for different content types
enum AudioPlaybackStyle {
    case continuous(narrative: Bool)  // Sleep stories, affirmations
    case pausable                      // Meditations, grounding
    case paced(interval: Int)         // Breathing exercises
    case interactive                   // CBT, journaling prompts
}

// MARK: - Content Status

enum GeneratedContentStatus: String, Codable {
    case generating
    case completed
    case failed
    case pendingReview = "pending_review"
    case approved
    case rejected
    case flagged
}

// MARK: - Voice Models

/// Supported languages for voice synthesis
enum VoiceLanguage: String, Codable, CaseIterable, Identifiable {
    case english = "en"
    case spanish = "es"
    case portuguese = "pt"
    case french = "fr"
    case german = "de"
    case italian = "it"
    case japanese = "ja"
    case mandarin = "zh"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Spanish"
        case .portuguese: return "Portuguese"
        case .french: return "French"
        case .german: return "German"
        case .italian: return "Italian"
        case .japanese: return "Japanese"
        case .mandarin: return "Mandarin Chinese"
        }
    }

    var flagEmoji: String {
        switch self {
        case .english: return "🇺🇸"
        case .spanish: return "🇪🇸"
        case .portuguese: return "🇧🇷"
        case .french: return "🇫🇷"
        case .german: return "🇩🇪"
        case .italian: return "🇮🇹"
        case .japanese: return "🇯🇵"
        case .mandarin: return "🇨🇳"
        }
    }
}

struct VoiceOption: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let gender: VoiceGender
    let style: String
    let language: VoiceLanguage
    let previewUrl: String?
    let sampleText: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case gender
        case style
        case language
        case previewUrl = "preview_url"
        case sampleText = "sample_text"
    }
}

struct VoicePreference: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let contentType: GeneratedContentType
    let preferredVoiceId: String
    let preferredSpeed: Double
    let backgroundSoundEnabled: Bool
    let backgroundSoundType: BackgroundSoundType?
    let backgroundSoundVolume: Double
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case contentType = "content_type"
        case preferredVoiceId = "preferred_voice_id"
        case preferredSpeed = "preferred_speed"
        case backgroundSoundEnabled = "background_sound_enabled"
        case backgroundSoundType = "background_sound_type"
        case backgroundSoundVolume = "background_sound_volume"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum BackgroundSoundType: String, Codable, CaseIterable {
    case rain
    case ocean
    case forest
    case fireplace
    case whiteNoise = "white_noise"
    case silence

    var displayName: String {
        switch self {
        case .rain: return "Rain"
        case .ocean: return "Ocean Waves"
        case .forest: return "Forest"
        case .fireplace: return "Fireplace"
        case .whiteNoise: return "White Noise"
        case .silence: return "Silence"
        }
    }

    var icon: String {
        switch self {
        case .rain: return "cloud.rain.fill"
        case .ocean: return "water.waves"
        case .forest: return "tree.fill"
        case .fireplace: return "flame.fill"
        case .whiteNoise: return "waveform"
        case .silence: return "speaker.slash.fill"
        }
    }
}

// MARK: - Generated Content

struct GeneratedContent: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let contentType: GeneratedContentType
    let title: String
    let textContent: String
    let audioUrl: String?
    let voiceId: String?
    let duration: Int?
    let qualityScore: Double?
    let status: GeneratedContentStatus
    let generationPrompt: String?
    let aiModel: String?
    let processingTimeMs: Int?
    let triggerWarnings: [String]?
    let averageRating: Double?
    let ratingCount: Int
    let seriesId: UUID?
    let seriesOrder: Int?
    let isFavorite: Bool
    let playCount: Int
    let lastPlayedAt: Date?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case contentType = "content_type"
        case title
        case textContent = "text_content"
        case audioUrl = "audio_url"
        case voiceId = "voice_id"
        case duration
        case qualityScore = "quality_score"
        case status
        case generationPrompt = "generation_prompt"
        case aiModel = "ai_model"
        case processingTimeMs = "processing_time_ms"
        case triggerWarnings = "trigger_warnings"
        case averageRating = "average_rating"
        case ratingCount = "rating_count"
        case seriesId = "series_id"
        case seriesOrder = "series_order"
        case isFavorite = "is_favorite"
        case playCount = "play_count"
        case lastPlayedAt = "last_played_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var formattedDuration: String {
        guard let duration = duration else { return "--" }
        let minutes = duration / 60
        let seconds = duration % 60
        if minutes > 0 {
            return seconds > 0 ? "\(minutes)m \(seconds)s" : "\(minutes) min"
        }
        return "\(seconds)s"
    }

    var hasAudio: Bool {
        audioUrl != nil && !audioUrl!.isEmpty
    }
}

// MARK: - Content Series

struct GeneratedContentSeries: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let title: String
    let description: String?
    let contentType: GeneratedContentType
    let totalParts: Int
    let completedParts: Int
    let theme: String?
    let isActive: Bool
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case description
        case contentType = "content_type"
        case totalParts = "total_parts"
        case completedParts = "completed_parts"
        case theme
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var progress: Double {
        guard totalParts > 0 else { return 0 }
        return Double(completedParts) / Double(totalParts)
    }

    var isComplete: Bool {
        completedParts >= totalParts
    }
}

// MARK: - Content Request

struct GenerateContentRequest: Codable {
    let contentType: GeneratedContentType
    let params: GenerateContentParams

    enum CodingKeys: String, CodingKey {
        case contentType = "contentType"
        case params
    }
}

struct GenerateContentParams: Codable {
    var duration: Int?
    var voiceId: String?
    var backgroundSound: BackgroundSoundType?
    var theme: String?
    var focus: String?
    var approach: String?
    var customPrompt: String?
    var seriesId: String?
    var culturalContext: String?
}

// MARK: - Content Response

struct GenerateContentResponse: Codable {
    let contentId: String
    let status: GeneratedContentStatus
    let textContent: String?
    let audioUrl: String?
    let title: String
    let duration: Int?
    let qualityScore: Double?
    let quotaUsed: Int
    let quotaLimit: Int
    let disclaimer: String
    let triggerWarnings: [String]?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case contentId
        case status
        case textContent
        case audioUrl
        case title
        case duration
        case qualityScore
        case quotaUsed
        case quotaLimit
        case disclaimer
        case triggerWarnings
        case error
    }

    var quotaRemaining: Int {
        quotaLimit - quotaUsed
    }
}

// MARK: - Content Rating

struct ContentRating: Codable, Identifiable {
    let id: UUID
    let contentId: UUID
    let userId: UUID
    let rating: Int
    let helpful: Bool?
    let feedback: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case contentId = "content_id"
        case userId = "user_id"
        case rating
        case helpful
        case feedback
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct RateContentRequest: Codable {
    let contentId: String
    let rating: Int
    let helpful: Bool?
    let feedback: String?
}

struct RateContentResponse: Codable {
    let success: Bool
    let ratingId: String
    let message: String
}

// MARK: - Content Flag

enum ContentFlagReason: String, Codable, CaseIterable {
    case inappropriate
    case inaccurate
    case harmful
    case offensive
    case misleading
    case triggering
    case other

    var displayName: String {
        switch self {
        case .inappropriate: return "Inappropriate"
        case .inaccurate: return "Inaccurate"
        case .harmful: return "Harmful"
        case .offensive: return "Offensive"
        case .misleading: return "Misleading"
        case .triggering: return "Triggering"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .inappropriate: return "exclamationmark.triangle"
        case .inaccurate: return "xmark.circle"
        case .harmful: return "hand.raised"
        case .offensive: return "speaker.slash"
        case .misleading: return "questionmark.circle"
        case .triggering: return "bolt.heart"
        case .other: return "ellipsis.circle"
        }
    }
}

struct FlagContentRequest: Codable {
    let contentId: String
    let reason: ContentFlagReason
    let details: String?
}

struct FlagContentResponse: Codable {
    let success: Bool
    let flagId: String
    let message: String
}

// MARK: - Quota

struct ContentQuotaStatus: Codable {
    let used: Int
    let limit: Int
    let isPremium: Bool
    let resetsAt: Date?

    var remaining: Int { limit - used }
    var percentUsed: Double { Double(used) / Double(limit) }
    var isExhausted: Bool { remaining <= 0 }

    enum CodingKeys: String, CodingKey {
        case used
        case limit
        case isPremium = "is_premium"
        case resetsAt = "resets_at"
    }
}

// MARK: - Default Voices

enum DefaultVoice {
    // English voices
    static let sarah = VoiceOption(
        id: "EXAVITQu4vr4xnSDxMaL",
        name: "Sarah",
        gender: .female,
        style: "calm",
        language: .english,
        previewUrl: "https://assets.mindfriend.app/audio/voices/sarah_preview.mp3",
        sampleText: "Welcome to MindFriend. Take a deep breath and relax."
    )

    static let josh = VoiceOption(
        id: "TxGEqnHWrfWFTfGW9XjX",
        name: "Josh",
        gender: .male,
        style: "warm",
        language: .english,
        previewUrl: "https://assets.mindfriend.app/audio/voices/josh_preview.mp3",
        sampleText: "Let's explore some calming exercises together."
    )

    static let adam = VoiceOption(
        id: "pNInz6obpgDQGcFmaJgB",
        name: "Adam",
        gender: .male,
        style: "deep",
        language: .english,
        previewUrl: "https://assets.mindfriend.app/audio/voices/adam_preview.mp3",
        sampleText: "Focus on your breath and let go of tension."
    )

    static let rachel = VoiceOption(
        id: "21m00Tcm4TlvDq8ikWAM",
        name: "Rachel",
        gender: .female,
        style: "soothing",
        language: .english,
        previewUrl: "https://assets.mindfriend.app/audio/voices/rachel_preview.mp3",
        sampleText: "Close your eyes and imagine a peaceful place."
    )

    static let elli = VoiceOption(
        id: "MF3mGyEYCl7XYWbV9V6O",
        name: "Elli",
        gender: .female,
        style: "whisper",
        language: .english,
        previewUrl: "https://assets.mindfriend.app/audio/voices/elli_preview.mp3",
        sampleText: "You're safe here. Let yourself relax completely."
    )

    // Spanish voices
    static let carla = VoiceOption(
        id: "N2lvsShYGNwcfxAqe4Df",
        name: "Carla",
        gender: .female,
        style: "warm",
        language: .spanish,
        previewUrl: "https://assets.mindfriend.app/audio/voices/carla_preview.mp3",
        sampleText: "Bienvenido a MindFriend. Respira profundamente y relájate."
    )

    static let diego = VoiceOption(
        id: "RPpA2eJQ3GfrTqxDrM7K",
        name: "Diego",
        gender: .male,
        style: "calm",
        language: .spanish,
        previewUrl: "https://assets.mindfriend.app/audio/voices/diego_preview.mp3",
        sampleText: "Cierra los ojos y imagina un lugar tranquilo."
    )

    // Portuguese voices
    static let maria = VoiceOption(
        id: "gDkYD8K7X4kT3q8fW2nP",
        name: "Maria",
        gender: .female,
        style: "gentle",
        language: .portuguese,
        previewUrl: "https://assets.mindfriend.app/audio/voices/maria_preview.mp3",
        sampleText: "Bem-vindo ao MindFriend. Respire profundamente e relaxe."
    )

    static let pedro = VoiceOption(
        id: "hEmBf9L5S6mT4rUhW8oQ",
        name: "Pedro",
        gender: .male,
        style: "soothing",
        language: .portuguese,
        previewUrl: "https://assets.mindfriend.app/audio/voices/pedro_preview.mp3",
        sampleText: "Foque na sua respiração e deixe a tensão ir embora."
    )

    // French voices
    static let amelie = VoiceOption(
        id: "vHpA8cL2M4nT7yWb3zK",
        name: "Amélie",
        gender: .female,
        style: "melodic",
        language: .french,
        previewUrl: "https://assets.mindfriend.app/audio/voices/amelie_preview.mp3",
        sampleText: "Bienvenue sur MindFriend. Respirez profondément et détendez-vous."
    )

    // German voices
    static let greta = VoiceOption(
        id: "kLqC9nO1P3sV5xZb8tD7",
        name: "Greta",
        gender: .female,
        style: "clear",
        language: .german,
        previewUrl: "https://assets.mindfriend.app/audio/voices/greta_preview.mp3",
        sampleText: "Willkommen bei MindFriend. Atmen Sie tief durch und entspannen Sie sich."
    )

    static let lukas = VoiceOption(
        id: "mNrE7fQ2R4uW7yAc9fH5",
        name: "Lukas",
        gender: .male,
        style: "calm",
        language: .german,
        previewUrl: "https://assets.mindfriend.app/audio/voices/lukas_preview.mp3",
        sampleText: "Schließen Sie die Augen und stellen Sie sich einen friedlichen Ort vor."
    )

    // All voices organized by language
    static let all: [VoiceOption] = [
        sarah, josh, adam, rachel, elli,
        carla, diego, maria, pedro, amelie, greta, lukas
    ]

    static func voices(for language: VoiceLanguage) -> [VoiceOption] {
        all.filter { $0.language == language }
    }

    static func voice(for id: String) -> VoiceOption? {
        all.first { $0.id == id }
    }

    static func previewText(for language: VoiceLanguage) -> String {
        switch language {
        case .english: return "Welcome to MindFriend. Take a deep breath and relax."
        case .spanish: return "Bienvenido a MindFriend. Respira profundamente y relájate."
        case .portuguese: return "Bem-vindo ao MindFriend. Respire profundamente e relaxe."
        case .french: return "Bienvenue sur MindFriend. Respirez profondément et détendez-vous."
        case .german: return "Willkommen bei MindFriend. Atmen Sie tief durch und entspannen Sie sich."
        case .italian: return "Benvenuto su MindFriend. Respira profondamente e rilassati."
        case .japanese: return "MindFriendへようこそ。深呼吸してリラックスしてください。"
        case .mandarin: return "欢迎来到MindFriend。深呼吸，放松身心。"
        }
    }
}

// MARK: - Content Disclaimer

enum ContentDisclaimer {
    static let standard = """
    This is AI-generated content designed for relaxation and wellness. \
    It is not a substitute for professional mental health treatment. \
    If you are in crisis, please call 988 or text HOME to 741741.
    """
}
