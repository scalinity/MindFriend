import SwiftUI

/// Non-AR Safe Space Creator fallback view
/// Guided visualization exercise for creating a mental safe space
public struct SafeSpaceFallbackView: View {

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var exerciseService: ARExerciseService

    // MARK: - Properties

    let exercise: ARExercise

    // MARK: - State

    @State private var currentStep: SafeSpaceStep = .welcome
    @State private var timeRemaining: TimeInterval = 0
    @State private var isPaused: Bool = false
    @State private var showCompletion: Bool = false
    @State private var showExitConfirmation: Bool = false
    @State private var effectivenessRating: Int = 0
    @State private var sessionId: UUID?
    @State private var isExerciseEnded: Bool = false
    @State private var stepProgress: Double = 0
    @State private var breathScale: CGFloat = 1.0

    // MARK: - Timer

    @State private var stepTimer: Timer?
    @State private var sessionTimer: Timer?

    // MARK: - Initialization

    public init(exercise: ARExercise) {
        self.exercise = exercise
        _timeRemaining = State(initialValue: TimeInterval(exercise.durationSeconds))
    }

    // MARK: - Body

    public var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [Color.purple.opacity(0.3), Color.indigo.opacity(0.2), Color.blue.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                topBar

                Spacer()

                // Main content
                stepContent

                Spacer()

                // Bottom bar
                bottomBar
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
        }
        .sheet(isPresented: $showCompletion) {
            completionView
        }
    }

    // MARK: - Subviews

    private var topBar: some View {
        HStack {
            Text(formatTime(timeRemaining))
                .font(.title2.monospacedDigit())
                .foregroundStyle(.primary)
                .accessibilityLabel("Time remaining: \(formatTime(timeRemaining))")

            Spacer()

            Button {
                showExitConfirmation = true
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("End exercise")
        }
        .padding()
    }

    private var stepContent: some View {
        VStack(spacing: 24) {
            // Step icon with breathing animation
            ZStack {
                Circle()
                    .fill(currentStep.color.opacity(0.2))
                    .frame(width: 140, height: 140)
                    .scaleEffect(breathScale)

                Image(systemName: currentStep.icon)
                    .font(.system(size: 60))
                    .foregroundStyle(currentStep.color)
            }
            .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: breathScale)

            // Step title
            Text(currentStep.title)
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            // Instruction
            Text(currentStep.instruction)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .fixedSize(horizontal: false, vertical: true)

            // Progress indicator
            ProgressView(value: stepProgress)
                .progressViewStyle(.linear)
                .frame(width: 200)
                .tint(currentStep.color)
                .padding(.top, 16)
        }
        .padding()
    }

    private var bottomBar: some View {
        HStack {
            // Step counter
            Text("Step \(currentStep.rawValue + 1)/\(SafeSpaceStep.allCases.count)")
                .font(.headline)
                .foregroundStyle(.secondary)

            Spacer()

            // Pause button
            Button {
                togglePause()
            } label: {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.title2)
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(isPaused ? "Resume exercise" : "Pause exercise")
        }
        .padding()
        .background(.ultraThinMaterial)
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
                        .background(.purple)
                        .cornerRadius(12)
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

                Text("Your Safe Space")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("You've created a sanctuary you can return to anytime")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

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
                        .background(.purple)
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
        breathScale = 1.15
        Task {
            do {
                let newSessionId = try await exerciseService.startSession(exercise: exercise)
                sessionId = newSessionId
                startStepTimer()
                startSessionTimer()
            } catch {
                #if DEBUG
                print("Safe space session start failed")
                #endif
            }
        }
    }

    private func stopExercise() {
        stepTimer?.invalidate()
        stepTimer = nil
        sessionTimer?.invalidate()
        sessionTimer = nil
        exerciseService.stopGuidance()
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .background, .inactive:
            if !isPaused && !isExerciseEnded {
                stepTimer?.invalidate()
                sessionTimer?.invalidate()
                exerciseService.recordInterruption()
            }
        case .active:
            if !isPaused && !isExerciseEnded && sessionId != nil {
                startStepTimer()
                startSessionTimer()
            }
        @unknown default:
            break
        }
    }

    private func togglePause() {
        isPaused.toggle()
        if isPaused {
            stepTimer?.invalidate()
            sessionTimer?.invalidate()
            exerciseService.recordInterruption()
        } else {
            startStepTimer()
            startSessionTimer()
        }
    }

    private func startStepTimer() {
        guard !isExerciseEnded else { return }
        stepProgress = 0

        let stepDuration = TimeInterval(exercise.durationSeconds) / TimeInterval(SafeSpaceStep.allCases.count)
        let interval: TimeInterval = 0.1

        stepTimer?.invalidate()
        stepTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            guard !self.isExerciseEnded else {
                self.stepTimer?.invalidate()
                return
            }

            self.stepProgress += interval / stepDuration

            if self.stepProgress >= 1.0 {
                self.stepTimer?.invalidate()
                self.advanceStep()
            }
        }
    }

    private func advanceStep() {
        guard !isExerciseEnded else { return }

        if let next = currentStep.next {
            currentStep = next
            stepProgress = 0
            startStepTimer()
        } else {
            endExercise(completed: true)
        }
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
            } else {
                self.sessionTimer?.invalidate()
                self.endExercise(completed: true)
            }
        }
    }

    private func endExercise(completed: Bool) {
        guard !isExerciseEnded else { return }
        isExerciseEnded = true

        stepTimer?.invalidate()
        stepTimer = nil
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
                    completedSteps: SafeSpaceStep.allCases.count,
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

// MARK: - Safe Space Steps

private enum SafeSpaceStep: Int, CaseIterable {
    case welcome
    case breathe
    case visualize
    case details
    case anchor
    case complete

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .breathe: return "Breathe"
        case .visualize: return "Visualize"
        case .details: return "Add Details"
        case .anchor: return "Anchor"
        case .complete: return "Remember"
        }
    }

    var instruction: String {
        switch self {
        case .welcome:
            return "Close your eyes and take a deep breath. We're going to create a peaceful sanctuary in your mind."
        case .breathe:
            return "Breathe slowly and deeply. With each breath, let tension leave your body."
        case .visualize:
            return "Imagine a place where you feel completely safe and calm. It could be real or imagined—a beach, forest, cozy room, or anywhere peaceful."
        case .details:
            return "Add details to your space. Notice the colors, textures, sounds, and scents. Make it vivid and personal."
        case .anchor:
            return "Feel the peace of this place. Notice how your body relaxes here. This feeling is always available to you."
        case .complete:
            return "Take a mental snapshot of this space. You can return here anytime by closing your eyes and breathing deeply."
        }
    }

    var icon: String {
        switch self {
        case .welcome: return "hand.wave.fill"
        case .breathe: return "wind"
        case .visualize: return "sparkles"
        case .details: return "paintpalette.fill"
        case .anchor: return "anchor.fill"
        case .complete: return "house.fill"
        }
    }

    var color: Color {
        switch self {
        case .welcome: return .blue
        case .breathe: return .teal
        case .visualize: return .purple
        case .details: return .pink
        case .anchor: return .indigo
        case .complete: return .purple
        }
    }

    var next: SafeSpaceStep? {
        let all = SafeSpaceStep.allCases
        guard let idx = all.firstIndex(of: self), idx + 1 < all.count else { return nil }
        return all[idx + 1]
    }
}
