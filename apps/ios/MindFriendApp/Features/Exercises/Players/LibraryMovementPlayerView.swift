import SwiftUI

/// Movement exercise player with step-by-step instructions
struct LibraryMovementPlayerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var viewModel: LibraryExercisePlayerViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header with overall progress
            headerSection

            Divider()

            // Movement steps
            if let movement = viewModel.movementInstructions {
                movementContent(movement)
            } else {
                fallbackContent
            }

            Divider()

            // Controls
            controlsSection
        }
        .background(SupportTheme.canvas)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: SupportTheme.Spacing.s) {
            // Overall progress
            StepProgressBar(
                progress: viewModel.progress,
                color: SupportTheme.accent
            )
            .padding(.horizontal, SupportTheme.Spacing.m)

            // Time display
            HStack {
                if let movement = viewModel.movementInstructions {
                    Text("Step \(viewModel.currentMovementIndex + 1) of \(movement.movements.count)")
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.textSecondary)
                }

                Spacer()

                TimerDisplay(seconds: viewModel.timeRemaining, style: .medium)
            }
            .padding(.horizontal, SupportTheme.Spacing.m)
        }
        .padding(.vertical, SupportTheme.Spacing.m)
    }

    // MARK: - Movement Content

    private func movementContent(_ movement: MovementInstructions) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: SupportTheme.Spacing.m) {
                    ForEach(Array(movement.movements.enumerated()), id: \.offset) { index, step in
                        MovementStepCard(
                            step: step,
                            isActive: index == viewModel.currentMovementIndex,
                            timeRemaining: index == viewModel.currentMovementIndex ? viewModel.movementTimeRemaining : nil
                        )
                        .id(index)
                    }
                }
                .padding(SupportTheme.Spacing.m)
            }
            .onChange(of: viewModel.currentMovementIndex) { _, newIndex in
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }

    // MARK: - Fallback

    private var fallbackContent: some View {
        VStack(spacing: SupportTheme.Spacing.l) {
            Spacer()

            // Animated figure
            Image(systemName: "figure.walk")
                .font(.system(.largeTitle))
                .foregroundStyle(SupportTheme.accent)
                .symbolEffect(.pulse, isActive: !reduceMotion && (viewModel.isPlaying))

            // Timer
            TimerDisplay(seconds: viewModel.timeRemaining, style: .large)

            // Description
            Text(viewModel.exercise.description)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(SupportTheme.textSecondary)
                .padding(.horizontal, SupportTheme.Spacing.xl)

            Spacer()
        }
    }

    // MARK: - Controls

    private var controlsSection: some View {
        HStack(spacing: SupportTheme.Spacing.xl) {
            // Reset
            Button {
                viewModel.resetTimer()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.title)
                .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                .accessibilityLabel("Restart")
            }
            .disabled(!viewModel.isPlaying && viewModel.currentMovementIndex == 0)

            // Play/Pause
            Button {
                if viewModel.isPlaying {
                    viewModel.pauseTimer()
                } else {
                    viewModel.startTimer()
                }
            } label: {
                Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(.largeTitle))
                    .foregroundStyle(SupportTheme.accent)
                    .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                    .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")
            }

            // Skip / Complete
            Button {
                if let movement = viewModel.movementInstructions,
                   viewModel.currentMovementIndex >= movement.movements.count - 1 {
                    viewModel.completeExercise()
                } else {
                    skipToNextMovement()
                }
            } label: {
                Image(systemName: viewModel.currentMovementIndex >= (viewModel.movementInstructions?.movements.count ?? 1) - 1
                    ? "checkmark.circle"
                    : "forward.fill")
                    .font(.title)
                .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                .accessibilityLabel("Continue exercise")
            }
        }
        .padding(SupportTheme.Spacing.m)
        .padding(.bottom, SupportTheme.Spacing.m)
    }

    // MARK: - Actions

    private func skipToNextMovement() {
        guard let movement = viewModel.movementInstructions else { return }

        if viewModel.currentMovementIndex < movement.movements.count - 1 {
            viewModel.currentMovementIndex += 1
            viewModel.movementTimeRemaining = movement.movements[viewModel.currentMovementIndex].durationSeconds
            HapticManager.selection()
        }
    }
}

// MARK: - Preview

// Preview removed - requires full DI setup
