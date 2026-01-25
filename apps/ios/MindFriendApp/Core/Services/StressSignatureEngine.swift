import Foundation
import Combine

/// Actor for coordinating alert creation with proper atomic concurrency control
actor AlertCreationCoordinator {
    private var isCreatingAlert = false
    private var lastAlertDate: Date?
    
    /// Attempt to acquire the creation lock
    /// Returns true if lock acquired, false if already creating or recent alert exists
    func canCreateAlert() -> Bool {
        guard !isCreatingAlert else { return false }
        
        // Check if we already created an alert today
        if let lastDate = lastAlertDate,
           Calendar.current.isDate(lastDate, inSameDayAs: Date()) {
            return false
        }
        
        isCreatingAlert = true
        return true
    }
    
    /// Mark that an alert was successfully created
    func didCreateAlert() {
        lastAlertDate = Date()
        isCreatingAlert = false
    }
    
    /// Cancel the creation (release lock without creating)
    func cancelCreation() {
        isCreatingAlert = false
    }
    
    /// Reset state (for testing or when user clears alerts)
    func reset() {
        isCreatingAlert = false
        lastAlertDate = nil
    }
}

/// Main coordinator for the Stress Signature system
/// Orchestrates signal collection, pattern detection, and intervention triggering
@MainActor
final class StressSignatureEngine: ObservableObject {
    // Dependencies
    private let supabaseDataService: SupabaseDataService
    private let patternLearner: PatternLearner
    private let signalMonitor: SignalMonitor
    private let patternDetector: PatternDetector
    private let _interventionService: EarlyInterventionService

    /// Public accessor for intervention service (for views that need to display pending interventions)
    var interventionService: EarlyInterventionService { _interventionService }

    // Published state
    @Published private(set) var currentSignature: WarningSignature?
    @Published private(set) var activeAlerts: [PatternAlert] = []
    @Published private(set) var isMonitoring = false
    @Published private(set) var lastDetectionResult: PatternEmergenceResult?
    @Published private(set) var accuracyStats: SignatureAccuracyStats?

    // Private state
    private var cancellables = Set<AnyCancellable>()
    private var detectionTask: Task<Void, Never>?
    
    // Actor-based coordinator for atomic alert creation
    private let alertCoordinator = AlertCreationCoordinator()

    init(
        supabaseDataService: SupabaseDataService,
        patternLearner: PatternLearner,
        signalMonitor: SignalMonitor,
        patternDetector: PatternDetector,
        interventionService: EarlyInterventionService
    ) {
        self.supabaseDataService = supabaseDataService
        self.patternLearner = patternLearner
        self.signalMonitor = signalMonitor
        self.patternDetector = patternDetector
        self._interventionService = interventionService

        setupSignalObserver()
    }

    deinit {
        detectionTask?.cancel()
    }

    // MARK: - Public API

    /// Start monitoring for pattern emergence
    func startMonitoring() async throws {
        guard !isMonitoring else { return }

        // Load user's signature
        currentSignature = try await fetchCurrentSignature()

        guard currentSignature != nil else {
            throw StressSignatureError.signatureNotInitialized
        }

        // Load active alerts
        activeAlerts = try await fetchActiveAlerts()

        // Load accuracy stats
        accuracyStats = try await fetchAccuracyStats()

        // Start signal monitoring
        signalMonitor.startObserving()
        isMonitoring = true

        // Schedule periodic detection
        schedulePeriodicDetection()
    }

    /// Stop monitoring
    func stopMonitoring() {
        isMonitoring = false
        signalMonitor.stopObserving()
        detectionTask?.cancel()
        detectionTask = nil
    }

    /// Get or refresh the current signature
    func getCurrentSignature() async throws -> WarningSignature? {
        if currentSignature == nil {
            currentSignature = try await fetchCurrentSignature()
        }
        return currentSignature
    }

    /// Create a new signature from selected components
    func createSignature(
        selectedComponentIds: Set<UUID>,
        crisisType: CrisisType = .general
    ) async throws -> WarningSignature {
        guard let userId = supabaseDataService.currentUserId else {
            throw StressSignatureError.signatureNotInitialized
        }

        let signature = WarningSignature.create(
            userId: userId,
            crisisType: crisisType,
            selectedComponentIds: selectedComponentIds
        )

        // Save to database
        try await supabaseDataService.insertWarningSignature(signature)

        currentSignature = signature
        return signature
    }

    /// Update signature sensitivity
    func updateSensitivity(_ sensitivity: Double) async throws {
        guard var signature = currentSignature else {
            throw StressSignatureError.signatureNotInitialized
        }

        // Validate sensitivity is within allowed range
        guard sensitivity >= 0.3 && sensitivity <= 0.9 else {
            throw StressSignatureError.invalidInput("Sensitivity must be between 0.3 and 0.9")
        }

        signature.detectionSensitivity = sensitivity
        try await supabaseDataService.updateWarningSignature(signature)
        currentSignature = signature
    }

    /// Learn from historical crisis data
    func learnFromHistory() async throws {
        let learnedSignature = try await patternLearner.learnSignatureFromHistory()
        currentSignature = learnedSignature
    }

    /// Submit feedback for an alert
    func submitFeedback(
        for alert: PatternAlert,
        feedback: AlertFeedback,
        notes: String? = nil
    ) async throws {
        guard var signature = currentSignature else {
            throw StressSignatureError.signatureNotInitialized
        }

        // Adjust weights based on feedback
        signature = try await patternDetector.adjustWeights(
            signature: signature,
            alert: alert,
            feedback: feedback
        )

        currentSignature = signature

        // Refresh accuracy stats
        accuracyStats = try await fetchAccuracyStats()

        // Refresh active alerts
        activeAlerts = try await fetchActiveAlerts()
    }

    /// Dismiss an active alert
    func dismissAlert(_ alert: PatternAlert) async throws {
        try await supabaseDataService.dismissPatternAlert(alertId: alert.id)
        activeAlerts = try await fetchActiveAlerts()
    }

    /// Report a new crisis event
    func reportCrisisEvent(
        crisisType: CrisisType,
        occurredAt: Date,
        severity: AlertSeverity
    ) async throws {
        try await supabaseDataService.insertCrisisEvent(
            crisisType: crisisType,
            occurredAt: occurredAt,
            severity: severity
        )

        // Learn from the new crisis
        if let signature = currentSignature {
            _ = try await patternDetector.learnFromMissedPattern(
                signature: signature,
                crisisDate: occurredAt
            )
            currentSignature = try await fetchCurrentSignature()
        }
    }

    /// Manually trigger pattern detection
    func detectPatternNow() async throws -> PatternEmergenceResult {
        guard let signature = currentSignature else {
            throw StressSignatureError.signatureNotInitialized
        }

        // Get current signals
        try await signalMonitor.measureSignalsNow()
        let signals = signalMonitor.getCurrentSignals()

        // Run detection
        let result = patternDetector.detectPatternEmergence(
            signature: signature,
            currentSignals: signals
        )

        lastDetectionResult = result

        // If pattern emerging, trigger intervention
        if result.isEmerging {
            try await handlePatternEmergence(result: result, signature: signature)
        }

        return result
    }

    /// Get active alert count for UI badge
    func getActiveAlertCount() -> Int {
        activeAlerts.count
    }

    // MARK: - Private Methods

    private func setupSignalObserver() {
        signalMonitor.onSignalUpdate { [weak self] signal in
            Task { @MainActor in
                await self?.handleSignalUpdate(signal)
            }
        }
    }

    private func handleSignalUpdate(_ signal: SignalUpdate) async {
        // Run detection if we have enough recent signals
        guard let signature = currentSignature else { return }

        let signals = signalMonitor.getCurrentSignals()
        guard signals.count >= 2 else { return }

        let result = patternDetector.detectPatternEmergence(
            signature: signature,
            currentSignals: signals
        )

        lastDetectionResult = result

        if result.isEmerging {
            try? await handlePatternEmergence(result: result, signature: signature)
        }
    }

    private func schedulePeriodicDetection() {
        detectionTask = Task { [weak self] in
            while !Task.isCancelled {
                // Run detection every hour
                try? await Task.sleep(nanoseconds: 60 * 60 * 1_000_000_000)

                guard let self = self, self.isMonitoring else { continue }

                do {
                    _ = try await self.detectPatternNow()
                } catch {
                    // Log without exposing sensitive user data
                    print("[StressSignatureEngine] Periodic detection error occurred")
                }
            }
        }
    }

    private func handlePatternEmergence(
        result: PatternEmergenceResult,
        signature: WarningSignature
    ) async throws {
        // Atomic check using Actor - returns false if already creating or recent alert exists
        guard await alertCoordinator.canCreateAlert() else { return }
        
        do {
            // ALWAYS fetch fresh alerts from database to prevent race conditions
            // (local activeAlerts array may be stale from concurrent operations)
            let freshAlerts = try await fetchActiveAlerts()
            
            // Check if we already have a recent alert in the database
            let existingAlert = freshAlerts.first {
                Calendar.current.isDate($0.detectedAt, inSameDayAs: Date())
            }

            if let existing = existingAlert {
                // Update local cache with fresh data
                activeAlerts = freshAlerts
                
                // Release lock without creating
                await alertCoordinator.cancelCreation()
                return
            }

            // Create new alert
            let alert = try await supabaseDataService.createPatternAlert(
                signatureId: signature.id,
                activeComponents: result.activeComponents,
                emergenceScore: result.emergenceScore,
                severity: result.severity,
                interventionTier: result.recommendedTier,
                predictedTimeToEvent: result.estimatedTimeToEvent
            )

            // Mark creation complete
            await alertCoordinator.didCreateAlert()

            // Trigger intervention
            try await _interventionService.triggerIntervention(
                for: alert,
                signature: signature
            )

            // Add to local cache immediately (avoid extra network call)
            activeAlerts.insert(alert, at: 0)
        } catch {
            // Release lock on error
            await alertCoordinator.cancelCreation()
            throw error
        }
    }

    private func fetchCurrentSignature() async throws -> WarningSignature? {
        try await supabaseDataService.fetchWarningSignature()
    }

    private func fetchActiveAlerts() async throws -> [PatternAlert] {
        try await supabaseDataService.fetchActivePatternAlerts()
    }

    private func fetchAccuracyStats() async throws -> SignatureAccuracyStats {
        try await supabaseDataService.fetchSignatureAccuracyStats()
    }
}

// MARK: - SupabaseDataService Extensions for Stress Signatures

extension SupabaseDataService {
    // Note: currentUserId is already defined in SupabaseDataService class

    func fetchWarningSignature() async throws -> WarningSignature? {
        let response = try await supabase
            .from("stress_signatures")
            .select()
            .order("updated_at", ascending: false)
            .limit(1)
            .execute()

        let signatures = try JSONDecoder.supabaseDecoder.decode([WarningSignature].self, from: response.data)
        return signatures.first
    }

    func insertWarningSignature(_ signature: WarningSignature) async throws {
        struct SignatureInsert: Encodable {
            let id: String
            let userId: String
            let crisisType: String
            let components: [WeightedComponent]
            let source: String
            let confidence: Double
            let detectionSensitivity: Double

            enum CodingKeys: String, CodingKey {
                case id
                case userId = "user_id"
                case crisisType = "crisis_type"
                case components
                case source
                case confidence
                case detectionSensitivity = "detection_sensitivity"
            }
        }

        let insert = SignatureInsert(
            id: signature.id.uuidString,
            userId: signature.userId.uuidString,
            crisisType: signature.crisisType.rawValue,
            components: signature.components,
            source: signature.source.rawValue,
            confidence: signature.confidence,
            detectionSensitivity: signature.detectionSensitivity
        )

        _ = try await supabase
            .from("stress_signatures")
            .insert(insert)
            .execute()
    }

    func fetchActivePatternAlerts() async throws -> [PatternAlert] {
        let oneDayAgo = Calendar.current.date(byAdding: .day, value: -1, to: Date())!

        let response = try await supabase
            .from("pattern_alerts")
            .select()
            .is("dismissed_at", value: nil)
            .gte("detected_at", value: ISO8601DateFormatter().string(from: oneDayAgo))
            .order("detected_at", ascending: false)
            .execute()

        return try JSONDecoder.supabaseDecoder.decode([PatternAlert].self, from: response.data)
    }

    func createPatternAlert(
        signatureId: UUID,
        activeComponents: [ActiveSignal],
        emergenceScore: Double,
        severity: AlertSeverity,
        interventionTier: InterventionTier,
        predictedTimeToEvent: Int?
    ) async throws -> PatternAlert {
        struct AlertInsert: Encodable {
            let id: String
            let signatureId: String
            let activeComponents: [ActiveSignal]
            let emergenceScore: Double
            let severity: String
            let interventionTier: String
            let interventionDelivered: Bool
            let predictedTimeToEvent: Int?

            enum CodingKeys: String, CodingKey {
                case id
                case signatureId = "signature_id"
                case activeComponents = "active_components"
                case emergenceScore = "emergence_score"
                case severity
                case interventionTier = "intervention_tier"
                case interventionDelivered = "intervention_delivered"
                case predictedTimeToEvent = "predicted_time_to_event"
            }
        }

        let alertId = UUID()
        let insert = AlertInsert(
            id: alertId.uuidString,
            signatureId: signatureId.uuidString,
            activeComponents: activeComponents,
            emergenceScore: emergenceScore,
            severity: severity.rawValue,
            interventionTier: interventionTier.rawValue,
            interventionDelivered: false,
            predictedTimeToEvent: predictedTimeToEvent
        )

        _ = try await supabase
            .from("pattern_alerts")
            .insert(insert)
            .execute()

        // Fetch the created alert
        let response = try await supabase
            .from("pattern_alerts")
            .select()
            .eq("id", value: alertId.uuidString)
            .single()
            .execute()

        return try JSONDecoder.supabaseDecoder.decode(PatternAlert.self, from: response.data)
    }

    func dismissPatternAlert(alertId: UUID) async throws {
        struct DismissUpdate: Encodable {
            let dismissedAt: String

            enum CodingKeys: String, CodingKey {
                case dismissedAt = "dismissed_at"
            }
        }

        let update = DismissUpdate(dismissedAt: ISO8601DateFormatter().string(from: Date()))

        _ = try await supabase
            .from("pattern_alerts")
            .update(update)
            .eq("id", value: alertId.uuidString)
            .execute()
    }

    func insertCrisisEvent(
        crisisType: CrisisType,
        occurredAt: Date,
        severity: AlertSeverity
    ) async throws {
        struct CrisisInsert: Encodable {
            let crisisType: String
            let occurredAt: String
            let severity: String
            let userReported: Bool
            let analyzed: Bool

            enum CodingKeys: String, CodingKey {
                case crisisType = "crisis_type"
                case occurredAt = "occurred_at"
                case severity
                case userReported = "user_reported"
                case analyzed
            }
        }

        let insert = CrisisInsert(
            crisisType: crisisType.rawValue,
            occurredAt: ISO8601DateFormatter().string(from: occurredAt),
            severity: severity.rawValue,
            userReported: true,
            analyzed: false
        )

        _ = try await supabase
            .from("crisis_events")
            .insert(insert)
            .execute()
    }

    func fetchSignatureAccuracyStats() async throws -> SignatureAccuracyStats {
        let response = try await supabase
            .from("pattern_alerts")
            .select("user_feedback")
            .execute()

        struct FeedbackRow: Decodable {
            let userFeedback: String?
            enum CodingKeys: String, CodingKey {
                case userFeedback = "user_feedback"
            }
        }

        let rows = try JSONDecoder.supabaseDecoder.decode([FeedbackRow].self, from: response.data)

        var accurate = 0
        var falseAlarm = 0
        var helped = 0
        var missed = 0

        for row in rows {
            switch row.userFeedback {
            case "accurate_prediction": accurate += 1
            case "false_alarm": falseAlarm += 1
            case "helped_prevent": helped += 1
            case "missed_pattern": missed += 1
            default: break
            }
        }

        return SignatureAccuracyStats(
            totalAlerts: rows.count,
            accuratePredictions: accurate,
            falseAlarms: falseAlarm,
            helpedPrevent: helped,
            missedPatterns: missed
        )
    }
}
