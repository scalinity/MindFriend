// SOSModels.swift
// MindFriend - SOS Panic Button Feature Models

import Foundation
import SwiftUI

// MARK: - SOS Event

/// A logged SOS panic button activation event
struct SOSEvent: Identifiable, Codable, Equatable {
    let id: String
    let userId: String
    let startedAt: Date
    var endedAt: Date?
    var triggerLocation: String?
    var moodBefore: Int?
    var moodAfter: Int?
    var completedPhases: [String]
    var wasInterrupted: Bool
    var interventionDurationSeconds: Int?
    var helpfulnessRating: Int?
    var notes: String?
    var familyAlertSent: Bool
    var contactNotified: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case triggerLocation = "trigger_location"
        case moodBefore = "mood_before"
        case moodAfter = "mood_after"
        case completedPhases = "completed_phases"
        case wasInterrupted = "was_interrupted"
        case interventionDurationSeconds = "intervention_duration_seconds"
        case helpfulnessRating = "helpfulness_rating"
        case notes
        case familyAlertSent = "family_alert_sent"
        case contactNotified = "contact_notified"
        case createdAt = "created_at"
    }

    /// Whether the intervention was completed successfully (not cancelled/interrupted)
    var completedSuccessfully: Bool {
        endedAt != nil && !wasInterrupted && !completedPhases.isEmpty
    }

    /// Create a new SOS event at the start of intervention
    static func create(userId: String, triggerLocation: String?) -> SOSEvent {
        SOSEvent(
            id: UUID().uuidString,
            userId: userId,
            startedAt: Date(),
            endedAt: nil,
            triggerLocation: triggerLocation,
            moodBefore: nil,
            moodAfter: nil,
            completedPhases: [],
            wasInterrupted: false,
            interventionDurationSeconds: nil,
            helpfulnessRating: nil,
            notes: nil,
            familyAlertSent: false,
            contactNotified: false,
            createdAt: Date()
        )
    }
}

// MARK: - SOS Settings

/// User preferences for SOS panic button feature
struct SOSSettings: Codable, Equatable {
    var id: UUID?
    let userId: String
    var sosEnabled: Bool
    var autoNotifyEnabled: Bool
    var autoNotifyContacts: Bool  // Alias for autoNotifyEnabled (view compatibility)
    var emergencyContactName: String?
    var emergencyContactPhone: String?
    var preferredBreathingPattern: BreathingPattern
    var countdownSeconds: Int
    var includeBreathing: Bool
    var includeGrounding: Bool
    var includeVoiceGuidance: Bool
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case sosEnabled = "sos_enabled"
        case autoNotifyEnabled = "auto_notify_enabled"
        case emergencyContactName = "emergency_contact_name"
        case emergencyContactPhone = "emergency_contact_phone"
        case preferredBreathingPattern = "preferred_breathing_pattern"
        case countdownSeconds = "countdown_seconds"
        case includeBreathing = "include_breathing"
        case includeGrounding = "include_grounding"
        case includeVoiceGuidance = "include_voice_guidance"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // Custom encoding to exclude autoNotifyContacts alias
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(sosEnabled, forKey: .sosEnabled)
        try container.encode(autoNotifyEnabled, forKey: .autoNotifyEnabled)
        try container.encodeIfPresent(emergencyContactName, forKey: .emergencyContactName)
        try container.encodeIfPresent(emergencyContactPhone, forKey: .emergencyContactPhone)
        try container.encode(preferredBreathingPattern, forKey: .preferredBreathingPattern)
        try container.encode(countdownSeconds, forKey: .countdownSeconds)
        try container.encode(includeBreathing, forKey: .includeBreathing)
        try container.encode(includeGrounding, forKey: .includeGrounding)
        try container.encode(includeVoiceGuidance, forKey: .includeVoiceGuidance)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    // Custom decoding to set autoNotifyContacts from autoNotifyEnabled
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        sosEnabled = try container.decodeIfPresent(Bool.self, forKey: .sosEnabled) ?? true
        autoNotifyEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoNotifyEnabled) ?? false
        autoNotifyContacts = autoNotifyEnabled  // Sync alias
        emergencyContactName = try container.decodeIfPresent(String.self, forKey: .emergencyContactName)
        emergencyContactPhone = try container.decodeIfPresent(String.self, forKey: .emergencyContactPhone)
        preferredBreathingPattern = try container.decodeIfPresent(BreathingPattern.self, forKey: .preferredBreathingPattern) ?? .calm478
        countdownSeconds = try container.decodeIfPresent(Int.self, forKey: .countdownSeconds) ?? 3
        includeBreathing = try container.decodeIfPresent(Bool.self, forKey: .includeBreathing) ?? true
        includeGrounding = try container.decodeIfPresent(Bool.self, forKey: .includeGrounding) ?? true
        includeVoiceGuidance = try container.decodeIfPresent(Bool.self, forKey: .includeVoiceGuidance) ?? true
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }

    /// Memberwise initializer
    init(
        id: UUID? = nil,
        userId: String,
        sosEnabled: Bool = true,
        autoNotifyEnabled: Bool = false,
        emergencyContactName: String? = nil,
        emergencyContactPhone: String? = nil,
        preferredBreathingPattern: BreathingPattern = .calm478,
        countdownSeconds: Int = 3,
        includeBreathing: Bool = true,
        includeGrounding: Bool = true,
        includeVoiceGuidance: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.sosEnabled = sosEnabled
        self.autoNotifyEnabled = autoNotifyEnabled
        self.autoNotifyContacts = autoNotifyEnabled  // Keep in sync
        self.emergencyContactName = emergencyContactName
        self.emergencyContactPhone = emergencyContactPhone
        self.preferredBreathingPattern = preferredBreathingPattern
        self.countdownSeconds = countdownSeconds
        self.includeBreathing = includeBreathing
        self.includeGrounding = includeGrounding
        self.includeVoiceGuidance = includeVoiceGuidance
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Default settings for new users
    static func defaults(userId: String) -> SOSSettings {
        SOSSettings(
            id: nil,
            userId: userId,
            sosEnabled: true,
            autoNotifyEnabled: false,
            emergencyContactName: nil,
            emergencyContactPhone: nil,
            preferredBreathingPattern: .calm478,
            countdownSeconds: 3,
            includeBreathing: true,
            includeGrounding: true,
            includeVoiceGuidance: true,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    /// Whether an emergency contact is configured
    var hasEmergencyContact: Bool {
        guard let phone = emergencyContactPhone else { return false }
        return !phone.isEmpty
    }
}

// MARK: - Breathing Pattern

/// Available breathing patterns for SOS intervention
enum BreathingPattern: String, Codable, CaseIterable, Identifiable {
    case boxBreathing = "box_breathing"
    case simple = "simple"
    case calm478 = "calm_478"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .boxBreathing: return "Box Breathing"
        case .simple: return "Simple Breaths"
        case .calm478: return "4-7-8 Calming"
        }
    }

    var description: String {
        switch self {
        case .boxBreathing: return "4 seconds each: inhale, hold, exhale, hold"
        case .simple: return "4 seconds inhale, 4 seconds exhale"
        case .calm478: return "4 seconds inhale, 7 hold, 8 exhale"
        }
    }

    /// Breathing phases with durations in seconds
    var phases: [(name: String, instruction: String, duration: TimeInterval)] {
        switch self {
        case .boxBreathing:
            return [
                ("inhale", "Breathe in", 4),
                ("hold", "Hold", 4),
                ("exhale", "Breathe out", 4),
                ("hold", "Hold", 4)
            ]
        case .simple:
            return [
                ("inhale", "Breathe in", 4),
                ("exhale", "Breathe out", 4)
            ]
        case .calm478:
            return [
                ("inhale", "Breathe in", 4),
                ("hold", "Hold", 7),
                ("exhale", "Breathe out", 8)
            ]
        }
    }

    /// Duration for inhale phase in seconds
    var inhaleSeconds: Int {
        switch self {
        case .boxBreathing: return 4
        case .simple: return 4
        case .calm478: return 4
        }
    }

    /// Duration for hold after inhale in seconds (0 if no hold)
    var holdAfterInhaleSeconds: Int {
        switch self {
        case .boxBreathing: return 4
        case .simple: return 0
        case .calm478: return 7
        }
    }

    /// Duration for exhale phase in seconds
    var exhaleSeconds: Int {
        switch self {
        case .boxBreathing: return 4
        case .simple: return 4
        case .calm478: return 8
        }
    }

    /// Duration for hold after exhale in seconds (0 if no hold)
    var holdAfterExhaleSeconds: Int {
        switch self {
        case .boxBreathing: return 4
        case .simple: return 0
        case .calm478: return 0
        }
    }

    /// Total duration of one complete cycle in seconds
    var cycleDuration: TimeInterval {
        phases.reduce(0) { $0 + $1.duration }
    }

    /// Default number of breathing cycles
    var defaultCycles: Int {
        switch self {
        case .boxBreathing: return 4
        case .simple: return 5
        case .calm478: return 3
        }
    }
}

// MARK: - SOS Phase

/// Current phase of the SOS intervention
enum SOSPhase: Equatable {
    case ready
    case countdown(remaining: Int)
    case breathing(cycleIndex: Int, totalCycles: Int, phaseIndex: Int)
    case grounding(sense: GroundingSense)
    case resources
    case checkIn
    case complete
    case cancelled
    case error(message: String)

    var isActive: Bool {
        switch self {
        case .ready, .complete, .cancelled, .error:
            return false
        default:
            return true
        }
    }

    var phaseName: String {
        switch self {
        case .ready: return "ready"
        case .countdown: return "countdown"
        case .breathing: return "breathing"
        case .grounding: return "grounding"
        case .resources: return "resources"
        case .checkIn: return "checkin"
        case .complete: return "complete"
        case .cancelled: return "cancelled"
        case .error: return "error"
        }
    }
}

// MARK: - Grounding Sense

/// Senses for the 5-4-3-2-1 grounding technique
enum GroundingSense: Int, CaseIterable, Identifiable {
    case see = 5
    case touch = 4
    case hear = 3
    case smell = 2
    case taste = 1

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .see: return "See"
        case .touch: return "Touch"
        case .hear: return "Hear"
        case .smell: return "Smell"
        case .taste: return "Taste"
        }
    }

    var prompt: String {
        switch self {
        case .see: return "Name 5 things you can SEE around you"
        case .touch: return "Name 4 things you can TOUCH or feel"
        case .hear: return "Name 3 things you can HEAR"
        case .smell: return "Name 2 things you can SMELL"
        case .taste: return "Name 1 thing you can TASTE"
        }
    }

    var icon: String {
        switch self {
        case .see: return "eye.fill"
        case .touch: return "hand.raised.fill"
        case .hear: return "ear.fill"
        case .smell: return "nose.fill"
        case .taste: return "mouth.fill"
        }
    }

    var color: Color {
        switch self {
        case .see: return .blue
        case .touch: return .green
        case .hear: return .purple
        case .smell: return .orange
        case .taste: return .pink
        }
    }

    /// Next sense in the sequence, nil if this is the last one
    var next: GroundingSense? {
        let allCases = GroundingSense.allCases.sorted { $0.rawValue > $1.rawValue }
        guard let currentIndex = allCases.firstIndex(of: self),
              currentIndex + 1 < allCases.count else {
            return nil
        }
        return allCases[currentIndex + 1]
    }

    /// All senses in order from 5 to 1
    static var orderedSenses: [GroundingSense] {
        allCases.sorted { $0.rawValue > $1.rawValue }
    }
}

// MARK: - Grounding Exercise

/// Static content for the 5-4-3-2-1 grounding exercise
struct GroundingExercise {
    /// Steps for the 5-4-3-2-1 grounding technique
    static let steps: [(count: Int, sense: GroundingSense, prompt: String, examples: [String])] = [
        (5, .see, "Name 5 things you can SEE around you", ["A window", "A plant", "Your hands", "A light", "The ceiling"]),
        (4, .touch, "Name 4 things you can TOUCH or feel", ["Your clothes", "The floor", "Your hair", "Your phone"]),
        (3, .hear, "Name 3 things you can HEAR", ["Your breathing", "Background noise", "Birds"]),
        (2, .smell, "Name 2 things you can SMELL", ["Fresh air", "Your soap"]),
        (1, .taste, "Name 1 thing you can TASTE", ["Water", "Coffee"])
    ]

    /// Introduction text for the grounding exercise
    static let introText = """
        Let's ground you in the present moment.
        This technique uses your five senses to bring you back to now.
        Take your time with each step.
        """

    /// Completion text
    static let completionText = """
        Well done. You've reconnected with the present moment.
        Notice how you feel now compared to before.
        """
}

// MARK: - SOS Haptic Type

/// Types of haptic feedback during SOS intervention
enum SOSHapticType {
    case sosStart       // Heavy impact on SOS activation
    case countdownTick  // Rigid impact each countdown second
    case inhale         // Medium impact at start of inhale
    case hold           // Soft continuous during hold
    case exhale         // Light impact at start of exhale
    case phaseComplete  // Success notification at phase end
    case groundingTap   // Light tap for grounding advancement
    case complete       // Success notification at intervention end
    case phaseStart     // Medium impact at phase start
    case gentleEnd      // Soft notification at gentle completion
    case success        // Success notification (alias for complete)
}

// MARK: - Offline SOS Event

/// Wrapper for offline-queued SOS events pending sync
struct OfflineSOSEvent: Codable, Identifiable {
    let event: SOSEvent
    let queuedAt: Date

    var id: String { event.id }
}
