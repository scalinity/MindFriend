import SwiftUI
import ARKit
import SceneKit

/// Protocol for configuring AR scenes
public protocol ARSceneConfiguration {
    func configureScene(_ scene: SCNScene, _ arView: ARSCNView)
    func sessionDidUpdate(_ frame: ARFrame)
    func handleTap(at location: CGPoint, in view: ARSCNView) -> Bool
}

/// Default implementation for protocol
public extension ARSceneConfiguration {
    func sessionDidUpdate(_ frame: ARFrame) {}
    func handleTap(at location: CGPoint, in view: ARSCNView) -> Bool { false }
}

/// UIViewRepresentable wrapper for ARSCNView
public struct ARSceneView: UIViewRepresentable {

    // MARK: - Configuration

    public let configuration: any ARSceneConfiguration
    @Binding public var trackingState: ARTrackingQuality
    @Binding public var isSessionRunning: Bool
    public var onTap: ((CGPoint) -> Void)?

    // MARK: - Initialization

    public init(
        configuration: any ARSceneConfiguration,
        trackingState: Binding<ARTrackingQuality>,
        isSessionRunning: Binding<Bool>,
        onTap: ((CGPoint) -> Void)? = nil
    ) {
        self.configuration = configuration
        self._trackingState = trackingState
        self._isSessionRunning = isSessionRunning
        self.onTap = onTap
    }

    // MARK: - UIViewRepresentable

    public func makeUIView(context: Context) -> ARSCNView {
        let arView = ARSCNView(frame: .zero)
        arView.delegate = context.coordinator
        arView.session.delegate = context.coordinator
        arView.autoenablesDefaultLighting = true
        arView.automaticallyUpdatesLighting = true

        // Configure scene
        let scene = SCNScene()
        arView.scene = scene
        configuration.configureScene(scene, arView)

        // Add tap gesture
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        arView.addGestureRecognizer(tapGesture)

        // Start AR session
        startSession(arView)

        return arView
    }

    public func updateUIView(_ arView: ARSCNView, context: Context) {
        // Update tracking state if needed
        context.coordinator.parent = self
    }

    public static func dismantleUIView(_ arView: ARSCNView, coordinator: Coordinator) {
        arView.session.pause()
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Session Management

    private func startSession(_ arView: ARSCNView) {
        guard ARWorldTrackingConfiguration.isSupported else {
            return
        }

        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .automatic

        // Enable scene reconstruction if available (LiDAR)
        if #available(iOS 13.4, *),
           ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
        }

        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    // MARK: - Coordinator

    public class Coordinator: NSObject, ARSCNViewDelegate, ARSessionDelegate {
        var parent: ARSceneView

        init(_ parent: ARSceneView) {
            self.parent = parent
        }

        // MARK: - ARSessionDelegate

        public func session(_ session: ARSession, didUpdate frame: ARFrame) {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.parent.trackingState = ARTrackingQuality(from: frame.camera.trackingState)
                self.parent.isSessionRunning = true
                self.parent.configuration.sessionDidUpdate(frame)
            }
        }

        public func session(_ session: ARSession, didFailWithError error: Error) {
            DispatchQueue.main.async { [weak self] in
                self?.parent.isSessionRunning = false
                self?.parent.trackingState = .notAvailable
            }
        }

        public func sessionWasInterrupted(_ session: ARSession) {
            DispatchQueue.main.async { [weak self] in
                self?.parent.trackingState = .limited(reason: nil)
            }
        }

        public func sessionInterruptionEnded(_ session: ARSession) {
            // Session will automatically resume tracking
        }

        // MARK: - ARSCNViewDelegate

        public func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
            // Handle anchor additions if needed
        }

        public func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
            // Handle anchor updates if needed
        }

        // MARK: - Gesture Handling

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let arView = gesture.view as? ARSCNView else { return }
            let location = gesture.location(in: arView)

            // First let configuration handle tap
            if parent.configuration.handleTap(at: location, in: arView) {
                return
            }

            // Then notify external handler
            parent.onTap?(location)
        }
    }
}

// MARK: - Basic Scene Configurations

/// Configuration for breathing orb exercise
public class BreathingOrbSceneConfiguration: ARSceneConfiguration {

    private var orbNode: SCNNode?
    private var particleNode: SCNNode?
    public var orbColor: UIColor
    public var particleCount: Int

    public init(orbColor: UIColor = UIColor(red: 0.39, green: 0.4, blue: 0.95, alpha: 0.8),
                particleCount: Int = 50) {
        self.orbColor = orbColor
        self.particleCount = particleCount
    }

    public func configureScene(_ scene: SCNScene, _ arView: ARSCNView) {
        // Create orb geometry
        let sphere = SCNSphere(radius: 0.15)
        sphere.segmentCount = 48

        // Create material with gradient effect
        let material = SCNMaterial()
        material.diffuse.contents = orbColor
        material.emission.contents = orbColor.withAlphaComponent(0.3)
        material.transparency = 0.8
        material.isDoubleSided = true
        material.lightingModel = .physicallyBased
        material.metalness.contents = 0.2
        material.roughness.contents = 0.4
        sphere.materials = [material]

        // Create node
        let orb = SCNNode(geometry: sphere)
        orb.position = SCNVector3(0, 0, -1.0) // 1 meter in front
        orb.name = "breathingOrb"

        // Add glow effect
        let glowSphere = SCNSphere(radius: 0.18)
        let glowMaterial = SCNMaterial()
        glowMaterial.diffuse.contents = orbColor.withAlphaComponent(0.2)
        glowMaterial.emission.contents = orbColor.withAlphaComponent(0.4)
        glowMaterial.transparency = 0.5
        glowSphere.materials = [glowMaterial]
        let glowNode = SCNNode(geometry: glowSphere)
        glowNode.name = "glow"
        orb.addChildNode(glowNode)

        // Add particles
        if let particleSystem = createParticleSystem() {
            let particles = SCNNode()
            particles.addParticleSystem(particleSystem)
            particles.name = "particles"
            orb.addChildNode(particles)
        }

        scene.rootNode.addChildNode(orb)
        orbNode = orb

        // Add ambient light
        let light = SCNLight()
        light.type = .ambient
        light.intensity = 500
        let lightNode = SCNNode()
        lightNode.light = light
        scene.rootNode.addChildNode(lightNode)
    }

    private func createParticleSystem() -> SCNParticleSystem? {
        let particles = SCNParticleSystem()
        particles.particleSize = 0.005
        particles.particleColor = orbColor.withAlphaComponent(0.6)
        particles.birthRate = CGFloat(particleCount)
        particles.particleLifeSpan = 2.0
        particles.spreadingAngle = 180
        particles.emissionDuration = CGFloat.infinity
        particles.loops = true
        particles.blendMode = .additive
        particles.emitterShape = SCNSphere(radius: 0.15)
        particles.particleVelocity = 0.02
        particles.particleVelocityVariation = 0.01
        return particles
    }

    public func sessionDidUpdate(_ frame: ARFrame) {
        // Could update based on frame if needed
    }

    public func handleTap(at location: CGPoint, in view: ARSCNView) -> Bool {
        return false
    }

    /// Animate orb to target scale
    public func animateOrb(to scale: Float, duration: TimeInterval) {
        guard let orb = orbNode else { return }

        let scaleAction = SCNAction.scale(to: CGFloat(scale), duration: duration)
        scaleAction.timingMode = .easeInEaseOut
        orb.runAction(scaleAction)
    }

    /// Pulse particles during breathing phase
    public func pulseParticles(expanding: Bool) {
        guard let particles = orbNode?.childNode(withName: "particles", recursively: true),
              let system = particles.particleSystems?.first else { return }

        system.particleVelocity = expanding ? 0.04 : 0.01
    }
}

/// Configuration for grounding 5-4-3-2-1 markers
public class Grounding541SceneConfiguration: ARSceneConfiguration {

    public var markers: [SCNNode] = []
    public var currentStep: GroundingStep = .see
    public var onMarkerPlaced: ((GroundingStep, Int) -> Void)?

    private var markerColors: MarkerColors

    public init(markerColors: MarkerColors = MarkerColors()) {
        self.markerColors = markerColors
    }

    public func configureScene(_ scene: SCNScene, _ arView: ARSCNView) {
        // Add ambient light
        let light = SCNLight()
        light.type = .ambient
        light.intensity = 800
        let lightNode = SCNNode()
        lightNode.light = light
        scene.rootNode.addChildNode(lightNode)
    }

    public func sessionDidUpdate(_ frame: ARFrame) {
        // Update markers if needed
    }

    public func handleTap(at location: CGPoint, in view: ARSCNView) -> Bool {
        // Perform hit test
        guard let query = view.raycastQuery(from: location, allowing: .estimatedPlane, alignment: .any) else {
            return false
        }

        let results = view.session.raycast(query)
        guard let result = results.first else {
            return false
        }

        // Check if we can add more markers for current step
        let currentMarkerCount = markers.filter { $0.name?.hasPrefix(currentStep.displayName) ?? false }.count
        guard currentMarkerCount < currentStep.count else {
            return false
        }

        // Create marker at hit location
        let marker = createMarker(for: currentStep, number: currentMarkerCount + 1)
        marker.simdTransform = result.worldTransform
        marker.position.y += 0.05 // Slightly above surface

        view.scene.rootNode.addChildNode(marker)
        markers.append(marker)

        // Notify
        onMarkerPlaced?(currentStep, currentMarkerCount + 1)

        return true
    }

    private func createMarker(for step: GroundingStep, number: Int) -> SCNNode {
        // Create cone marker
        let cone = SCNCone(topRadius: 0, bottomRadius: 0.03, height: 0.08)

        // Color based on step
        let colorHex = markerColors[keyPath: step.colorKey]
        let color = UIColor(hex: colorHex) ?? .blue

        let material = SCNMaterial()
        material.diffuse.contents = color
        material.emission.contents = color.withAlphaComponent(0.3)
        cone.materials = [material]

        let node = SCNNode(geometry: cone)
        node.name = "\(step.displayName)_\(number)"

        // Add number label
        let text = SCNText(string: "\(number)", extrusionDepth: 0.01)
        text.font = UIFont.boldSystemFont(ofSize: 0.03)
        text.flatness = 0.1
        let textMaterial = SCNMaterial()
        textMaterial.diffuse.contents = UIColor.white
        text.materials = [textMaterial]

        let textNode = SCNNode(geometry: text)
        textNode.scale = SCNVector3(0.5, 0.5, 0.5)
        textNode.position = SCNVector3(-0.01, 0.09, 0)
        node.addChildNode(textNode)

        // Add pulse animation
        let pulse = SCNAction.sequence([
            SCNAction.scale(to: 1.1, duration: 0.5),
            SCNAction.scale(to: 1.0, duration: 0.5)
        ])
        node.runAction(SCNAction.repeatForever(pulse))

        return node
    }

    /// Remove last marker
    public func undoLastMarker() {
        guard let last = markers.popLast() else { return }
        last.removeFromParentNode()
    }

    /// Clear all markers
    public func clearMarkers() {
        markers.forEach { $0.removeFromParentNode() }
        markers.removeAll()
    }

    /// Advance to next grounding step
    public func advanceStep() -> Bool {
        if let next = currentStep.next {
            currentStep = next
            return true
        }
        return false
    }
}

// MARK: - UIColor Extension

extension UIColor {
    convenience init?(hex: String) {
        let r, g, b: CGFloat
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)

        guard hex.count == 6 else { return nil }

        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        r = CGFloat((int >> 16) & 0xFF) / 255.0
        g = CGFloat((int >> 8) & 0xFF) / 255.0
        b = CGFloat(int & 0xFF) / 255.0

        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
