// AdaptiveBreathingView.swift
// MindFriendApp
// Standalone adaptive breathing view with biofeedback

import SwiftUI

struct AdaptiveBreathingView: View {
    @StateObject private var viewModel: AdaptiveBreathingViewModel
    @Environment(\.dismiss) private var dismiss

    init(biofeedbackService: BiofeedbackService) {
        _viewModel = StateObject(wrappedValue: AdaptiveBreathingViewModel(
            biofeedbackService: biofeedbackService
        ))
    }

    var body: some View {
        ZStack {
            // Background
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                // Header
                headerSection

                // Biofeedback status
                if viewModel.isBiofeedbackEnabled {
                    biofeedbackStatusSection
                }

                Spacer()

                // Breathing visualization
                breathingSection

                Spacer()

                // Controls
                controlsSection
            }
            .padding()
        }
        .navigationTitle("Adaptive Breathing")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                biofeedbackToggle
            }
        }
        .task {
            if viewModel.isBiofeedbackEnabled {
                await viewModel.startBiofeedback()
            }
        }
        .onDisappear {
            viewModel.cleanup()
        }
        .sheet(isPresented: $viewModel.showSummary) {
            if let summary = viewModel.summary {
                SessionSummaryView(summary: summary) {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("Adaptive Breathing")
                .font(.title2)
                .fontWeight(.semibold)

            Text(viewModel.isBiofeedbackEnabled
                ? "Pace adapts to your heart rate"
                : "Follow the guided breathing pattern")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Biofeedback Toggle

    private var biofeedbackToggle: some View {
        Toggle(isOn: $viewModel.isBiofeedbackEnabled) {
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                Text("Biofeedback")
            }
            .font(.caption)
        }
        .toggleStyle(.button)
        .tint(viewModel.isBiofeedbackEnabled ? .red : .secondary)
    }

    // MARK: - Biofeedback Status

    private var biofeedbackStatusSection: some View {
        HStack(spacing: 20) {
            // Heart Rate
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                    if let hr = viewModel.currentHeartRate {
                        Text("\(Int(hr))")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    } else {
                        Text("--")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("BPM")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .frame(height: 40)

            // Stress Level
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.stressLevel.icon)
                        .foregroundStyle(viewModel.stressLevel.color)
                    Text(viewModel.stressLevel.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                Text("Stress")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .frame(height: 40)

            // Trend
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.trend.icon)
                        .foregroundStyle(viewModel.trend.color)
                    Text(viewModel.trend.rawValue.capitalized)
                        .font(.subheadline)
                }
                Text("Trend")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Breathing Section

    private var breathingSection: some View {
        VStack(spacing: 24) {
            // Current pattern display
            Text(viewModel.currentPattern.displayName + " Pattern")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1))
                .clipShape(Capsule())

            // Breathing circle
            ZStack {
                // Outer guide ring
                Circle()
                    .stroke(viewModel.phaseColor.opacity(0.2), lineWidth: 4)
                    .frame(width: 240, height: 240)

                // Pulsing ring during active breathing
                if viewModel.isActive {
                    Circle()
                        .stroke(viewModel.phaseColor.opacity(0.4), lineWidth: 2)
                        .frame(width: 250, height: 250)
                        .scaleEffect(viewModel.pulseScale)
                        .animation(
                            .easeInOut(duration: 1).repeatForever(autoreverses: true),
                            value: viewModel.pulseScale
                        )
                }

                // Main breathing circle
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                viewModel.phaseColor.opacity(0.6),
                                viewModel.phaseColor.opacity(0.3)
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: viewModel.circleSize / 2
                        )
                    )
                    .frame(width: viewModel.circleSize, height: viewModel.circleSize)
                    .animation(
                        .easeInOut(duration: viewModel.phaseDuration),
                        value: viewModel.circleSize
                    )

                // Center content
                VStack(spacing: 8) {
                    Text(viewModel.instruction)
                        .font(.title3)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.center)

                    if viewModel.isActive {
                        Text("\(viewModel.secondsRemaining)")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(viewModel.phaseColor)

                        Text("Cycle \(viewModel.currentCycle)/\(viewModel.totalCycles)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Adaptation notification
            if let adaptation = viewModel.adaptationMessage {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars")
                    Text(adaptation)
                }
                .font(.caption)
                .foregroundStyle(.purple)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.purple.opacity(0.1))
                .clipShape(Capsule())
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    // MARK: - Controls Section

    private var controlsSection: some View {
        VStack(spacing: 16) {
            // Timer display
            Text(viewModel.formattedTime)
                .font(.title3)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            // Main action button
            if !viewModel.isActive {
                Button {
                    viewModel.start()
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            } else {
                HStack(spacing: 12) {
                    Button {
                        viewModel.togglePause()
                    } label: {
                        Label(
                            viewModel.isPaused ? "Resume" : "Pause",
                            systemImage: viewModel.isPaused ? "play.fill" : "pause.fill"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        viewModel.stop()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .foregroundStyle(.red)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
    }
}

// MARK: - View Model

@MainActor
final class AdaptiveBreathingViewModel: ObservableObject {
    // MARK: - Published State

    @Published var isBiofeedbackEnabled = true
    @Published var currentHeartRate: Double?
    @Published var stressLevel: BiofeedbackStressLevel = .unknown
    @Published var trend: BiofeedbackTrendDirection = .stable
    @Published var currentPattern: BiofeedbackBreathingPattern = .moderate
    @Published var adaptationMessage: String?
    @Published var showSummary = false
    @Published var summary: BiofeedbackSummary?

    // Breathing state
    @Published var isActive = false
    @Published var isPaused = false
    @Published var instruction = "Ready to begin"
    @Published var secondsRemaining = 4
    @Published var currentCycle = 1
    @Published var circleSize: CGFloat = 80
    @Published var phaseColor: Color = .blue
    @Published var phaseDuration: Double = 1.0
    @Published var pulseScale: CGFloat = 1.0

    let totalCycles = 4
    var formattedTime: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Private State

    private let biofeedbackService: BiofeedbackService
    private var heartRateMonitor: HeartRateMonitor?
    private var adaptationEngine: AdaptationEngine?
    private var session: BiofeedbackSession?
    private var breathingTimer: Timer?
    private var elapsedTimer: Timer?
    private var elapsedSeconds = 0
    private var currentPhase: Phase = .ready

    private let minSize: CGFloat = 60
    private let maxSize: CGFloat = 180

    enum Phase {
        case ready, inhale, hold, exhale, pause, complete
    }

    // MARK: - Init

    init(biofeedbackService: BiofeedbackService) {
        self.biofeedbackService = biofeedbackService
    }

    // MARK: - Lifecycle

    func startBiofeedback() async {
        heartRateMonitor = HeartRateMonitor()
        adaptationEngine = AdaptationEngine(
            baseline: biofeedbackService.baseline,
            mode: .auto
        )

        do {
            session = try await biofeedbackService.startSession(adaptationMode: .auto)

            heartRateMonitor?.onHeartRateUpdate = { [weak self] hr, _ in
                Task { @MainActor in
                    self?.handleHeartRate(hr)
                }
            }

            try await heartRateMonitor?.startMonitoring()
        } catch {
            // Don't log error details - may contain PHI
            print("Failed to start biofeedback")
            isBiofeedbackEnabled = false
        }
    }

    func cleanup() {
        heartRateMonitor?.stopMonitoring()
        breathingTimer?.invalidate()
        elapsedTimer?.invalidate()

        if let sessionId = session?.id {
            Task {
                _ = try? await biofeedbackService.completeSession(sessionId: sessionId)
            }
        }
    }

    // MARK: - Heart Rate Processing

    private func handleHeartRate(_ hr: Double) {
        currentHeartRate = hr

        guard let engine = adaptationEngine else { return }

        let reading = LiveBiometricData(heartRate: hr, hrvRMSSD: nil, timestamp: Date())
        let result = engine.processReading(reading)

        stressLevel = engine.currentStressLevel
        trend = engine.currentTrend

        if result.adapted {
            currentPattern = result.parameters.breathingPattern
            showAdaptationMessage(result.changes.first?.description)
        }

        // Record reading
        if let sessionId = session?.id {
            Task {
                try? await biofeedbackService.recordReading(sessionId: sessionId, heartRate: hr)
            }
        }
    }

    private func showAdaptationMessage(_ message: String?) {
        guard let message = message else { return }

        withAnimation {
            adaptationMessage = message
        }

        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            withAnimation {
                adaptationMessage = nil
            }
        }
    }

    // MARK: - Breathing Control

    func start() {
        isActive = true
        isPaused = false
        currentCycle = 1
        elapsedSeconds = 0
        pulseScale = 1.1
        startElapsedTimer()
        startInhale()
    }

    func togglePause() {
        if isPaused {
            isPaused = false
            startTimer()
        } else {
            isPaused = true
            breathingTimer?.invalidate()
        }
    }

    func stop() {
        isActive = false
        isPaused = false
        breathingTimer?.invalidate()
        elapsedTimer?.invalidate()
        currentPhase = .ready
        instruction = "Ready to begin"
        circleSize = minSize
        phaseColor = .blue
        pulseScale = 1.0

        // End session and show summary
        if let sessionId = session?.id {
            Task {
                _ = try? await biofeedbackService.completeSession(sessionId: sessionId)
                summary = try? await biofeedbackService.fetchSummary(sessionId: sessionId)
                if summary != nil {
                    showSummary = true
                }
            }
        }
    }

    // MARK: - Phase Management

    private func startInhale() {
        currentPhase = .inhale
        instruction = "Breathe In"
        secondsRemaining = Int(currentPattern.inhale)
        phaseDuration = currentPattern.inhale
        circleSize = maxSize
        phaseColor = .blue
        startTimer()
    }

    private func startHold() {
        currentPhase = .hold
        instruction = "Hold"
        secondsRemaining = Int(currentPattern.hold)
        phaseDuration = currentPattern.hold
        phaseColor = .purple
    }

    private func startExhale() {
        currentPhase = .exhale
        instruction = "Breathe Out"
        secondsRemaining = Int(currentPattern.exhale)
        phaseDuration = currentPattern.exhale
        circleSize = minSize
        phaseColor = .teal
    }

    private func startPause() {
        currentPhase = .pause
        instruction = "Rest"
        secondsRemaining = Int(currentPattern.pause)
        phaseDuration = currentPattern.pause
        phaseColor = .gray
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
        instruction = "Well done!"
        circleSize = maxSize
        phaseColor = .green
        pulseScale = 1.0
        breathingTimer?.invalidate()
        elapsedTimer?.invalidate()

        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            stop()
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

        secondsRemaining -= 1

        if secondsRemaining <= 0 {
            switch currentPhase {
            case .inhale: startHold()
            case .hold: startExhale()
            case .exhale: startPause()
            case .pause: completeCycle()
            default: break
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
}
