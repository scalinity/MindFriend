import SwiftUI

/// Quick 15-second breathing exercise with haptic feedback
struct QuickBreathingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.supportRootEmbedded) private var supportEmbedded
    @Environment(\.dismiss) private var dismiss
    let onComplete: ((MicroCompletionData) -> Void)?

    @State private var phase: BreathPhase = .ready
    @State private var circleScale: CGFloat = 0.5
    @State private var breathCount = 0
    @State private var isActive = false
    @State private var startTime: Date?
    @State private var breathingTask: Task<Void, Never>?

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
        VStack(spacing: SupportTheme.Spacing.xl) {
            Spacer()

            // Breathing circle
            ZStack {
                Circle()
                    .fill(
                        SupportTheme.surface
                    )
                    .frame(width: 300, height: 300)
                    .scaleEffect(reduceMotion ? 1 : (circleScale))

                Circle()
                    .stroke(SupportTheme.accent.opacity(0.5), lineWidth: 2)
                    .frame(width: 300, height: 300)
                    .scaleEffect(reduceMotion ? 1 : (circleScale))

                VStack(spacing: SupportTheme.Spacing.xs) {
                    Text(phase.instruction)
                        .font(.title2)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.center)
                        .id(phase)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: phase)

                    if phase != .ready && phase != .complete {
                        Text("\(breathCount + 1) of \(totalBreaths)")
                            .font(.caption)
                            .foregroundStyle(SupportTheme.textSecondary)
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
                HStack(spacing: SupportTheme.Spacing.xs) {
                    ForEach(0..<totalBreaths, id: \.self) { index in
                        Circle()
                            .fill(index < breathCount ? SupportTheme.accent : SupportTheme.textSecondary.opacity(0.3))
                            .frame(width: 10, height: 10)
                    }
                }
                .accessibilityLabel("Breath \(breathCount) of \(totalBreaths)")
            }

            if !supportEmbedded {
                Button("Close") {
                    breathingTask?.cancel()
                    dismiss()
                }
                .buttonStyle(.supportSecondary)
                .padding(.horizontal, SupportTheme.Spacing.m)
                .padding(.bottom, SupportTheme.Spacing.xl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .supportScreen()
        .navigationTitle("Quick breathing")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            breathingTask?.cancel()
            breathingTask = nil
        }
    }

    private func startBreathing() {
        isActive = true
        breathCount = 0
        startTime = Date()

        // Cancel any existing task
        breathingTask?.cancel()

        // Start new breathing task
        breathingTask = Task {
            await performBreathCycleAsync()
        }
    }

    private func performBreathCycleAsync() async {
        while breathCount < totalBreaths {
            // Check for cancellation
            guard !Task.isCancelled else { return }

            // Inhale
            await MainActor.run {
                phase = .inhale
                triggerHaptic(.inhale)
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: inhaleDuration)) {
                    circleScale = 1.0
                }
            }

            // Wait for inhale duration
            do {
                try await Task.sleep(nanoseconds: UInt64(inhaleDuration * 1_000_000_000))
            } catch {
                return // Task was cancelled
            }

            // Check for cancellation
            guard !Task.isCancelled else { return }

            // Exhale
            await MainActor.run {
                phase = .exhale
                triggerHaptic(.exhale)
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: exhaleDuration)) {
                    circleScale = 0.5
                }
            }

            // Wait for exhale duration
            do {
                try await Task.sleep(nanoseconds: UInt64(exhaleDuration * 1_000_000_000))
            } catch {
                return // Task was cancelled
            }

            // Increment breath count
            await MainActor.run {
                breathCount += 1
            }
        }

        // Complete exercise if not cancelled
        if !Task.isCancelled {
            await completeExerciseAsync()
        }
    }

    private func completeExerciseAsync() async {
        await MainActor.run {
            phase = .complete
            triggerHaptic(.complete)
        }

        let endTime = Date()
        let duration = Int(endTime.timeIntervalSince(startTime ?? endTime))

        // Record completion if callback provided
        if let onComplete = onComplete {
            let completion = MicroCompletionData(
                templateId: quickBreathingTemplateId,
                triggerSource: .manual,
                context: nil,
                startedAt: startTime ?? endTime,
                completedAt: endTime,
                durationActualSeconds: duration,
                feltHelpful: nil
            )
            onComplete(completion)
        }

        // Wait before dismissing
        do {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                dismiss()
            }
        } catch {
            // Task was cancelled, don't dismiss
        }
    }

    /// Template ID for the quick breathing exercise - matches seed data
    private var quickBreathingTemplateId: String {
        // This ID should match the "3-breath-reset" template in the database
        // Using a computed property allows for future lookup if needed
        "3-breath-reset"
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
