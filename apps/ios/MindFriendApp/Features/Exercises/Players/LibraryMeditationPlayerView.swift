import SwiftUI

/// Meditation player with progressive instruction display
struct LibraryMeditationPlayerView: View {
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
        .background(Color(.systemBackground))
        .onAppear {
            // Auto-play audio when view appears if audio is available
            if viewModel.hasAudio {
                viewModel.audioPlayer.play()
            }
        }
        .onDisappear {
            // Stop audio when leaving
            if viewModel.hasAudio {
                viewModel.audioPlayer.pause()
            }
        }
    }

    // MARK: - Audio Indicator

    private var audioIndicator: some View {
        HStack(spacing: 8) {
            Image(systemName: viewModel.audioPlayer.isPlaying ? "waveform" : "speaker.wave.2")
                .font(.caption)
                .foregroundStyle(viewModel.audioPlayer.isPlaying ? Color.accentColor : Color.secondary)
                .symbolEffect(.variableColor.iterative, isActive: viewModel.audioPlayer.isPlaying)

            Text("Guided Audio")
                .font(.caption)
                .foregroundStyle(.secondary)

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
                    .foregroundStyle(viewModel.audioPlayer.isPlaying ? Color.accentColor : Color.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            // Progress bar
            StepProgressBar(
                progress: viewModel.progress,
                color: .accentColor
            )
            .padding(.horizontal)

            // Time display
            HStack {
                Text(elapsedTimeFormatted)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                TimerDisplay(seconds: viewModel.timeRemaining, style: .medium)

                Spacer()

                Text("-\(viewModel.timeRemainingFormatted)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 16)
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
                LazyVStack(spacing: 16) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                        SegmentView(
                            text: segment.text,
                            isActive: index == viewModel.currentSegmentIndex,
                            segmentType: segment.segmentType
                        )
                        .id(index)
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.currentSegmentIndex) { _, newIndex in
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }

    // MARK: - Fallback

    private var fallbackContent: some View {
        VStack(spacing: 24) {
            Spacer()

            // Exercise description as content
            if let text = viewModel.exercise.contentText {
                Text(text)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 32)
            } else {
                Text(viewModel.exercise.description)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 32)
            }

            Spacer()
        }
    }

    // MARK: - Controls

    private var controlsSection: some View {
        HStack(spacing: 24) {
            // Previous segment
            Button {
                viewModel.previousSegment()
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title)
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
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)
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
            }
        }
        .padding()
        .padding(.bottom, 16)
    }
}

// MARK: - Progress Indicator

private struct SegmentProgressIndicator: View {
    let total: Int
    let current: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index <= current ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(height: 4)
            }
        }
    }
}

// MARK: - Preview

// Preview removed - requires full DI setup
