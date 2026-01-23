import Foundation
import Supabase
import OSLog

/// Main orchestrator for nervous system state classification
@MainActor
final class NervousSystemStateEngine: ObservableObject {
    // MARK: - Properties

    private let voiceExtractor: VoicePolyvagalExtractor
    private let hrvExtractor: HRVPolyvagalExtractor
    private let behavioralTracker: BehavioralPolyvagalTracker
    private let classifier: PolyvagalClassifier
    private let cascadeDetector: CascadeDetector
    private let interventionRecommender: InterventionRecommender
    private let supabase: SupabaseClient
    private let logger = Logger(subsystem: "com.mindfriend", category: "NervousSystemStateEngine")

    // Published state
    @Published private(set) var currentState: NervousSystemState?
    @Published private(set) var currentConfidence: Double = 0
    @Published private(set) var lastClassificationTime: Date?
    @Published private(set) var isClassifying = false

    // Configuration
    private let latencyBudget: TimeInterval = 0.8 // 800ms
    private let minConfidenceThreshold = 0.6
    
    // PERFORMANCE: Shared encoder instances to avoid repeated allocation
    private let jsonEncoder = JSONEncoder()
    private let isoDateFormatter = ISO8601DateFormatter()

    // MARK: - Initialization

    init(
        voiceExtractor: VoicePolyvagalExtractor,
        hrvExtractor: HRVPolyvagalExtractor,
        behavioralTracker: BehavioralPolyvagalTracker,
        classifier: PolyvagalClassifier,
        cascadeDetector: CascadeDetector,
        interventionRecommender: InterventionRecommender,
        supabase: SupabaseClient
    ) {
        self.voiceExtractor = voiceExtractor
        self.hrvExtractor = hrvExtractor
        self.behavioralTracker = behavioralTracker
        self.classifier = classifier
        self.cascadeDetector = cascadeDetector
        self.interventionRecommender = interventionRecommender
        self.supabase = supabase
    }

    // MARK: - Public Interface - Real-Time Classification

    /// Classify state from voice emotions (during voice session)
    /// - Parameters:
    ///   - voiceEmotions: Recent emotion predictions from EmotionAnalyzer
    ///   - timestamp: Classification timestamp
    /// - Returns: Classified nervous system state
    func classifyState(
        voiceEmotions: [EmotionPrediction],
        timestamp: Date = Date()
    ) async throws -> NervousSystemState {
        let startTime = Date()
        isClassifying = true
        defer { isClassifying = false }

        // Extract features in parallel
        async let voiceFeatures = extractVoiceFeatures(from: voiceEmotions)
        async let hrvFeatures = extractHRVFeatures()
        let behavioralFeatures = behavioralTracker.getCurrentBehavioralFeatures()

        // Classify
        let result = try await classifier.classify(
            voice: voiceFeatures,
            hrv: hrvFeatures,
            behavioral: behavioralFeatures
        )

        // Check latency budget
        let latency = Date().timeIntervalSince(startTime)
        if latency > latencyBudget {
            logger.warning("Classification exceeded latency budget: \(Int(latency * 1000))ms")
        }

        // Store state record
        try await storeStateRecord(
            result: result,
            voiceFeatures: voiceFeatures,
            hrvFeatures: hrvFeatures,
            behavioralFeatures: behavioralFeatures,
            source: .voiceSession,
            timestamp: timestamp
        )

        // Update published properties
        currentState = result.state
        currentConfidence = result.confidence
        lastClassificationTime = timestamp

        // PERFORMANCE: Check for cascade in background to avoid blocking
        Task.detached { [weak self] in
            await self?.checkForCascade()
        }

        return result.state
    }

    /// Classify state passively (foreground, no voice)
    func classifyPassiveState() async throws -> NervousSystemState {
        let startTime = Date()
        isClassifying = true
        defer { isClassifying = false }

        // Extract HRV and behavioral features (no voice)
        async let hrvFeatures = extractHRVFeatures()
        let behavioralFeatures = behavioralTracker.getCurrentBehavioralFeatures()

        // Classify
        let result = classifier.classify(
            voice: nil,
            hrv: try await hrvFeatures,
            behavioral: behavioralFeatures
        )

        // Store state record
        try await storeStateRecord(
            result: result,
            voiceFeatures: nil,
            hrvFeatures: hrvFeatures,
            behavioralFeatures: behavioralFeatures,
            source: .passiveForeground,
            timestamp: Date()
        )

        // Update published properties
        currentState = result.state
        currentConfidence = result.confidence
        lastClassificationTime = Date()

        return result.state
    }

    // MARK: - Public Interface - State History

    /// Get current state (most recent classification)
    func getCurrentState() async throws -> NervousSystemStateRecord? {
        guard let userId = try await getCurrentUserId() else {
            return nil
        }

        let records: [NervousSystemStateRecord] = try await supabase
            .from("nervous_system_states")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("classified_at", ascending: false)
            .limit(1)
            .execute()
            .value

        return records.first
    }

    /// Get state history
    /// - Parameters:
    ///   - from: Start date
    ///   - to: End date
    /// - Returns: Ordered state records (newest first)
    func getStateHistory(from: Date, to: Date) async throws -> [NervousSystemStateRecord] {
        guard let userId = try await getCurrentUserId() else {
            return []
        }

        let records: [NervousSystemStateRecord] = try await supabase
            .from("nervous_system_states")
            .select()
            .eq("user_id", value: userId.uuidString)
            .gte("classified_at", value: isoDateFormatter.string(from: from))
            .lte("classified_at", value: isoDateFormatter.string(from: to))
            .order("classified_at", ascending: false)
            .execute()
            .value

        return records
    }

    // MARK: - Public Interface - Cascade Detection

    /// Detect cascade from recent state history
    func detectCascade(states: [NervousSystemStateRecord]) -> CascadeEvent? {
        return cascadeDetector.detectCascade(states: states)
    }

    // MARK: - Public Interface - Intervention Recommendations

    /// Get intervention recommendations for current state
    func getInterventionRecommendations(
        for state: NervousSystemState,
        cascadeEvent: CascadeEvent? = nil
    ) async throws -> [InterventionRecommendation] {
        guard let userId = try await getCurrentUserId() else {
            return []
        }

        return try await interventionRecommender.recommend(
            for: state,
            cascadeEvent: cascadeEvent,
            userId: userId
        )
    }

    // MARK: - Private Methods - Feature Extraction

    private func extractVoiceFeatures(from emotions: [EmotionPrediction]) async -> PolyvagalVoiceFeatures? {
        guard !emotions.isEmpty else { return nil }
        return voiceExtractor.extractFeatures(from: emotions)
    }

    private func extractHRVFeatures() async -> PolyvagalHRVFeatures? {
        do {
            return try await hrvExtractor.extractRecentHRV(lookbackMinutes: 5)
        } catch {
            logger.info("HRV extraction failed (Apple Watch may not be connected): \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Private Methods - State Storage

    private func storeStateRecord(
        result: NervousSystemStateResult,
        voiceFeatures: PolyvagalVoiceFeatures?,
        hrvFeatures: PolyvagalHRVFeatures?,
        behavioralFeatures: PolyvagalBehavioralFeatures,
        source: ClassificationSource,
        timestamp: Date
    ) async throws {
        guard let userId = try await getCurrentUserId() else {
            throw NervousSystemError.databaseError("User not authenticated")
        }

        // Only store if confidence meets threshold
        guard result.confidence >= minConfidenceThreshold else {
            logger.info("Skipping storage: confidence \(result.confidence) below threshold \(minConfidenceThreshold)")
            return
        }

        // Prepare JSONB fields using shared encoder
        let voiceJSON = voiceFeatures.flatMap { try? jsonEncoder.encode($0) }
        let hrvJSON = hrvFeatures.flatMap { try? jsonEncoder.encode($0) }
        let behavioralJSON = try? jsonEncoder.encode(behavioralFeatures)

        // Insert record
        struct InsertPayload: Encodable {
            let userId: String
            let state: String
            let confidence: Double
            let voiceFeatures: Data?
            let hrvFeatures: Data?
            let behavioralFeatures: Data?
            let latencyMs: Int
            let source: String
            let classifiedAt: String

            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case state
                case confidence
                case voiceFeatures = "voice_features"
                case hrvFeatures = "hrv_features"
                case behavioralFeatures = "behavioral_features"
                case latencyMs = "latency_ms"
                case source
                case classifiedAt = "classified_at"
            }
        }

        let payload = InsertPayload(
            userId: userId.uuidString,
            state: result.state.rawValue,
            confidence: result.confidence,
            voiceFeatures: voiceJSON,
            hrvFeatures: hrvJSON,
            behavioralFeatures: behavioralJSON,
            latencyMs: result.latencyMs,
            source: source.rawValue,
            classifiedAt: isoDateFormatter.string(from: timestamp)
        )

        try await supabase
            .from("nervous_system_states")
            .insert(payload)
            .execute()

        logger.info("Stored state: \(result.state.rawValue) (confidence: \(result.confidence), latency: \(result.latencyMs)ms)")
    }

    // MARK: - Private Methods - Cascade Handling

    private func checkForCascade() async {
        do {
            // Get recent state history (last 10 minutes)
            let tenMinutesAgo = Date().addingTimeInterval(-600)
            let recentStates = try await getStateHistory(from: tenMinutesAgo, to: Date())

            // Detect cascade
            if let cascade = cascadeDetector.detectCascade(states: recentStates) {
                logger.warning("Cascade detected: \(cascade.severity.rawValue) (\(cascade.transitionCount) transitions)")

                // Store cascade event
                try await storeCascadeEvent(cascade)

                // Trigger cascade handling (notifications, high-urgency interventions)
                await handleCascade(cascade)
            }
        } catch {
            logger.error("Failed to check for cascade: \(error.localizedDescription)")
        }
    }

    private func storeCascadeEvent(_ cascade: CascadeEvent) async throws {
        struct InsertPayload: Encodable {
            let userId: String
            let startedAt: String
            let endedAt: String
            let stateSequence: [String]
            let severity: String
            let transitionCount: Int

            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case startedAt = "started_at"
                case endedAt = "ended_at"
                case stateSequence = "state_sequence"
                case severity
                case transitionCount = "transition_count"
            }
        }

        let payload = InsertPayload(
            userId: cascade.userId.uuidString,
            startedAt: isoDateFormatter.string(from: cascade.startedAt),
            endedAt: isoDateFormatter.string(from: cascade.endedAt),
            stateSequence: cascade.stateSequence.map { $0.rawValue },
            severity: cascade.severity.rawValue,
            transitionCount: cascade.transitionCount
        )

        try await supabase
            .from("cascade_events")
            .insert(payload)
            .execute()
    }

    private func handleCascade(_ cascade: CascadeEvent) async {
        // Future: Trigger push notification, show crisis resources, etc.
        logger.info("Handling cascade: \(cascade.severity.rawValue)")
    }

    // MARK: - Private Methods - User Management

    private func getCurrentUserId() async throws -> UUID? {
        let session = try await supabase.auth.session
        return UUID(uuidString: session.user.id.uuidString)
    }
}
