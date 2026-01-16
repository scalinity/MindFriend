import SwiftUI

/// Quick 15-second breathing exercise with haptic feedback
struct QuickBreathingView: View {
    @Environment(\.dismiss) private var dismiss
    let onComplete: ((MicroCompletionData) -> Void)?

    @State private var phase: BreathPhase = .ready
    @State private var circleScale: CGFloat = 0.5
    @State private var breathCount = 0
    @State private var isActive = false
    @State private var startTime: Date?

    private let totalBreaths = 3
    private let inhaleDuration = 4.0
    private let exhaleDuration = 4.0

    init(onComplete: ((MicroCompletionData) -> Void)? = nil) {
        self.onComplete = onComplete
    }

    enum BreathPhase {
        case ready, inhale, exhale, complete

        var instruction: String {
            switch self {
            case .ready: return "Tap to begin"
            case .inhale: return "Breathe in..."
            case .exhale: return "Breathe out..."
            case .complete: return "Well done"
            }
        }

        var accessibilityAnnouncement: String {
            switch self {
            case .ready: return "Ready to begin breathing exercise. Tap the circle to start."
            case .inhale: return "Breathe in"
            case .exhale: return "Breathe out"
            case .complete: return "Exercise complete. Well done!"
            }
        }
    }

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // Breathing circle
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.blue.opacity(0.3), .blue.opacity(0.1)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 150
                        )
                    )
                    .frame(width: 300, height: 300)
                    .scaleEffect(circleScale)

                Circle()
                    .stroke(Color.blue.opacity(0.5), lineWidth: 2)
                    .frame(width: 300, height: 300)
                    .scaleEffect(circleScale)

                VStack(spacing: 8) {
                    Text(phase.instruction)
                        .font(.title2)
                        .fontWeight(.medium)

                    if phase != .ready && phase != .complete {
                        Text("\(breathCount + 1) of \(totalBreaths)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onTapGesture {
                if phase == .ready {
                    startBreathing()
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(phase.accessibilityAnnouncement)
            .accessibilityAddTraits(phase == .ready ? .isButton : [])

            Spacer()

            // Progress indicators
            if isActive {
                HStack(spacing: 8) {
                    ForEach(0..<totalBreaths, id: \.self) { index in
                        Circle()
                            .fill(index < breathCount ? Color.blue : Color.gray.opacity(0.3))
                            .frame(width: 10, height: 10)
                    }
                }
                .accessibilityLabel("Breath \(breathCount) of \(totalBreaths)")
            }

            // Close button
            Button("Close") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private func startBreathing() {
        isActive = true
        breathCount = 0
        startTime = Date()
        performBreathCycle()
    }

    private func performBreathCycle() {
        guard breathCount < totalBreaths else {
            completeExercise()
            return
        }

        // Inhale
        phase = .inhale
        triggerHaptic(.inhale)

        withAnimation(.easeInOut(duration: inhaleDuration)) {
            circleScale = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + inhaleDuration) {
            // Exhale
            phase = .exhale
            triggerHaptic(.exhale)

            withAnimation(.easeInOut(duration: exhaleDuration)) {
                circleScale = 0.5
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + exhaleDuration) {
                breathCount += 1
                performBreathCycle()
            }
        }
    }

    private func completeExercise() {
        phase = .complete
        triggerHaptic(.complete)

        let endTime = Date()
        let duration = Int(endTime.timeIntervalSince(startTime ?? endTime))

        // Record completion if callback provided
        if let onComplete = onComplete {
            // Use the "3-breath-reset" template ID - this matches seed data
            let completion = MicroCompletionData(
                templateId: "3-breath-reset",
                triggerSource: .manual,
                context: nil,
                startedAt: startTime ?? endTime,
                completedAt: endTime,
                durationActualSeconds: duration,
                feltHelpful: nil
            )
            onComplete(completion)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            dismiss()
        }
    }

    private func triggerHaptic(_ type: HapticType) {
        let generator: UIImpactFeedbackGenerator
        switch type {
        case .inhale:
            generator = UIImpactFeedbackGenerator(style: .medium)
        case .exhale:
            generator = UIImpactFeedbackGenerator(style: .light)
        case .complete:
            generator = UIImpactFeedbackGenerator(style: .heavy)
        }
        generator.impactOccurred()
    }

    enum HapticType {
        case inhale, exhale, complete
    }
}

// MARK: - Preview

#Preview {
    QuickBreathingView()
}
