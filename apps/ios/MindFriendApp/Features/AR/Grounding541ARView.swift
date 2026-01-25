import SwiftUI
import ARKit
import SceneKit

/// AR 5-4-3-2-1 Grounding exercise view
public struct Grounding541ARView: View {

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var exerciseService: ARExerciseService

    // MARK: - Properties

    let exercise: ARExercise

    // MARK: - State

    @State private var trackingState: ARTrackingQuality = .notAvailable
    @State private var isSessionRunning: Bool = false
    @State private var currentStep: GroundingStep = .see
    @State private var markersPlaced: Int = 0
    @State private var totalMarkersPlaced: Int = 0
    @State private var showCompletion: Bool = false
    @State private var showExitConfirmation: Bool = false
    @State private var effectivenessRating: Int = 0
    @State private var showStepTransition: Bool = false
    @State private var sessionId: UUID?  // Track actual session ID
    @State private var isExerciseEnded: Bool = false  // Guard against race conditions

    // MARK: - Scene Configuration

    @State private var sceneConfig: Grounding541SceneConfiguration

    // MARK: - Rate Limiting
    
    // Total markers expected: 5+4+3+2+1 = 15, allow some buffer
    private static let maxMarkersPerSession = 20

    // MARK: - Initialization

    public init(exercise: ARExercise) {
        self.exercise = exercise
        let colors = exercise.sceneConfig.markerColors ?? MarkerColors()
        _sceneConfig = State(initialValue: Grounding541SceneConfiguration(markerColors: colors))
    }

    // MARK: - Body

    public var body: some View {
        ZStack {
            // AR Scene
            ARSceneView(
                configuration: sceneConfig,
                trackingState: $trackingState,
                isSessionRunning: $isSessionRunning
            )
            .ignoresSafeArea()

            // Crosshair
            crosshair

            // HUD Overlay
            VStack {
                // Top bar
                HStack {
                    // Tracking indicator
                    trackingIndicator

                    Spacer()

                    // Step progress
                    stepProgressView

                    Spacer()

                    // Exit button
                    Button {
                        showExitConfirmation = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding()
                .background(.ultraThinMaterial.opacity(0.6))

                Spacer()

                // Center instruction
                instructionCard

                Spacer()

                // Bottom bar
                HStack {
                    // Voice guidance toggle
                    Button {
                        if exerciseService.isSpeaking {
                            exerciseService.stopGuidance()
                        } else {
                            exerciseService.speakGuidance(currentStep.instruction)
                        }
                    } label: {
                        Image(systemName: exerciseService.isSpeaking ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }

                    Spacer()

                    // Marker count
                    Text("\(markersPlaced)/\(currentStep.count)")
                        .font(.title2.bold())
                        .foregroundStyle(.white)

                    Spacer()

                    // Undo button
                    Button {
                        undoLastMarker()
                    } label: {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                            .font(.title2)
                            .foregroundStyle(markersPlaced > 0 ? .white : .white.opacity(0.3))
                            .frame(width: 44, height: 44)
                    }
                    .disabled(markersPlaced == 0)
                }
                .padding()
                .background(.ultraThinMaterial.opacity(0.6))
            }

            // Tracking warning overlay
            if case .limited(let reason) = trackingState {
                trackingWarningOverlay(reason: reason)
            }

            // Step transition overlay
            if showStepTransition {
                stepTransitionOverlay
            }
        }
        .onAppear {
            startExercise()
        }
        .onDisappear {
            stopExercise()
        }
        .onChange(of: sceneConfig.markers.count) { _, newCount in
            handleMarkerUpdate()
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

    private var crosshair: some View {
        Circle()
            .stroke(.white.opacity(0.6), lineWidth: 2)
            .frame(width: 30, height: 30)
            .overlay {
                Circle()
                    .fill(.white.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
    }

    private var trackingIndicator: some View {
        Circle()
            .fill(trackingColor)
            .frame(width: 12, height: 12)
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.3), lineWidth: 1)
            }
    }

    private var trackingColor: Color {
        switch trackingState {
        case .normal: return .green
        case .limited: return .yellow
        case .notAvailable: return .red
        }
    }

    private var stepProgressView: some View {
        HStack(spacing: 8) {
            ForEach(GroundingStep.allCases, id: \.rawValue) { step in
                Circle()
                    .fill(stepColor(for: step))
                    .frame(width: 16, height: 16)
                    .overlay {
                        if step == currentStep {
                            Circle()
                                .stroke(.white, lineWidth: 2)
                        }
                    }
            }
        }
    }

    private func stepColor(for step: GroundingStep) -> Color {
        let markerColors = exercise.sceneConfig.markerColors ?? MarkerColors()
        let colorHex = markerColors[keyPath: step.colorKey]
        if step.rawValue > currentStep.rawValue {
            return .gray.opacity(0.5)
        }
        return Color(UIColor(hex: colorHex) ?? .blue)
    }

    private var instructionCard: some View {
        VStack(spacing: 12) {
            Text(currentStep.displayName.uppercased())
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)

            Text(currentStep.instruction)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text("Tap objects in your environment")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .padding(.horizontal, 32)
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

    private var stepTransitionOverlay: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)

                Text("Step Complete!")
                    .font(.title)
                    .foregroundStyle(.white)

                if let nextStep = currentStep.next {
                    Text("Next: \(nextStep.instruction)")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .transition(.opacity)
    }

    private var completionView: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue)

                Text("You're grounded!")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("You identified \(totalMarkersPlaced) things in your environment")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // Summary of what was marked
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(GroundingStep.allCases, id: \.rawValue) { step in
                        HStack {
                            Circle()
                                .fill(stepColor(for: step))
                                .frame(width: 12, height: 12)
                            Text("\(step.count) things you \(step.displayName.lowercased())")
                                .font(.subheadline)
                            Spacer()
                            Image(systemName: "checkmark")
                                .foregroundStyle(.green)
                        }
                    }
                }
                .padding()
                .background(.gray.opacity(0.1))
                .cornerRadius(12)

                VStack(spacing: 12) {
                    Text("How effective was this exercise?")
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
        
        sceneConfig.onMarkerPlaced = { step, count in
            markersPlaced = count
            exerciseService.recordTrackingQuality(trackingState.qualityValue)
        }

        Task {
            do {
                let newSessionId = try await exerciseService.startSession(exercise: exercise)
                sessionId = newSessionId
                exerciseService.speakGuidance(currentStep.instruction)
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

    private func handleMarkerUpdate() {
        let stepMarkers = sceneConfig.markers.filter {
            $0.name?.hasPrefix(currentStep.displayName) ?? false
        }
        markersPlaced = stepMarkers.count
        totalMarkersPlaced = sceneConfig.markers.count

        // Check if current step is complete
        if markersPlaced >= currentStep.count {
            advanceToNextStep()
        }
    }

    private func advanceToNextStep() {
        guard !isExerciseEnded else { return }
        
        showStepTransition = true
        exerciseService.speakGuidance("Great job!")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            guard !isExerciseEnded else { return }
            
            showStepTransition = false

            if sceneConfig.advanceStep() {
                currentStep = sceneConfig.currentStep
                markersPlaced = 0
                exerciseService.speakGuidance(currentStep.instruction)
            } else {
                // All steps complete
                endExercise(completed: true)
            }
        }
    }

    private func undoLastMarker() {
        sceneConfig.undoLastMarker()
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
                    completedSteps: totalMarkersPlaced,
                    rating: validatedRating
                )
            }
        }
        showCompletion = false
        dismiss()
    }
}
