import SwiftUI

/// Non-AR Nature Immersion fallback view
/// Guided nature visualization with ambient sounds
public struct NatureImmersionFallbackView: View {

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var exerciseService: ARExerciseService

    // MARK: - Properties

    let exercise: ARExercise

    // MARK: - State

    @State private var currentStep: NatureStep = .arrive
    @State private var timeRemaining: TimeInterval = 0
    @State private var isPaused: Bool = false
    @State private var showCompletion: Bool = false
    @State private var showExitConfirmation: Bool = false
    @State private var effectivenessRating: Int = 0
    @State private var sessionId: UUID?
    @State private var isExerciseEnded: Bool = false
    @State private var stepProgress: Double = 0
    @State private var leafOffset: CGFloat = 0
    @State private var leafOpacity: Double = 1.0

    // MARK: - Timer

    @State private var stepTimer: Timer?
    @State private var sessionTimer: Timer?
    @State private var animationTimer: Timer?

    // MARK: - Initialization

    public init(exercise: ARExercise) {
        self.exercise = exercise
        _timeRemaining = State(initialValue: TimeInterval(exercise.durationSeconds))
    }

    // MARK: - Body

    public var body: some View {
        ZStack {
            // Nature gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.2, green: 0.4, blue: 0.3),
                    Color(red: 0.15, green: 0.35, blue: 0.25),
                    Color(red: 0.1, green: 0.25, blue: 0.2)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Floating leaves animation
            floatingLeaves

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

    private var floatingLeaves: some View {
        GeometryReader { geo in
            ForEach(0..<5, id: \.self) { index in
                Image(systemName: "leaf.fill")
                    .font(.system(size: CGFloat(20 + index * 5)))
                    .foregroundStyle(.green.opacity(0.3))
                    .offset(
                        x: CGFloat(index * 80) + leafOffset * CGFloat(index % 2 == 0 ? 1 : -1),
                        y: geo.size.height * CGFloat(index) / 5 + leafOffset * 2
                    )
                    .opacity(leafOpacity)
            }
        }
    }

    private var topBar: some View {
        HStack {
            Text(formatTime(timeRemaining))
                .font(.title2.monospacedDigit())
                .foregroundStyle(.white)
                .accessibilityLabel("Time remaining: \(formatTime(timeRemaining))")

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
    }

    private var stepContent: some View {
        VStack(spacing: 24) {
            // Step icon
            ZStack {
                Circle()
                    .fill(.white.opacity(0.1))
                    .frame(width: 140, height: 140)

                Image(systemName: currentStep.icon)
                    .font(.system(size: 60))
                    .foregroundStyle(.white)
            }

            // Step title
            Text(currentStep.title)
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            // Instruction
            Text(currentStep.instruction)
                .font(.body)
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .fixedSize(horizontal: false, vertical: true)

            // Progress indicator
            ProgressView(value: stepProgress)
                .progressViewStyle(.linear)
                .frame(width: 200)
                .tint(.green)
                .padding(.top, 16)
        }
        .padding()
    }

    private var bottomBar: some View {
        HStack {
            // Step counter
            Text("Step \(currentStep.rawValue + 1)/\(NatureStep.allCases.count)")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.8))

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
            .accessibilityLabel(isPaused ? "Resume exercise" : "Pause exercise")
        }
        .padding()
        .background(.ultraThinMaterial.opacity(0.3))
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

                Text("Nature Connection")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("You've completed your nature immersion journey")
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
                        .background(.green)
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
        startLeafAnimation()
        Task {
            do {
                let newSessionId = try await exerciseService.startSession(exercise: exercise)
                sessionId = newSessionId
                startStepTimer()
                startSessionTimer()
            } catch {
                #if DEBUG
                print("Nature immersion session start failed")
                #endif
            }
        }
    }

    private func stopExercise() {
        stepTimer?.invalidate()
        stepTimer = nil
        sessionTimer?.invalidate()
        sessionTimer = nil
        animationTimer?.invalidate()
        animationTimer = nil
        exerciseService.stopGuidance()
    }

    private func startLeafAnimation() {
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.05)) {
                leafOffset = sin(Date().timeIntervalSince1970) * 20
                leafOpacity = 0.3 + abs(sin(Date().timeIntervalSince1970 * 0.5)) * 0.3
            }
        }
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .background, .inactive:
            if !isPaused && !isExerciseEnded {
                stepTimer?.invalidate()
                sessionTimer?.invalidate()
                animationTimer?.invalidate()
                exerciseService.recordInterruption()
            }
        case .active:
            if !isPaused && !isExerciseEnded && sessionId != nil {
                startStepTimer()
                startSessionTimer()
                startLeafAnimation()
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
            animationTimer?.invalidate()
            exerciseService.recordInterruption()
        } else {
            startStepTimer()
            startSessionTimer()
            startLeafAnimation()
        }
    }

    private func startStepTimer() {
        guard !isExerciseEnded else { return }
        stepProgress = 0

        let stepDuration = TimeInterval(exercise.durationSeconds) / TimeInterval(NatureStep.allCases.count)
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
        animationTimer?.invalidate()
        animationTimer = nil
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
                    completedSteps: NatureStep.allCases.count,
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

// MARK: - Nature Steps

private enum NatureStep: Int, CaseIterable {
    case arrive
    case ground
    case observe
    case listen
    case breathe
    case connect

    var title: String {
        switch self {
        case .arrive: return "Arrive"
        case .ground: return "Ground"
        case .observe: return "Observe"
        case .listen: return "Listen"
        case .breathe: return "Breathe"
        case .connect: return "Connect"
        }
    }

    var instruction: String {
        switch self {
        case .arrive:
            return "Close your eyes. Imagine stepping into a peaceful forest. Feel the soft earth beneath your feet."
        case .ground:
            return "Notice the ground supporting you. Feel the texture of the forest floor—leaves, moss, soft soil."
        case .observe:
            return "Open your mind's eye. See the sunlight filtering through leaves. Notice the shades of green all around you."
        case .listen:
            return "Listen to the forest. Birds singing, leaves rustling, perhaps a distant stream. Let these sounds wash over you."
        case .breathe:
            return "Breathe deeply. Inhale the fresh, clean forest air. Smell the earth, the trees, the life around you."
        case .connect:
            return "Feel yourself as part of nature. You belong here. This peace is always within you."
        }
    }

    var icon: String {
        switch self {
        case .arrive: return "figure.walk"
        case .ground: return "leaf.fill"
        case .observe: return "eye.fill"
        case .listen: return "ear.fill"
        case .breathe: return "wind"
        case .connect: return "heart.fill"
        }
    }

    var next: NatureStep? {
        let all = NatureStep.allCases
        guard let idx = all.firstIndex(of: self), idx + 1 < all.count else { return nil }
        return all[idx + 1]
    }
}
