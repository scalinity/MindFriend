import SwiftUI

/// Non-AR Breathing exercise fallback view
/// Used when device doesn't support AR or camera permission denied
public struct BreathingOrbFallbackView: View {

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var exerciseService: ARExerciseService

    // MARK: - Properties

    let exercise: ARExercise

    // MARK: - State

    @State private var currentPhase: ARBreathingPhase = .inhale
    @State private var cyclesCompleted: Int = 0
    @State private var totalCycles: Int = 0
    @State private var timeRemaining: TimeInterval = 0
    @State private var isPaused: Bool = false
    @State private var showCompletion: Bool = false
    @State private var showExitConfirmation: Bool = false
    @State private var effectivenessRating: Int = 0
    @State private var orbScale: CGFloat = 1.0
    @State private var orbOpacity: Double = 0.8
    @State private var phaseProgress: Double = 0
    @State private var sessionId: UUID?
    @State private var isExerciseEnded: Bool = false

    // MARK: - Timer

    @State private var phaseTimer: Timer?
    @State private var sessionTimer: Timer?
    @State private var phaseElapsedTime: TimeInterval = 0  // Track elapsed time as state
    @State private var timeRemainingAtPause: TimeInterval = 0  // Track time when paused

    // MARK: - Computed Properties

    private var breathPattern: BreathPattern {
        exercise.sceneConfig.breathPattern ?? BreathPattern()
    }

    private var currentPhaseDuration: Int {
        switch currentPhase {
        case .inhale: return breathPattern.inhale
        case .hold: return breathPattern.hold
        case .exhale: return breathPattern.exhale
        }
    }

    private var orbColor: Color {
        Color(UIColor(hex: exercise.sceneConfig.orbColor ?? "#6366F1") ?? .systemIndigo)
    }

    // MARK: - Initialization

    public init(exercise: ARExercise) {
        self.exercise = exercise
        let pattern = exercise.sceneConfig.breathPattern ?? BreathPattern()
        _totalCycles = State(initialValue: exercise.durationSeconds / pattern.cycleDuration)
        _timeRemaining = State(initialValue: TimeInterval(exercise.durationSeconds))
    }

    // MARK: - Body

    public var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [.black, Color(white: 0.15)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
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
                    .accessibilityHint("Double tap to exit and save progress")
                }
                .padding()

                Spacer()

                // Breathing orb
                ZStack {
                    // Glow effect
                    Circle()
                        .fill(orbColor.opacity(0.2))
                        .frame(width: 240, height: 240)
                        .scaleEffect(orbScale * 1.2)
                        .blur(radius: 30)

                    // Main orb
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [orbColor.opacity(0.9), orbColor.opacity(0.6)],
                                center: .center,
                                startRadius: 0,
                                endRadius: 100
                            )
                        )
                        .frame(width: 180, height: 180)
                        .scaleEffect(orbScale)
                        .opacity(orbOpacity)
                        .shadow(color: orbColor.opacity(0.5), radius: 20)
                }

                Spacer()

                // Phase instruction
                VStack(spacing: 16) {
                    Text(currentPhase.instruction)
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .accessibilityLabel("Current phase: \(currentPhase.instruction)")

                    // Phase progress bar
                    ProgressView(value: phaseProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 200)
                        .tint(phaseColor)
                        .accessibilityLabel("Phase progress: \(Int(phaseProgress * 100)) percent")
                }

                Spacer()

                // Bottom bar
                HStack {
                    // Voice toggle
                    Button {
                        if exerciseService.isSpeaking {
                            exerciseService.stopGuidance()
                        } else {
                            exerciseService.speakGuidance(currentPhase.instruction)
                        }
                    } label: {
                        Image(systemName: exerciseService.isSpeaking ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(exerciseService.isSpeaking ? "Stop voice guidance" : "Start voice guidance")

                    Spacer()

                    // Cycle counter
                    Text("Cycle \(cyclesCompleted + 1)/\(totalCycles)")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .accessibilityLabel("Cycle \(cyclesCompleted + 1) of \(totalCycles)")

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

    private var phaseColor: Color {
        switch currentPhase {
        case .inhale: return .blue
        case .hold: return .purple
        case .exhale: return .green
        }
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
                        .background(.blue)
                        .cornerRadius(12)
                }
            }
        }
    }

    private var completionView: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.green)

                Text("Great job!")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("You completed \(cyclesCompleted) breathing cycles")
                    .font(.headline)
                    .foregroundStyle(.secondary)

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
        Task {
            do {
                let newSessionId = try await exerciseService.startSession(exercise: exercise)
                sessionId = newSessionId
                startBreathingCycle()
                startSessionTimer()
                exerciseService.speakNextGuidance(for: exercise)
            } catch {
                // Log error without PHI exposure
                #if DEBUG
                print("AR session start failed")
                #endif
            }
        }
    }

    private func stopExercise() {
        phaseTimer?.invalidate()
        phaseTimer = nil
        sessionTimer?.invalidate()
        sessionTimer = nil
        exerciseService.stopGuidance()
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .background, .inactive:
            // Pause timers and save current time when app goes to background
            if !isPaused && !isExerciseEnded {
                timeRemainingAtPause = timeRemaining
                phaseTimer?.invalidate()
                phaseTimer = nil
                sessionTimer?.invalidate()
                sessionTimer = nil
                exerciseService.recordInterruption()
            }
        case .active:
            // Resume timers when app becomes active
            if !isPaused && !isExerciseEnded && sessionId != nil {
                timeRemaining = timeRemainingAtPause
                startBreathingCycle()
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
            phaseTimer?.invalidate()
            phaseTimer = nil
            sessionTimer?.invalidate()
            sessionTimer = nil
            exerciseService.recordInterruption()
        } else {
            timeRemaining = timeRemainingAtPause
            startBreathingCycle()
            startSessionTimer()
        }
    }

    private func startBreathingCycle() {
        guard !isExerciseEnded else { return }
        phaseProgress = 0
        phaseElapsedTime = 0  // Reset elapsed time at cycle start

        // Animate orb
        let targetScale: CGFloat = currentPhase == .exhale ? 1.0 : 1.8
        let duration = TimeInterval(currentPhaseDuration)

        withAnimation(.easeInOut(duration: duration)) {
            orbScale = targetScale
            orbOpacity = currentPhase == .hold ? 1.0 : 0.8
        }

        // Start phase timer
        let interval: TimeInterval = 0.1

        phaseTimer?.invalidate()
        phaseTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak exerciseService] timer in
            guard !self.isExerciseEnded else {
                timer.invalidate()
                return
            }
            
            self.phaseElapsedTime += interval
            self.phaseProgress = min(1.0, self.phaseElapsedTime / duration)

            if self.phaseElapsedTime >= duration {
                timer.invalidate()
                self.advancePhase()
            }
        }
    }

    private func advancePhase() {
        guard !isExerciseEnded else { return }
        
        let wasExhale = currentPhase == .exhale
        currentPhase = currentPhase.next

        if wasExhale {
            cyclesCompleted += 1
        }

        if cyclesCompleted >= totalCycles || timeRemaining <= 0 {
            endExercise(completed: true)
        } else {
            startBreathingCycle()
            exerciseService.speakGuidance(currentPhase.instruction)
        }
    }

    private func startSessionTimer() {
        guard !isExerciseEnded else { return }
        
        sessionTimer?.invalidate()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak exerciseService] timer in
            guard !self.isExerciseEnded else {
                timer.invalidate()
                return
            }
            
            if self.timeRemaining > 0 {
                self.timeRemaining -= 1
            } else {
                timer.invalidate()
                self.endExercise(completed: true)
            }
        }
    }

    private func endExercise(completed: Bool) {
        // Guard against race conditions - only end once
        guard !isExerciseEnded else { return }
        isExerciseEnded = true
        
        phaseTimer?.invalidate()
        phaseTimer = nil
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
        // Validate rating (1-5 range)
        let validatedRating: Int? = (1...5).contains(effectivenessRating) ? effectivenessRating : nil
        
        Task {
            // Use actual session ID, not exercise ID
            if let currentSessionId = sessionId {
                try? await exerciseService.completeSession(
                    sessionId: currentSessionId,
                    completedSteps: cyclesCompleted,
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
