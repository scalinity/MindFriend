import SwiftUI

/// Full-screen player view for sleep content
struct SleepPlayerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let content: SleepContent
    @ObservedObject var viewModel: SleepViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showTimerPicker = false
    @State private var isDraggingProgress = false
    @State private var dragProgress: Double = 0

    var body: some View {
        ZStack {
            // Background
            backgroundGradient

            VStack(spacing: 0) {
                // Header
                headerBar

                Spacer()

                // Artwork
                artworkView

                Spacer()

                // Track Info
                trackInfoView

                // Progress Bar
                progressView

                // Controls
                controlsView

                // Sleep Timer
                timerView

                Spacer(minLength: SupportTheme.Spacing.xl)
            }
            .padding(SupportTheme.Spacing.m)
        }

        .sheet(isPresented: $showTimerPicker) {
            sleepTimerPicker
        }
    }

    // MARK: - Subviews

    private var backgroundGradient: some View {
        SupportTheme.canvas
        .ignoresSafeArea()
    }

    private var headerBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.title2)
                    .foregroundStyle(SupportTheme.textPrimary.opacity(0.8))
                    .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                    .accessibilityLabel("Close player")
            }

            Spacer()

            VStack(spacing: SupportTheme.Spacing.xxs) {
                Text("NOW PLAYING")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(SupportTheme.textPrimary.opacity(0.5))
                    .tracking(1)

                Text(content.contentType.displayName)
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textPrimary.opacity(0.7))
            }

            Spacer()

            // Only show timer button for non-soundscape content
            if content.contentType != .soundscape {
                Button {
                    showTimerPicker = true
                } label: {
                    Image(systemName: viewModel.playerState.sleepTimerDuration != nil ? "moon.fill" : "moon")
                        .font(.title2)
                        .foregroundStyle(viewModel.playerState.sleepTimerDuration != nil ? .indigo : SupportTheme.textPrimary.opacity(0.8))
                        .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                        .accessibilityLabel("Sleep timer")
                }
            } else {
                // Spacer to balance layout for soundscapes
                Color.clear
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.top, SupportTheme.Spacing.xs)
    }

    private var artworkView: some View {
        ZStack {
            // Glow effect
            Circle()
                .fill(
                    SupportTheme.surface
                )
                .frame(width: 360, height: 360)
                .blur(radius: 30)

            // Main artwork circle
            ZStack {
                Circle()
                    .fill(
                        SupportTheme.surface
                    )

                // Icon
                Image(systemName: content.contentType.icon)
                    .font(.system(.largeTitle))
                    .foregroundStyle(SupportTheme.textPrimary.opacity(0.9))

                // Animated ring when playing
                if viewModel.playerState.isPlaying {
                    Circle()
                        .stroke(SupportTheme.surface.opacity(0.2), lineWidth: 2)
                        .scaleEffect(1.1)
                }
            }
            .frame(width: 240, height: 240)
            .shadow(color: SupportTheme.canvas.opacity(0.3), radius: 20, y: 10)
        }
    }

    private var trackInfoView: some View {
        VStack(spacing: SupportTheme.Spacing.xs) {
            Text(content.title)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(SupportTheme.textPrimary)
                .multilineTextAlignment(.center)

            // Only show category, no "Loopable" text (soundscapes loop by default)
            Label(content.category.displayName, systemImage: content.category.icon)
                .font(.caption)
                .foregroundStyle(SupportTheme.textPrimary.opacity(0.5))
        }
        .padding(.vertical, SupportTheme.Spacing.m)
    }

    private var progressView: some View {
        VStack(spacing: SupportTheme.Spacing.xs) {
            // Progress slider
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track background
                    Capsule()
                        .fill(SupportTheme.surface.opacity(0.2))
                        .frame(height: 4)

                    // Progress
                    Capsule()
                        .fill(SupportTheme.surface)
                        .frame(
                            width: CGFloat(isDraggingProgress ? dragProgress : min(1, max(0, viewModel.playerState.progress))) * geometry.size.width,
                            height: 4
                        )
                        .animation(reduceMotion ? nil : isDraggingProgress ? nil : .linear(duration: 0.5), value: viewModel.playerState.progress)

                    // Knob
                    Circle()
                        .fill(SupportTheme.surface)
                        .frame(width: 12, height: 12)
                        .offset(x: CGFloat(isDraggingProgress ? dragProgress : min(1, max(0, viewModel.playerState.progress))) * (geometry.size.width - 12))
                        .animation(reduceMotion ? nil : isDraggingProgress ? nil : .linear(duration: 0.5), value: viewModel.playerState.progress)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    isDraggingProgress = true
                                    dragProgress = min(max(0, value.location.x / geometry.size.width), 1)
                                }
                                .onEnded { _ in
                                    viewModel.seek(to: dragProgress * viewModel.playerState.duration)
                                    isDraggingProgress = false
                                }
                        )
                }
            }
            .frame(height: 20)

            // Time labels
            HStack {
                Text(viewModel.playerState.formattedCurrentTime)
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textPrimary.opacity(0.6))
                    .monospacedDigit()

                Spacer()

                Text(viewModel.playerState.formattedTimeRemaining)
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textPrimary.opacity(0.6))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, SupportTheme.Spacing.m)
    }

    private var controlsView: some View {
        HStack(spacing: SupportTheme.Spacing.xl) {
            // Backward 15s
            Button {
                viewModel.seekBackward(15)
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.title)
                    .foregroundStyle(SupportTheme.textPrimary.opacity(0.8))
                    .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                    .accessibilityLabel("Back 15 seconds")
            }

            // Play/Pause
            Button {
                viewModel.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(SupportTheme.surface)
                        .frame(width: 72, height: 72)

                    if viewModel.playerState.isBuffering {
                        ProgressView()
                            .tint(SupportTheme.accent)
                    } else {
                        Image(systemName: viewModel.playerState.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title)
                            .foregroundStyle(SupportTheme.textPrimary)
                            .offset(x: viewModel.playerState.isPlaying ? 0 : 2)
                    }
                }
                .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                .accessibilityLabel(viewModel.playerState.isPlaying ? "Pause" : "Play")
            }

            // Forward 15s
            Button {
                viewModel.seekForward(15)
            } label: {
                Image(systemName: "goforward.15")
                    .font(.title)
                    .foregroundStyle(SupportTheme.textPrimary.opacity(0.8))
                    .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                    .accessibilityLabel("Forward 15 seconds")
            }
        }
        .padding(.vertical, SupportTheme.Spacing.m)
    }

    private var timerView: some View {
        Group {
            // Only show timer view for non-soundscape content
            if content.contentType != .soundscape {
                if let remaining = viewModel.playerState.sleepTimerRemaining {
                    HStack(spacing: SupportTheme.Spacing.xs) {
                        Image(systemName: "moon.fill")
                            .foregroundStyle(SupportTheme.accent)

                        Text("Sleep timer: \(formatTime(remaining))")
                            .font(.subheadline)
                            .foregroundStyle(SupportTheme.textPrimary.opacity(0.7))

                        Spacer()

                        Button("Cancel") {
                            viewModel.cancelSleepTimer()
                        }
                        .font(.subheadline)
                        .foregroundStyle(SupportTheme.accent)
                    }
                    .padding(SupportTheme.Spacing.m)
                    .background(SupportTheme.surface.opacity(0.05))
                    .cornerRadius(SupportTheme.controlRadius)
                } else if viewModel.playerState.isFading {
                    HStack(spacing: SupportTheme.Spacing.xs) {
                        ProgressView()
                            .tint(SupportTheme.accent)

                        Text("Fading out...")
                            .font(.subheadline)
                            .foregroundStyle(SupportTheme.textPrimary.opacity(0.7))
                    }
                    .padding(SupportTheme.Spacing.m)
                    .background(SupportTheme.surface.opacity(0.05))
                    .cornerRadius(SupportTheme.controlRadius)
                }
            }
        }
    }

    private var sleepTimerPicker: some View {
        NavigationStack {
            List {
                ForEach(SleepTimerDuration.allCases) { duration in
                    Button {
                        viewModel.setSleepTimer(duration)
                        showTimerPicker = false
                    } label: {
                        HStack {
                            Text(duration.displayName)
                                .foregroundStyle(SupportTheme.textPrimary)

                            Spacer()

                            if viewModel.playerState.sleepTimerDuration == duration {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(SupportTheme.accent)
                            }
                        }
                    }
                }

                if viewModel.playerState.sleepTimerDuration != nil {
                    Button(role: .destructive) {
                        viewModel.cancelSleepTimer()
                        showTimerPicker = false
                    } label: {
                        Text("Turn Off Timer")
                    }
                }
            }
            .supportScreen()
            .navigationTitle("Sleep Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        showTimerPicker = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers

    private func gradientColors(for type: SleepContentType) -> [Color] {
        switch type {
        case .story:
            return [SupportTheme.accent, SupportTheme.accent]
        case .soundscape:
            return [SupportTheme.accent, SupportTheme.accent]
        case .routine:
            return [SupportTheme.accent, SupportTheme.accent]
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Preview

#Preview {
    SleepPlayerView(
        content: SleepContent(
            id: "1",
            title: "Rainy Night in the Forest",
            description: "A gentle walk through a misty forest as rain softly falls",
            contentType: .story,
            category: .nature,
            durationSeconds: 1800,
            narrator: "Sarah",
            isPremium: false,
            isKids: false,
            audioUrl: "https://example.com/audio.m4a",
            thumbnailUrl: nil,
            isLoopable: false,
            isFeatured: true,
            sortOrder: 1,
            createdAt: Date()
        ),
        viewModel: SleepViewModel(container: DependencyContainer.preview, appState: AppState())
    )
}
