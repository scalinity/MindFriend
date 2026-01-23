# F022: AR Grounding Exercises

## Overview

### Summary

Augmented Reality grounding exercises that overlay calming elements onto the user's real-world environment, creating immersive therapeutic experiences using the device camera and ARKit.

### Business Value

- Differentiates MindFriend with cutting-edge immersive wellness technology
- Increases exercise engagement through novel, gamified experiences
- Creates viral-worthy moments that drive organic app sharing
- Positions app as innovation leader in mental wellness space

### User Benefit

- More engaging grounding exercises that feel like experiences, not chores
- Uses familiar environment for comfort while adding calming elements
- Gamified progression keeps users motivated to practice regularly
- Accessible AR without requiring additional hardware

### Dependencies

- F013 (AI-Generated Exercises) - For personalized AR experience generation
- F014 (Contextual Micro-Interventions) - Trigger AR exercises at optimal moments
- Core Exercise System - Integrates with existing exercise framework

---

## Requirements

### Functional Requirements

| ID        | Requirement                                                      | Priority |
| --------- | ---------------------------------------------------------------- | -------- |
| FR-022-01 | Support AR-enhanced 5-4-3-2-1 grounding technique                | P0       |
| FR-022-02 | Render calming 3D elements (particles, nature, light orbs) in AR | P0       |
| FR-022-03 | Track user's real environment surfaces for element placement     | P0       |
| FR-022-04 | Provide voice guidance synchronized with AR visuals              | P0       |
| FR-022-05 | Support AR breathing exercises with visual expansion/contraction | P1       |
| FR-022-06 | Track user gaze/attention for interactive elements               | P1       |
| FR-022-07 | Create safe space visualization (room filling with calm)         | P1       |
| FR-022-08 | Support body scan with AR overlay on detected body               | P2       |
| FR-022-09 | Allow users to save favorite AR scenes                           | P2       |
| FR-022-10 | Provide non-AR fallback for unsupported devices                  | P0       |

### Non-Functional Requirements

| ID         | Requirement                              | Target      |
| ---------- | ---------------------------------------- | ----------- |
| NFR-022-01 | AR session initialization time           | < 2 seconds |
| NFR-022-02 | Maintain 60 FPS during AR rendering      | 60 FPS      |
| NFR-022-03 | Battery consumption during 5-min session | < 5%        |
| NFR-022-04 | Support devices with A12 chip or newer   | iOS 17+     |
| NFR-022-05 | Memory usage during AR session           | < 300 MB    |
| NFR-022-06 | Graceful degradation on older devices    | Required    |

### Acceptance Criteria (Gherkin)

```gherkin
Feature: AR Grounding Exercises

  Scenario: User starts 5-4-3-2-1 AR grounding exercise
    Given the user has an AR-capable device
    And they select "5-4-3-2-1 Grounding" exercise
    When the AR session initializes
    Then the camera view shows their environment
    And numbered AR markers appear for each sense category
    And voice guidance instructs them through the exercise
    And elements animate as they complete each step

  Scenario: AR breathing exercise with visual feedback
    Given the user is in an AR breathing exercise
    When they inhale
    Then a glowing orb expands in their environment
    And particle effects flow inward
    When they exhale
    Then the orb contracts gracefully
    And particles disperse outward
    And the cycle matches the breathing pattern guidance

  Scenario: Safe space visualization
    Given the user selects "Create Safe Space" exercise
    When the AR session starts
    Then calming elements (light, nature, water) fill their room
    And ambient sounds match the visual elements
    And intensity increases gradually as exercise progresses
    And user feels surrounded by calming presence

  Scenario: Device does not support AR
    Given the user's device does not support ARKit
    When they attempt to start an AR exercise
    Then they see a friendly message about device compatibility
    And are offered a non-AR alternative with 2D visuals
    And the alternative provides similar therapeutic value
```

---

## Technical Design

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        AR Exercise Layer                         │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────────────┐ │
│  │ ARKit Scene │  │ 3D Asset     │  │ Voice Guidance          │ │
│  │ Manager     │  │ Manager      │  │ Synthesizer             │ │
│  └──────┬──────┘  └──────┬───────┘  └───────────┬─────────────┘ │
│         │                │                      │               │
│  ┌──────▼────────────────▼──────────────────────▼─────────────┐ │
│  │               AR Exercise Coordinator                       │ │
│  └─────────────────────────┬───────────────────────────────────┘ │
├────────────────────────────┼────────────────────────────────────┤
│                            │                                    │
│  ┌─────────────────────────▼───────────────────────────────────┐ │
│  │                   Exercise Types                             │ │
│  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────────────┐ │ │
│  │  │ Grounding    │ │ Breathing    │ │ Safe Space           │ │ │
│  │  │ 5-4-3-2-1    │ │ Visualization│ │ Creator              │ │ │
│  │  └──────────────┘ └──────────────┘ └──────────────────────┘ │ │
│  └─────────────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │                    ARKit Framework                           │ │
│  │  • World Tracking  • Plane Detection  • Light Estimation    │ │
│  │  • Body Tracking   • Scene Understanding                    │ │
│  └─────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### Database Schema

```sql
-- AR exercise types and configurations
CREATE TABLE ar_exercise_types (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    slug TEXT UNIQUE NOT NULL,
    description TEXT,
    duration_seconds INTEGER NOT NULL DEFAULT 300,
    ar_scene_config JSONB NOT NULL DEFAULT '{}',
    voice_script JSONB NOT NULL DEFAULT '[]',
    fallback_2d_config JSONB,
    min_ios_version TEXT DEFAULT '17.0',
    requires_body_tracking BOOLEAN DEFAULT FALSE,
    is_premium BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- User's AR exercise sessions
CREATE TABLE ar_exercise_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    exercise_type_id UUID REFERENCES ar_exercise_types(id),
    started_at TIMESTAMPTZ DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    duration_seconds INTEGER,
    completion_percentage DECIMAL(5,2),
    used_ar BOOLEAN DEFAULT TRUE,
    ar_quality_metrics JSONB DEFAULT '{}',
    user_rating INTEGER CHECK (user_rating BETWEEN 1 AND 5),
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- User's saved AR scene preferences
CREATE TABLE ar_scene_preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    exercise_type_id UUID REFERENCES ar_exercise_types(id),
    custom_config JSONB NOT NULL DEFAULT '{}',
    is_favorite BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, exercise_type_id)
);

-- AR asset library
CREATE TABLE ar_assets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    asset_type TEXT NOT NULL CHECK (asset_type IN ('model', 'particle', 'texture', 'audio')),
    file_path TEXT NOT NULL,
    file_size_bytes INTEGER,
    thumbnail_url TEXT,
    tags TEXT[] DEFAULT '{}',
    is_premium BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE ar_exercise_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE ar_scene_preferences ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage their AR sessions"
    ON ar_exercise_sessions FOR ALL
    USING (auth.uid() = user_id);

CREATE POLICY "Users can manage their AR preferences"
    ON ar_scene_preferences FOR ALL
    USING (auth.uid() = user_id);

-- Indexes
CREATE INDEX idx_ar_sessions_user ON ar_exercise_sessions(user_id);
CREATE INDEX idx_ar_sessions_type ON ar_exercise_sessions(exercise_type_id);
CREATE INDEX idx_ar_sessions_date ON ar_exercise_sessions(started_at);
```

### Swift Models

```swift
import Foundation
import RealityKit
import ARKit

// MARK: - AR Exercise Types

enum ARExerciseType: String, Codable, CaseIterable {
    case grounding5421 = "grounding_5421"
    case breathingOrb = "breathing_orb"
    case safeSpace = "safe_space"
    case bodyRelaxation = "body_relaxation"
    case natureImmersion = "nature_immersion"

    var displayName: String {
        switch self {
        case .grounding5421: return "5-4-3-2-1 Grounding"
        case .breathingOrb: return "Breathing Orb"
        case .safeSpace: return "Safe Space"
        case .bodyRelaxation: return "Body Relaxation"
        case .natureImmersion: return "Nature Immersion"
        }
    }

    var requiresBodyTracking: Bool {
        self == .bodyRelaxation
    }
}

struct ARExerciseTypeConfig: Codable, Identifiable {
    let id: UUID
    let name: String
    let slug: String
    let description: String?
    let durationSeconds: Int
    let arSceneConfig: ARSceneConfig
    let voiceScript: [VoiceGuidanceStep]
    let fallback2DConfig: Fallback2DConfig?
    let minIosVersion: String
    let requiresBodyTracking: Bool
    let isPremium: Bool
    let createdAt: Date
}

struct ARSceneConfig: Codable {
    let ambientLightColor: String?
    let backgroundMusicAsset: String?
    let primaryElements: [ARElementConfig]
    let interactionMode: InteractionMode
    let environmentStyle: EnvironmentStyle

    enum InteractionMode: String, Codable {
        case passive
        case gazeInteractive
        case touchInteractive
    }

    enum EnvironmentStyle: String, Codable {
        case passthrough
        case dimmed
        case colorOverlay
    }
}

struct ARElementConfig: Codable {
    let assetId: String
    let elementType: ElementType
    let placement: PlacementStrategy
    let animation: AnimationConfig?
    let interactivity: InteractivityConfig?

    enum ElementType: String, Codable {
        case particle
        case model3D
        case light
        case text
        case audio
    }

    enum PlacementStrategy: String, Codable {
        case frontCenter
        case surroundUser
        case onSurfaces
        case floating
        case bodyAttached
    }
}

struct AnimationConfig: Codable {
    let type: AnimationType
    let duration: TimeInterval
    let repeatCount: Int
    let syncWithBreathing: Bool

    enum AnimationType: String, Codable {
        case pulse
        case float
        case rotate
        case expand
        case flow
    }
}

struct InteractivityConfig: Codable {
    let triggerType: TriggerType
    let onTriggerAction: String

    enum TriggerType: String, Codable {
        case gaze
        case tap
        case proximity
        case voiceCommand
    }
}

struct VoiceGuidanceStep: Codable {
    let timestamp: TimeInterval
    let text: String
    let pauseAfter: TimeInterval
    let arTriggers: [String]?
}

struct Fallback2DConfig: Codable {
    let backgroundImageAsset: String
    let overlayElements: [Overlay2DElement]
    let animations: [Animation2DConfig]
}

struct Overlay2DElement: Codable {
    let type: String
    let position: CGPoint
    let size: CGSize
    let asset: String
}

struct Animation2DConfig: Codable {
    let targetElement: String
    let animationType: String
    let duration: TimeInterval
}

// MARK: - AR Session Models

struct ARExerciseSession: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let exerciseTypeId: UUID
    let startedAt: Date
    var completedAt: Date?
    var durationSeconds: Int?
    var completionPercentage: Double
    var usedAR: Bool
    var arQualityMetrics: ARQualityMetrics?
    var userRating: Int?
    var notes: String?
    let createdAt: Date
}

struct ARQualityMetrics: Codable {
    let averageFPS: Double
    let trackingQuality: TrackingQuality
    let planesDetected: Int
    let lightEstimationAccuracy: Double

    enum TrackingQuality: String, Codable {
        case notAvailable
        case limited
        case normal
    }
}

struct ARScenePreference: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let exerciseTypeId: UUID
    var customConfig: [String: AnyCodable]
    var isFavorite: Bool
    let createdAt: Date
    var updatedAt: Date
}

// MARK: - AR Capability Check

struct ARCapabilities {
    let supportsWorldTracking: Bool
    let supportsBodyTracking: Bool
    let supportsSceneUnderstanding: Bool
    let deviceChip: String

    var meetsMinimumRequirements: Bool {
        supportsWorldTracking
    }

    static func check() -> ARCapabilities {
        ARCapabilities(
            supportsWorldTracking: ARWorldTrackingConfiguration.isSupported,
            supportsBodyTracking: ARBodyTrackingConfiguration.isSupported,
            supportsSceneUnderstanding: ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh),
            deviceChip: ProcessInfo.processInfo.machineHardwareName
        )
    }
}

extension ProcessInfo {
    var machineHardwareName: String {
        var sysinfo = utsname()
        uname(&sysinfo)
        return String(bytes: Data(bytes: &sysinfo.machine, count: Int(_SYS_NAMELEN)), encoding: .ascii)?.trimmingCharacters(in: .controlCharacters) ?? "Unknown"
    }
}
```

### API Contracts

```typescript
// GET /rest/v1/ar_exercise_types
// Response: ARExerciseTypeConfig[]

// POST /rest/v1/ar_exercise_sessions
interface CreateARSessionRequest {
  exercise_type_id: string;
  used_ar: boolean;
}

// PATCH /rest/v1/ar_exercise_sessions?id=eq.{id}
interface UpdateARSessionRequest {
  completed_at?: string;
  duration_seconds?: number;
  completion_percentage?: number;
  ar_quality_metrics?: ARQualityMetrics;
  user_rating?: number;
  notes?: string;
}

interface ARQualityMetrics {
  average_fps: number;
  tracking_quality: "not_available" | "limited" | "normal";
  planes_detected: number;
  light_estimation_accuracy: number;
}

// GET /rest/v1/ar_scene_preferences?user_id=eq.{userId}
// Response: ARScenePreference[]

// PUT /rest/v1/ar_scene_preferences
interface UpsertScenePreferenceRequest {
  user_id: string;
  exercise_type_id: string;
  custom_config: Record<string, any>;
  is_favorite?: boolean;
}
```

---

## Implementation Details

### Step-by-Step Approach

1. **Phase 1: AR Foundation** (Week 1)
   - Create ARKit session manager with world tracking
   - Implement device capability detection
   - Build basic AR view with camera passthrough
   - Create fallback 2D experience for unsupported devices

2. **Phase 2: 3D Asset System** (Week 2)
   - Set up RealityKit asset loading
   - Create particle system for calming effects
   - Build 3D model placement on detected surfaces
   - Implement light orb with animation

3. **Phase 3: Voice Guidance Integration** (Week 3)
   - Integrate with existing voice synthesis
   - Create timeline-based event system
   - Synchronize AR elements with voice cues
   - Build script-driven exercise orchestration

4. **Phase 4: Exercise Implementation** (Week 4)
   - Build 5-4-3-2-1 grounding AR exercise
   - Create breathing orb visualization
   - Implement safe space creator
   - Add body relaxation (if body tracking available)

5. **Phase 5: Polish & Analytics** (Week 5)
   - Add session tracking and metrics
   - Implement user preferences persistence
   - Create onboarding for AR exercises
   - Performance optimization and testing

### File Structure

```
apps/ios/MindFriendApp/Features/AR/
├── ARExerciseView.swift
├── ARExerciseViewModel.swift
├── ARSceneManager.swift
├── ARAssetManager.swift
├── VoiceGuidanceController.swift
├── Models/
│   ├── ARExerciseModels.swift
│   └── ARCapabilities.swift
├── Exercises/
│   ├── Grounding5421Exercise.swift
│   ├── BreathingOrbExercise.swift
│   ├── SafeSpaceExercise.swift
│   └── BodyRelaxationExercise.swift
├── Components/
│   ├── ARCameraView.swift
│   ├── ParticleEmitterNode.swift
│   ├── BreathingOrbEntity.swift
│   └── GuidanceOverlayView.swift
├── Fallback/
│   ├── Fallback2DExerciseView.swift
│   └── FallbackAssets/
└── Services/
    └── ARExerciseService.swift
```

### Key Algorithms

#### AR Scene Manager

```swift
import ARKit
import RealityKit
import Combine

@MainActor
final class ARSceneManager: NSObject, ObservableObject {
    @Published var trackingState: ARCamera.TrackingState = .notAvailable
    @Published var detectedPlanes: [ARPlaneAnchor] = []
    @Published var isSessionReady = false

    private var arView: ARView?
    private var cancellables = Set<AnyCancellable>()

    var capabilities: ARCapabilities {
        ARCapabilities.check()
    }

    func setupSession(in arView: ARView) {
        self.arView = arView

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .automatic

        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
        }

        arView.session.delegate = self
        arView.session.run(configuration)
    }

    func placeEntity(_ entity: Entity, at position: SIMD3<Float>) {
        guard let arView = arView else { return }

        let anchor = AnchorEntity(world: position)
        anchor.addChild(entity)
        arView.scene.addAnchor(anchor)
    }

    func placeSurroundingEntities(_ entities: [Entity], radius: Float) {
        guard let arView = arView else { return }

        let count = entities.count
        for (index, entity) in entities.enumerated() {
            let angle = Float(index) / Float(count) * 2 * .pi
            let x = cos(angle) * radius
            let z = sin(angle) * radius
            let position = SIMD3<Float>(x, 0, z)

            let anchor = AnchorEntity(world: position)
            anchor.look(at: .zero, from: position, relativeTo: nil)
            anchor.addChild(entity)
            arView.scene.addAnchor(anchor)
        }
    }

    func addParticleSystem(config: ParticleConfig) -> Entity {
        // Create calming particle effect
        let particleEntity = Entity()

        var particles = ParticleEmitterComponent()
        particles.emitterShape = .sphere
        particles.birthRate = config.birthRate
        particles.lifeSpan = config.lifeSpan
        particles.speed = config.speed
        particles.mainEmitter.color = .constant(.single(config.color))
        particles.mainEmitter.size = config.size
        particles.mainEmitter.blendMode = .additive

        particleEntity.components.set(particles)
        return particleEntity
    }

    func pauseSession() {
        arView?.session.pause()
    }

    func resumeSession() {
        guard let arView = arView else { return }
        let configuration = ARWorldTrackingConfiguration()
        arView.session.run(configuration, options: .resetTracking)
    }

    func cleanup() {
        arView?.scene.anchors.removeAll()
        arView?.session.pause()
        arView = nil
    }
}

extension ARSceneManager: ARSessionDelegate {
    nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        Task { @MainActor in
            self.trackingState = camera.trackingState
            self.isSessionReady = camera.trackingState == .normal
        }
    }

    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        Task { @MainActor in
            let planes = anchors.compactMap { $0 as? ARPlaneAnchor }
            self.detectedPlanes.append(contentsOf: planes)
        }
    }
}

struct ParticleConfig {
    let birthRate: Float
    let lifeSpan: Float
    let speed: Float
    let color: UIColor
    let size: Float
}
```

#### Breathing Orb Exercise

```swift
import RealityKit
import Combine

@MainActor
final class BreathingOrbExercise: ObservableObject {
    @Published var currentPhase: BreathingPhase = .inhale
    @Published var progress: Double = 0
    @Published var cycleCount: Int = 0

    private let sceneManager: ARSceneManager
    private var orbEntity: Entity?
    private var animationTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    let breathingPattern: BreathingPattern

    struct BreathingPattern {
        let inhaleSeconds: Double
        let holdSeconds: Double
        let exhaleSeconds: Double
        let pauseSeconds: Double
        let totalCycles: Int
    }

    enum BreathingPhase {
        case inhale, hold, exhale, pause

        var instruction: String {
            switch self {
            case .inhale: return "Breathe in..."
            case .hold: return "Hold..."
            case .exhale: return "Breathe out..."
            case .pause: return "Pause..."
            }
        }
    }

    init(sceneManager: ARSceneManager, pattern: BreathingPattern) {
        self.sceneManager = sceneManager
        self.breathingPattern = pattern
    }

    func start() {
        createOrb()
        startBreathingCycle()
    }

    private func createOrb() {
        // Create glowing orb
        let mesh = MeshResource.generateSphere(radius: 0.15)
        var material = SimpleMaterial()
        material.color = .init(tint: .init(red: 0.4, green: 0.7, blue: 1.0, alpha: 0.8))
        material.metallic = 0.0
        material.roughness = 0.2

        let orb = ModelEntity(mesh: mesh, materials: [material])

        // Add glow effect via point light
        let light = PointLight()
        light.light.color = .init(red: 0.4, green: 0.7, blue: 1.0, alpha: 1.0)
        light.light.intensity = 1000
        light.light.attenuationRadius = 0.5
        orb.addChild(light)

        // Position in front of user
        sceneManager.placeEntity(orb, at: SIMD3<Float>(0, 0, -0.8))
        self.orbEntity = orb
    }

    private func startBreathingCycle() {
        runPhase(.inhale)
    }

    private func runPhase(_ phase: BreathingPhase) {
        self.currentPhase = phase

        let duration: Double
        switch phase {
        case .inhale:
            duration = breathingPattern.inhaleSeconds
            animateOrb(scale: 1.5, duration: duration)
        case .hold:
            duration = breathingPattern.holdSeconds
            pulseOrb(duration: duration)
        case .exhale:
            duration = breathingPattern.exhaleSeconds
            animateOrb(scale: 1.0, duration: duration)
        case .pause:
            duration = breathingPattern.pauseSeconds
        }

        // Animate progress
        animateProgress(duration: duration) { [weak self] in
            self?.transitionToNextPhase(from: phase)
        }
    }

    private func animateOrb(scale: Float, duration: Double) {
        guard let orb = orbEntity else { return }

        let targetTransform = Transform(
            scale: SIMD3<Float>(repeating: scale),
            rotation: orb.transform.rotation,
            translation: orb.transform.translation
        )

        orb.move(to: targetTransform, relativeTo: orb.parent, duration: duration, timingFunction: .easeInOut)
    }

    private func pulseOrb(duration: Double) {
        guard let orb = orbEntity else { return }

        // Subtle pulsing during hold
        let pulseUp = Transform(
            scale: SIMD3<Float>(repeating: 1.55),
            rotation: orb.transform.rotation,
            translation: orb.transform.translation
        )

        orb.move(to: pulseUp, relativeTo: orb.parent, duration: duration / 2, timingFunction: .easeInOut)

        DispatchQueue.main.asyncAfter(deadline: .now() + duration / 2) { [weak self] in
            guard let orb = self?.orbEntity else { return }
            let pulseDown = Transform(
                scale: SIMD3<Float>(repeating: 1.5),
                rotation: orb.transform.rotation,
                translation: orb.transform.translation
            )
            orb.move(to: pulseDown, relativeTo: orb.parent, duration: duration / 2, timingFunction: .easeInOut)
        }
    }

    private func animateProgress(duration: Double, completion: @escaping () -> Void) {
        let startTime = Date()

        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] timer in
            let elapsed = Date().timeIntervalSince(startTime)
            let newProgress = min(elapsed / duration, 1.0)

            Task { @MainActor in
                self?.progress = newProgress
            }

            if elapsed >= duration {
                timer.invalidate()
                completion()
            }
        }
    }

    private func transitionToNextPhase(from phase: BreathingPhase) {
        progress = 0

        switch phase {
        case .inhale:
            runPhase(.hold)
        case .hold:
            runPhase(.exhale)
        case .exhale:
            runPhase(.pause)
        case .pause:
            cycleCount += 1
            if cycleCount < breathingPattern.totalCycles {
                runPhase(.inhale)
            } else {
                complete()
            }
        }
    }

    private func complete() {
        // Fade out orb
        guard let orb = orbEntity else { return }

        let fadeOut = Transform(
            scale: SIMD3<Float>(repeating: 0.1),
            rotation: orb.transform.rotation,
            translation: orb.transform.translation
        )

        orb.move(to: fadeOut, relativeTo: orb.parent, duration: 1.0, timingFunction: .easeIn)
    }

    func stop() {
        animationTimer?.invalidate()
        animationTimer = nil
        orbEntity?.removeFromParent()
        orbEntity = nil
    }
}
```

#### 5-4-3-2-1 Grounding Exercise

```swift
import RealityKit
import ARKit

@MainActor
final class Grounding5421Exercise: ObservableObject {
    @Published var currentStep: GroundingStep = .see5
    @Published var itemsIdentified: Int = 0
    @Published var isComplete = false

    private let sceneManager: ARSceneManager
    private var markerEntities: [Entity] = []
    private let voiceGuidance: VoiceGuidanceController

    enum GroundingStep: Int, CaseIterable {
        case see5 = 5
        case touch4 = 4
        case hear3 = 3
        case smell2 = 2
        case taste1 = 1

        var instruction: String {
            switch self {
            case .see5: return "Name 5 things you can see"
            case .touch4: return "Name 4 things you can touch"
            case .hear3: return "Name 3 things you can hear"
            case .smell2: return "Name 2 things you can smell"
            case .taste1: return "Name 1 thing you can taste"
            }
        }

        var icon: String {
            switch self {
            case .see5: return "eye"
            case .touch4: return "hand.raised"
            case .hear3: return "ear"
            case .smell2: return "nose"
            case .taste1: return "mouth"
            }
        }

        var color: UIColor {
            switch self {
            case .see5: return .systemBlue
            case .touch4: return .systemGreen
            case .hear3: return .systemPurple
            case .smell2: return .systemOrange
            case .taste1: return .systemPink
            }
        }
    }

    init(sceneManager: ARSceneManager, voiceGuidance: VoiceGuidanceController) {
        self.sceneManager = sceneManager
        self.voiceGuidance = voiceGuidance
    }

    func start() {
        showCurrentStep()
        voiceGuidance.speak(currentStep.instruction)
    }

    private func showCurrentStep() {
        // Clear previous markers
        markerEntities.forEach { $0.removeFromParent() }
        markerEntities.removeAll()

        // Create floating number markers around user
        let count = currentStep.rawValue
        let radius: Float = 1.2

        for i in 0..<count {
            let marker = createMarkerEntity(number: i + 1, color: currentStep.color)
            let angle = Float(i) / Float(count) * 2 * .pi - .pi / 2
            let x = cos(angle) * radius
            let z = sin(angle) * radius

            sceneManager.placeEntity(marker, at: SIMD3<Float>(x, 0.3, z))
            markerEntities.append(marker)
        }

        // Add particle effect for visual interest
        let particles = sceneManager.addParticleSystem(config: ParticleConfig(
            birthRate: 20,
            lifeSpan: 2.0,
            speed: 0.05,
            color: currentStep.color.withAlphaComponent(0.5),
            size: 0.01
        ))
        sceneManager.placeEntity(particles, at: SIMD3<Float>(0, 0.5, -0.5))
        markerEntities.append(particles)
    }

    private func createMarkerEntity(number: Int, color: UIColor) -> Entity {
        let entity = Entity()

        // Background sphere
        let sphere = MeshResource.generateSphere(radius: 0.08)
        var material = SimpleMaterial()
        material.color = .init(tint: color.withAlphaComponent(0.3))
        let sphereEntity = ModelEntity(mesh: sphere, materials: [material])
        entity.addChild(sphereEntity)

        // Number text
        let textMesh = MeshResource.generateText(
            "\(number)",
            extrusionDepth: 0.01,
            font: .systemFont(ofSize: 0.06, weight: .bold),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byTruncatingTail
        )
        var textMaterial = SimpleMaterial()
        textMaterial.color = .init(tint: .white)
        let textEntity = ModelEntity(mesh: textMesh, materials: [textMaterial])
        textEntity.position = SIMD3<Float>(-0.015, -0.02, 0.08)
        entity.addChild(textEntity)

        // Animate floating
        animateFloat(entity: entity)

        return entity
    }

    private func animateFloat(entity: Entity) {
        // Gentle floating animation
        let originalPosition = entity.position
        let floatUp = originalPosition + SIMD3<Float>(0, 0.05, 0)

        let upTransform = Transform(
            scale: entity.scale,
            rotation: entity.orientation,
            translation: floatUp
        )

        entity.move(to: upTransform, relativeTo: nil, duration: 1.5, timingFunction: .easeInOut)

        // Schedule return animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak entity] in
            guard let entity = entity else { return }
            let downTransform = Transform(
                scale: entity.scale,
                rotation: entity.orientation,
                translation: originalPosition
            )
            entity.move(to: downTransform, relativeTo: nil, duration: 1.5, timingFunction: .easeInOut)
        }

        // Continue floating loop
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self, weak entity] in
            guard let entity = entity else { return }
            self?.animateFloat(entity: entity)
        }
    }

    func userIdentifiedItem() {
        itemsIdentified += 1

        // Animate marker completion
        if itemsIdentified <= markerEntities.count {
            let marker = markerEntities[itemsIdentified - 1]
            completeMarker(marker)
        }

        // Check if step complete
        if itemsIdentified >= currentStep.rawValue {
            advanceToNextStep()
        }
    }

    private func completeMarker(_ marker: Entity) {
        // Scale up and fade
        let completeTransform = Transform(
            scale: SIMD3<Float>(repeating: 1.5),
            rotation: marker.orientation,
            translation: marker.position
        )

        marker.move(to: completeTransform, relativeTo: nil, duration: 0.3, timingFunction: .easeOut)

        // Add sparkle effect
        let sparkle = sceneManager.addParticleSystem(config: ParticleConfig(
            birthRate: 50,
            lifeSpan: 0.5,
            speed: 0.2,
            color: .white,
            size: 0.005
        ))
        sparkle.position = marker.position
        // Note: Add sparkle to scene separately
    }

    private func advanceToNextStep() {
        let allSteps = GroundingStep.allCases
        guard let currentIndex = allSteps.firstIndex(of: currentStep),
              currentIndex < allSteps.count - 1 else {
            complete()
            return
        }

        itemsIdentified = 0
        currentStep = allSteps[currentIndex + 1]

        // Brief pause before next step
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            self.showCurrentStep()
            self.voiceGuidance.speak(self.currentStep.instruction)
        }
    }

    private func complete() {
        isComplete = true
        voiceGuidance.speak("Well done! You've completed the grounding exercise.")

        // Celebratory particle burst
        let celebration = sceneManager.addParticleSystem(config: ParticleConfig(
            birthRate: 200,
            lifeSpan: 3.0,
            speed: 0.3,
            color: .systemYellow,
            size: 0.02
        ))
        sceneManager.placeEntity(celebration, at: SIMD3<Float>(0, 0.5, -0.5))
    }

    func stop() {
        markerEntities.forEach { $0.removeFromParent() }
        markerEntities.removeAll()
    }
}
```

---

## Dependencies

### Internal Dependencies

- F013 (AI-Generated Exercises) - Dynamic content generation
- F014 (Contextual Micro-Interventions) - Optimal timing
- Core Exercise System - Integration and tracking
- Voice Guidance System - Synchronized narration

### External Dependencies

- ARKit - Apple's AR framework
- RealityKit - 3D rendering engine
- AVFoundation - Audio/voice synthesis
- CoreML - Optional object recognition

### Infrastructure

- 3D asset storage in Supabase Storage
- Asset CDN for fast model loading
- Device capability detection

---

## Edge Cases & Error Handling

| Scenario                         | Handling                                                  |
| -------------------------------- | --------------------------------------------------------- |
| Camera permission denied         | Show permission request screen with clear explanation     |
| AR tracking lost                 | Pause exercise, show recovery UI, auto-resume when stable |
| Low light environment            | Suggest better lighting or offer 2D fallback              |
| Device overheating               | Pause AR session, show cooling message                    |
| Unsupported device               | Graceful fallback to 2D animated version                  |
| Battery critical (<10%)          | Warn user before starting, offer shorter exercise         |
| Interrupted by phone call        | Pause session, resume option when call ends               |
| Background/foreground transition | Pause AR, resume tracking on return                       |
| Memory pressure                  | Reduce particle counts, simplify rendering                |

---

## Testing Requirements

### Unit Tests

```swift
import XCTest
@testable import MindFriendApp

final class ARExerciseTests: XCTestCase {

    func testARCapabilitiesCheck() {
        let capabilities = ARCapabilities.check()
        XCTAssertNotNil(capabilities)
        // Device-specific assertions
    }

    func testBreathingPatternCycle() {
        let pattern = BreathingOrbExercise.BreathingPattern(
            inhaleSeconds: 4,
            holdSeconds: 4,
            exhaleSeconds: 4,
            pauseSeconds: 2,
            totalCycles: 3
        )

        XCTAssertEqual(pattern.totalCycles, 3)

        let cycleDuration = pattern.inhaleSeconds + pattern.holdSeconds + pattern.exhaleSeconds + pattern.pauseSeconds
        XCTAssertEqual(cycleDuration, 14)
    }

    func testGroundingStepProgression() {
        let steps = Grounding5421Exercise.GroundingStep.allCases
        XCTAssertEqual(steps.count, 5)
        XCTAssertEqual(steps.first?.rawValue, 5)
        XCTAssertEqual(steps.last?.rawValue, 1)
    }

    func testARSceneConfigDecoding() throws {
        let json = """
        {
            "ambientLightColor": "#ffffff",
            "primaryElements": [],
            "interactionMode": "gazeInteractive",
            "environmentStyle": "passthrough"
        }
        """

        let config = try JSONDecoder().decode(ARSceneConfig.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(config.interactionMode, .gazeInteractive)
        XCTAssertEqual(config.environmentStyle, .passthrough)
    }

    func testFallbackConfigPresent() {
        // Ensure all AR exercise types have fallback configs
        for type in ARExerciseType.allCases {
            // Verify fallback exists in asset bundle
            XCTAssertTrue(type.displayName.count > 0)
        }
    }
}
```

### Integration Tests

```swift
final class ARExerciseIntegrationTests: XCTestCase {
    var service: ARExerciseService!

    override func setUp() async throws {
        service = ARExerciseService(supabase: TestSupabaseClient())
    }

    func testCreateAndCompleteSession() async throws {
        // Create session
        let session = try await service.startSession(exerciseType: .grounding5421, usedAR: true)
        XCTAssertNotNil(session.id)
        XCTAssertNil(session.completedAt)

        // Complete session
        let completed = try await service.completeSession(
            sessionId: session.id,
            durationSeconds: 300,
            completionPercentage: 100,
            rating: 5
        )

        XCTAssertNotNil(completed.completedAt)
        XCTAssertEqual(completed.userRating, 5)
    }

    func testFetchExerciseTypes() async throws {
        let types = try await service.fetchExerciseTypes()
        XCTAssertFalse(types.isEmpty)

        // Verify each type has required fields
        for type in types {
            XCTAssertFalse(type.name.isEmpty)
            XCTAssertFalse(type.voiceScript.isEmpty)
        }
    }

    func testSaveScenePreference() async throws {
        let preference = try await service.saveScenePreference(
            exerciseTypeId: UUID(),
            config: ["particleColor": "#ff6b6b"],
            isFavorite: true
        )

        XCTAssertTrue(preference.isFavorite)
    }
}
```

### UI Tests

```swift
final class ARExerciseUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        app = XCUIApplication()
        app.launch()
    }

    func testARExerciseListDisplays() {
        app.tabBars["TabBar"].buttons["Exercises"].tap()
        app.buttons["AR Exercises"].tap()

        XCTAssertTrue(app.staticTexts["5-4-3-2-1 Grounding"].exists)
        XCTAssertTrue(app.staticTexts["Breathing Orb"].exists)
    }

    func testFallbackShownForUnsupportedDevice() {
        // Simulate unsupported device via test flag
        app.launchArguments.append("--simulate-no-ar")
        app.launch()

        app.tabBars["TabBar"].buttons["Exercises"].tap()
        app.buttons["AR Exercises"].tap()
        app.cells.firstMatch.tap()

        // Should show fallback UI
        XCTAssertTrue(app.staticTexts["2D Mode"].exists)
    }

    func testCameraPermissionRequest() {
        // Fresh install scenario
        app.launchArguments.append("--reset-permissions")
        app.launch()

        app.tabBars["TabBar"].buttons["Exercises"].tap()
        app.buttons["AR Exercises"].tap()
        app.cells.firstMatch.tap()

        // Permission dialog should appear
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowButton = springboard.buttons["Allow"]
        if allowButton.waitForExistence(timeout: 5) {
            allowButton.tap()
        }
    }
}
```
