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
        VStack(spacing: 24) {
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
        .padding(20)
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
        VStack(spacing: 8) {
            Text("Step \(stepNumber) of \(totalSteps)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            Text(step.typeDescription)
                .font(.title2)
                .fontWeight(.bold)
        }
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        VStack(spacing: 16) {
            // Step prompt
            Text(step.prompt)
                .font(.body)
                .multilineTextAlignment(.center)
                .padding()

            // Instructions (if any)
            if let instructions = step.instructions {
                Text(instructions)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
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
        VStack(spacing: 16) {
            if let remaining = remainingSeconds {
                Text(formatTime(remaining))
                    .font(.system(size: 48, weight: .light, design: .rounded))
                    .monospacedDigit()

                HStack(spacing: 24) {
                    Button {
                        startTimer()
                    } label: {
                        Label("Start", systemImage: "play.fill")
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)

                    Button {
                        remainingSeconds = step.durationSeconds
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
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
                .padding()
                .background(Color.pink)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.top, 20)
    }

    // MARK: - Complete State

    private var completeState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Step Complete!")
                .font(.headline)

            Text("Tap Continue to proceed")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.green.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
                .stroke(Color.pink.opacity(0.2), lineWidth: 4)
                .frame(width: 180, height: 180)

            // Animated inner circle
            Circle()
                .fill(Color.pink.opacity(0.6))
                .frame(width: 100 * scale, height: 100 * scale)

            // Text overlay
            VStack {
                Text(phaseText)
                    .font(.headline)
                    .foregroundStyle(.white)

                if animationCompleted {
                    Text("Breathe naturally")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
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
        withAnimation(.easeInOut(duration: inhaleDuration)) {
            phase = .inhale
            scale = inhaleScale
        }

        withAnimation(.easeInOut(duration: holdInhaleDuration).delay(inhaleDuration)) {
            phase = .holdAfterInhale
        }

        withAnimation(.easeInOut(duration: exhaleDuration).delay(inhaleDuration + holdInhaleDuration)) {
            phase = .exhale
            scale = exhaleScale
        }

        withAnimation(.easeInOut(duration: holdExhaleDuration).delay(inhaleDuration + holdInhaleDuration + exhaleDuration)) {
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
