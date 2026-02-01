import SwiftUI

/// Immersive breathing exercise player with animated circle
struct LibraryBreathingPlayerView: View {
    @ObservedObject var viewModel: LibraryExercisePlayerViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Immersive gradient background
            ImmersiveBackground(colors: viewModel.breathingPhaseColors)
                .animation(.easeInOut(duration: 0.5), value: viewModel.breathingPhase)

            VStack(spacing: 40) {
                Spacer()

                // Intro text (before starting)
                if !viewModel.isPlaying && viewModel.currentCycle == 1 {
                    if let intro = viewModel.breathingInstructions?.introText {
                        Text(intro)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .transition(.opacity)
                    }
                }

                // Phase label
                PhaseLabel(
                    text: viewModel.breathingPhase.displayText,
                    color: .white
                )
                .opacity(viewModel.isPlaying ? 1 : 0.5)

                // Animated breathing circle
                if reduceMotion {
                    // Static circle for reduced motion
                    Circle()
                        .fill(viewModel.breathingPhase.color.opacity(0.6))
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
                    .foregroundStyle(.white)

                // Cycle counter
                if let instructions = viewModel.breathingInstructions {
                    CycleCounter(
                        current: viewModel.currentCycle,
                        total: instructions.cycles
                    )
                    .foregroundStyle(.white.opacity(0.7))
                }

                Spacer()

                // Controls
                PlayerControls(
                    isPlaying: viewModel.isPlaying,
                    canReset: viewModel.isPlaying || viewModel.currentCycle > 1,
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
                .foregroundStyle(.white)
                .padding(.bottom, 32)
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
