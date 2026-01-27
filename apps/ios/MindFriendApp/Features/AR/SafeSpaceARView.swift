import SwiftUI
import ARKit
import SceneKit

/// AR Safe Space exercise view (Premium feature)
public struct SafeSpaceARView: View {

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var exerciseService: ARExerciseService

    // MARK: - Properties

    let exercise: ARExercise

    // MARK: - State

    @State private var trackingState: ARTrackingQuality = .notAvailable
    @State private var isSessionRunning: Bool = false
    @State private var isScanning: Bool = true
    @State private var planeDetected: Bool = false
    @State private var selectedObjectType: String?
    @State private var placedObjects: [ARSceneObject] = []
    @State private var showExitConfirmation: Bool = false
    @State private var showSaveSheet: Bool = false
    @State private var sceneName: String = ""
    @State private var showCompletion: Bool = false
    @State private var effectivenessRating: Int = 0
    @State private var sessionId: UUID?  // Track actual session ID
    @State private var isExerciseEnded: Bool = false  // Guard against race conditions
    @State private var sceneConfig: SafeSpaceSceneConfiguration

    // MARK: - Available Objects

    private let availableObjects = [
        ("plant", "leaf.fill", "Plant"),
        ("candle", "flame.fill", "Candle"),
        ("crystal", "diamond.fill", "Crystal"),
        ("cushion", "rectangle.fill", "Cushion"),
        ("light_orb", "circle.fill", "Light Orb"),
        ("water_fountain", "drop.fill", "Fountain")
    ]

    // MARK: - Rate Limiting
    
    private static let maxObjectsPerScene = 50
    @State private var lastTapTime: Date = .distantPast

    // MARK: - Initialization

    public init(exercise: ARExercise) {
        self.exercise = exercise
        let ambientLight = exercise.sceneConfig.ambientLight ?? 0.7
        _sceneConfig = State(initialValue: SafeSpaceSceneConfiguration(ambientLightIntensity: ambientLight))
    }

    // MARK: - Body

    public var body: some View {
        ZStack {
            // AR Scene - configuration handles taps directly via ray casting
            ARSceneView(
                configuration: sceneConfig,
                trackingState: $trackingState,
                isSessionRunning: $isSessionRunning
            )
            .ignoresSafeArea()

            // HUD Overlay
            VStack {
                // Top bar
                HStack {
                    // Tracking indicator
                    trackingIndicator

                    Spacer()

                    // Title
                    Text("Your Safe Space")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Spacer()

                    // Exit button
                    Button {
                        showExitConfirmation = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .accessibilityLabel("End exercise")
                    .accessibilityHint("Double tap to exit without saving")
                }
                .padding()
                .background(.ultraThinMaterial.opacity(0.6))

                // Scanning instruction
                if isScanning {
                    scanningOverlay
                }

                Spacer()

                // Object palette (shown after plane detected)
                if planeDetected {
                    objectPalette
                }

                // Bottom bar
                HStack {
                    // Object count
                    Text("\(placedObjects.count) objects")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .accessibilityLabel("\(placedObjects.count) objects placed")

                    Spacer()

                    // Undo button
                    Button {
                        removeLastObject()
                    } label: {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.title2)
                            .foregroundStyle(placedObjects.isEmpty ? .white.opacity(0.3) : .white)
                    }
                    .disabled(placedObjects.isEmpty)
                    .accessibilityLabel("Remove last object")
                    .accessibilityHint(placedObjects.isEmpty ? "No objects to remove" : "Removes the last placed object")

                    Spacer()

                    // Save button
                    Button {
                        showSaveSheet = true
                    } label: {
                        Text("Save")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(.blue)
                            .cornerRadius(8)
                    }
                    .disabled(placedObjects.isEmpty)
                    .accessibilityLabel("Save safe space")
                    .accessibilityHint(placedObjects.isEmpty ? "Place at least one object first" : "Save your current safe space configuration")
                }
                .padding()
                .background(.ultraThinMaterial.opacity(0.6))
            }

            // Tracking warning
            if case .limited(let reason) = trackingState {
                trackingWarningOverlay(reason: reason)
            }
        }
        .onAppear {
            setupSceneCallbacks()
            startExercise()
        }
        .onDisappear {
            stopExercise()
        }
        .alert("End Exercise?", isPresented: $showExitConfirmation) {
            Button("Continue", role: .cancel) {}
            Button("End", role: .destructive) {
                endExercise(completed: false)
            }
        } message: {
            Text("Your safe space will not be saved.")
        }
        .sheet(isPresented: $showSaveSheet) {
            saveSceneSheet
        }
        .sheet(isPresented: $showCompletion) {
            completionView
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
        .onChange(of: selectedObjectType) { _, newValue in
            sceneConfig.selectedObjectType = newValue
        }
    }

    // MARK: - Subviews

    private var trackingIndicator: some View {
        Circle()
            .fill(trackingColor)
            .frame(width: 12, height: 12)
            .accessibilityLabel("AR tracking status: \(trackingState == .normal ? "good" : "limited")")
    }

    private var trackingColor: Color {
        switch trackingState {
        case .normal: return .green
        case .limited: return .yellow
        case .notAvailable: return .red
        }
    }

    private var scanningOverlay: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.white)

            Text("Scanning your environment...")
                .font(.headline)
                .foregroundStyle(.white)

            Text("Move your camera to scan the floor")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding()
        .background(.black.opacity(0.6))
        .cornerRadius(16)
        .onAppear {
            // Simulate plane detection after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                withAnimation {
                    isScanning = false
                    planeDetected = true
                }
                exerciseService.speakGuidance("Floor detected. Choose objects to place.")
            }
        }
    }

    private var objectPalette: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(availableObjects, id: \.0) { object in
                    objectButton(type: object.0, icon: object.1, name: object.2)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 12)
        .background(.ultraThinMaterial.opacity(0.8))
    }

    private func objectButton(type: String, icon: String, name: String) -> some View {
        Button {
            selectedObjectType = (selectedObjectType == type) ? nil : type
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(selectedObjectType == type ? .blue : .white)
                    .frame(width: 50, height: 50)
                    .background(
                        Circle()
                            .fill(selectedObjectType == type ? .white : .white.opacity(0.2))
                    )

                Text(name)
                    .font(.caption2)
                    .foregroundStyle(.white)
            }
        }
        .accessibilityLabel("\(name)")
        .accessibilityHint(selectedObjectType == type ? "Currently selected. Tap to deselect" : "Tap to select, then tap in scene to place")
        .accessibilityAddTraits(selectedObjectType == type ? .isSelected : [])
    }

    private func trackingWarningOverlay(reason: ARCamera.TrackingState.Reason?) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.yellow)

            Text(trackingState.limitedTrackingMessage ?? "Limited tracking")
                .font(.headline)
                .foregroundStyle(.white)
        }
        .padding()
        .background(.black.opacity(0.7))
        .cornerRadius(16)
    }

    private var saveSceneSheet: some View {
        NavigationStack {
            VStack(spacing: 24) {
                TextField("Scene name", text: $sceneName)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)

                Text("You've placed \(placedObjects.count) objects in your safe space.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    saveScene()
                } label: {
                    Text("Save Safe Space")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(sceneName.isEmpty ? .gray : .blue)
                        .cornerRadius(12)
                }
                .disabled(sceneName.isEmpty)
                .padding()
            }
            .padding(.top)
            .navigationTitle("Save Your Space")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showSaveSheet = false
                    }
                }
            }
        }
    }

    private var completionView: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Image(systemName: "house.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.purple)

                Text("Safe Space Created!")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("You can return to '\(sceneName)' anytime")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    Text("How relaxing was this experience?")
                        .font(.subheadline)

                    HStack(spacing: 8) {
                        ForEach(1...5, id: \.self) { rating in
                            Button {
                                effectivenessRating = rating
                            } label: {
                                Image(systemName: rating <= effectivenessRating ? "star.fill" : "star")
                                    .font(.title)
                                    .foregroundStyle(rating <= effectivenessRating ? .yellow : .gray)
                            }
                            .accessibilityLabel("\(rating) star\(rating != 1 ? "s" : "")")
                            .accessibilityAddTraits(rating <= effectivenessRating ? .isSelected : [])
                        }
                    }
                }

                Spacer()

                Button {
                    saveAndDismiss()
                } label: {
                    Text("Done")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue)
                        .cornerRadius(12)
                }
            }
            .padding()
            .navigationTitle("Session Complete")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Actions

    private func setupSceneCallbacks() {
        sceneConfig.onObjectPlaced = { object in
            guard placedObjects.count < Self.maxObjectsPerScene else { return }
            placedObjects.append(object)
            exerciseService.speakGuidance("\(object.objectType.replacingOccurrences(of: "_", with: " ")) placed")
        }
    }

    private func startExercise() {
        guard !isExerciseEnded else { return }
        
        Task {
            do {
                let newSessionId = try await exerciseService.startSession(exercise: exercise)
                sessionId = newSessionId
                exerciseService.speakGuidance("Welcome to Safe Space Creator. Let's build your sanctuary.")
            } catch {
                #if DEBUG
                print("AR session start failed")
                #endif
            }
        }
    }

    private func stopExercise() {
        exerciseService.stopGuidance()
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .background, .inactive:
            // Record interruption when app goes to background
            if !isExerciseEnded && sessionId != nil {
                exerciseService.recordInterruption()
            }
        case .active:
            // Resume voice guidance if needed
            break
        @unknown default:
            break
        }
    }

    private func removeLastObject() {
        guard !placedObjects.isEmpty else { return }
        placedObjects.removeLast()
        sceneConfig.undoLastNode()
    }

    private func saveScene() {
        showSaveSheet = false

        // Sanitize scene name: trim, limit length, remove control characters
        let sanitizedName = sanitizeSceneName(sceneName)
        guard !sanitizedName.isEmpty else { return }

        Task {
            let sceneData = ARSceneData(
                objects: placedObjects,
                environmentPrefs: .default
            )

            do {
                try await exerciseService.saveScenePreference(
                    name: sanitizedName,
                    data: sceneData,
                    isDefault: true
                )
                showCompletion = true
            } catch {
                #if DEBUG
                print("Scene save failed")
                #endif
            }
        }
    }
    
    /// Sanitize scene name to prevent injection and limit length
    private func sanitizeSceneName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.unicodeScalars
            .filter { !$0.properties.isPatternSyntax && $0.value >= 32 }
            .map { Character($0) }
        return String(String(cleaned).prefix(50))
    }

    private func endExercise(completed: Bool) {
        // Guard against race conditions - only end once
        guard !isExerciseEnded else { return }
        isExerciseEnded = true
        
        exerciseService.stopGuidance()

        if completed {
            showCompletion = true
        } else {
            Task {
                await exerciseService.abandonSession()
            }
            dismiss()
        }
    }

    private func saveAndDismiss() {
        // Validate rating (1-5 range)
        let validatedRating: Int? = (1...5).contains(effectivenessRating) ? effectivenessRating : nil
        
        Task {
            // Use actual session ID, not exercise ID
            if let currentSessionId = sessionId {
                try? await exerciseService.completeSession(
                    sessionId: currentSessionId,
                    completedSteps: placedObjects.count,
                    rating: validatedRating
                )
            }
        }
        showCompletion = false
        dismiss()
    }
}

// MARK: - Safe Space Scene Configuration

class SafeSpaceSceneConfiguration: ARSceneConfiguration {
    var selectedObjectType: String?
    var onObjectPlaced: ((ARSceneObject) -> Void)?
    private var placedNodes: [SCNNode] = []
    private let ambientLightIntensity: Float

    private static let tapCooldownInterval: TimeInterval = 0.15
    private var lastTapTime: Date = .distantPast

    init(ambientLightIntensity: Float = 0.7) {
        self.ambientLightIntensity = ambientLightIntensity
    }

    func configureScene(_ scene: SCNScene, _ arView: ARSCNView) {
        // Add ambient light
        let light = SCNLight()
        light.type = .ambient
        light.intensity = CGFloat(ambientLightIntensity * 1000)
        light.color = UIColor(white: 1.0, alpha: 1.0)
        let lightNode = SCNNode()
        lightNode.light = light
        scene.rootNode.addChildNode(lightNode)

        // Add directional light for shadows
        let directional = SCNLight()
        directional.type = .directional
        directional.intensity = 500
        directional.castsShadow = true
        let directionalNode = SCNNode()
        directionalNode.light = directional
        directionalNode.eulerAngles = SCNVector3(-Float.pi / 4, 0, 0)
        scene.rootNode.addChildNode(directionalNode)
    }

    func sessionDidUpdate(_ frame: ARFrame) {}

    func handleTap(at location: CGPoint, in view: ARSCNView) -> Bool {
        guard let objectType = selectedObjectType else { return false }

        // Rate limiting
        let now = Date()
        guard now.timeIntervalSince(lastTapTime) >= Self.tapCooldownInterval else { return false }
        lastTapTime = now

        // Ray cast to find a surface
        guard let query = view.raycastQuery(from: location, allowing: .estimatedPlane, alignment: .horizontal) else {
            return false
        }

        let results = view.session.raycast(query)
        guard let result = results.first else { return false }

        // Create 3D node for this object type
        let node = createObjectNode(type: objectType)
        node.simdTransform = result.worldTransform
        node.position.y += 0.02 // Slightly above surface

        // Add appear animation
        node.scale = SCNVector3(0.01, 0.01, 0.01)
        let scaleUp = SCNAction.scale(to: 1.0, duration: 0.3)
        scaleUp.timingMode = .easeOut
        node.runAction(scaleUp)

        view.scene.rootNode.addChildNode(node)
        placedNodes.append(node)

        // Notify SwiftUI layer
        let object = ARSceneObject(
            objectType: objectType,
            positionX: node.position.x,
            positionY: node.position.y,
            positionZ: node.position.z,
            scale: 0.1
        )
        onObjectPlaced?(object)

        return true
    }

    private func createObjectNode(type: String) -> SCNNode {
        let node = SCNNode()
        node.name = "safeSpace_\(type)_\(placedNodes.count)"

        switch type {
        case "plant":
            let stem = SCNCylinder(radius: 0.005, height: 0.06)
            let stemMaterial = SCNMaterial()
            stemMaterial.diffuse.contents = UIColor(red: 0.2, green: 0.5, blue: 0.2, alpha: 1)
            stemMaterial.lightingModel = .blinn
            stem.materials = [stemMaterial]
            let stemNode = SCNNode(geometry: stem)
            stemNode.position.y = 0.03

            let leaves = SCNSphere(radius: 0.04)
            let leavesMaterial = SCNMaterial()
            leavesMaterial.diffuse.contents = UIColor(red: 0.15, green: 0.7, blue: 0.3, alpha: 0.9)
            leavesMaterial.emission.contents = UIColor(red: 0.05, green: 0.2, blue: 0.05, alpha: 0.3)
            leavesMaterial.lightingModel = .blinn
            leaves.materials = [leavesMaterial]
            let leavesNode = SCNNode(geometry: leaves)
            leavesNode.position.y = 0.07

            node.addChildNode(stemNode)
            node.addChildNode(leavesNode)

        case "candle":
            let body = SCNCylinder(radius: 0.015, height: 0.06)
            let bodyMaterial = SCNMaterial()
            bodyMaterial.diffuse.contents = UIColor(red: 1.0, green: 0.95, blue: 0.85, alpha: 1)
            bodyMaterial.lightingModel = .blinn
            body.materials = [bodyMaterial]
            let bodyNode = SCNNode(geometry: body)
            bodyNode.position.y = 0.03

            let flame = SCNSphere(radius: 0.008)
            let flameMaterial = SCNMaterial()
            flameMaterial.diffuse.contents = UIColor.orange
            flameMaterial.emission.contents = UIColor(red: 1.0, green: 0.7, blue: 0.2, alpha: 1.0)
            flameMaterial.lightingModel = .constant
            flame.materials = [flameMaterial]
            let flameNode = SCNNode(geometry: flame)
            flameNode.position.y = 0.065

            // Glow halo around flame (no SCNLight to avoid ARKit conflicts)
            let glow = SCNSphere(radius: 0.02)
            let glowMaterial = SCNMaterial()
            glowMaterial.diffuse.contents = UIColor(red: 1.0, green: 0.8, blue: 0.3, alpha: 0.25)
            glowMaterial.emission.contents = UIColor(red: 1.0, green: 0.7, blue: 0.2, alpha: 0.5)
            glowMaterial.lightingModel = .constant
            glowMaterial.isDoubleSided = true
            glowMaterial.transparency = 0.4
            glow.materials = [glowMaterial]
            let glowNode = SCNNode(geometry: glow)
            glowNode.position.y = 0.065

            // Flicker animation on both flame and glow
            let flicker = SCNAction.sequence([
                SCNAction.scale(to: 1.2, duration: 0.3),
                SCNAction.scale(to: 0.9, duration: 0.2),
                SCNAction.scale(to: 1.0, duration: 0.25)
            ])
            flameNode.runAction(SCNAction.repeatForever(flicker))
            glowNode.runAction(SCNAction.repeatForever(flicker))

            node.addChildNode(bodyNode)
            node.addChildNode(glowNode)
            node.addChildNode(flameNode)

        case "crystal":
            let crystal = SCNPyramid(width: 0.03, height: 0.07, length: 0.03)
            let crystalMaterial = SCNMaterial()
            crystalMaterial.diffuse.contents = UIColor(red: 0.6, green: 0.4, blue: 0.9, alpha: 0.8)
            crystalMaterial.emission.contents = UIColor(red: 0.4, green: 0.2, blue: 0.8, alpha: 0.4)
            crystalMaterial.transparency = 0.7
            crystalMaterial.lightingModel = .physicallyBased
            crystalMaterial.metalness.contents = 0.3
            crystalMaterial.roughness.contents = 0.1
            crystal.materials = [crystalMaterial]
            let crystalNode = SCNNode(geometry: crystal)
            crystalNode.position.y = 0.035

            // Gentle rotation
            let rotate = SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 8)
            crystalNode.runAction(SCNAction.repeatForever(rotate))

            node.addChildNode(crystalNode)

        case "cushion":
            let cushion = SCNBox(width: 0.08, height: 0.025, length: 0.08, chamferRadius: 0.01)
            let cushionMaterial = SCNMaterial()
            cushionMaterial.diffuse.contents = UIColor(red: 0.3, green: 0.5, blue: 0.8, alpha: 1)
            cushionMaterial.lightingModel = .blinn
            cushion.materials = [cushionMaterial]
            let cushionNode = SCNNode(geometry: cushion)
            cushionNode.position.y = 0.0125
            node.addChildNode(cushionNode)

        case "light_orb":
            let orb = SCNSphere(radius: 0.03)
            let orbMaterial = SCNMaterial()
            orbMaterial.diffuse.contents = UIColor(red: 1.0, green: 0.95, blue: 0.7, alpha: 0.9)
            orbMaterial.emission.contents = UIColor(red: 1.0, green: 0.9, blue: 0.5, alpha: 1.0)
            orbMaterial.lightingModel = .constant
            orbMaterial.transparency = 0.7
            orb.materials = [orbMaterial]
            let orbNode = SCNNode(geometry: orb)
            orbNode.position.y = 0.08

            // Outer glow halo (no SCNLight to avoid ARKit conflicts)
            let halo = SCNSphere(radius: 0.05)
            let haloMaterial = SCNMaterial()
            haloMaterial.diffuse.contents = UIColor(red: 1.0, green: 0.95, blue: 0.6, alpha: 0.15)
            haloMaterial.emission.contents = UIColor(red: 1.0, green: 0.9, blue: 0.5, alpha: 0.3)
            haloMaterial.lightingModel = .constant
            haloMaterial.isDoubleSided = true
            haloMaterial.transparency = 0.3
            halo.materials = [haloMaterial]
            let haloNode = SCNNode(geometry: halo)
            haloNode.position.y = 0.08

            // Floating animation
            let floatUp = SCNAction.moveBy(x: 0, y: 0.015, z: 0, duration: 1.5)
            floatUp.timingMode = .easeInEaseOut
            let floatDown = floatUp.reversed()
            let floatSequence = SCNAction.repeatForever(SCNAction.sequence([floatUp, floatDown]))
            orbNode.runAction(floatSequence)
            haloNode.runAction(floatSequence)

            node.addChildNode(haloNode)
            node.addChildNode(orbNode)

        case "water_fountain":
            let base = SCNCylinder(radius: 0.035, height: 0.02)
            let baseMaterial = SCNMaterial()
            baseMaterial.diffuse.contents = UIColor(red: 0.6, green: 0.6, blue: 0.65, alpha: 1)
            baseMaterial.lightingModel = .blinn
            base.materials = [baseMaterial]
            let baseNode = SCNNode(geometry: base)
            baseNode.position.y = 0.01

            let water = SCNSphere(radius: 0.02)
            let waterMaterial = SCNMaterial()
            waterMaterial.diffuse.contents = UIColor(red: 0.3, green: 0.6, blue: 0.9, alpha: 0.7)
            waterMaterial.emission.contents = UIColor(red: 0.2, green: 0.4, blue: 0.7, alpha: 0.3)
            waterMaterial.transparency = 0.6
            waterMaterial.lightingModel = .blinn
            water.materials = [waterMaterial]
            let waterNode = SCNNode(geometry: water)
            waterNode.position.y = 0.04

            // Ripple animation
            let pulse = SCNAction.sequence([
                SCNAction.scale(to: 1.15, duration: 0.8),
                SCNAction.scale(to: 1.0, duration: 0.8)
            ])
            waterNode.runAction(SCNAction.repeatForever(pulse))

            node.addChildNode(baseNode)
            node.addChildNode(waterNode)

        default:
            let sphere = SCNSphere(radius: 0.03)
            let defaultMaterial = SCNMaterial()
            defaultMaterial.diffuse.contents = UIColor.systemBlue
            defaultMaterial.lightingModel = .blinn
            sphere.materials = [defaultMaterial]
            let defaultNode = SCNNode(geometry: sphere)
            defaultNode.position.y = 0.03
            node.addChildNode(defaultNode)
        }

        return node
    }

    func undoLastNode() {
        guard let last = placedNodes.popLast() else { return }
        let fadeOut = SCNAction.sequence([
            SCNAction.scale(to: 0.01, duration: 0.2),
            SCNAction.removeFromParentNode()
        ])
        last.runAction(fadeOut)
    }

    func clearAllNodes() {
        placedNodes.forEach { $0.removeFromParentNode() }
        placedNodes.removeAll()
    }
}
