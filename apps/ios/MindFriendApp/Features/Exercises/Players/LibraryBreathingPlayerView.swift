import SwiftUI

/// Immersive breathing exercise player with animated circle
struct LibraryBreathingPlayerView: View {
    @ObservedObject var viewModel: LibraryExercisePlayerViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Immersive gradient background
            ImmersiveBackground(area: viewModel.breathingPhase.area)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: viewModel.breathingPhase)

            VStack(spacing: SupportTheme.Spacing.xl) {
                Spacer()

                // Intro text (before starting)
                if !viewModel.isPlaying && viewModel.currentCycle == 1 {
                    if let intro = viewModel.breathingInstructions?.introText {
                        Text(intro)
                            .font(.body)
                            .foregroundStyle(SupportTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, SupportTheme.Spacing.xl)
                            .transition(reduceMotion ? .opacity : .opacity)
                    }
                }

                // Phase label
                PhaseLabel(
                    text: viewModel.breathingPhase.displayText,
                    color: SupportTheme.textPrimary
                )
                .opacity(viewModel.isPlaying ? 1 : 0.5)

                // Animated breathing circle
                if reduceMotion {
                    // Static circle for reduced motion
                    Circle()
                        .fill(viewModel.breathingPhase.color)
                        .frame(width: 200, height: 200)
                } else {
                    BreathingCircle(
                        scale: viewModel.breathingCircleScale,
                        phase: viewModel.breathingPhase
                    )
                    .frame(width: 250, height: 250)
                }

                // Timer
                TimerDisplay(seconds: viewModel.timeRemaining, style: .large)
                    .foregroundStyle(SupportTheme.textPrimary)

                // Cycle counter
                if let instructions = viewModel.breathingInstructions {
                    CycleCounter(
                        current: viewModel.currentCycle,
                        total: instructions.cycles
                    )
                    .foregroundStyle(SupportTheme.textSecondary)
                }

                Spacer()

                // Controls
                PlayerControls(
                    isPlaying: viewModel.isPlaying,
                    canReset: viewModel.isPlaying || viewModel.currentCycle > 1,
                    tint: viewModel.breathingPhase.area.palette.ink,
                    onPlayPause: {
                        if viewModel.isPlaying {
                            viewModel.pauseTimer()
                        } else {
                            viewModel.startTimer()
                        }
                    },
                    onReset: {
                        viewModel.resetTimer()
                    },
                    onComplete: {
                        viewModel.completeExercise()
                    }
                )
                .foregroundStyle(SupportTheme.textPrimary)
                .padding(.bottom, SupportTheme.Spacing.xl)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let phaseText = viewModel.breathingPhase.accessibilityLabel
        let cycleText = "Cycle \(viewModel.currentCycle) of \(viewModel.totalCycles)"
        let timeText = "Time remaining: \(viewModel.timeRemainingFormatted)"
        return "\(phaseText). \(cycleText). \(timeText)"
    }
}

// MARK: - Fallback for exercises without instructions

extension LibraryBreathingPlayerView {
    /// Creates default breathing pattern if instructions are missing
    static func defaultPattern() -> PlayerBreathPattern {
        return .boxBreathing
    }
}

// MARK: - Preview

// Preview removed - requires full DI setup
