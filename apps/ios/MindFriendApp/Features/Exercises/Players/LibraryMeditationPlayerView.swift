import SwiftUI

/// Meditation player with progressive instruction display
struct LibraryMeditationPlayerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var viewModel: LibraryExercisePlayerViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header with timer and progress
            headerSection

            // Audio indicator if audio is available
            if viewModel.hasAudio {
                audioIndicator
            }

            Divider()

            // Scrollable segments
            if let meditation = viewModel.meditationInstructions {
                segmentsScrollView(segments: meditation.segments)
            } else {
                // Fallback for exercises without structured instructions
                fallbackContent
            }

            Divider()

            // Bottom controls
            controlsSection
        }
        .background(SupportTheme.Area.journal.palette.softGradient.ignoresSafeArea())
        .tint(SupportTheme.Area.journal.palette.ink)
        .onDisappear {
            // Stop audio when leaving
            if viewModel.hasAudio {
                viewModel.audioPlayer.pause()
            }
        }
    }

    // MARK: - Audio Indicator

    private var audioIndicator: some View {
        HStack(spacing: SupportTheme.Spacing.xs) {
            Image(systemName: viewModel.audioPlayer.isPlaying ? "waveform" : "speaker.wave.2")
                .font(.caption)
                .foregroundStyle(viewModel.audioPlayer.isPlaying ? SupportTheme.Area.journal.palette.ink : SupportTheme.textSecondary)
                .symbolEffect(.variableColor.iterative, isActive: !reduceMotion && (viewModel.audioPlayer.isPlaying))

            Text("Guided Audio")
                .font(.caption)
                .foregroundStyle(SupportTheme.textSecondary)

            Spacer()

            // Audio volume/mute toggle
            Button {
                if viewModel.audioPlayer.isPlaying {
                    viewModel.audioPlayer.pause()
                } else {
                    viewModel.audioPlayer.play()
                }
            } label: {
                Image(systemName: viewModel.audioPlayer.isPlaying ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.caption)
                    .foregroundStyle(viewModel.audioPlayer.isPlaying ? SupportTheme.Area.journal.palette.ink : SupportTheme.textSecondary)
                    .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                    .accessibilityLabel(viewModel.audioPlayer.isPlaying ? "Mute audio" : "Play audio")
            }
        }
        .padding(.horizontal, SupportTheme.Spacing.m)
        .padding(.vertical, SupportTheme.Spacing.xs)
        .background(SupportTheme.surface)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: SupportTheme.Spacing.s) {
            // Progress bar
            StepProgressBar(
                progress: viewModel.progress,
                color: SupportTheme.Area.journal.palette.ink
            )
            .padding(.horizontal, SupportTheme.Spacing.m)

            // Time display
            HStack {
                Text(elapsedTimeFormatted)
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)

                Spacer()

                TimerDisplay(seconds: viewModel.timeRemaining, style: .medium)

                Spacer()

                Text("-\(viewModel.timeRemainingFormatted)")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }
            .padding(.horizontal, SupportTheme.Spacing.m)
        }
        .padding(.vertical, SupportTheme.Spacing.m)
    }

    private var elapsedTimeFormatted: String {
        let minutes = Int(viewModel.elapsedTime) / 60
        let seconds = Int(viewModel.elapsedTime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - Segments

    private func segmentsScrollView(segments: [MeditationSegment]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: SupportTheme.Spacing.m) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                        SegmentView(
                            text: segment.text,
                            isActive: index == viewModel.currentSegmentIndex,
                            segmentType: segment.segmentType
                        )
                        .id(index)
                    }
                }
                .padding(SupportTheme.Spacing.m)
            }
            .onChange(of: viewModel.currentSegmentIndex) { _, newIndex in
                withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: 0.3)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }

    // MARK: - Fallback

    private var fallbackContent: some View {
        VStack(spacing: SupportTheme.Spacing.l) {
            Spacer()

            // Exercise description as content
            if let text = viewModel.exercise.contentText {
                Text(text)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(SupportTheme.textPrimary)
                    .padding(.horizontal, SupportTheme.Spacing.xl)
            } else {
                Text(viewModel.exercise.description)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(SupportTheme.textPrimary)
                    .padding(.horizontal, SupportTheme.Spacing.xl)
            }

            Spacer()
        }
    }

    // MARK: - Controls

    private var controlsSection: some View {
        HStack(spacing: SupportTheme.Spacing.l) {
            // Previous segment
            Button {
                viewModel.previousSegment()
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title)
                .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                .accessibilityLabel("Previous step")
            }
            .disabled(viewModel.currentSegmentIndex == 0)

            Spacer()

            // Play/Pause
            Button {
                if viewModel.isPlaying {
                    viewModel.pauseTimer()
                    if viewModel.hasAudio {
                        viewModel.audioPlayer.pause()
                    }
                } else {
                    viewModel.startTimer()
                    if viewModel.hasAudio {
                        viewModel.audioPlayer.play()
                    }
                }
            } label: {
                Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(.largeTitle))
                    .foregroundStyle(SupportTheme.Area.journal.palette.ink)
                    .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                    .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")
            }

            Spacer()

            // Next segment / Complete
            Button {
                if let meditation = viewModel.meditationInstructions,
                   viewModel.currentSegmentIndex >= meditation.segments.count - 1 {
                    viewModel.completeExercise()
                } else {
                    viewModel.advanceSegment()
                }
            } label: {
                Image(systemName: viewModel.currentSegmentIndex >= (viewModel.meditationInstructions?.segments.count ?? 1) - 1
                    ? "checkmark.circle.fill"
                    : "chevron.right.circle.fill")
                    .font(.title)
                .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                .accessibilityLabel("Continue exercise")
            }
        }
        .padding(SupportTheme.Spacing.m)
        .padding(.bottom, SupportTheme.Spacing.m)
    }
}

// MARK: - Progress Indicator

private struct SegmentProgressIndicator: View {
    let total: Int
    let current: Int

    var body: some View {
        HStack(spacing: SupportTheme.Spacing.xxs) {
            ForEach(0..<total, id: \.self) { index in
                RoundedRectangle(cornerRadius: SupportTheme.controlRadius)
                    .fill(index <= current ? SupportTheme.Area.journal.palette.ink : SupportTheme.textSecondary.opacity(0.3))
                    .frame(height: 4)
            }
        }
    }
}

// MARK: - Preview

// Preview removed - requires full DI setup
