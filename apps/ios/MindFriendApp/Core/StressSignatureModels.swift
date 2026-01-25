import Foundation

// MARK: - Component Category

/// Categories for signature components
enum SignatureComponentCategory: String, Codable, CaseIterable, Sendable {
    case sleep = "sleep"
    case social = "social"
    case cognitive = "cognitive"
    case emotional = "emotional"
    case behavioral = "behavioral"
    case physical = "physical"

    var displayName: String {
        switch self {
        case .sleep: return "Sleep"
        case .social: return "Social"
        case .cognitive: return "Thinking"
        case .emotional: return "Emotional"
        case .behavioral: return "Behavior"
        case .physical: return "Physical"
        }
    }

    var icon: String {
        switch self {
        case .sleep: return "moon.zzz.fill"
        case .social: return "person.2.fill"
        case .cognitive: return "brain.head.profile"
        case .emotional: return "heart.fill"
        case .behavioral: return "figure.walk"
        case .physical: return "figure.stand"
        }
    }
}

// MARK: - Signature Component (Library)

/// A predefined warning sign component from the library
struct SignatureComponent: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let signalType: String
    let category: SignatureComponentCategory
    let displayName: String
    let description: String
    let defaultThreshold: Double

    enum CodingKeys: String, CodingKey {
        case id
        case signalType = "signal_type"
        case category
        case displayName = "display_name"
        case description
        case defaultThreshold = "default_threshold"
    }

    /// Predefined library of 15 signature components
    static let library: [SignatureComponent] = [
        // Sleep (3)
        SignatureComponent(
            id: UUID(uuidString: "11111111-0001-0001-0001-000000000001")!,
            signalType: "insomnia_wired",
            category: .sleep,
            displayName: "Can't sleep but feel wired",
            description: "Difficulty sleeping despite feeling mentally active or anxious",
            defaultThreshold: 0.6
        ),
        SignatureComponent(
            id: UUID(uuidString: "11111111-0001-0001-0001-000000000002")!,
            signalType: "oversleeping",
            category: .sleep,
            displayName: "Sleeping too much",
            description: "Wanting to sleep 10+ hours or stay in bed all day",
            defaultThreshold: 0.6
        ),
        SignatureComponent(
            id: UUID(uuidString: "11111111-0001-0001-0001-000000000003")!,
            signalType: "early_waking",
            category: .sleep,
            displayName: "Waking up too early",
            description: "Waking at 3-4am and unable to fall back asleep",
            defaultThreshold: 0.6
        ),
        // Social (2)
        SignatureComponent(
            id: UUID(uuidString: "11111111-0001-0001-0002-000000000001")!,
            signalType: "isolation",
            category: .social,
            displayName: "Withdrawing from people",
            description: "Avoiding friends, ignoring messages, canceling plans",
            defaultThreshold: 0.6
        ),
        SignatureComponent(
            id: UUID(uuidString: "11111111-0001-0001-0002-000000000002")!,
            signalType: "irritability",
            category: .social,
            displayName: "Snapping at loved ones",
            description: "Getting unusually irritated with people close to you",
            defaultThreshold: 0.6
        ),
        // Cognitive (3)
        SignatureComponent(
            id: UUID(uuidString: "11111111-0001-0001-0003-000000000001")!,
            signalType: "rumination",
            category: .cognitive,
            displayName: "Can't stop thinking about problems",
            description: "Obsessive thoughts about work, relationships, or mistakes",
            defaultThreshold: 0.6
        ),
        SignatureComponent(
            id: UUID(uuidString: "11111111-0001-0001-0003-000000000002")!,
            signalType: "indecision",
            category: .cognitive,
            displayName: "Can't make decisions",
            description: "Even small decisions feel overwhelming",
            defaultThreshold: 0.6
        ),
        SignatureComponent(
            id: UUID(uuidString: "11111111-0001-0001-0003-000000000003")!,
            signalType: "catastrophizing",
            category: .cognitive,
            displayName: "Worst-case thinking",
            description: "Everything feels like it will lead to disaster",
            defaultThreshold: 0.6
        ),
        // Emotional (2)
        SignatureComponent(
            id: UUID(uuidString: "11111111-0001-0001-0004-000000000001")!,
            signalType: "numbness",
            category: .emotional,
            displayName: "Feeling numb or empty",
            description: "Unable to feel emotions, going through the motions",
            defaultThreshold: 0.6
        ),
        SignatureComponent(
            id: UUID(uuidString: "11111111-0001-0001-0004-000000000002")!,
            signalType: "tearfulness",
            category: .emotional,
            displayName: "Crying easily",
            description: "Tears come unexpectedly or at small triggers",
            defaultThreshold: 0.6
        ),
        // Behavioral (2)
        SignatureComponent(
            id: UUID(uuidString: "11111111-0001-0001-0005-000000000001")!,
            signalType: "procrastination",
            category: .behavioral,
            displayName: "Avoiding responsibilities",
            description: "Putting off work, chores, or important tasks",
            defaultThreshold: 0.6
        ),
        SignatureComponent(
            id: UUID(uuidString: "11111111-0001-0001-0005-000000000002")!,
            signalType: "compulsions",
            category: .behavioral,
            displayName: "Stress behaviors",
            description: "Nail biting, skin picking, or other nervous habits",
            defaultThreshold: 0.6
        ),
        // Physical (3)
        SignatureComponent(
            id: UUID(uuidString: "11111111-0001-0001-0006-000000000001")!,
            signalType: "appetite_change",
            category: .physical,
            displayName: "Appetite changes",
            description: "Eating much more or much less than usual",
            defaultThreshold: 0.6
        ),
        SignatureComponent(
            id: UUID(uuidString: "11111111-0001-0001-0006-000000000002")!,
            signalType: "tension",
            category: .physical,
            displayName: "Physical tension",
            description: "Headaches, jaw clenching, shoulder tightness",
            defaultThreshold: 0.6
        ),
        SignatureComponent(
            id: UUID(uuidString: "11111111-0001-0001-0006-000000000003")!,
            signalType: "low_energy",
            category: .physical,
            displayName: "Low energy",
            description: "Feeling exhausted even after rest, no motivation",
            defaultThreshold: 0.6
        )
    ]

    /// Get components by category
    static func components(for category: SignatureComponentCategory) -> [SignatureComponent] {
        library.filter { $0.category == category }
    }

    /// Find component by signal type
    static func component(for signalType: String) -> SignatureComponent? {
        library.first { $0.signalType == signalType }
    }
}

// MARK: - Crisis Type

/// Types of crisis patterns
enum CrisisType: String, Codable, CaseIterable, Sendable {
    case anxiety = "anxiety"
    case depression = "depression"
    case burnout = "burnout"
    case panic = "panic"
    case general = "general"

    var displayName: String {
        switch self {
        case .anxiety: return "Anxiety"
        case .depression: return "Depression"
        case .burnout: return "Burnout"
        case .panic: return "Panic"
        case .general: return "General"
        }
    }
}

// MARK: - Weighted Component

/// A component within a user's signature with personalized weight and threshold
struct WeightedComponent: Codable, Hashable, Sendable {
    let componentId: UUID
    let signal: String
    var weight: Double
    var detectionThreshold: Double
    var lastActive: Date?

    enum CodingKeys: String, CodingKey {
        case componentId = "component_id"
        case signal
        case weight
        case detectionThreshold = "detection_threshold"
        case lastActive = "last_active"
    }

    /// Create from a library component with default values
    static func from(component: SignatureComponent) -> WeightedComponent {
        WeightedComponent(
            componentId: component.id,
            signal: component.signalType,
            weight: 0.5,
            detectionThreshold: component.defaultThreshold,
            lastActive: nil
        )
    }
}

// MARK: - Signature Source

/// Source of how the signature was created
enum SignatureSource: String, Codable, Sendable {
    case userReported = "user_reported"
    case historicalLearned = "historical_learned"
    case hybridRefined = "hybrid_refined"

    var displayName: String {
        switch self {
        case .userReported: return "Self-Reported"
        case .historicalLearned: return "Learned from History"
        case .hybridRefined: return "Refined Over Time"
        }
    }
}

// MARK: - Warning Signature (F026 Early Warning Fingerprint)

/// User's personalized warning signature containing weighted warning sign components
/// Named WarningSignature to avoid conflict with existing StressSignature type
struct WarningSignature: Codable, Identifiable, Sendable {
    let id: UUID
    let userId: UUID
    let crisisType: CrisisType
    var components: [WeightedComponent]
    var source: SignatureSource
    var confidence: Double
    var detectionSensitivity: Double
    let lastLearnedAt: Date?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case crisisType = "crisis_type"
        case components
        case source
        case confidence
        case detectionSensitivity = "detection_sensitivity"
        case lastLearnedAt = "last_learned_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Create a new signature from selected components
    static func create(
        userId: UUID,
        crisisType: CrisisType = .general,
        selectedComponentIds: Set<UUID>
    ) -> WarningSignature {
        let components = selectedComponentIds.compactMap { id -> WeightedComponent? in
            guard let component = SignatureComponent.library.first(where: { $0.id == id }) else {
                return nil
            }
            return WeightedComponent.from(component: component)
        }

        return WarningSignature(
            id: UUID(),
            userId: userId,
            crisisType: crisisType,
            components: components,
            source: .userReported,
            confidence: 0.5,
            detectionSensitivity: 0.5,
            lastLearnedAt: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    /// Get component display info
    func componentDisplayInfo() -> [(component: SignatureComponent, weighted: WeightedComponent)] {
        components.compactMap { weighted in
            guard let component = SignatureComponent.component(for: weighted.signal) else {
                return nil
            }
            return (component, weighted)
        }
    }
}

// MARK: - Active Signal

/// A signal that's currently active above threshold
struct ActiveSignal: Codable, Hashable, Sendable {
    let componentId: UUID
    let signal: String
    let detectedValue: Double
    let threshold: Double
    let daysActive: Int

    enum CodingKeys: String, CodingKey {
        case componentId = "component_id"
        case signal
        case detectedValue = "detected_value"
        case threshold
        case daysActive = "days_active"
    }
}

// MARK: - Alert Severity

/// Severity level of a pattern alert
enum AlertSeverity: String, Codable, Sendable {
    case mild = "mild"
    case moderate = "moderate"
    case severe = "severe"

    var displayName: String {
        switch self {
        case .mild: return "Mild"
        case .moderate: return "Moderate"
        case .severe: return "Severe"
        }
    }

    var color: String {
        switch self {
        case .mild: return "yellow"
        case .moderate: return "orange"
        case .severe: return "red"
        }
    }
}

// MARK: - Intervention Tier

/// Tier of intervention based on pattern severity
enum InterventionTier: String, Codable, Sendable {
    case gentle = "gentle"
    case moderate = "moderate"
    case immediate = "immediate"

    var displayName: String {
        switch self {
        case .gentle: return "Gentle Check-in"
        case .moderate: return "Active Support"
        case .immediate: return "Priority Care"
        }
    }
}

// MARK: - Alert Feedback

/// User feedback on prediction accuracy
enum AlertFeedback: String, Codable, Sendable {
    case accuratePrediction = "accurate_prediction"
    case falseAlarm = "false_alarm"
    case helpedPrevent = "helped_prevent"
    case missedPattern = "missed_pattern"

    var displayName: String {
        switch self {
        case .accuratePrediction: return "This was accurate"
        case .falseAlarm: return "This was a false alarm"
        case .helpedPrevent: return "The intervention helped"
        case .missedPattern: return "I had a crisis without warning"
        }
    }

    var isPositive: Bool {
        switch self {
        case .accuratePrediction, .helpedPrevent: return true
        case .falseAlarm, .missedPattern: return false
        }
    }
}

// MARK: - Pattern Alert

/// An alert generated when pattern emergence is detected
struct PatternAlert: Codable, Identifiable, Sendable {
    let id: UUID
    let userId: UUID
    let signatureId: UUID
    let detectedAt: Date
    let activeComponents: [ActiveSignal]
    let emergenceScore: Double
    let severity: AlertSeverity
    let predictedTimeToEvent: Int? // seconds
    let interventionTier: InterventionTier
    var interventionDelivered: Bool
    var interventionDeliveredAt: Date?
    var userFeedback: AlertFeedback?
    var feedbackNotes: String?
    var feedbackAt: Date?
    var dismissedAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case signatureId = "signature_id"
        case detectedAt = "detected_at"
        case activeComponents = "active_components"
        case emergenceScore = "emergence_score"
        case severity
        case predictedTimeToEvent = "predicted_time_to_event"
        case interventionTier = "intervention_tier"
        case interventionDelivered = "intervention_delivered"
        case interventionDeliveredAt = "intervention_delivered_at"
        case userFeedback = "user_feedback"
        case feedbackNotes = "feedback_notes"
        case feedbackAt = "feedback_at"
        case dismissedAt = "dismissed_at"
        case createdAt = "created_at"
    }

    /// Predicted hours to crisis event
    var predictedHours: Int? {
        guard let seconds = predictedTimeToEvent else { return nil }
        return seconds / 3600
    }

    /// Get display names for active components
    var activeComponentNames: [String] {
        activeComponents.compactMap { active in
            SignatureComponent.component(for: active.signal)?.displayName
        }
    }

    /// Check if alert is active (not dismissed)
    var isActive: Bool {
        dismissedAt == nil
    }
}

// MARK: - Signature Signal

/// A real-time signal measurement
struct SignatureSignal: Codable, Identifiable, Sendable {
    let id: UUID
    let userId: UUID
    let signalType: String
    let value: Double
    let date: Date
    let source: SignalSource
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case signalType = "signal_type"
        case value
        case date
        case source
        case createdAt = "created_at"
    }
}

// MARK: - Signal Source

/// Source of a signal measurement
enum SignalSource: String, Codable, Sendable {
    case healthkit = "healthkit"
    case appActivity = "app_activity"
    case cognitiveDetection = "cognitive_detection"
    case nervousSystem = "nervous_system"
    case socialVitality = "social_vitality"
    case wellbeingDebt = "wellbeing_debt"
    case userInput = "user_input"
}

// MARK: - Crisis Event

/// A user-reported or detected crisis event
struct CrisisEvent: Codable, Identifiable, Sendable {
    let id: UUID
    let userId: UUID
    let conversationId: UUID?
    let crisisType: CrisisType
    let occurredAt: Date
    let severity: AlertSeverity
    let userReported: Bool
    let analyzed: Bool
    let detectedAt: Date
    let handled: Bool
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case conversationId = "conversation_id"
        case crisisType = "crisis_type"
        case occurredAt = "occurred_at"
        case severity
        case userReported = "user_reported"
        case analyzed
        case detectedAt = "detected_at"
        case handled
        case notes
    }
}

// MARK: - Pattern Emergence Result

/// Result of pattern detection analysis
struct PatternEmergenceResult: Sendable {
    let isEmerging: Bool
    let emergenceScore: Double
    let activeComponents: [ActiveSignal]
    let estimatedTimeToEvent: Int? // seconds
    let recommendedTier: InterventionTier
    let severity: AlertSeverity

    /// Calculate severity from active component count
    static func calculateSeverity(activeCount: Int) -> AlertSeverity {
        switch activeCount {
        case 0...2: return .mild
        case 3...4: return .moderate
        default: return .severe
        }
    }

    /// Calculate intervention tier from emergence score
    static func calculateTier(emergenceScore: Double) -> InterventionTier {
        if emergenceScore >= 0.8 { return .immediate }
        if emergenceScore >= 0.6 { return .moderate }
        return .gentle
    }
}

// MARK: - Accuracy Stats

/// Statistics on prediction accuracy
struct SignatureAccuracyStats: Sendable {
    let totalAlerts: Int
    let accuratePredictions: Int
    let falseAlarms: Int
    let helpedPrevent: Int
    let missedPatterns: Int

    var accuracyRate: Double {
        guard totalAlerts > 0 else { return 0 }
        return Double(accuratePredictions + helpedPrevent) / Double(totalAlerts)
    }

    var accuracyPercentage: Int {
        Int(accuracyRate * 100)
    }
}

// MARK: - Signal Update

/// Update for a signal measurement
struct SignalUpdate: Sendable {
    let signalType: String
    let value: Double
    let source: SignalSource
    let timestamp: Date

    init(signalType: String, value: Double, source: SignalSource, timestamp: Date = Date()) {
        self.signalType = signalType
        self.value = min(max(value, 0.0), 1.0) // Clamp to 0-1
        self.source = source
        self.timestamp = timestamp
    }
}

// MARK: - Errors

enum StressSignatureError: LocalizedError {
    case signatureNotInitialized
    case insufficientData
    case detectionFailed
    case integrationUnavailable(String)
    case networkError
    case invalidConfiguration
    case invalidInput(String)

    var errorDescription: String? {
        switch self {
        case .signatureNotInitialized:
            return "Stress signature not initialized. Please complete setup first."
        case .insufficientData:
            return "Not enough data to learn patterns. Continue using the app to build your profile."
        case .detectionFailed:
            return "Pattern detection failed. Please try again."
        case .integrationUnavailable(let service):
            return "\(service) integration is not available."
        case .networkError:
            return "Network error. Please check your connection."
        case .invalidConfiguration:
            return "Invalid configuration. Please contact support."
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        }
    }
}
