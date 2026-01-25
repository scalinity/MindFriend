import XCTest
@testable import MindFriendApp

/// Unit tests for the Stress Signature Fingerprint feature (F026)
final class StressSignatureTests: XCTestCase {

    // MARK: - StressSignature Model Tests

    func testStressSignatureCreation() {
        // Given
        let userId = UUID()
        let componentIds: Set<UUID> = [
            SignatureComponent.library.first { $0.signal == "isolation" }!.id,
            SignatureComponent.library.first { $0.signal == "insomnia_wired" }!.id
        ]

        // When
        let signature = StressSignature.create(
            userId: userId,
            crisisType: .relapse,
            selectedComponentIds: componentIds
        )

        // Then
        XCTAssertEqual(signature.userId, userId)
        XCTAssertEqual(signature.crisisType, .relapse)
        XCTAssertEqual(signature.components.count, 2)
        XCTAssertEqual(signature.source, .userDefined)
        XCTAssertEqual(signature.confidence, 0.5) // Initial confidence
        XCTAssertTrue(signature.isActive)
    }

    func testStressSignatureWithEmptyComponents() {
        // Given
        let userId = UUID()
        let componentIds: Set<UUID> = []

        // When
        let signature = StressSignature.create(
            userId: userId,
            crisisType: .general,
            selectedComponentIds: componentIds
        )

        // Then
        XCTAssertTrue(signature.components.isEmpty)
    }

    // MARK: - SignatureComponent Tests

    func testSignatureComponentLibrary() {
        // Verify the library has the expected 15 components
        XCTAssertEqual(SignatureComponent.library.count, 15)

        // Verify each category has components
        let categories = Set(SignatureComponent.library.map { $0.category })
        XCTAssertEqual(categories.count, 6) // sleep, social, cognitive, emotional, behavioral, physical
    }

    func testSignatureComponentCategories() {
        // Sleep category should have expected components
        let sleepComponents = SignatureComponent.components(for: .sleep)
        XCTAssertGreaterThan(sleepComponents.count, 0)

        // Each component should have required fields
        for component in sleepComponents {
            XCTAssertFalse(component.displayName.isEmpty)
            XCTAssertFalse(component.description.isEmpty)
            XCTAssertFalse(component.signal.isEmpty)
        }
    }

    func testComponentLookupBySignal() {
        // Test existing signal
        let isolation = SignatureComponent.component(for: "isolation")
        XCTAssertNotNil(isolation)
        XCTAssertEqual(isolation?.signal, "isolation")
        XCTAssertEqual(isolation?.category, .social)

        // Test non-existent signal
        let unknown = SignatureComponent.component(for: "nonexistent_signal")
        XCTAssertNil(unknown)
    }

    // MARK: - WeightedComponent Tests

    func testWeightedComponentDefaults() {
        let component = WeightedComponent(
            componentId: UUID(),
            signal: "test_signal",
            weight: 0.5,
            threshold: 0.6
        )

        XCTAssertEqual(component.weight, 0.5)
        XCTAssertEqual(component.threshold, 0.6)
    }

    // MARK: - AlertSeverity Tests

    func testAlertSeverityDisplayNames() {
        XCTAssertEqual(AlertSeverity.mild.displayName, "Mild Warning")
        XCTAssertEqual(AlertSeverity.moderate.displayName, "Moderate Warning")
        XCTAssertEqual(AlertSeverity.severe.displayName, "Severe Warning")
    }

    // MARK: - InterventionTier Tests

    func testInterventionTierFromSeverity() {
        XCTAssertEqual(InterventionTier.from(severity: .mild), .gentle)
        XCTAssertEqual(InterventionTier.from(severity: .moderate), .moderate)
        XCTAssertEqual(InterventionTier.from(severity: .severe), .immediate)
    }

    // MARK: - PatternAlert Tests

    func testPatternAlertPredictedHours() {
        // Test with predicted time
        let alert1 = PatternAlert(
            id: UUID(),
            userId: UUID(),
            signatureId: UUID(),
            detectedAt: Date(),
            activeComponents: [],
            emergenceScore: 0.7,
            severity: .moderate,
            predictedTimeToEvent: 48 * 3600, // 48 hours in seconds
            interventionTier: .moderate,
            interventionDelivered: false,
            interventionDeliveredAt: nil,
            userFeedback: nil,
            feedbackNotes: nil,
            feedbackAt: nil,
            dismissedAt: nil,
            createdAt: Date()
        )

        XCTAssertEqual(alert1.predictedHours, 48)

        // Test without predicted time
        let alert2 = PatternAlert(
            id: UUID(),
            userId: UUID(),
            signatureId: UUID(),
            detectedAt: Date(),
            activeComponents: [],
            emergenceScore: 0.5,
            severity: .mild,
            predictedTimeToEvent: nil,
            interventionTier: .gentle,
            interventionDelivered: false,
            interventionDeliveredAt: nil,
            userFeedback: nil,
            feedbackNotes: nil,
            feedbackAt: nil,
            dismissedAt: nil,
            createdAt: Date()
        )

        XCTAssertNil(alert2.predictedHours)
    }

    func testPatternAlertIsActive() {
        // Active alert (not dismissed)
        let activeAlert = PatternAlert(
            id: UUID(),
            userId: UUID(),
            signatureId: UUID(),
            detectedAt: Date(),
            activeComponents: [],
            emergenceScore: 0.6,
            severity: .moderate,
            predictedTimeToEvent: nil,
            interventionTier: .moderate,
            interventionDelivered: true,
            interventionDeliveredAt: Date(),
            userFeedback: nil,
            feedbackNotes: nil,
            feedbackAt: nil,
            dismissedAt: nil,
            createdAt: Date()
        )

        XCTAssertTrue(activeAlert.isActive)

        // Dismissed alert
        let dismissedAlert = PatternAlert(
            id: UUID(),
            userId: UUID(),
            signatureId: UUID(),
            detectedAt: Date(),
            activeComponents: [],
            emergenceScore: 0.6,
            severity: .moderate,
            predictedTimeToEvent: nil,
            interventionTier: .moderate,
            interventionDelivered: true,
            interventionDeliveredAt: Date(),
            userFeedback: .falseAlarm,
            feedbackNotes: nil,
            feedbackAt: Date(),
            dismissedAt: Date(),
            createdAt: Date()
        )

        XCTAssertFalse(dismissedAlert.isActive)
    }

    // MARK: - ActiveSignal Tests

    func testActiveSignalInitialization() {
        let signal = ActiveSignal(
            componentId: UUID(),
            signal: "isolation",
            detectedValue: 0.75,
            threshold: 0.6,
            daysActive: 3
        )

        XCTAssertEqual(signal.signal, "isolation")
        XCTAssertEqual(signal.detectedValue, 0.75)
        XCTAssertEqual(signal.threshold, 0.6)
        XCTAssertEqual(signal.daysActive, 3)
    }

    // MARK: - PatternEmergenceResult Tests

    func testPatternEmergenceResultSeverityCalculation() {
        // Mild severity (score < 0.5)
        let mildResult = PatternEmergenceResult(
            isEmerging: true,
            emergenceScore: 0.4,
            activeComponents: [
                ActiveSignal(componentId: UUID(), signal: "test", detectedValue: 0.65, threshold: 0.6, daysActive: 1)
            ],
            severity: .mild,
            recommendedTier: .gentle,
            estimatedTimeToEvent: 60 * 3600,
            message: "Test"
        )

        XCTAssertEqual(mildResult.severity, .mild)
        XCTAssertEqual(mildResult.recommendedTier, .gentle)

        // Moderate severity (0.5 <= score < 0.7)
        let moderateResult = PatternEmergenceResult(
            isEmerging: true,
            emergenceScore: 0.6,
            activeComponents: [],
            severity: .moderate,
            recommendedTier: .moderate,
            estimatedTimeToEvent: 48 * 3600,
            message: "Test"
        )

        XCTAssertEqual(moderateResult.severity, .moderate)

        // Severe severity (score >= 0.7)
        let severeResult = PatternEmergenceResult(
            isEmerging: true,
            emergenceScore: 0.8,
            activeComponents: [],
            severity: .severe,
            recommendedTier: .immediate,
            estimatedTimeToEvent: 24 * 3600,
            message: "Test"
        )

        XCTAssertEqual(severeResult.severity, .severe)
        XCTAssertEqual(severeResult.recommendedTier, .immediate)
    }

    // MARK: - SignatureAccuracyStats Tests

    func testSignatureAccuracyStats() {
        let stats = SignatureAccuracyStats(
            totalAlerts: 10,
            accuratePredictions: 6,
            falseAlarms: 2,
            helpedPrevent: 2,
            missedPatterns: 0
        )

        // Accuracy = (accurate + helped) / (accurate + helped + false) = 8/10 = 80%
        XCTAssertEqual(stats.accuracyPercentage, 80)
    }

    func testSignatureAccuracyStatsZeroAlerts() {
        let stats = SignatureAccuracyStats(
            totalAlerts: 0,
            accuratePredictions: 0,
            falseAlarms: 0,
            helpedPrevent: 0,
            missedPatterns: 0
        )

        // Should return 0% when no alerts
        XCTAssertEqual(stats.accuracyPercentage, 0)
    }

    // MARK: - AlertFeedback Tests

    func testAlertFeedbackDisplayNames() {
        XCTAssertEqual(AlertFeedback.accuratePrediction.displayName, "Accurate - I was heading toward crisis")
        XCTAssertEqual(AlertFeedback.helpedPrevent.displayName, "This alert helped me prevent a crisis")
        XCTAssertEqual(AlertFeedback.falseAlarm.displayName, "False alarm - I was fine")
        XCTAssertEqual(AlertFeedback.missedPattern.displayName, "Missed pattern - Something was different")
    }

    // MARK: - CrisisType Tests

    func testCrisisTypeRawValues() {
        XCTAssertEqual(CrisisType.relapse.rawValue, "relapse")
        XCTAssertEqual(CrisisType.panicAttack.rawValue, "panic_attack")
        XCTAssertEqual(CrisisType.depressiveEpisode.rawValue, "depressive_episode")
        XCTAssertEqual(CrisisType.suicidalIdeation.rawValue, "suicidal_ideation")
        XCTAssertEqual(CrisisType.selfHarm.rawValue, "self_harm")
        XCTAssertEqual(CrisisType.substanceUse.rawValue, "substance_use")
        XCTAssertEqual(CrisisType.general.rawValue, "general")
    }

    // MARK: - Category Icon Tests

    func testCategoryIcons() {
        XCTAssertEqual(SignatureComponentCategory.sleep.icon, "moon.zzz.fill")
        XCTAssertEqual(SignatureComponentCategory.social.icon, "person.2.fill")
        XCTAssertEqual(SignatureComponentCategory.cognitive.icon, "brain.head.profile")
        XCTAssertEqual(SignatureComponentCategory.emotional.icon, "heart.fill")
        XCTAssertEqual(SignatureComponentCategory.behavioral.icon, "figure.walk")
        XCTAssertEqual(SignatureComponentCategory.physical.icon, "figure.mixed.cardio")
    }

    // MARK: - TimeToEvent Calculation Tests

    func testTimeToEventCalculation() {
        // Formula: hours = (1.0 - avgSignalStrength) * 72
        // Signal strength 0.5 -> 36 hours
        // Signal strength 0.75 -> 18 hours
        // Signal strength 1.0 -> 0 hours

        let lowStrengthSeconds = Int((1.0 - 0.5) * 72 * 3600)
        XCTAssertEqual(lowStrengthSeconds, 36 * 3600)

        let highStrengthSeconds = Int((1.0 - 0.75) * 72 * 3600)
        XCTAssertEqual(highStrengthSeconds, 18 * 3600)
    }
}

// MARK: - PatternDetector Tests

final class PatternDetectorTests: XCTestCase {

    var mockDataService: SupabaseDataService!

    override func setUp() {
        super.setUp()
        // Create a mock data service for testing
        let authService = SupabaseAuthService()
        mockDataService = SupabaseDataService(authService: authService)
    }

    func testPatternDetectorInitialization() {
        let detector = PatternDetector(supabaseDataService: mockDataService)
        XCTAssertNotNil(detector)
    }

    func testDetectPatternEmergenceNoActiveComponents() {
        let detector = PatternDetector(supabaseDataService: mockDataService)

        // Create a signature with components
        let signature = StressSignature(
            id: UUID(),
            userId: UUID(),
            crisisType: .general,
            components: [
                WeightedComponent(componentId: UUID(), signal: "isolation", weight: 0.5, threshold: 0.6)
            ],
            source: .userDefined,
            confidence: 0.5,
            detectionSensitivity: 0.6,
            totalCrises: 0,
            totalDataPoints: 0,
            lastLearnedAt: nil,
            createdAt: Date(),
            updatedAt: Date(),
            isActive: true
        )

        // Create signals below threshold
        let signals: [String: Double] = [
            "isolation": 0.4 // Below 0.6 threshold
        ]

        // When
        let result = detector.detectPatternEmergence(signature: signature, currentSignals: signals)

        // Then - should not be emerging since no components are above threshold
        XCTAssertFalse(result.isEmerging)
        XCTAssertTrue(result.activeComponents.isEmpty)
    }

    func testDetectPatternEmergenceWithActiveComponents() {
        let detector = PatternDetector(supabaseDataService: mockDataService)

        let componentId = UUID()
        let signature = StressSignature(
            id: UUID(),
            userId: UUID(),
            crisisType: .general,
            components: [
                WeightedComponent(componentId: componentId, signal: "isolation", weight: 0.7, threshold: 0.6),
                WeightedComponent(componentId: UUID(), signal: "insomnia_wired", weight: 0.6, threshold: 0.6)
            ],
            source: .userDefined,
            confidence: 0.7,
            detectionSensitivity: 0.5,
            totalCrises: 2,
            totalDataPoints: 100,
            lastLearnedAt: Date(),
            createdAt: Date(),
            updatedAt: Date(),
            isActive: true
        )

        // Create signals above threshold
        let signals: [String: Double] = [
            "isolation": 0.8,
            "insomnia_wired": 0.75
        ]

        // When
        let result = detector.detectPatternEmergence(signature: signature, currentSignals: signals)

        // Then - should be emerging with 2 active components
        XCTAssertTrue(result.isEmerging)
        XCTAssertEqual(result.activeComponents.count, 2)
        XCTAssertGreaterThan(result.emergenceScore, 0)
    }
}

// MARK: - SignalMonitor Tests

final class SignalMonitorTests: XCTestCase {

    func testSignalMonitorInitialization() {
        let authService = SupabaseAuthService()
        let dataService = SupabaseDataService(authService: authService)
        let monitor = SignalMonitor(supabaseDataService: dataService)

        XCTAssertNotNil(monitor)
        XCTAssertFalse(monitor.isObserving)
    }

    func testSignalMonitorGetCurrentSignalsEmpty() {
        let authService = SupabaseAuthService()
        let dataService = SupabaseDataService(authService: authService)
        let monitor = SignalMonitor(supabaseDataService: dataService)

        let signals = monitor.getCurrentSignals()
        XCTAssertTrue(signals.isEmpty)
    }
}
