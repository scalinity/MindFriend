// AIConsent.swift
// Per-feature AI consent state for App Store guidelines 5.1.1(i) / 5.1.2(i).

import Foundation

enum AIFeature: String, CaseIterable, Codable, Identifiable {
    case chat
    case journalAI = "journal_ai"
    case voiceJournalAI = "voice_journal_ai"
    case imageGen = "image_gen"
    case insights
    case ttsVoice = "tts_voice"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chat:           return NSLocalizedString("ai.feature.chat", value: "AI chat companion", comment: "")
        case .journalAI:      return NSLocalizedString("ai.feature.journal_ai", value: "AI analysis of journals & reflections", comment: "")
        case .voiceJournalAI: return NSLocalizedString("ai.feature.voice_journal_ai", value: "AI voice journaling", comment: "")
        case .imageGen:       return NSLocalizedString("ai.feature.image_gen", value: "AI image generation", comment: "")
        case .insights:       return NSLocalizedString("ai.feature.insights", value: "AI insights & summaries", comment: "")
        case .ttsVoice:       return NSLocalizedString("ai.feature.tts_voice", value: "Spoken meditation playback", comment: "")
        }
    }

    var providerName: String {
        switch self {
        case .chat, .journalAI, .voiceJournalAI, .insights: return "xAI"
        case .imageGen: return "OpenAI"
        case .ttsVoice: return "Google Cloud TTS"
        }
    }

    var dataSentDescription: String {
        switch self {
        case .chat:
            return NSLocalizedString("ai.feature.chat.desc",
                value: "Your messages and the last 20 messages of conversation context.",
                comment: "")
        case .journalAI:
            return NSLocalizedString("ai.feature.journal_ai.desc",
                value: "The text you choose to enter in journals, thought records, and reflection prompts.",
                comment: "")
        case .voiceJournalAI:
            return NSLocalizedString("ai.feature.voice_journal_ai.desc",
                value: "Audio you record and its transcribed text.",
                comment: "")
        case .imageGen:
            return NSLocalizedString("ai.feature.image_gen.desc",
                value: "Prompts you write or that are generated from your journal entries to create artwork and profile pictures.",
                comment: "")
        case .insights:
            return NSLocalizedString("ai.feature.insights.desc",
                value: "Mood ratings, completed quests, and aggregated activity history used to generate your weekly story and pattern insights.",
                comment: "")
        case .ttsVoice:
            return NSLocalizedString("ai.feature.tts_voice.desc",
                value: "The text of guided meditations, sent for text-to-speech synthesis.",
                comment: "")
        }
    }
}

enum ConsentState: String, Codable {
    case unknown
    case granted
    case denied
}

enum AIConsent {
    /// IMPORTANT: Mirror this with the backend constant in supabase/functions/_shared/ai-consent.ts.
    /// When bumping, also ship a Postgres migration that updates the
    /// `policy_version <= N` predicate in ai_consents_self_insert/update RLS policies.
    static let currentPolicyVersion = 1

    /// EEA + UK + Switzerland — locales where the consent gate defaults to opt-in (toggles off)
    /// per GDPR / UK GDPR / Swiss FADP.
    static let euOptInRegions: Set<String> = [
        "AT","BE","BG","HR","CY","CZ","DK","EE","FI","FR","DE","GR",
        "HU","IS","IE","IT","LV","LI","LT","LU","MT","NL","NO","PL",
        "PT","RO","SK","SI","ES","SE","GB","CH",
    ]

    static var defaultsToOptIn: Bool {
        guard let region = Locale.current.region?.identifier else { return false }
        return euOptInRegions.contains(region)
    }
}

struct AIConsentRecord: Codable, Equatable, Identifiable {
    let userId: UUID
    let feature: AIFeature
    var state: ConsentState
    var grantedAt: Date?
    var revokedAt: Date?
    var policyVersion: Int
    var updatedAt: Date

    var id: String { "\(userId.uuidString):\(feature.rawValue)" }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case feature
        case state
        case grantedAt = "granted_at"
        case revokedAt = "revoked_at"
        case policyVersion = "policy_version"
        case updatedAt = "updated_at"
    }
}

/// Thrown when an AI-touching call is rejected because the user has not granted consent.
struct AIConsentRequiredError: LocalizedError {
    let feature: AIFeature
    var errorDescription: String? {
        "AI consent required for \(feature.displayName)."
    }
}
