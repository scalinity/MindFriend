import Foundation
import ARKit
import AVFoundation
import Combine

/// Service for detecting and managing AR capabilities on the current device
@MainActor
public final class ARCapabilityService: ObservableObject, ARCapabilityServiceProtocol {

    // MARK: - Published Properties

    /// Current device capabilities
    @Published public private(set) var capabilities: ARCapabilities

    /// Camera authorization status
    @Published public private(set) var cameraAuthStatus: AVAuthorizationStatus

    /// Overall AR capability level
    @Published public private(set) var capabilityLevel: ARCapability

    // MARK: - Initialization

    public init() {
        self.capabilities = ARCapabilities.detect()
        self.cameraAuthStatus = AVCaptureDevice.authorizationStatus(for: .video)
        self.capabilityLevel = ARCapabilities.detect().capabilityLevel
    }

    // MARK: - Public Methods

    /// Refresh capability detection
    public func refreshCapabilities() {
        capabilities = ARCapabilities.detect()
        cameraAuthStatus = AVCaptureDevice.authorizationStatus(for: .video)
        capabilityLevel = capabilities.capabilityLevel
    }

    /// Request camera permission for AR
    /// - Returns: true if permission granted
    public func requestCameraPermission() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        await MainActor.run {
            self.cameraAuthStatus = AVCaptureDevice.authorizationStatus(for: .video)
        }
        return granted
    }

    /// Check if device can run specific AR exercise
    /// - Parameter exercise: The AR exercise to check
    /// - Returns: Tuple of (canRun, reason if cannot)
    public func canRun(exercise: ARExercise) -> (canRun: Bool, reason: String?) {
        // Check AR capability level
        let requiredCapabilities = exercise.sceneConfig.requiredCapabilities

        // For nature immersion, require LiDAR
        if exercise.arType == .natureImmersion && !capabilities.lidar {
            return (false, "This exercise requires a device with LiDAR (iPhone 12 Pro or newer)")
        }

        // Check basic AR support
        if !capabilities.arkit {
            if exercise.arType.supportsFallback {
                return (true, nil) // Will use fallback
            }
            return (false, "AR is not supported on this device")
        }

        // Check camera permission
        if cameraAuthStatus == .denied || cameraAuthStatus == .restricted {
            return (false, "Camera access is required for AR exercises")
        }

        return (true, nil)
    }

    /// Check if fallback mode should be used for exercise
    /// - Parameter exercise: The AR exercise to check
    /// - Returns: true if fallback should be used
    public func shouldUseFallback(for exercise: ARExercise) -> Bool {
        // No AR support at all
        if !capabilities.arkit {
            return true
        }

        // Camera permission denied
        if cameraAuthStatus == .denied || cameraAuthStatus == .restricted {
            return true
        }

        return false
    }

    /// Get fallback exercise suggestions for exercises that can't run AR
    /// - Parameter exercise: The unavailable exercise
    /// - Returns: Array of suggested alternative exercise names
    public func suggestFallback(for exercise: ARExercise) -> [String] {
        switch exercise.arType {
        case .breathingOrb:
            return ["Breathing Exercise", "Box Breathing", "4-7-8 Breathing"]
        case .grounding541:
            return ["5-4-3-2-1 Grounding", "Body Scan", "Grounding Meditation"]
        case .safeSpace:
            return ["Guided Visualization", "Safe Place Meditation"]
        case .natureImmersion:
            return ["Nature Sounds", "Forest Meditation", "Ocean Waves"]
        }
    }

    /// Check if device supports world tracking
    public func supportsWorldTracking() -> Bool {
        return ARWorldTrackingConfiguration.isSupported
    }

    /// Check if device supports scene reconstruction (LiDAR)
    public func supportsSceneReconstruction() -> Bool {
        if #available(iOS 13.4, *) {
            return ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
        }
        return false
    }

    /// Check if device has LiDAR
    public func supportsLiDAR() -> Bool {
        return capabilities.lidar
    }

    /// Check if device supports face tracking (TrueDepth camera)
    public func supportsFaceTracking() -> Bool {
        return ARFaceTrackingConfiguration.isSupported
    }

    /// Get a summary of device capabilities for display
    public func capabilitySummary() -> String {
        var features: [String] = []

        if capabilities.arkit {
            features.append("AR World Tracking")
        }
        if capabilities.trueDepth {
            features.append("TrueDepth Camera")
        }
        if capabilities.lidar {
            features.append("LiDAR Scanner")
        }

        if features.isEmpty {
            return "No AR support"
        }

        return features.joined(separator: ", ")
    }

    /// Determine recommended AR quality settings based on device
    public func recommendedQualitySettings() -> ARQualitySettings {
        if capabilities.lidar {
            // High-end device with LiDAR
            return ARQualitySettings(
                particleCount: 100,
                shadowQuality: .high,
                environmentTextures: true,
                frameRate: 60
            )
        } else if capabilities.arkit {
            // Standard AR-capable device
            return ARQualitySettings(
                particleCount: 50,
                shadowQuality: .medium,
                environmentTextures: true,
                frameRate: 60
            )
        } else {
            // Fallback/2D mode
            return ARQualitySettings(
                particleCount: 20,
                shadowQuality: .low,
                environmentTextures: false,
                frameRate: 30
            )
        }
    }
}

// MARK: - AR Scene Config Extension

extension ARSceneConfig {
    /// Required capabilities parsed from scene config
    var requiredCapabilities: ARCapabilities {
        // Default: basic ARKit only
        return ARCapabilities(arkit: true, trueDepth: false, lidar: false)
    }
}

// MARK: - AR Quality Settings

/// Quality settings for AR rendering
public struct ARQualitySettings {
    public let particleCount: Int
    public let shadowQuality: ShadowQuality
    public let environmentTextures: Bool
    public let frameRate: Int

    public enum ShadowQuality {
        case low
        case medium
        case high
    }
}
