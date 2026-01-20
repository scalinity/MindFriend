//
//  LocalizationModels.swift
//  MindFriendApp
//
//  Created by dev-pipeline on 2026-01-19.
//  Multi-language localization models
//

import Foundation

// MARK: - Supported Language

/// Represents a language supported by the app
struct SupportedLanguage: Codable, Identifiable, Equatable {
    let code: String
    let name: String
    let nativeName: String
    let direction: String
    let isActive: Bool
    let translationCoverage: Double
    let createdAt: Date

    var id: String { code }
    var isRTL: Bool { direction == "rtl" }

    enum CodingKeys: String, CodingKey {
        case code
        case name
        case nativeName = "native_name"
        case direction
        case isActive = "is_active"
        case translationCoverage = "translation_coverage"
        case createdAt = "created_at"
    }
}

// MARK: - UI Translation

/// Represents a translated UI string (button, label, message)
struct UITranslation: Codable {
    let id: UUID
    let stringKey: String
    let languageCode: String
    let translation: String
    let context: String?
    let isVerified: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case stringKey = "string_key"
        case languageCode = "language_code"
        case translation
        case context
        case isVerified = "is_verified"
    }
}

// MARK: - Content Translation

/// Represents translated content (exercises, quests, badges)
struct ContentTranslation: Codable {
    let id: UUID
    let contentType: String
    let contentId: UUID
    let languageCode: String
    let title: String?
    let description: String?
    let content: String?
    let instructions: ExerciseInstructions?
    let isVerified: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case contentType = "content_type"
        case contentId = "content_id"
        case languageCode = "language_code"
        case title
        case description
        case content
        case instructions
        case isVerified = "is_verified"
    }
}

/// Structured instructions for exercises with multiple steps
struct ExerciseInstructions: Codable, Equatable {
    let steps: [ExerciseStep]
}

/// Individual step within exercise instructions
struct ExerciseStep: Codable, Equatable {
    let order: Int
    let text: String
    let durationSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case order
        case text
        case durationSeconds = "duration_seconds"
    }
}

// MARK: - Crisis Resources

/// Database model for localized crisis resources
struct LocalizedCrisisResources: Codable {
    let id: UUID
    let countryCode: String
    let languageCode: String
    let emergencyNumber: String
    let crisisHotline: String?
    let crisisHotlineName: String?
    let crisisTextLine: String?
    let crisisWebsite: String?
    let introMessage: String
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case countryCode = "country_code"
        case languageCode = "language_code"
        case emergencyNumber = "emergency_number"
        case crisisHotline = "crisis_hotline"
        case crisisHotlineName = "crisis_hotline_name"
        case crisisTextLine = "crisis_text_line"
        case crisisWebsite = "crisis_website"
        case introMessage = "intro_message"
        case isActive = "is_active"
    }
}

/// Client-side crisis resources model (simplified for UI)
struct CrisisResources {
    let emergencyNumber: String
    let hotline: String?
    let hotlineName: String?
    let textLine: String?
    let website: String?
    let introMessage: String

    /// Initialize from localized database model
    init(from localized: LocalizedCrisisResources) {
        self.emergencyNumber = localized.emergencyNumber
        self.hotline = localized.crisisHotline
        self.hotlineName = localized.crisisHotlineName
        self.textLine = localized.crisisTextLine
        self.website = localized.crisisWebsite
        self.introMessage = localized.introMessage
    }

    /// Hardcoded US default fallback (always available offline)
    static let usDefault = CrisisResources(
        emergencyNumber: "911",
        hotline: "988",
        hotlineName: "Suicide & Crisis Lifeline",
        textLine: "Text HOME to 741741",
        website: "https://988lifeline.org",
        introMessage: "If you're in crisis, help is available 24/7."
    )

    /// Direct initializer for creating resources
    init(
        emergencyNumber: String,
        hotline: String? = nil,
        hotlineName: String? = nil,
        textLine: String? = nil,
        website: String? = nil,
        introMessage: String
    ) {
        self.emergencyNumber = emergencyNumber
        self.hotline = hotline
        self.hotlineName = hotlineName
        self.textLine = textLine
        self.website = website
        self.introMessage = introMessage
    }
}
