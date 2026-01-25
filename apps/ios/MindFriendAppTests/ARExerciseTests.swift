import XCTest
@testable import MindFriendApp

/// Tests for AR Grounding Exercise functionality
@MainActor
final class ARExerciseTests: XCTestCase {

    // MARK: - ARCapabilityService Tests

    func testCapabilityServiceInitialization() {
        let service = ARCapabilityService()

        // Capabilities should be detected on init
        // Note: In simulator, ARKit is typically not available
        XCTAssertNotNil(service.capabilities)
    }

    func testCapabilitiesStructDefaults() {
        let capabilities = ARCapabilities(
            arkit: false,
            trueDepth: false,
            lidar: false
        )

        XCTAssertFalse(capabilities.arkit)
        XCTAssertFalse(capabilities.trueDepth)
        XCTAssertFalse(capabilities.lidar)
    }

    func testCapabilitiesWithFullSupport() {
        let capabilities = ARCapabilities(
            arkit: true,
            trueDepth: true,
            lidar: true
        )

        XCTAssertTrue(capabilities.arkit)
        XCTAssertTrue(capabilities.trueDepth)
        XCTAssertTrue(capabilities.lidar)
    }

    func testCapabilityLevel() {
        // No ARKit = fallback
        let noAR = ARCapabilities(arkit: false, trueDepth: false, lidar: false)
        XCTAssertEqual(noAR.capabilityLevel, .fallback)

        // Basic ARKit = limitedAR
        let basicAR = ARCapabilities(arkit: true, trueDepth: false, lidar: false)
        XCTAssertEqual(basicAR.capabilityLevel, .limitedAR)

        // LiDAR = fullAR
        let fullAR = ARCapabilities(arkit: true, trueDepth: true, lidar: true)
        XCTAssertEqual(fullAR.capabilityLevel, .fullAR)
    }

    // MARK: - ARExercise Model Tests

    func testARExerciseCreation() {
        let exercise = ARExercise(
            id: UUID(),
            exerciseName: "Test Exercise",
            arType: .breathingOrb,
            description: "A test AR exercise",
            durationSeconds: 180,
            instructions: ["Step 1", "Step 2"],
            voiceGuidanceScript: ["Welcome", "Let's begin"],
            sceneConfig: ARSceneConfig(),
            isPremium: false
        )

        XCTAssertEqual(exercise.exerciseName, "Test Exercise")
        XCTAssertEqual(exercise.arType, .breathingOrb)
        XCTAssertEqual(exercise.durationSeconds, 180)
        XCTAssertFalse(exercise.isPremium)
        XCTAssertTrue(exercise.isAvailable)
    }

    func testARExerciseTypeEnum() {
        XCTAssertEqual(ARExerciseTypeEnum.breathingOrb.rawValue, "breathing_orb")
        XCTAssertEqual(ARExerciseTypeEnum.grounding541.rawValue, "grounding_541")
        XCTAssertEqual(ARExerciseTypeEnum.safeSpace.rawValue, "safe_space")
        XCTAssertEqual(ARExerciseTypeEnum.natureImmersion.rawValue, "nature_immersion")
    }

    func testARExerciseTypeDisplayNames() {
        XCTAssertEqual(ARExerciseTypeEnum.breathingOrb.displayName, "Breathing Orb")
        XCTAssertEqual(ARExerciseTypeEnum.grounding541.displayName, "5-4-3-2-1 Grounding")
        XCTAssertEqual(ARExerciseTypeEnum.safeSpace.displayName, "Safe Space")
        XCTAssertEqual(ARExerciseTypeEnum.natureImmersion.displayName, "Nature Immersion")
    }

    func testARExerciseTypeFallbackSupport() {
        XCTAssertTrue(ARExerciseTypeEnum.breathingOrb.supportsFallback)
        XCTAssertTrue(ARExerciseTypeEnum.grounding541.supportsFallback)
        XCTAssertFalse(ARExerciseTypeEnum.safeSpace.supportsFallback)
        XCTAssertFalse(ARExerciseTypeEnum.natureImmersion.supportsFallback)
    }

    // MARK: - BreathPattern Tests

    func testBreathPatternDefaults() {
        let pattern = BreathPattern()

        XCTAssertEqual(pattern.inhale, 4)
        XCTAssertEqual(pattern.hold, 2)
        XCTAssertEqual(pattern.exhale, 6)
    }

    func testBreathPatternCycleDuration() {
        let pattern = BreathPattern(inhale: 4, hold: 4, exhale: 4)
        XCTAssertEqual(pattern.cycleDuration, 12)
    }

    func testBreathPatternCustomValues() {
        let pattern = BreathPattern(inhale: 5, hold: 5, exhale: 10)

        XCTAssertEqual(pattern.inhale, 5)
        XCTAssertEqual(pattern.hold, 5)
        XCTAssertEqual(pattern.exhale, 10)
        XCTAssertEqual(pattern.cycleDuration, 20)
    }

    // MARK: - MarkerColors Tests

    func testMarkerColorsDefaults() {
        let colors = MarkerColors()

        XCTAssertEqual(colors.see, "#3B82F6")
        XCTAssertEqual(colors.touch, "#10B981")
        XCTAssertEqual(colors.hear, "#F59E0B")
        XCTAssertEqual(colors.smell, "#F97316")
        XCTAssertEqual(colors.taste, "#8B5CF6")
    }

    func testMarkerColorsCustomValues() {
        let colors = MarkerColors(
            see: "#FF0000",
            touch: "#00FF00",
            hear: "#0000FF",
            smell: "#FFFF00",
            taste: "#FF00FF"
        )

        XCTAssertEqual(colors.see, "#FF0000")
        XCTAssertEqual(colors.touch, "#00FF00")
        XCTAssertEqual(colors.hear, "#0000FF")
        XCTAssertEqual(colors.smell, "#FFFF00")
        XCTAssertEqual(colors.taste, "#FF00FF")
    }

    // MARK: - ARSceneConfig Tests

    func testARSceneConfigDefaults() {
        let config = ARSceneConfig()

        XCTAssertNil(config.breathPattern)
        XCTAssertNil(config.markerColors)
        XCTAssertNil(config.orbColor)
        XCTAssertNil(config.particleCount)
    }

    func testARSceneConfigWithBreathPattern() {
        let pattern = BreathPattern(inhale: 4, hold: 4, exhale: 8)
        let config = ARSceneConfig(breathPattern: pattern)

        XCTAssertNotNil(config.breathPattern)
        XCTAssertEqual(config.breathPattern?.inhale, 4)
        XCTAssertEqual(config.breathPattern?.exhale, 8)
    }

    // MARK: - GroundingStep Tests

    func testGroundingStepCounts() {
        XCTAssertEqual(GroundingStep.see.rawValue, 5)
        XCTAssertEqual(GroundingStep.touch.rawValue, 4)
        XCTAssertEqual(GroundingStep.hear.rawValue, 3)
        XCTAssertEqual(GroundingStep.smell.rawValue, 2)
        XCTAssertEqual(GroundingStep.taste.rawValue, 1)
    }

    func testGroundingStepDisplayNames() {
        XCTAssertEqual(GroundingStep.see.displayName, "See")
        XCTAssertEqual(GroundingStep.touch.displayName, "Touch")
        XCTAssertEqual(GroundingStep.hear.displayName, "Hear")
        XCTAssertEqual(GroundingStep.smell.displayName, "Smell")
        XCTAssertEqual(GroundingStep.taste.displayName, "Taste")
    }

    // MARK: - ARBreathingPhase Tests

    func testARBreathingPhaseProgression() {
        XCTAssertEqual(ARBreathingPhase.inhale.next, .hold)
        XCTAssertEqual(ARBreathingPhase.hold.next, .exhale)
        XCTAssertEqual(ARBreathingPhase.exhale.next, .inhale)
    }

    func testARBreathingPhaseInstructions() {
        XCTAssertEqual(ARBreathingPhase.inhale.instruction, "Breathe In")
        XCTAssertEqual(ARBreathingPhase.hold.instruction, "Hold")
        XCTAssertEqual(ARBreathingPhase.exhale.instruction, "Breathe Out")
    }

    // MARK: - ARTrackingQuality Tests

    func testTrackingQualityValues() {
        XCTAssertEqual(ARTrackingQuality.normal.qualityValue, 1.0)
        XCTAssertEqual(ARTrackingQuality.notAvailable.qualityValue, 0.0)

        // Limited tracking should have value between 0 and 1
        let limited = ARTrackingQuality.limited(reason: nil)
        XCTAssertEqual(limited.qualityValue, 0.5)
    }

    func testTrackingQualityMessages() {
        XCTAssertNil(ARTrackingQuality.normal.limitedTrackingMessage)
        XCTAssertNil(ARTrackingQuality.notAvailable.limitedTrackingMessage)

        // Limited without reason
        let limitedNoReason = ARTrackingQuality.limited(reason: nil)
        XCTAssertEqual(limitedNoReason.limitedTrackingMessage, "Limited tracking")
    }

    // MARK: - ARSceneData Tests

    func testARSceneDataCreation() {
        let objects = [
            ARSceneObject(
                objectType: "plant",
                positionX: 0.0,
                positionY: 0.0,
                positionZ: -1.0,
                scale: 0.5
            )
        ]
        let prefs = AREnvironmentPrefs.default

        let sceneData = ARSceneData(objects: objects, environmentPrefs: prefs)

        XCTAssertEqual(sceneData.objects.count, 1)
        XCTAssertEqual(sceneData.objects[0].objectType, "plant")
    }

    func testARSceneObjectCreation() {
        let object = ARSceneObject(
            objectType: "crystal",
            positionX: 1.0,
            positionY: 0.5,
            positionZ: -2.0,
            scale: 0.3
        )

        XCTAssertEqual(object.objectType, "crystal")
        XCTAssertEqual(object.positionX, 1.0)
        XCTAssertEqual(object.positionY, 0.5)
        XCTAssertEqual(object.positionZ, -2.0)
        XCTAssertEqual(object.scale, 0.3)
    }

    func testAREnvironmentPrefsDefault() {
        let prefs = AREnvironmentPrefs.default

        XCTAssertEqual(prefs.lightingIntensity, 0.7)
        XCTAssertEqual(prefs.ambientAudioVolume, 0.5)
        XCTAssertTrue(prefs.particleEffectsEnabled)
    }

    // MARK: - ARExerciseSession Tests

    func testARExerciseSessionCreation() {
        let sessionId = UUID()
        let userId = UUID()
        let exerciseTypeId = UUID()

        let session = ARExerciseSession(
            id: sessionId,
            userId: userId,
            exerciseTypeId: exerciseTypeId,
            startedAt: Date(),
            completedAt: nil,
            effectivenessRating: nil,
            trackingQualityAvg: 0.9,
            interruptionsCount: 0,
            deviceCapability: "full_ar",
            usedVoiceGuidance: false,
            completedSteps: 0
        )

        XCTAssertEqual(session.id, sessionId)
        XCTAssertEqual(session.userId, userId)
        XCTAssertEqual(session.exerciseTypeId, exerciseTypeId)
        XCTAssertNil(session.completedAt)
        XCTAssertEqual(session.completedSteps, 0)
        XCTAssertFalse(session.isCompleted)
        XCTAssertEqual(session.trackingQualityAvg, 0.9)
    }

    // MARK: - ARExerciseError Tests

    func testARExerciseErrorDescriptions() {
        XCTAssertEqual(
            ARExerciseError.deviceNotSupported.localizedDescription,
            "AR is not supported on this device"
        )
        XCTAssertEqual(
            ARExerciseError.cameraPermissionDenied.localizedDescription,
            "Camera access is required for AR exercises"
        )
        XCTAssertEqual(
            ARExerciseError.sessionNotFound.localizedDescription,
            "Session not found"
        )
        XCTAssertNotNil(ARExerciseError.trackingFailed.localizedDescription)
        XCTAssertEqual(
            ARExerciseError.premiumRequired.localizedDescription,
            "This exercise requires a premium subscription"
        )
    }

    // MARK: - Capability Service Logic Tests

    func testCanRunExerciseWithoutARKit() {
        let service = ARCapabilityService()

        // Create a test exercise
        let exercise = ARExercise(
            id: UUID(),
            exerciseName: "Test",
            arType: .breathingOrb,
            description: "Test",
            durationSeconds: 60,
            instructions: [],
            voiceGuidanceScript: [],
            sceneConfig: ARSceneConfig(),
            isPremium: false
        )

        // In simulator, ARKit is typically not available
        // The service should handle this gracefully
        let result = service.canRun(exercise: exercise)
        let shouldFallback = service.shouldUseFallback(for: exercise)

        // If ARKit is not available, should use fallback
        if !service.capabilities.arkit {
            XCTAssertTrue(result.canRun || shouldFallback) // Breathing supports fallback
        }
    }

    func testSuggestFallbackForNonARDevice() {
        let service = ARCapabilityService()

        let exercise = ARExercise(
            id: UUID(),
            exerciseName: "Test",
            arType: .grounding541,
            description: "Test",
            durationSeconds: 120,
            instructions: [],
            voiceGuidanceScript: [],
            sceneConfig: ARSceneConfig(),
            isPremium: false
        )

        let fallbacks = service.suggestFallback(for: exercise)
        XCTAssertFalse(fallbacks.isEmpty)
        // Should contain grounding-related fallback suggestions
        XCTAssertTrue(fallbacks.contains { $0.contains("Grounding") || $0.contains("grounding") || $0.contains("Body") })
    }

    // MARK: - ARScenePreference Tests

    func testARScenePreferenceCreation() {
        let sceneData = ARSceneData(
            objects: [],
            environmentPrefs: .default
        )

        let preference = ARScenePreference(
            id: UUID(),
            userId: UUID(),
            sceneName: "My Safe Space",
            sceneData: sceneData,
            isDefault: true,
            createdAt: Date(),
            updatedAt: Date()
        )

        XCTAssertEqual(preference.sceneName, "My Safe Space")
        XCTAssertTrue(preference.isDefault)
    }
}

// MARK: - Integration Tests

@MainActor
final class ARExerciseIntegrationTests: XCTestCase {

    func testARCapabilityDetectionFlow() {
        // Test the full flow of capability detection
        let service = ARCapabilityService()

        // Refresh capabilities
        service.refreshCapabilities()

        // Capabilities should be populated
        let caps = service.capabilities
        XCTAssertNotNil(caps)

        // All boolean values should be accessible
        _ = caps.arkit
        _ = caps.trueDepth
        _ = caps.lidar
    }

    func testGroundingStepCompleteFlow() {
        // Test progressing through all 5-4-3-2-1 steps
        var totalItems = 0
        
        for step in GroundingStep.allCases {
            totalItems += step.rawValue
        }

        // 5 + 4 + 3 + 2 + 1 = 15
        XCTAssertEqual(totalItems, 15)
    }

    func testBreathingCycleFlow() {
        // Test a complete breathing cycle
        let pattern = BreathPattern()
        var currentPhase: ARBreathingPhase = .inhale

        var totalDuration = 0

        // One complete cycle
        totalDuration += pattern.inhale
        currentPhase = currentPhase.next
        XCTAssertEqual(currentPhase, .hold)

        totalDuration += pattern.hold
        currentPhase = currentPhase.next
        XCTAssertEqual(currentPhase, .exhale)

        totalDuration += pattern.exhale
        currentPhase = currentPhase.next
        XCTAssertEqual(currentPhase, .inhale) // Cycles back

        XCTAssertEqual(totalDuration, pattern.cycleDuration)
    }
}
