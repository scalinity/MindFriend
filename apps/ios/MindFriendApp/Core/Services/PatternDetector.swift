import Foundation

/// Service for detecting pattern emergence and managing signature weights
@MainActor
final class PatternDetector: ObservableObject {
    private let supabaseDataService: SupabaseDataService

    @Published private(set) var lastDetectionResult: PatternEmergenceResult?
    @Published private(set) var isDetecting = false

    init(supabaseDataService: SupabaseDataService) {
        self.supabaseDataService = supabaseDataService
    }

    /// Detect pattern emergence by comparing current signals to user's signature
    /// - Parameters:
    ///   - signature: The user's stress signature
    ///   - currentSignals: Dictionary of current signal values
    /// - Returns: Pattern emergence result
    func detectPatternEmergence(
        signature: WarningSignature,
        currentSignals: [String: Double]
    ) -> PatternEmergenceResult {
        var activeComponents: [ActiveSignal] = []
        var totalWeight: Double = 0
        var activeWeight: Double = 0

        for component in signature.components {
            // Only count components with positive weight
            guard component.weight > 0 else { continue }
            totalWeight += component.weight

            guard let currentValue = currentSignals[component.signal] else {
                continue
            }

            if currentValue >= component.detectionThreshold {
                activeWeight += component.weight
                activeComponents.append(ActiveSignal(
                    componentId: component.componentId,
                    signal: component.signal,
                    detectedValue: currentValue,
                    threshold: component.detectionThreshold,
                    daysActive: 1 // Will be updated from database
                ))
            }
        }

        // Calculate emergence score with safe division
        let emergenceScore: Double
        if totalWeight > 0 {
            emergenceScore = activeWeight / totalWeight
        } else {
            // No valid components - cannot detect patterns
            emergenceScore = 0
        }

        // Pattern is emerging if score >= sensitivity AND at least 2 components are active
        let isEmerging = emergenceScore >= signature.detectionSensitivity && activeComponents.count >= 2

        // Calculate estimated time to event
        var estimatedTimeToEvent: Int? = nil
        if isEmerging && activeComponents.count >= 2 {
            let values = activeComponents.map { $0.detectedValue }
            // Guard against empty values (should never happen if activeComponents.count >= 2, but be safe)
            guard !values.isEmpty else {
                estimatedTimeToEvent = nil
                // Continue with nil estimate rather than crashing
                return PatternEmergenceResult(
                    isEmerging: isEmerging,
                    emergenceScore: emergenceScore,
                    activeComponents: activeComponents,
                    estimatedTimeToEvent: nil,
                    recommendedTier: PatternEmergenceResult.calculateTier(emergenceScore: emergenceScore),
                    severity: PatternEmergenceResult.calculateSeverity(activeCount: activeComponents.count)
                )
            }
            let avgStrength = values.reduce(0, +) / Double(values.count)
            // Clamp avgStrength to [0.0, 1.0] to prevent negative time estimates
            let clampedAvg = max(0.0, min(1.0, avgStrength))
            // Formula: (1.0 - avgSignalStrength) * 72 hours, converted to seconds
            estimatedTimeToEvent = Int((1.0 - clampedAvg) * 72 * 3600)
        }

        let severity = PatternEmergenceResult.calculateSeverity(activeCount: activeComponents.count)
        let tier = PatternEmergenceResult.calculateTier(emergenceScore: emergenceScore)

        let result = PatternEmergenceResult(
            isEmerging: isEmerging,
            emergenceScore: emergenceScore,
            activeComponents: activeComponents,
            estimatedTimeToEvent: estimatedTimeToEvent,
            recommendedTier: tier,
            severity: severity
        )

        lastDetectionResult = result
        return result
    }

    /// Detect pattern emergence using the edge function (server-side)
    func detectPatternEmergenceRemote(signatureId: UUID? = nil) async throws -> PatternEmergenceResult {
        isDetecting = true
        defer { isDetecting = false }

        var payload: [String: Any] = [:]
        if let signatureId = signatureId {
            payload["signature_id"] = signatureId.uuidString
        }

        let responseData = try await supabaseDataService.invokeFunction(
            name: "detect-pattern-emergence",
            payload: payload
        )

        let result = try JSONDecoder.supabaseDecoder.decode(
            DetectPatternResponse.self,
            from: responseData
        )

        let emergenceResult = PatternEmergenceResult(
            isEmerging: result.isEmerging,
            emergenceScore: result.emergenceScore,
            activeComponents: result.activeComponents,
            estimatedTimeToEvent: result.estimatedHours.map { $0 * 3600 },
            recommendedTier: InterventionTier(rawValue: result.interventionTier) ?? .gentle,
            severity: AlertSeverity(rawValue: result.severity) ?? .mild
        )

        lastDetectionResult = emergenceResult
        return emergenceResult
    }

    /// Adjust component weights based on user feedback
    /// - Parameters:
    ///   - signature: The signature to adjust
    ///   - alert: The alert being given feedback on
    ///   - feedback: The user's feedback
    /// - Returns: Updated signature with adjusted weights
    func adjustWeights(
        signature: WarningSignature,
        alert: PatternAlert,
        feedback: AlertFeedback
    ) async throws -> WarningSignature {
        var updatedSignature = signature

        // Get active component signals from the alert
        let activeSignals = Set(alert.activeComponents.map { $0.signal })

        // Minimum weight to maintain detection capability
        let minimumWeight: Double = 0.2

        // Adjust weights based on feedback
        for i in 0..<updatedSignature.components.count {
            let signal = updatedSignature.components[i].signal

            if activeSignals.contains(signal) {
                switch feedback {
                case .accuratePrediction, .helpedPrevent:
                    // Increase weight for accurate predictions (+0.05)
                    updatedSignature.components[i].weight = min(
                        updatedSignature.components[i].weight + 0.05,
                        1.0
                    )
                case .falseAlarm:
                    // Decrease weight for false alarms (-0.1), but maintain minimum
                    updatedSignature.components[i].weight = max(
                        updatedSignature.components[i].weight - 0.1,
                        minimumWeight
                    )
                case .missedPattern:
                    // This is handled separately - we need to add signals that were active
                    break
                }
            }
        }

        // Adjust confidence
        switch feedback {
        case .accuratePrediction, .helpedPrevent:
            updatedSignature.confidence = min(updatedSignature.confidence + 0.05, 0.95)
        case .falseAlarm:
            updatedSignature.confidence = max(updatedSignature.confidence - 0.02, 0.3)
        case .missedPattern:
            // Learn from missed patterns by analyzing recent signals
            updatedSignature.confidence = max(updatedSignature.confidence - 0.01, 0.3)
        }

        // Persist updated signature
        try await supabaseDataService.updateWarningSignature(updatedSignature)

        // Update alert with feedback
        try await supabaseDataService.updatePatternAlertFeedback(
            alertId: alert.id,
            feedback: feedback,
            notes: nil
        )

        return updatedSignature
    }

    /// Learn from a missed pattern by analyzing signals that were active during the crisis
    func learnFromMissedPattern(
        signature: WarningSignature,
        crisisDate: Date
    ) async throws -> WarningSignature {
        // Get signals from 3 days before the crisis
        let signals = try await supabaseDataService.fetchSignatureSignals(
            fromDate: Calendar.current.date(byAdding: .day, value: -3, to: crisisDate)!,
            toDate: crisisDate
        )

        var updatedSignature = signature

        // Find signals that were elevated but not in the signature
        let existingSignals = Set(signature.components.map { $0.signal })

        for signal in signals {
            if signal.value >= 0.6 && !existingSignals.contains(signal.signalType) {
                // Add new component with moderate weight
                let newComponent = WeightedComponent(
                    componentId: UUID(),
                    signal: signal.signalType,
                    weight: 0.5,
                    detectionThreshold: 0.6,
                    lastActive: signal.date
                )
                updatedSignature.components.append(newComponent)
            }
        }

        // Mark source as hybrid if we added new components
        if updatedSignature.components.count > signature.components.count {
            updatedSignature.source = .hybridRefined
        }

        // Persist updated signature
        try await supabaseDataService.updateWarningSignature(updatedSignature)

        return updatedSignature
    }
}

// MARK: - Response Models

private struct DetectPatternResponse: Decodable {
    let isEmerging: Bool
    let emergenceScore: Double
    let activeComponents: [ActiveSignal]
    let activeComponentCount: Int
    let totalComponentCount: Int
    let severity: String
    let interventionTier: String
    let estimatedHours: Int?
    let alert: AlertInfo?

    enum CodingKeys: String, CodingKey {
        case isEmerging = "is_emerging"
        case emergenceScore = "emergence_score"
        case activeComponents = "active_components"
        case activeComponentCount = "active_component_count"
        case totalComponentCount = "total_component_count"
        case severity
        case interventionTier = "intervention_tier"
        case estimatedHours = "estimated_hours"
        case alert
    }

    struct AlertInfo: Decodable {
        let id: String
        let severity: String
        let interventionTier: String
        let message: String
        let updated: Bool

        enum CodingKeys: String, CodingKey {
            case id
            case severity
            case interventionTier = "intervention_tier"
            case message
            case updated
        }
    }
}

// MARK: - SupabaseDataService Extensions

extension SupabaseDataService {
    func updateWarningSignature(_ signature: WarningSignature) async throws {
        struct SignatureUpdate: Encodable {
            let components: [WeightedComponent]
            let source: String
            let confidence: Double
            let detectionSensitivity: Double

            enum CodingKeys: String, CodingKey {
                case components
                case source
                case confidence
                case detectionSensitivity = "detection_sensitivity"
            }
        }

        let update = SignatureUpdate(
            components: signature.components,
            source: signature.source.rawValue,
            confidence: signature.confidence,
            detectionSensitivity: signature.detectionSensitivity
        )

        _ = try await supabase
            .from("stress_signatures")
            .update(update)
            .eq("id", value: signature.id.uuidString)
            .execute()
    }

    func updatePatternAlertFeedback(
        alertId: UUID,
        feedback: AlertFeedback,
        notes: String?
    ) async throws {
        struct FeedbackUpdate: Encodable {
            let userFeedback: String
            let feedbackAt: String
            let feedbackNotes: String?

            enum CodingKeys: String, CodingKey {
                case userFeedback = "user_feedback"
                case feedbackAt = "feedback_at"
                case feedbackNotes = "feedback_notes"
            }
        }

        let update = FeedbackUpdate(
            userFeedback: feedback.rawValue,
            feedbackAt: ISO8601DateFormatter().string(from: Date()),
            feedbackNotes: notes
        )

        _ = try await supabase
            .from("pattern_alerts")
            .update(update)
            .eq("id", value: alertId.uuidString)
            .execute()
    }

    func fetchSignatureSignals(
        fromDate: Date,
        toDate: Date
    ) async throws -> [SignatureSignal] {
        let formatter = ISO8601DateFormatter()
        let fromDateString = String(formatter.string(from: fromDate).prefix(10))
        let toDateString = String(formatter.string(from: toDate).prefix(10))

        let response = try await supabase
            .from("signature_signals")
            .select()
            .gte("date", value: fromDateString)
            .lte("date", value: toDateString)
            .execute()

        return try JSONDecoder.supabaseDecoder.decode([SignatureSignal].self, from: response.data)
    }
}
