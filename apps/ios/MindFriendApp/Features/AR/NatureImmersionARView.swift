import SwiftUI
import ARKit
import SceneKit

/// AR Nature Immersion exercise view (Premium, LiDAR preferred)
/// Passive immersive forest environment with spatial particles and ambient effects
public struct NatureImmersionARView: View {

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var exerciseService: ARExerciseService

    // MARK: - Properties

    let exercise: ARExercise

    // MARK: - State

    @State private var trackingState: ARTrackingQuality = .notAvailable
    @State private var isSessionRunning: Bool = false
    @State private var timeRemaining: TimeInterval
    @State private var isPaused: Bool = false
    @State private var showCompletion: Bool = false
    @State private var showExitConfirmation: Bool = false
    @State private var effectivenessRating: Int = 0
    @State private var sessionId: UUID?
    @State private var isExerciseEnded: Bool = false
    @State private var sessionTimer: Timer?
    @State private var timeRemainingAtPause: TimeInterval = 0
    @State private var breathPhaseText: String = "Breathe naturally"
    @State private var sceneConfig: NatureImmersionSceneConfiguration

    // MARK: - Initialization

    public init(exercise: ARExercise) {
        self.exercise = exercise
        _timeRemaining = State(initialValue: TimeInterval(exercise.durationSeconds))
        _sceneConfig = State(initialValue: NatureImmersionSceneConfiguration())
    }

    // MARK: - Body

    public var body: some View {
        ZStack {
            // AR Scene - passive immersive environment
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
                    trackingIndicator

                    Spacer()

                    timerDisplay

                    Spacer()

                    Button {
                        showExitConfirmation = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .accessibilityLabel("End exercise")
                }
                .padding()
                .background(.ultraThinMaterial.opacity(0.4))

                Spacer()

                // Center breathing prompt
                VStack(spacing: 12) {
                    Text(breathPhaseText)
                        .font(.title)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 6)
                        .accessibilityLabel("Instruction: \(breathPhaseText)")

                    Text("Let the forest surround you")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .shadow(color: .black.opacity(0.4), radius: 4)
                }

                Spacer()

                // Bottom bar
                HStack {
                    // Voice guidance toggle
                    Button {
                        if exerciseService.isSpeaking {
                            exerciseService.stopGuidance()
                        } else {
                            exerciseService.speakGuidance(breathPhaseText)
                        }
                    } label: {
                        Image(systemName: exerciseService.isSpeaking ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(exerciseService.isSpeaking ? "Stop voice guidance" : "Start voice guidance")

                    Spacer()

                    // Pause button
                    Button {
                        togglePause()
                    } label: {
                        Image(systemName: isPaused ? "play.fill" : "pause.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(isPaused ? "Resume" : "Pause")
                }
                .padding()
                .background(.ultraThinMaterial.opacity(0.4))
            }

            // Tracking warning
            if case .limited(let reason) = trackingState {
                trackingWarningOverlay(reason: reason)
            }

            // Pause overlay
            if isPaused {
                pauseOverlay
            }
        }
        .onAppear {
            startExercise()
        }
        .onDisappear {
            stopExercise()
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
        .alert("End Exercise?", isPresented: $showExitConfirmation) {
            Button("Continue", role: .cancel) {}
            Button("End", role: .destructive) {
                endExercise(completed: false)
            }
        } message: {
            Text("Your progress will be saved.")
        }
        .sheet(isPresented: $showCompletion) {
            completionView
        }
    }

    // MARK: - Subviews

    private var trackingIndicator: some View {
        Circle()
            .fill(trackingColor)
            .frame(width: 12, height: 12)
            .accessibilityLabel("AR tracking: \(trackingState == .normal ? "good" : "limited")")
    }

    private var trackingColor: Color {
        switch trackingState {
        case .normal: return .green
        case .limited: return .yellow
        case .notAvailable: return .red
        }
    }

    private var timerDisplay: some View {
        Text(formatTime(timeRemaining))
            .font(.title2.monospacedDigit())
            .foregroundStyle(.white)
            .accessibilityLabel("Time remaining: \(formatTime(timeRemaining))")
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

    private var pauseOverlay: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.white)

                Text("Paused")
                    .font(.title)
                    .foregroundStyle(.white)

                Button {
                    togglePause()
                } label: {
                    Text("Resume")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(.green)
                        .cornerRadius(12)
                }
            }
        }
    }

    private var completionView: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.green)

                Text("Session Complete")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("You spent time immersed in nature")
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
                        .background(.green)
                        .cornerRadius(12)
                }
            }
            .padding()
            .navigationTitle("Nature Immersion")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Actions

    private func startExercise() {
        Task {
            do {
                let newSessionId = try await exerciseService.startSession(exercise: exercise)
                sessionId = newSessionId
                startSessionTimer()
                startBreathingPrompts()
                exerciseService.speakNextGuidance(for: exercise)
            } catch {
                #if DEBUG
                print("Nature immersion session start failed")
                #endif
            }
        }
    }

    private func stopExercise() {
        sessionTimer?.invalidate()
        sessionTimer = nil
        exerciseService.stopGuidance()
    }

    private func startSessionTimer() {
        guard !isExerciseEnded else { return }

        sessionTimer?.invalidate()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            guard !self.isExerciseEnded else {
                self.sessionTimer?.invalidate()
                return
            }

            if self.timeRemaining > 0 {
                self.timeRemaining -= 1
                self.exerciseService.recordTrackingQuality(self.trackingState.qualityValue)
            } else {
                self.sessionTimer?.invalidate()
                self.endExercise(completed: true)
            }
        }
    }

    private func startBreathingPrompts() {
        // Cycle through calming prompts
        let prompts = [
            "Breathe naturally",
            "Listen to the forest",
            "Feel the calm around you",
            "Let go of tension",
            "Breathe deeply",
            "Be present in this moment"
        ]

        var index = 0
        Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { timer in
            guard !self.isExerciseEnded && !self.isPaused else {
                if self.isExerciseEnded { timer.invalidate() }
                return
            }
            index = (index + 1) % prompts.count
            withAnimation(.easeInOut(duration: 0.5)) {
                self.breathPhaseText = prompts[index]
            }
        }
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .background, .inactive:
            if !isPaused && !isExerciseEnded {
                timeRemainingAtPause = timeRemaining
                sessionTimer?.invalidate()
                sessionTimer = nil
                exerciseService.recordInterruption()
            }
        case .active:
            if !isPaused && !isExerciseEnded && sessionId != nil {
                timeRemaining = timeRemainingAtPause
                startSessionTimer()
            }
        @unknown default:
            break
        }
    }

    private func togglePause() {
        isPaused.toggle()
        if isPaused {
            timeRemainingAtPause = timeRemaining
            sessionTimer?.invalidate()
            sessionTimer = nil
            exerciseService.recordInterruption()
        } else {
            timeRemaining = timeRemainingAtPause
            startSessionTimer()
        }
    }

    private func endExercise(completed: Bool) {
        guard !isExerciseEnded else { return }
        isExerciseEnded = true

        sessionTimer?.invalidate()
        sessionTimer = nil
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
        let validatedRating: Int? = (1...5).contains(effectivenessRating) ? effectivenessRating : nil

        Task {
            if let currentSessionId = sessionId {
                try? await exerciseService.completeSession(
                    sessionId: currentSessionId,
                    completedSteps: exercise.durationSeconds - Int(timeRemaining),
                    rating: validatedRating
                )
            }
        }
        showCompletion = false
        dismiss()
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Nature Immersion Scene Configuration

class NatureImmersionSceneConfiguration: ARSceneConfiguration {

    func configureScene(_ scene: SCNScene, _ arView: ARSCNView) {
        // Forest-toned ambient light
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 500
        ambient.color = UIColor(red: 0.6, green: 0.8, blue: 0.55, alpha: 1.0)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        // Dappled sunlight from above
        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 800
        sun.color = UIColor(red: 1.0, green: 0.95, blue: 0.75, alpha: 1.0)
        sun.castsShadow = true
        sun.shadowRadius = 3
        sun.shadowSampleCount = 4
        let sunNode = SCNNode()
        sunNode.light = sun
        sunNode.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 6, 0)
        scene.rootNode.addChildNode(sunNode)

        // Build the forest
        addGroundPlane(to: scene)
        addTrees(to: scene)
        addRocks(to: scene)
        addFallingLeaves(to: scene)
        addFireflies(to: scene)
        addGroundFoliage(to: scene)
    }

    // MARK: - Ground

    private func addGroundPlane(to scene: SCNScene) {
        let ground = SCNPlane(width: 8, height: 8)
        let groundMaterial = SCNMaterial()
        groundMaterial.diffuse.contents = UIColor(red: 0.2, green: 0.35, blue: 0.12, alpha: 0.6)
        groundMaterial.lightingModel = .blinn
        groundMaterial.transparency = 0.5
        ground.materials = [groundMaterial]

        let groundNode = SCNNode(geometry: ground)
        groundNode.eulerAngles.x = -.pi / 2 // Lay flat
        groundNode.position = SCNVector3(0, -0.5, -1.0)
        groundNode.name = "ground"
        scene.rootNode.addChildNode(groundNode)
    }

    // MARK: - Trees

    private func addTrees(to scene: SCNScene) {
        // Place trees in a ring around the user
        let treePositions: [(x: Float, z: Float, scale: Float)] = [
            // Close ring
            (-1.2, -1.5, 1.0),
            (1.3, -1.4, 0.9),
            (-0.8, -2.2, 1.1),
            (0.9, -2.0, 0.85),
            (0.0, -2.5, 1.05),
            // Side trees
            (-2.0, -1.0, 1.2),
            (2.0, -0.8, 1.15),
            (-1.5, -0.5, 0.8),
            (1.6, -0.6, 0.75),
            // Behind user
            (-1.0, 0.5, 0.9),
            (1.0, 0.6, 0.95),
            (0.0, 1.0, 1.0),
        ]

        for (i, pos) in treePositions.enumerated() {
            let tree = createTree(scale: pos.scale, variant: i % 3)
            tree.position = SCNVector3(pos.x, -0.5, pos.z)
            tree.name = "tree_\(i)"
            scene.rootNode.addChildNode(tree)
        }
    }

    private func createTree(scale: Float, variant: Int) -> SCNNode {
        let tree = SCNNode()

        // Trunk
        let trunkHeight: CGFloat = CGFloat(0.6 * scale)
        let trunk = SCNCylinder(radius: CGFloat(0.04 * scale), height: trunkHeight)
        let trunkMaterial = SCNMaterial()
        // Vary trunk color slightly
        let brownVariation = Float.random(in: -0.05...0.05)
        trunkMaterial.diffuse.contents = UIColor(
            red: CGFloat(0.35 + brownVariation),
            green: CGFloat(0.22 + brownVariation),
            blue: CGFloat(0.12 + brownVariation),
            alpha: 1.0
        )
        trunkMaterial.lightingModel = .blinn
        trunk.materials = [trunkMaterial]
        let trunkNode = SCNNode(geometry: trunk)
        trunkNode.position.y = Float(trunkHeight / 2)
        tree.addChildNode(trunkNode)

        // Canopy - different shapes per variant
        let canopyNode: SCNNode
        let greenVariation = CGFloat(Float.random(in: -0.08...0.08))
        let canopyMaterial = SCNMaterial()
        canopyMaterial.diffuse.contents = UIColor(
            red: 0.12 + greenVariation,
            green: 0.55 + greenVariation,
            blue: 0.18 + greenVariation,
            alpha: 0.9
        )
        canopyMaterial.emission.contents = UIColor(red: 0.03, green: 0.1, blue: 0.02, alpha: 0.2)
        canopyMaterial.lightingModel = .blinn
        canopyMaterial.isDoubleSided = true

        switch variant {
        case 0:
            // Round canopy
            let sphere = SCNSphere(radius: CGFloat(0.25 * scale))
            sphere.segmentCount = 24
            sphere.materials = [canopyMaterial]
            canopyNode = SCNNode(geometry: sphere)
        case 1:
            // Cone (pine-like)
            let cone = SCNCone(topRadius: 0, bottomRadius: CGFloat(0.22 * scale), height: CGFloat(0.5 * scale))
            cone.materials = [canopyMaterial]
            canopyNode = SCNNode(geometry: cone)
        default:
            // Layered canopy (two spheres)
            let lower = SCNSphere(radius: CGFloat(0.22 * scale))
            lower.segmentCount = 20
            lower.materials = [canopyMaterial]
            let lowerNode = SCNNode(geometry: lower)

            let upperMaterial = SCNMaterial()
            upperMaterial.diffuse.contents = UIColor(
                red: 0.1 + greenVariation,
                green: 0.5 + greenVariation,
                blue: 0.15 + greenVariation,
                alpha: 0.85
            )
            upperMaterial.emission.contents = UIColor(red: 0.02, green: 0.08, blue: 0.01, alpha: 0.15)
            upperMaterial.lightingModel = .blinn
            upperMaterial.isDoubleSided = true
            let upper = SCNSphere(radius: CGFloat(0.16 * scale))
            upper.segmentCount = 18
            upper.materials = [upperMaterial]
            let upperNode = SCNNode(geometry: upper)
            upperNode.position.y = Float(0.15 * scale)

            canopyNode = SCNNode()
            canopyNode.addChildNode(lowerNode)
            canopyNode.addChildNode(upperNode)
        }

        canopyNode.position.y = Float(trunkHeight) + Float(0.1 * scale)
        tree.addChildNode(canopyNode)

        // Gentle sway animation
        let swayAngle = Float.random(in: 0.01...0.03)
        let swayDuration = Double.random(in: 3.0...5.0)
        let swayLeft = SCNAction.rotateBy(x: 0, y: 0, z: CGFloat(swayAngle), duration: swayDuration)
        swayLeft.timingMode = .easeInEaseOut
        let swayRight = SCNAction.rotateBy(x: 0, y: 0, z: CGFloat(-swayAngle * 2), duration: swayDuration * 2)
        swayRight.timingMode = .easeInEaseOut
        let swayBack = SCNAction.rotateBy(x: 0, y: 0, z: CGFloat(swayAngle), duration: swayDuration)
        swayBack.timingMode = .easeInEaseOut
        tree.runAction(SCNAction.repeatForever(SCNAction.sequence([swayLeft, swayRight, swayBack])))

        return tree
    }

    // MARK: - Rocks

    private func addRocks(to scene: SCNScene) {
        let rockPositions: [(x: Float, y: Float, z: Float)] = [
            (-0.6, -0.48, -1.2),
            (0.7, -0.48, -1.5),
            (-0.3, -0.48, -2.0),
            (1.5, -0.48, -1.0),
            (-1.4, -0.48, -0.8),
            (0.2, -0.48, -0.9),
        ]

        for (i, pos) in rockPositions.enumerated() {
            let rock = createRock()
            rock.position = SCNVector3(pos.x, pos.y, pos.z)
            rock.name = "rock_\(i)"
            scene.rootNode.addChildNode(rock)
        }
    }

    private func createRock() -> SCNNode {
        let size = Float.random(in: 0.04...0.1)
        let rock = SCNSphere(radius: CGFloat(size))
        rock.segmentCount = 12

        let material = SCNMaterial()
        let grayValue = CGFloat(Float.random(in: 0.35...0.55))
        material.diffuse.contents = UIColor(red: grayValue, green: grayValue - 0.02, blue: grayValue - 0.05, alpha: 1.0)
        material.lightingModel = .blinn
        rock.materials = [material]

        let node = SCNNode(geometry: rock)
        // Squash slightly to look like a rock
        node.scale = SCNVector3(1.0, Float.random(in: 0.5...0.7), Float.random(in: 0.8...1.2))
        return node
    }

    // MARK: - Ground Foliage

    private func addGroundFoliage(to scene: SCNScene) {
        // Small ground plants / ferns
        let positions: [(x: Float, z: Float)] = [
            (-0.4, -1.0), (0.5, -1.3), (-0.9, -1.8),
            (0.3, -0.7), (-1.1, -1.1), (0.8, -2.1),
            (-0.2, -1.6), (1.2, -0.9), (-0.7, -0.6),
        ]

        for (i, pos) in positions.enumerated() {
            let plant = createGroundPlant()
            plant.position = SCNVector3(pos.x, -0.48, pos.z)
            plant.name = "fern_\(i)"
            scene.rootNode.addChildNode(plant)
        }
    }

    private func createGroundPlant() -> SCNNode {
        let node = SCNNode()

        // Small cluster of upright leaves
        let leafCount = Int.random(in: 3...5)
        for j in 0..<leafCount {
            let leaf = SCNBox(width: 0.01, height: CGFloat(Float.random(in: 0.04...0.08)), length: 0.005, chamferRadius: 0.002)
            let leafMaterial = SCNMaterial()
            let greenVal = CGFloat(Float.random(in: 0.4...0.7))
            leafMaterial.diffuse.contents = UIColor(red: 0.1, green: greenVal, blue: 0.15, alpha: 0.9)
            leafMaterial.emission.contents = UIColor(red: 0.02, green: 0.1, blue: 0.02, alpha: 0.15)
            leafMaterial.lightingModel = .blinn
            leafMaterial.isDoubleSided = true
            leaf.materials = [leafMaterial]

            let leafNode = SCNNode(geometry: leaf)
            let angle = Float(j) * (.pi * 2 / Float(leafCount)) + Float.random(in: -0.3...0.3)
            let spread: Float = 0.02
            leafNode.position = SCNVector3(cos(angle) * spread, 0.02, sin(angle) * spread)
            leafNode.eulerAngles.z = Float.random(in: -0.3...0.3)
            node.addChildNode(leafNode)
        }

        return node
    }

    // MARK: - Particles

    private func addFallingLeaves(to scene: SCNScene) {
        let leaves = SCNParticleSystem()
        leaves.particleSize = 0.02
        leaves.particleSizeVariation = 0.01
        leaves.particleColor = UIColor(red: 0.4, green: 0.65, blue: 0.2, alpha: 0.85)
        leaves.particleColorVariation = SCNVector4(0.2, 0.15, 0.05, 0.1)
        leaves.birthRate = 5
        leaves.particleLifeSpan = 10
        leaves.particleLifeSpanVariation = 4
        leaves.spreadingAngle = 40
        leaves.emissionDuration = CGFloat.infinity
        leaves.loops = true
        leaves.blendMode = .alpha
        leaves.particleVelocity = 0.03
        leaves.particleVelocityVariation = 0.02
        leaves.acceleration = SCNVector3(0.005, -0.01, 0) // Drift + gentle fall
        leaves.particleAngularVelocity = 1.0
        leaves.particleAngularVelocityVariation = 2.0

        let emitter = SCNNode()
        emitter.position = SCNVector3(0, 1.5, -1.5)
        leaves.emitterShape = SCNBox(width: 4.0, height: 0.1, length: 4.0, chamferRadius: 0)
        emitter.addParticleSystem(leaves)
        emitter.name = "fallingLeaves"
        scene.rootNode.addChildNode(emitter)
    }

    private func addFireflies(to scene: SCNScene) {
        let fireflies = SCNParticleSystem()
        fireflies.particleSize = 0.008
        fireflies.particleSizeVariation = 0.004
        fireflies.particleColor = UIColor(red: 0.85, green: 1.0, blue: 0.4, alpha: 0.95)
        fireflies.birthRate = 4
        fireflies.particleLifeSpan = 6
        fireflies.particleLifeSpanVariation = 3
        fireflies.spreadingAngle = 180
        fireflies.emissionDuration = CGFloat.infinity
        fireflies.loops = true
        fireflies.blendMode = .additive
        fireflies.particleVelocity = 0.015
        fireflies.particleVelocityVariation = 0.01

        let emitter = SCNNode()
        emitter.position = SCNVector3(0, 0.2, -1.5)
        fireflies.emitterShape = SCNSphere(radius: 2.5)
        emitter.addParticleSystem(fireflies)
        emitter.name = "fireflies"
        scene.rootNode.addChildNode(emitter)
    }

    func sessionDidUpdate(_ frame: ARFrame) {}

    func handleTap(at location: CGPoint, in view: ARSCNView) -> Bool {
        return false
    }
}
