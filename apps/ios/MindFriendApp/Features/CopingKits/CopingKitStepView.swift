import SwiftUI

// MARK: - Coping Kit Step View

struct CopingKitStepView: View {
    let step: CopingKitStep
    let stepNumber: Int
    let totalSteps: Int

    @State private var timer: Timer?
    @State private var remainingSeconds: Int?
    @State private var isTimerRunning = false
    @State private var isComplete = false

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.l) {
            // Step header
            stepHeader

            // Step content
            stepContent

            // Timer (if applicable)
            if step.durationSeconds != nil && !isTimerRunning && !isComplete {
                timerView
            }

            // Complete button
            if !isComplete {
                completeButton
            } else {
                completeState
            }
        }
        .padding(SupportTheme.Spacing.m)
        .onAppear {
            if let duration = step.durationSeconds {
                remainingSeconds = duration
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    // MARK: - Step Header

    private var stepHeader: some View {
        VStack(spacing: SupportTheme.Spacing.xs) {
            Text("Step \(stepNumber) of \(totalSteps)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(SupportTheme.textSecondary)

            Text(step.typeDescription)
                .font(.title2)
                .fontWeight(.bold)
        }
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            // Step prompt
            Text(step.prompt)
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(SupportTheme.Spacing.m)

            // Instructions (if any)
            if let instructions = step.instructions {
                Text(instructions)
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SupportTheme.Spacing.m)
            }

            // Breathing pattern visualization
            if let pattern = step.breathingPattern {
                BreathingVisualization(pattern: pattern)
                    .frame(height: 200)
            }
        }
    }

    // MARK: - Timer View

    private var timerView: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            if let remaining = remainingSeconds {
                Text(formatTime(remaining))
                    .font(.system(.largeTitle, design: .rounded).weight(.light))
                    .monospacedDigit()

                HStack(spacing: SupportTheme.Spacing.l) {
                    Button {
                        startTimer()
                    } label: {
                        Label("Start", systemImage: "play.fill")
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.supportPrimary)
                    .tint(SupportTheme.accent)

                    Button {
                        remainingSeconds = step.durationSeconds
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.supportSecondary)
                }
            }
        }
        .padding(SupportTheme.Spacing.m)
    }

    // MARK: - Complete Button

    private var completeButton: some View {
        Button {
            isComplete = true
            timer?.invalidate()
        } label: {
            Text("Done")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.supportPrimary)
        .padding(.top, SupportTheme.Spacing.m)
    }

    // MARK: - Complete State

    private var completeState: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(.largeTitle))
                .foregroundStyle(SupportTheme.accent)

            Text("Step Complete!")
                .font(.headline)

            Text("Tap Continue to proceed")
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
        }
        .padding(SupportTheme.Spacing.m)
        .frame(maxWidth: .infinity)
        .background(SupportTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
    }

    // MARK: - Helpers

    private func startTimer() {
        guard let duration = step.durationSeconds else { return }
        remainingSeconds = duration
        isTimerRunning = true

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if let current = remainingSeconds, current > 0 {
                remainingSeconds = current - 1
            } else {
                timer?.invalidate()
                isTimerRunning = false
                isComplete = true
            }
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        if mins > 0 {
            return String(format: "%d:%02d", mins, secs)
        } else {
            return String(format: "%d", secs)
        }
    }
}

// MARK: - Breathing Visualization

struct BreathingVisualization: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let pattern: BreathingPattern

    @State private var phase: BreathingPhase = .inhale
    @State private var scale: CGFloat = 0.8
    @State private var animationCompleted = false

    enum BreathingPhase {
        case inhale
        case holdAfterInhale
        case exhale
        case holdAfterExhale
    }

    var body: some View {
        ZStack {
            // Outer circle
            Circle()
                .stroke(SupportTheme.accent.opacity(0.2), lineWidth: 4)
                .frame(width: 180, height: 180)

            // Animated inner circle
            Circle()
                .fill(SupportTheme.accent.opacity(0.6))
                .frame(width: reduceMotion ? 100 : 100 * scale, height: reduceMotion ? 100 : 100 * scale)

            // Text overlay
            VStack {
                Text(phaseText)
                    .font(.headline)
                    .id(phaseText)
                    .transition(.opacity)
                    .foregroundStyle(SupportTheme.textPrimary)

                if animationCompleted {
                    Text("Breathe naturally")
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textPrimary.opacity(0.8))
                }
            }
        }
        .onAppear {
            startAnimation()
        }
    }

    private var phaseText: String {
        switch phase {
        case .inhale: return "Inhale"
        case .holdAfterInhale: return "Hold"
        case .exhale: return "Exhale"
        case .holdAfterExhale: return "Hold"
        }
    }

    private func startAnimation() {
        let inhaleDuration = Double(pattern.inhaleSeconds)
        let holdInhaleDuration = Double(pattern.holdAfterInhaleSeconds)
        let exhaleDuration = Double(pattern.exhaleSeconds)
        let holdExhaleDuration = Double(pattern.holdAfterExhaleSeconds)

        let totalDuration = inhaleDuration + holdInhaleDuration + exhaleDuration + holdExhaleDuration

        // Calculate scale based on breath ratio
        let inhaleScale: CGFloat = 1.3
        let exhaleScale: CGFloat = 0.7

        // Create animation sequence
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: inhaleDuration)) {
            phase = .inhale
            scale = inhaleScale
        }

        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: holdInhaleDuration).delay(inhaleDuration)) {
            phase = .holdAfterInhale
        }

        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: exhaleDuration).delay(inhaleDuration + holdInhaleDuration)) {
            phase = .exhale
            scale = exhaleScale
        }

        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: holdExhaleDuration).delay(inhaleDuration + holdInhaleDuration + exhaleDuration)) {
            phase = .holdAfterExhale
        }

        // Loop animation
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration + 0.1) {
            animationCompleted = true
            // Optionally loop again or just show "breathe naturally"
        }
    }
}

// MARK: - Preview

#Preview {
    CopingKitStepView(
        step: CopingKitStep(
            type: .breathing,
            exerciseType: nil,
            prompt: "Inhale for 4 seconds, hold for 7, exhale for 8",
            durationSeconds: 60,
            durationCycles: 3,
            breathingPattern: BreathingPattern.calm478,
            instructions: "Repeat this pattern 3 times"
        ),
        stepNumber: 1,
        totalSteps: 3
    )
}
