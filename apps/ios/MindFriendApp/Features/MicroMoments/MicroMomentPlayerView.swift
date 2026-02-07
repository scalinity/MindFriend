import SwiftUI

/// Player view for template-based micro-moment exercises
struct MicroMomentPlayerView: View {
    let template: MicroMomentTemplate
    let onComplete: (MicroCompletionData) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0
    @State private var phase: PlayerPhase = .ready
    @State private var circleScale: CGFloat = 0.5
    @State private var elapsedSeconds = 0
    @State private var startTime: Date?
    @State private var showCompletionSheet = false
    @State private var feltHelpful: Bool?
    @State private var timer: Timer?

    enum PlayerPhase {
        case ready, playing, paused, complete
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [template.type.color.opacity(0.1), Color(.systemBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 32) {
                    // Animation area
                    animationView
                        .frame(height: 250)

                    // Current instruction
                    if phase == .playing || phase == .paused {
                        instructionView
                    }

                    // Progress
                    progressView

                    Spacer()

                    // Controls
                    controlsView
                }
                .padding()
            }
            .navigationTitle(template.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        stopTimer()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showCompletionSheet) {
                completionSheet
            }
            .onDisappear {
                stopTimer()
            }
        }
    }

    // MARK: - Animation View

    @ViewBuilder
    private var animationView: some View {
        switch template.animationType {
        case .breathingCircle, .none:
            breathingCircleAnimation
        case .bodyScan:
            bodyScanAnimation
        case .countdown:
            countdownAnimation
        case .pulse:
            pulseAnimation
        case .wave:
            waveAnimation
        }
    }

    private var breathingCircleAnimation: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [template.type.color.opacity(0.4), template.type.color.opacity(0.1)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 120
                    )
                )
                .frame(width: 240, height: 240)
                .scaleEffect(circleScale)

            Circle()
                .stroke(template.type.color.opacity(0.5), lineWidth: 2)
                .frame(width: 240, height: 240)
                .scaleEffect(circleScale)

            Image(systemName: template.type.icon)
                .font(.system(size: 40))
                .foregroundStyle(template.type.color)
        }
        .accessibilityLabel("Breathing animation")
    }

    private var bodyScanAnimation: some View {
        VStack {
            Image(systemName: "figure.stand")
                .font(.system(size: 100))
                .foregroundStyle(
                    LinearGradient(
                        colors: [template.type.color, template.type.color.opacity(0.3)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .accessibilityLabel("Body scan visualization")
    }

    private var countdownAnimation: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                .frame(width: 180, height: 180)

            Circle()
                .trim(from: 0, to: progressFraction)
                .stroke(template.type.color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .frame(width: 180, height: 180)
                .rotationEffect(.degrees(-90))

            Text("\(remainingSeconds)")
                .font(.system(size: 60, weight: .light, design: .rounded))
                .foregroundStyle(template.type.color)
        }
        .accessibilityLabel("\(remainingSeconds) seconds remaining")
    }

    private var pulseAnimation: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(template.type.color.opacity(0.3 - Double(index) * 0.1), lineWidth: 2)
                    .frame(width: 120 + CGFloat(index) * 40, height: 120 + CGFloat(index) * 40)
                    .scaleEffect(phase == .playing ? 1.1 : 1.0)
                    .animation(
                        .easeInOut(duration: 1.5)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.3),
                        value: phase
                    )
            }

            Image(systemName: template.type.icon)
                .font(.system(size: 40))
                .foregroundStyle(template.type.color)
        }
        .accessibilityLabel("Pulse animation")
    }

    private var waveAnimation: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { index in
                WaveShape(
                    amplitude: 20 - CGFloat(index) * 3,
                    frequency: 2,
                    phase: phase == .playing ? Double(index) * 0.5 : 0
                )
                .stroke(template.type.color.opacity(0.6 - Double(index) * 0.1), lineWidth: 2)
                .frame(height: 60)
                .offset(y: CGFloat(index) * 15 - 30)
            }
        }
        .frame(width: 200)
        .accessibilityLabel("Wave animation")
    }

    // MARK: - Instruction View

    private var instructionView: some View {
        VStack(spacing: 12) {
            if currentStep < template.instructions.count {
                let instruction = template.instructions[currentStep]

                Text(instruction.text)
                    .font(.title3)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .transition(.opacity.combined(with: .scale))
                    .id(instruction.id)

                if let action = instruction.action {
                    Label(action.rawValue.capitalized, systemImage: iconForAction(action))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal)
        .animation(.easeInOut, value: currentStep)
    }

    private func iconForAction(_ action: InstructionAction) -> String {
        switch action {
        case .inhale: return "arrow.down"
        case .exhale: return "arrow.up"
        case .hold: return "pause"
        case .observe: return "eye"
        case .move: return "figure.walk"
        case .speak: return "mic"
        case .tap: return "hand.tap"
        }
    }

    // MARK: - Progress View

    private var progressView: some View {
        VStack(spacing: 8) {
            // Step indicators
            HStack(spacing: 4) {
                ForEach(0..<template.instructions.count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index <= currentStep ? template.type.color : Color.gray.opacity(0.3))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal)

            // Time
            HStack {
                Text(formatTime(elapsedSeconds))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Spacer()

                Text(formatTime(template.durationSeconds))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal)
        }
        .accessibilityLabel("Step \(currentStep + 1) of \(template.instructions.count)")
    }

    private var progressFraction: Double {
        guard template.durationSeconds > 0 else { return 0 }
        return Double(elapsedSeconds) / Double(template.durationSeconds)
    }

    private var remainingSeconds: Int {
        max(0, template.durationSeconds - elapsedSeconds)
    }

    private func formatTime(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }

    // MARK: - Controls View

    private var controlsView: some View {
        HStack(spacing: 40) {
            if phase == .playing {
                Button {
                    pauseExercise()
                } label: {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(template.type.color)
                }
                .accessibilityLabel("Pause")
            } else {
                Button {
                    if phase == .ready {
                        startExercise()
                    } else if phase == .paused {
                        resumeExercise()
                    }
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(template.type.color)
                }
                .accessibilityLabel(phase == .ready ? "Start" : "Resume")
            }
        }
        .padding(.bottom, 20)
    }

    // MARK: - Completion Sheet

    private var completionSheet: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("Well done!")
                .font(.title)
                .fontWeight(.bold)

            Text("You completed \(template.title)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Feedback question
            VStack(spacing: 12) {
                Text("Did this help?")
                    .font(.headline)

                HStack(spacing: 20) {
                    Button {
                        feltHelpful = true
                        saveAndDismiss()
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "hand.thumbsup.fill")
                                .font(.title)
                            Text("Yes")
                                .font(.caption)
                        }
                        .foregroundStyle(feltHelpful == true ? .white : template.type.color)
                        .frame(width: 80, height: 80)
                        .background(feltHelpful == true ? template.type.color : Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Yes, this helped")

                    Button {
                        feltHelpful = false
                        saveAndDismiss()
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "hand.thumbsdown.fill")
                                .font(.title)
                            Text("Not really")
                                .font(.caption)
                        }
                        .foregroundStyle(feltHelpful == false ? .white : .gray)
                        .frame(width: 80, height: 80)
                        .background(feltHelpful == false ? Color.gray : Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("No, this didn't help")
                }
            }

            Button("Skip") {
                saveAndDismiss()
            }
            .foregroundStyle(.secondary)
            .padding(.top)
        }
        .padding()
        .presentationDetents([.medium])
    }

    // MARK: - Exercise Control

    private func startExercise() {
        phase = .playing
        startTime = Date()
        startTimer()
        triggerHaptic(.medium)

        // Start breathing animation if applicable
        if template.animationType == .breathingCircle || template.animationType == nil {
            startBreathingAnimation()
        }
    }

    private func pauseExercise() {
        phase = .paused
        timer?.invalidate()
        timer = nil
        triggerHaptic(.light)
    }

    private func resumeExercise() {
        phase = .playing
        startTimer()
        triggerHaptic(.medium)

        if template.animationType == .breathingCircle || template.animationType == nil {
            startBreathingAnimation()
        }
    }

    private func completeExercise() {
        phase = .complete
        stopTimer()
        triggerHaptic(.heavy)
        showCompletionSheet = true
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            elapsedSeconds += 1

            // Update current step based on instruction durations
            updateCurrentStep()

            // Check if exercise is complete
            if elapsedSeconds >= template.durationSeconds {
                completeExercise()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateCurrentStep() {
        var accumulated = 0
        for (index, instruction) in template.instructions.enumerated() {
            accumulated += instruction.durationSeconds
            if elapsedSeconds < accumulated {
                if currentStep != index {
                    currentStep = index
                    triggerHaptic(.light)
                    // Sync breathing animation with step change
                    if template.animationType == .breathingCircle || template.animationType == nil {
                        animateBreathingForCurrentStep()
                    }
                }
                return
            }
        }
    }

    private func startBreathingAnimation() {
        guard let _ = template.instructions.first else { return }

        // Animate circle based on instruction action
        animateBreathingForCurrentStep()
    }

    private func animateBreathingForCurrentStep() {
        guard currentStep < template.instructions.count else { return }
        let instruction = template.instructions[currentStep]

        let targetScale: CGFloat = instruction.action == .inhale ? 1.0 : 0.5
        let duration = Double(instruction.durationSeconds)

        withAnimation(.easeInOut(duration: duration)) {
            circleScale = targetScale
        }
    }

    private func saveAndDismiss() {
        let endTime = Date()
        let completion = MicroCompletionData(
            templateId: template.id,
            triggerSource: .manual,
            context: nil,
            startedAt: startTime ?? endTime,
            completedAt: endTime,
            durationActualSeconds: elapsedSeconds,
            feltHelpful: feltHelpful
        )
        onComplete(completion)
        dismiss()
    }

    private func triggerHaptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.impactOccurred()
    }
}

// MARK: - Wave Shape

struct WaveShape: Shape {
    var amplitude: CGFloat
    var frequency: CGFloat
    var phase: Double

    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY

        path.move(to: CGPoint(x: 0, y: midY))

        for x in stride(from: 0, to: rect.width, by: 1) {
            let relativeX = x / rect.width
            let sine = sin(relativeX * frequency * .pi * 2 + phase)
            let y = midY + amplitude * sine
            path.addLine(to: CGPoint(x: x, y: y))
        }

        return path
    }
}

// MARK: - Preview

#Preview {
    MicroMomentPlayerView(
        template: MicroMomentTemplate(
            id: "preview",
            name: "Preview Exercise",
            slug: "preview",
            type: .breathing,
            title: "Box Breathing",
            description: "A calming breathing technique",
            durationSeconds: 60,
            instructions: [
                MicroInstruction(id: "1", step: 1, text: "Breathe in slowly", durationSeconds: 4, action: .inhale),
                MicroInstruction(id: "2", step: 2, text: "Hold your breath", durationSeconds: 4, action: .hold),
                MicroInstruction(id: "3", step: 3, text: "Breathe out slowly", durationSeconds: 4, action: .exhale),
                MicroInstruction(id: "4", step: 4, text: "Hold", durationSeconds: 4, action: .hold)
            ],
            animationType: .breathingCircle,
            audioUrl: nil,
            hapticPattern: nil,
            suggestedContexts: ["stress", "anxiety"],
            energyEffect: .calming,
            isPremium: false,
            isActive: true,
            sortOrder: 1,
            createdAt: "",
            updatedAt: ""
        )
    ) { _ in }
}
