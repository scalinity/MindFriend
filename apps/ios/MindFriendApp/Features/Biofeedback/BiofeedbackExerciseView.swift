// BiofeedbackExerciseView.swift
// MindFriendApp
// Exercise view with biofeedback overlay

import SwiftUI

struct BiofeedbackExerciseView: View {
    @StateObject private var viewModel: BiofeedbackExerciseViewModel
    @Environment(\.dismiss) private var dismiss

    init(
        biofeedbackService: BiofeedbackService,
        exerciseSessionId: UUID? = nil,
        adaptationMode: AdaptationMode = .auto
    ) {
        _viewModel = StateObject(wrappedValue: BiofeedbackExerciseViewModel(
            biofeedbackService: biofeedbackService,
            exerciseSessionId: exerciseSessionId,
            adaptationMode: adaptationMode
        ))
    }

    var body: some View {
        ZStack {
            // Background gradient based on stress level
            backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Header with heart rate
                headerView

                Spacer()

                // Main breathing visualization
                breathingVisualization

                Spacer()

                // Bottom controls
                controlsView
            }
            .padding()
        }
        .navigationBarHidden(true)
        .task {
            await viewModel.startSession()
        }
        .onDisappear {
            Task {
                await viewModel.endSession()
            }
        }
        .alert("Extend Session?", isPresented: $viewModel.showExtensionPrompt) {
            Button("Continue") {
                Task {
                    await viewModel.extendSession()
                }
            }
            Button("Finish", role: .cancel) {
                Task {
                    await viewModel.endSession()
                    dismiss()
                }
            }
        } message: {
            Text(viewModel.extensionReason ?? "Would you like to continue for a bit longer?")
        }
        .sheet(isPresented: $viewModel.showSummary) {
            if let summary = viewModel.sessionSummary {
                SessionSummaryView(summary: summary) {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Background Gradient

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                viewModel.stressLevel.color.opacity(0.3),
                Color(uiColor: .systemBackground)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .animation(.easeInOut(duration: 1.0), value: viewModel.stressLevel)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            // Close button
            Button {
                Task {
                    await viewModel.endSession()
                    dismiss()
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Heart rate display
            if viewModel.isMonitoring {
                heartRateDisplay
            } else {
                watchNotConnectedBadge
            }

            Spacer()

            // Timer
            timerDisplay
        }
    }

    private var heartRateDisplay: some View {
        HStack(spacing: 8) {
            Image(systemName: "heart.fill")
                .foregroundStyle(.red)
                .symbolEffect(.pulse, options: .repeating)

            if let hr = viewModel.currentHeartRate {
                Text("\(Int(hr))")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .monospacedDigit()

                // Trend indicator
                Image(systemName: viewModel.trend.icon)
                    .foregroundStyle(viewModel.trend.color)
                    .font(.caption)
            } else {
                Text("--")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }

            Text("BPM")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    private var watchNotConnectedBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "applewatch.slash")
            Text("No Watch")
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }

    private var timerDisplay: some View {
        Text(viewModel.formattedElapsedTime)
            .font(.title3)
            .fontWeight(.medium)
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }

    // MARK: - Breathing Visualization

    private var breathingVisualization: some View {
        VStack(spacing: 24) {
            // Stress level badge
            StressLevelBadge(level: viewModel.stressLevel)

            // Breathing circle
            ZStack {
                // Outer ring
                Circle()
                    .stroke(
                        viewModel.breathingPhaseColor.opacity(0.3),
                        lineWidth: 8
                    )
                    .frame(width: 220, height: 220)

                // Animated breathing circle
                Circle()
                    .fill(viewModel.breathingPhaseColor.opacity(0.4))
                    .frame(
                        width: viewModel.breathingCircleSize,
                        height: viewModel.breathingCircleSize
                    )
                    .animation(
                        .easeInOut(duration: viewModel.currentPhaseDuration),
                        value: viewModel.breathingCircleSize
                    )

                // Phase instruction
                VStack(spacing: 8) {
                    Text(viewModel.breathingInstruction)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("\(viewModel.phaseSecondsRemaining)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .monospacedDigit()

                    if viewModel.isActive {
                        Text("Cycle \(viewModel.currentCycle)/\(viewModel.totalCycles)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Adaptation indicator
            if let adaptation = viewModel.lastAdaptation {
                adaptationIndicator(adaptation)
            }
        }
    }

    private func adaptationIndicator(_ adaptation: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "wand.and.stars")
            Text(adaptation)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .transition(.opacity.combined(with: .scale))
    }

    // MARK: - Controls

    private var controlsView: some View {
        VStack(spacing: 16) {
            if !viewModel.isActive {
                Button {
                    viewModel.startBreathing()
                } label: {
                    Text("Start")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            } else {
                Button {
                    viewModel.pauseBreathing()
                } label: {
                    Text(viewModel.isPaused ? "Resume" : "Pause")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
}

// MARK: - Stress Level Badge

struct StressLevelBadge: View {
    let level: BiofeedbackStressLevel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: level.icon)
            Text(level.displayName)
        }
        .font(.subheadline)
        .fontWeight(.medium)
        .foregroundStyle(level.color)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(level.color.opacity(0.15))
        .clipShape(Capsule())
    }
}

// MARK: - View Model

@MainActor
final class BiofeedbackExerciseViewModel: ObservableObject {
    // MARK: - Published State

    @Published var currentHeartRate: Double?
    @Published var stressLevel: BiofeedbackStressLevel = .unknown
    @Published var trend: BiofeedbackTrendDirection = .stable
    @Published var isMonitoring = false
    @Published var isActive = false
    @Published var isPaused = false
    @Published var showExtensionPrompt = false
    @Published var showSummary = false
    @Published var sessionSummary: BiofeedbackSummary?
    @Published var extensionReason: String?
    @Published var lastAdaptation: String?

    // Breathing state
    @Published var breathingInstruction = "Ready"
    @Published var breathingCircleSize: CGFloat = 80
    @Published var breathingPhaseColor: Color = .blue
    @Published var currentPhaseDuration: Double = 1.0
    @Published var phaseSecondsRemaining = 4
    @Published var currentCycle = 1
    let totalCycles = 4

    // Timer
    @Published var elapsedSeconds = 0
    var formattedElapsedTime: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Dependencies

    private let biofeedbackService: BiofeedbackService
    private let exerciseSessionId: UUID?
    private let adaptationMode: AdaptationMode

    private var heartRateMonitor: HeartRateMonitor?
    private var adaptationEngine: AdaptationEngine?
    private var session: BiofeedbackSession?
    private var breathingTimer: Timer?
    private var elapsedTimer: Timer?
    private var currentPhase: BreathingPhase = .ready
    private var parameters: AdaptationParameters = .default

    private let minCircleSize: CGFloat = 60
    private let maxCircleSize: CGFloat = 160

    enum BreathingPhase {
        case ready, inhale, hold, exhale, pause, complete
    }

    // MARK: - Initialization

    init(
        biofeedbackService: BiofeedbackService,
        exerciseSessionId: UUID?,
        adaptationMode: AdaptationMode
    ) {
        self.biofeedbackService = biofeedbackService
        self.exerciseSessionId = exerciseSessionId
        self.adaptationMode = adaptationMode
    }

    // MARK: - Session Lifecycle

    func startSession() async {
        // Initialize heart rate monitor
        heartRateMonitor = HeartRateMonitor()

        // Initialize adaptation engine
        adaptationEngine = AdaptationEngine(
            baseline: biofeedbackService.baseline,
            mode: adaptationMode
        )

        // Start biofeedback session
        do {
            session = try await biofeedbackService.startSession(
                exerciseSessionId: exerciseSessionId,
                adaptationMode: adaptationMode
            )
        } catch {
            // Don't log error details - may contain PHI
            print("Failed to start biofeedback session")
        }

        // Start heart rate monitoring
        do {
            heartRateMonitor?.onHeartRateUpdate = { [weak self] hr, _ in
                Task { @MainActor in
                    self?.processHeartRateUpdate(hr)
                }
            }
            try await heartRateMonitor?.startMonitoring()
            isMonitoring = true
        } catch {
            // Don't log error details - may contain PHI
            print("Failed to start heart rate monitoring")
            isMonitoring = false
        }

        // Start elapsed timer
        startElapsedTimer()
    }

    func endSession() async {
        // Stop monitoring
        heartRateMonitor?.stopMonitoring()
        heartRateMonitor = nil
        stopBreathing()
        stopElapsedTimer()

        // Complete session
        guard let sessionId = session?.id else { return }

        do {
            _ = try await biofeedbackService.completeSession(sessionId: sessionId)

            // Fetch summary
            sessionSummary = try await biofeedbackService.fetchSummary(sessionId: sessionId)
            showSummary = true
        } catch {
            // Don't log error details - may contain PHI
            print("Failed to complete session")
        }
    }

    func extendSession() async {
        guard let sessionId = session?.id else { return }

        do {
            try await biofeedbackService.extendSession(sessionId: sessionId, additionalSeconds: 180)
            showExtensionPrompt = false

            // Continue breathing
            if isActive {
                startBreathing()
            }
        } catch {
            // Don't log error details - may contain PHI
            print("Failed to extend session")
        }
    }

    // MARK: - Heart Rate Processing

    private func processHeartRateUpdate(_ heartRate: Double) {
        currentHeartRate = heartRate

        // Process through adaptation engine
        guard let engine = adaptationEngine else { return }

        let reading = LiveBiometricData(
            heartRate: heartRate,
            hrvRMSSD: nil,
            timestamp: Date()
        )

        let result = engine.processReading(reading)
        stressLevel = engine.currentStressLevel
        trend = engine.currentTrend

        if result.adapted {
            parameters = result.parameters
            updateBreathingParameters()

            // Show adaptation notification
            if let change = result.changes.first {
                withAnimation {
                    lastAdaptation = change.description
                }
                // Clear after delay
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    withAnimation {
                        lastAdaptation = nil
                    }
                }
            }
        }

        // Record reading
        if let sessionId = session?.id {
            Task {
                try? await biofeedbackService.recordReading(
                    sessionId: sessionId,
                    heartRate: heartRate
                )
            }
        }

        // Check for extension recommendation
        if isActive && elapsedSeconds >= 180 && elapsedSeconds % 60 == 0 {
            let recommendation = engine.checkShouldExtend(
                averageHR: heartRate,
                elapsedTime: TimeInterval(elapsedSeconds)
            )

            if case .recommended(_, let reason) = recommendation {
                extensionReason = reason
                showExtensionPrompt = true
            }
        }
    }

    // MARK: - Breathing Control

    func startBreathing() {
        isActive = true
        isPaused = false
        currentCycle = 1
        startInhale()
    }

    func pauseBreathing() {
        if isPaused {
            isPaused = false
            startTimer()
        } else {
            isPaused = true
            breathingTimer?.invalidate()
        }
    }

    func stopBreathing() {
        isActive = false
        isPaused = false
        breathingTimer?.invalidate()
        breathingTimer = nil
        currentPhase = .ready
        breathingInstruction = "Ready"
        breathingCircleSize = minCircleSize
    }

    private func updateBreathingParameters() {
        // This will affect the next breathing cycle
    }

    private func startInhale() {
        currentPhase = .inhale
        breathingInstruction = "Breathe In"
        phaseSecondsRemaining = Int(parameters.breathingInhaleSeconds)
        currentPhaseDuration = parameters.breathingInhaleSeconds
        breathingCircleSize = maxCircleSize
        breathingPhaseColor = .blue
        startTimer()
    }

    private func startHold() {
        currentPhase = .hold
        breathingInstruction = "Hold"
        phaseSecondsRemaining = Int(parameters.breathingHoldSeconds)
        currentPhaseDuration = parameters.breathingHoldSeconds
        breathingPhaseColor = .purple
    }

    private func startExhale() {
        currentPhase = .exhale
        breathingInstruction = "Breathe Out"
        phaseSecondsRemaining = Int(parameters.breathingExhaleSeconds)
        currentPhaseDuration = parameters.breathingExhaleSeconds
        breathingCircleSize = minCircleSize
        breathingPhaseColor = .teal
    }

    private func startPause() {
        currentPhase = .pause
        breathingInstruction = "Rest"
        phaseSecondsRemaining = Int(parameters.breathingPauseSeconds)
        currentPhaseDuration = parameters.breathingPauseSeconds
        breathingPhaseColor = .gray
    }

    private func completeCycle() {
        if currentCycle >= totalCycles {
            completeSession()
        } else {
            currentCycle += 1
            startInhale()
        }
    }

    private func completeSession() {
        currentPhase = .complete
        breathingInstruction = "Complete!"
        breathingCircleSize = maxCircleSize
        breathingPhaseColor = .green

        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await endSession()
        }
    }

    // MARK: - Timers

    private func startTimer() {
        breathingTimer?.invalidate()
        breathingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func tick() {
        guard !isPaused else { return }

        phaseSecondsRemaining -= 1

        if phaseSecondsRemaining <= 0 {
            switch currentPhase {
            case .inhale:
                startHold()
            case .hold:
                startExhale()
            case .exhale:
                startPause()
            case .pause:
                completeCycle()
            default:
                break
            }
        }
    }

    private func startElapsedTimer() {
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.elapsedSeconds += 1
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }
}
