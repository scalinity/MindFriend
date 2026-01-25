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
    private static let tapCooldownInterval: TimeInterval = 0.15
    @State private var lastTapTime: Date = .distantPast

    // MARK: - Body

    public var body: some View {
        ZStack {
            // AR Scene (simplified for safe space)
            ARSceneView(
                configuration: SafeSpaceSceneConfiguration(),
                trackingState: $trackingState,
                isSessionRunning: $isSessionRunning,
                onTap: handleTap
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

    private func handleTap(_ location: CGPoint) {
        guard let objectType = selectedObjectType, planeDetected else { return }
        
        // Rate limiting: enforce minimum time between taps
        let now = Date()
        guard now.timeIntervalSince(lastTapTime) >= Self.tapCooldownInterval else { return }
        lastTapTime = now
        
        // Limit maximum objects per scene
        guard placedObjects.count < Self.maxObjectsPerScene else { return }

        // Create object at tap location (simplified - would use AR hit test)
        let object = ARSceneObject(
            objectType: objectType,
            positionX: Float.random(in: -0.5...0.5),
            positionY: 0,
            positionZ: Float.random(in: -1.0...(-0.5)),
            scale: 0.1
        )

        placedObjects.append(object)
        exerciseService.speakGuidance("\(objectType.replacingOccurrences(of: "_", with: " ")) placed")
    }

    private func removeLastObject() {
        guard !placedObjects.isEmpty else { return }
        placedObjects.removeLast()
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
    func configureScene(_ scene: SCNScene, _ arView: ARSCNView) {
        // Add ambient light
        let light = SCNLight()
        light.type = .ambient
        light.intensity = 600
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
        return false
    }
}
