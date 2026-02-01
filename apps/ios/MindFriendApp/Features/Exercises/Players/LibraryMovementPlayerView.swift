import SwiftUI

/// Movement exercise player with step-by-step instructions
struct LibraryMovementPlayerView: View {
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
        .background(Color(.systemBackground))
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            // Overall progress
            StepProgressBar(
                progress: viewModel.progress,
                color: .pink
            )
            .padding(.horizontal)

            // Time display
            HStack {
                if let movement = viewModel.movementInstructions {
                    Text("Step \(viewModel.currentMovementIndex + 1) of \(movement.movements.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                TimerDisplay(seconds: viewModel.timeRemaining, style: .medium)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 16)
    }

    // MARK: - Movement Content

    private func movementContent(_ movement: MovementInstructions) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(Array(movement.movements.enumerated()), id: \.offset) { index, step in
                        MovementStepCard(
                            step: step,
                            isActive: index == viewModel.currentMovementIndex,
                            timeRemaining: index == viewModel.currentMovementIndex ? viewModel.movementTimeRemaining : nil
                        )
                        .id(index)
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.currentMovementIndex) { _, newIndex in
                withAnimation(.easeInOut) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }

    // MARK: - Fallback

    private var fallbackContent: some View {
        VStack(spacing: 24) {
            Spacer()

            // Animated figure
            Image(systemName: "figure.walk")
                .font(.system(size: 80))
                .foregroundStyle(.pink)
                .symbolEffect(.pulse, isActive: viewModel.isPlaying)

            // Timer
            TimerDisplay(seconds: viewModel.timeRemaining, style: .large)

            // Description
            Text(viewModel.exercise.description)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)

            Spacer()
        }
    }

    // MARK: - Controls

    private var controlsSection: some View {
        HStack(spacing: 32) {
            // Reset
            Button {
                viewModel.resetTimer()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.title)
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
                    .font(.system(size: 64))
                    .foregroundStyle(.pink)
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
            }
        }
        .padding()
        .padding(.bottom, 16)
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
