import Foundation
import ARKit
import SceneKit

// MARK: - AR Capability Detection

/// Device AR capability level
public enum ARCapability: String, Codable, CaseIterable {
    case fullAR = "full_ar"         // ARWorldTracking + LiDAR + all features
    case limitedAR = "limited_ar"   // Basic ARWorldTracking without LiDAR
    case fallback = "fallback"      // No AR support, use 2D fallback

    /// Human-readable description
    var displayName: String {
        switch self {
        case .fullAR: return "Full AR"
        case .limitedAR: return "Basic AR"
        case .fallback: return "Standard Mode"
        }
    }
}

/// Device capabilities for AR features
public struct ARCapabilities: Codable, Equatable {
    public let arkit: Bool
    public let trueDepth: Bool
    public let lidar: Bool

    public init(arkit: Bool, trueDepth: Bool, lidar: Bool) {
        self.arkit = arkit
        self.trueDepth = trueDepth
        self.lidar = lidar
    }

    /// Detect current device AR capabilities
    public static func detect() -> ARCapabilities {
        let arkitSupported = ARWorldTrackingConfiguration.isSupported

        // TrueDepth camera (iPhone X and later)
        let trueDepthSupported = ARFaceTrackingConfiguration.isSupported

        // LiDAR scanner (iPhone 12 Pro and later)
        let lidarSupported: Bool
        if #available(iOS 13.4, *) {
            lidarSupported = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        } else {
            lidarSupported = false
        }

        return ARCapabilities(
            arkit: arkitSupported,
            trueDepth: trueDepthSupported,
            lidar: lidarSupported
        )
    }

    /// Determine overall capability level
    public var capabilityLevel: ARCapability {
        if !arkit {
            return .fallback
        }
        if lidar {
            return .fullAR
        }
        return .limitedAR
    }

    /// Check if device meets requirements for specific capabilities
    public func meets(requirements: ARCapabilities) -> Bool {
        if requirements.arkit && !arkit { return false }
        if requirements.trueDepth && !trueDepth { return false }
        if requirements.lidar && !lidar { return false }
        return true
    }
}

// MARK: - AR Exercise Type

/// Types of AR exercises available
public enum ARExerciseTypeEnum: String, Codable, CaseIterable {
    case breathingOrb = "breathing_orb"
    case grounding541 = "grounding_541"
    case safeSpace = "safe_space"
    case natureImmersion = "nature_immersion"

    /// Human-readable name
    var displayName: String {
        switch self {
        case .breathingOrb: return "Breathing Orb"
        case .grounding541: return "5-4-3-2-1 Grounding"
        case .safeSpace: return "Safe Space"
        case .natureImmersion: return "Nature Immersion"
        }
    }

    /// SF Symbol name for exercise icon
    var iconName: String {
        switch self {
        case .breathingOrb: return "circle.hexagongrid.fill"
        case .grounding541: return "hand.point.up.fill"
        case .safeSpace: return "house.fill"
        case .natureImmersion: return "leaf.fill"
        }
    }

    /// Whether this exercise supports fallback mode
    var supportsFallback: Bool {
        switch self {
        case .breathingOrb, .grounding541:
            return true
        case .safeSpace, .natureImmersion:
            return false
        }
    }
}

// MARK: - AR Exercise

/// AR exercise definition from database
public struct ARExercise: Codable, Identifiable, Equatable {
    public let id: UUID
    public let exerciseName: String
    public let arType: ARExerciseTypeEnum
    public let description: String
    public let durationSeconds: Int
    public let instructions: [String]
    public let voiceGuidanceScript: [String]
    public let sceneConfig: ARSceneConfig
    public let isPremium: Bool
    public var isAvailable: Bool
    public var unavailableReason: String?

    public init(
        id: UUID,
        exerciseName: String,
        arType: ARExerciseTypeEnum,
        description: String,
        durationSeconds: Int,
        instructions: [String],
        voiceGuidanceScript: [String],
        sceneConfig: ARSceneConfig,
        isPremium: Bool,
        isAvailable: Bool = true,
        unavailableReason: String? = nil
    ) {
        self.id = id
        self.exerciseName = exerciseName
        self.arType = arType
        self.description = description
        self.durationSeconds = durationSeconds
        self.instructions = instructions
        self.voiceGuidanceScript = voiceGuidanceScript
        self.sceneConfig = sceneConfig
        self.isPremium = isPremium
        self.isAvailable = isAvailable
        self.unavailableReason = unavailableReason
    }

    enum CodingKeys: String, CodingKey {
        case id
        case exerciseName = "exercise_name"
        case arType = "ar_type"
        case description
        case durationSeconds = "duration_seconds"
        case instructions
        case voiceGuidanceScript = "voice_guidance_script"
        case sceneConfig = "scene_config"
        case isPremium = "is_premium"
        case isAvailable = "is_available"
        case unavailableReason = "unavailable_reason"
    }

    /// Duration formatted as "X min"
    var formattedDuration: String {
        let minutes = durationSeconds / 60
        return "\(minutes) min"
    }

    /// Human-readable unavailability message
    var unavailabilityMessage: String? {
        guard let reason = unavailableReason else { return nil }
        switch reason {
        case "requires_premium":
            return "Premium subscription required"
        case "requires_lidar":
            return "Requires iPhone 12 Pro or newer with LiDAR"
        case "requires_ar":
            return "AR not supported on this device"
        default:
            return "Not available"
        }
    }
}

// MARK: - Scene Configuration

/// AR scene configuration for exercises
public struct ARSceneConfig: Codable, Equatable {
    public var breathPattern: BreathPattern?
    public var orbColor: String?
    public var particleCount: Int?
    public var markerColors: MarkerColors?
    public var availableObjects: [String]?
    public var ambientLight: Float?
    public var sceneType: String?
    public var ambientAudio: String?
    public var particleEffects: [String]?

    public init(
        breathPattern: BreathPattern? = nil,
        orbColor: String? = nil,
        particleCount: Int? = nil,
        markerColors: MarkerColors? = nil,
        availableObjects: [String]? = nil,
        ambientLight: Float? = nil,
        sceneType: String? = nil,
        ambientAudio: String? = nil,
        particleEffects: [String]? = nil
    ) {
        self.breathPattern = breathPattern
        self.orbColor = orbColor
        self.particleCount = particleCount
        self.markerColors = markerColors
        self.availableObjects = availableObjects
        self.ambientLight = ambientLight
        self.sceneType = sceneType
        self.ambientAudio = ambientAudio
        self.particleEffects = particleEffects
    }
}

/// Breathing pattern timing (in seconds)
public struct BreathPattern: Codable, Equatable {
    public let inhale: Int
    public let hold: Int
    public let exhale: Int

    public init(inhale: Int = 4, hold: Int = 2, exhale: Int = 6) {
        self.inhale = inhale
        self.hold = hold
        self.exhale = exhale
    }

    /// Total cycle duration
    var cycleDuration: Int {
        inhale + hold + exhale
    }
}

/// Marker colors for 5-4-3-2-1 grounding
public struct MarkerColors: Codable, Equatable {
    public let see: String
    public let touch: String
    public let hear: String
    public let smell: String
    public let taste: String

    public init(
        see: String = "#3B82F6",
        touch: String = "#10B981",
        hear: String = "#F59E0B",
        smell: String = "#F97316",
        taste: String = "#8B5CF6"
    ) {
        self.see = see
        self.touch = touch
        self.hear = hear
        self.smell = smell
        self.taste = taste
    }
}

// MARK: - AR Exercise Session

/// Recorded AR exercise session
public struct ARExerciseSession: Codable, Identifiable, Equatable {
    public let id: UUID
    public let userId: UUID
    public let exerciseTypeId: UUID
    public let startedAt: Date
    public var completedAt: Date?
    public var effectivenessRating: Int?
    public var trackingQualityAvg: Double?
    public var interruptionsCount: Int
    public var deviceCapability: String?
    public var usedVoiceGuidance: Bool
    public var completedSteps: Int

    public init(
        id: UUID = UUID(),
        userId: UUID,
        exerciseTypeId: UUID,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        effectivenessRating: Int? = nil,
        trackingQualityAvg: Double? = nil,
        interruptionsCount: Int = 0,
        deviceCapability: String? = nil,
        usedVoiceGuidance: Bool = false,
        completedSteps: Int = 0
    ) {
        self.id = id
        self.userId = userId
        self.exerciseTypeId = exerciseTypeId
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.effectivenessRating = effectivenessRating
        self.trackingQualityAvg = trackingQualityAvg
        self.interruptionsCount = interruptionsCount
        self.deviceCapability = deviceCapability
        self.usedVoiceGuidance = usedVoiceGuidance
        self.completedSteps = completedSteps
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case exerciseTypeId = "exercise_type_id"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case effectivenessRating = "effectiveness_rating"
        case trackingQualityAvg = "tracking_quality_avg"
        case interruptionsCount = "interruptions_count"
        case deviceCapability = "device_capability"
        case usedVoiceGuidance = "used_voice_guidance"
        case completedSteps = "completed_steps"
    }

    /// Whether session was completed
    var isCompleted: Bool {
        completedAt != nil
    }

    /// Session duration in seconds
    var durationSeconds: Int? {
        guard let completedAt = completedAt else { return nil }
        return Int(completedAt.timeIntervalSince(startedAt))
    }
}

// MARK: - AR Scene Preferences

/// User's saved AR scene preferences (Safe Space)
public struct ARScenePreference: Codable, Identifiable, Equatable {
    public let id: UUID
    public let userId: UUID
    public var sceneName: String
    public var sceneData: ARSceneData
    public var isDefault: Bool
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID,
        userId: UUID,
        sceneName: String,
        sceneData: ARSceneData,
        isDefault: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.sceneName = sceneName
        self.sceneData = sceneData
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case sceneName = "scene_name"
        case sceneData = "scene_data"
        case isDefault = "is_default"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Scene data for Safe Space
public struct ARSceneData: Codable, Equatable {
    public var objects: [ARSceneObject]
    public var environmentPrefs: AREnvironmentPrefs

    public init(
        objects: [ARSceneObject] = [],
        environmentPrefs: AREnvironmentPrefs = .default
    ) {
        self.objects = objects
        self.environmentPrefs = environmentPrefs
    }
}

/// Individual object placed in AR scene
public struct ARSceneObject: Codable, Identifiable, Equatable {
    public let id: UUID
    public let objectType: String
    public var positionX: Float
    public var positionY: Float
    public var positionZ: Float
    public var rotationW: Float
    public var rotationX: Float
    public var rotationY: Float
    public var rotationZ: Float
    public var scale: Float
    public var customData: [String: String]?

    public init(
        id: UUID = UUID(),
        objectType: String,
        positionX: Float = 0,
        positionY: Float = 0,
        positionZ: Float = -1,
        rotationW: Float = 1,
        rotationX: Float = 0,
        rotationY: Float = 0,
        rotationZ: Float = 0,
        scale: Float = 1,
        customData: [String: String]? = nil
    ) {
        self.id = id
        self.objectType = objectType
        self.positionX = positionX
        self.positionY = positionY
        self.positionZ = positionZ
        self.rotationW = rotationW
        self.rotationX = rotationX
        self.rotationY = rotationY
        self.rotationZ = rotationZ
        self.scale = scale
        self.customData = customData
    }

    /// Position as SIMD3
    var position: SIMD3<Float> {
        SIMD3<Float>(positionX, positionY, positionZ)
    }

    /// Rotation as quaternion
    var rotation: simd_quatf {
        simd_quatf(ix: rotationX, iy: rotationY, iz: rotationZ, r: rotationW)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case objectType = "object_type"
        case positionX = "position_x"
        case positionY = "position_y"
        case positionZ = "position_z"
        case rotationW = "rotation_w"
        case rotationX = "rotation_x"
        case rotationY = "rotation_y"
        case rotationZ = "rotation_z"
        case scale
        case customData = "custom_data"
    }
}

/// Environment preferences for AR scene
public struct AREnvironmentPrefs: Codable, Equatable {
    public var lightingIntensity: Float
    public var ambientAudioVolume: Float
    public var particleEffectsEnabled: Bool

    public init(
        lightingIntensity: Float = 0.7,
        ambientAudioVolume: Float = 0.5,
        particleEffectsEnabled: Bool = true
    ) {
        self.lightingIntensity = lightingIntensity
        self.ambientAudioVolume = ambientAudioVolume
        self.particleEffectsEnabled = particleEffectsEnabled
    }

    public static var `default`: AREnvironmentPrefs {
        AREnvironmentPrefs()
    }

    enum CodingKeys: String, CodingKey {
        case lightingIntensity = "lighting_intensity"
        case ambientAudioVolume = "ambient_audio_volume"
        case particleEffectsEnabled = "particle_effects_enabled"
    }
}

// MARK: - AR Tracking Quality

/// AR tracking state wrapper
public enum ARTrackingQuality: Equatable {
    case notAvailable
    case limited(reason: ARCamera.TrackingState.Reason?)
    case normal

    public init(from state: ARCamera.TrackingState) {
        switch state {
        case .notAvailable:
            self = .notAvailable
        case .limited(let reason):
            self = .limited(reason: reason)
        case .normal:
            self = .normal
        }
    }

    /// Quality as 0-1 value
    var qualityValue: Double {
        switch self {
        case .notAvailable: return 0.0
        case .limited: return 0.5
        case .normal: return 1.0
        }
    }

    /// User-facing message for limited tracking
    var limitedTrackingMessage: String? {
        guard case .limited(let reason) = self else { return nil }
        switch reason {
        case .initializing:
            return "Initializing AR..."
        case .excessiveMotion:
            return "Move camera more slowly"
        case .insufficientFeatures:
            return "Point at a textured surface"
        case .relocalizing:
            return "Relocating position..."
        case .none:
            return "Limited tracking"
        @unknown default:
            return "Limited tracking"
        }
    }
}

// MARK: - AR Exercise Error

/// Errors that can occur during AR exercises
public enum ARExerciseError: Error, LocalizedError {
    case networkFailure(Error)
    case notAuthenticated
    case deviceNotSupported
    case premiumRequired
    case sessionNotFound
    case cameraPermissionDenied
    case trackingFailed
    case sessionInterrupted
    case invalidExerciseData

    public var errorDescription: String? {
        switch self {
        case .networkFailure(let error):
            return "Network error: \(error.localizedDescription)"
        case .notAuthenticated:
            return "Please sign in to use AR exercises"
        case .deviceNotSupported:
            return "AR is not supported on this device"
        case .premiumRequired:
            return "This exercise requires a premium subscription"
        case .sessionNotFound:
            return "Session not found"
        case .cameraPermissionDenied:
            return "Camera access is required for AR exercises"
        case .trackingFailed:
            return "AR tracking failed. Try moving to a better-lit area."
        case .sessionInterrupted:
            return "AR session was interrupted"
        case .invalidExerciseData:
            return "Invalid exercise data"
        }
    }

    /// Whether this error is recoverable
    var isRecoverable: Bool {
        switch self {
        case .networkFailure, .trackingFailed, .sessionInterrupted:
            return true
        case .notAuthenticated, .deviceNotSupported, .premiumRequired,
             .sessionNotFound, .cameraPermissionDenied, .invalidExerciseData:
            return false
        }
    }
}

// MARK: - Grounding Step

/// Step in 5-4-3-2-1 grounding exercise
public enum GroundingStep: Int, CaseIterable {
    case see = 5      // 5 things you see
    case touch = 4    // 4 things you can touch
    case hear = 3     // 3 things you hear
    case smell = 2    // 2 things you smell
    case taste = 1    // 1 thing you taste

    /// Display name for the step
    var displayName: String {
        switch self {
        case .see: return "See"
        case .touch: return "Touch"
        case .hear: return "Hear"
        case .smell: return "Smell"
        case .taste: return "Taste"
        }
    }

    /// Instruction for the step
    var instruction: String {
        switch self {
        case .see: return "Tap \(rawValue) things you can SEE"
        case .touch: return "Tap \(rawValue) things you could TOUCH"
        case .hear: return "Tap \(rawValue) things you can HEAR"
        case .smell: return "Tap \(rawValue) things you can SMELL"
        case .taste: return "Tap \(rawValue) thing you can TASTE"
        }
    }

    /// Number of items to identify
    var count: Int { rawValue }

    /// Next step in sequence
    var next: GroundingStep? {
        switch self {
        case .see: return .touch
        case .touch: return .hear
        case .hear: return .smell
        case .smell: return .taste
        case .taste: return nil
        }
    }

    /// Color key for marker colors
    var colorKey: KeyPath<MarkerColors, String> {
        switch self {
        case .see: return \.see
        case .touch: return \.touch
        case .hear: return \.hear
        case .smell: return \.smell
        case .taste: return \.taste
        }
    }
}

// MARK: - AR Breathing Phase

/// Current phase in AR breathing exercise cycle
/// Named distinctly to avoid conflict with BreathingPhase in other features
public enum ARBreathingPhase: String, CaseIterable {
    case inhale
    case hold
    case exhale

    public var instruction: String {
        switch self {
        case .inhale: return "Breathe In"
        case .hold: return "Hold"
        case .exhale: return "Breathe Out"
        }
    }

    /// Next phase in cycle
    public var next: ARBreathingPhase {
        switch self {
        case .inhale: return .hold
        case .hold: return .exhale
        case .exhale: return .inhale
        }
    }
}
