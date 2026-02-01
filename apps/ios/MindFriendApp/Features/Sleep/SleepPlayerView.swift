import SwiftUI

/// Full-screen player view for sleep content
struct SleepPlayerView: View {
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

                Spacer(minLength: 40)
            }
            .padding()
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showTimerPicker) {
            sleepTimerPicker
        }
    }

    // MARK: - Subviews

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.05, blue: 0.2),
                Color(red: 0.1, green: 0.05, blue: 0.15),
                Color(red: 0.02, green: 0.02, blue: 0.08)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var headerBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.8))
            }

            Spacer()

            VStack(spacing: 2) {
                Text("NOW PLAYING")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white.opacity(0.5))
                    .tracking(1)

                Text(content.contentType.displayName)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            // Only show timer button for non-soundscape content
            if content.contentType != .soundscape {
                Button {
                    showTimerPicker = true
                } label: {
                    Image(systemName: viewModel.playerState.sleepTimerDuration != nil ? "moon.fill" : "moon")
                        .font(.title2)
                        .foregroundStyle(viewModel.playerState.sleepTimerDuration != nil ? .indigo : .white.opacity(0.8))
                }
            } else {
                // Spacer to balance layout for soundscapes
                Color.clear
                    .frame(width: 32, height: 32)
            }
        }
        .padding(.top, 8)
    }

    private var artworkView: some View {
        ZStack {
            // Glow effect
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.indigo.opacity(0.4),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 80,
                        endRadius: 180
                    )
                )
                .frame(width: 360, height: 360)
                .blur(radius: 30)

            // Main artwork circle
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: gradientColors(for: content.contentType),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // Icon
                Image(systemName: content.contentType.icon)
                    .font(.system(size: 60))
                    .foregroundStyle(.white.opacity(0.9))

                // Animated ring when playing
                if viewModel.playerState.isPlaying {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 2)
                        .scaleEffect(1.1)
                }
            }
            .frame(width: 240, height: 240)
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        }
    }

    private var trackInfoView: some View {
        VStack(spacing: 8) {
            Text(content.title)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            // Only show category, no "Loopable" text (soundscapes loop by default)
            Label(content.category.displayName, systemImage: content.category.icon)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.vertical)
    }

    private var progressView: some View {
        VStack(spacing: 8) {
            // Progress slider
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track background
                    Capsule()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 4)

                    // Progress
                    Capsule()
                        .fill(Color.white)
                        .frame(
                            width: CGFloat(isDraggingProgress ? dragProgress : min(1, max(0, viewModel.playerState.progress))) * geometry.size.width,
                            height: 4
                        )
                        .animation(isDraggingProgress ? nil : .linear(duration: 0.5), value: viewModel.playerState.progress)

                    // Knob
                    Circle()
                        .fill(Color.white)
                        .frame(width: 12, height: 12)
                        .offset(x: CGFloat(isDraggingProgress ? dragProgress : min(1, max(0, viewModel.playerState.progress))) * (geometry.size.width - 12))
                        .animation(isDraggingProgress ? nil : .linear(duration: 0.5), value: viewModel.playerState.progress)
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
                    .foregroundStyle(.white.opacity(0.6))
                    .monospacedDigit()

                Spacer()

                Text(viewModel.playerState.formattedTimeRemaining)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal)
    }

    private var controlsView: some View {
        HStack(spacing: 40) {
            // Backward 15s
            Button {
                viewModel.seekBackward(15)
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.8))
            }

            // Play/Pause
            Button {
                viewModel.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 72, height: 72)

                    if viewModel.playerState.isBuffering {
                        ProgressView()
                            .tint(.black)
                    } else {
                        Image(systemName: viewModel.playerState.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title)
                            .foregroundStyle(.black)
                            .offset(x: viewModel.playerState.isPlaying ? 0 : 2)
                    }
                }
            }

            // Forward 15s
            Button {
                viewModel.seekForward(15)
            } label: {
                Image(systemName: "goforward.15")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(.vertical)
    }

    private var timerView: some View {
        Group {
            // Only show timer view for non-soundscape content
            if content.contentType != .soundscape {
                if let remaining = viewModel.playerState.sleepTimerRemaining {
                    HStack(spacing: 8) {
                        Image(systemName: "moon.fill")
                            .foregroundStyle(.indigo)

                        Text("Sleep timer: \(formatTime(remaining))")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))

                        Spacer()

                        Button("Cancel") {
                            viewModel.cancelSleepTimer()
                        }
                        .font(.subheadline)
                        .foregroundStyle(.indigo)
                    }
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(12)
                } else if viewModel.playerState.isFading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(.indigo)

                        Text("Fading out...")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding()
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(12)
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
                                .foregroundStyle(.primary)

                            Spacer()

                            if viewModel.playerState.sleepTimerDuration == duration {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.indigo)
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
            return [Color.indigo, Color.purple]
        case .soundscape:
            return [Color.teal, Color.cyan]
        case .routine:
            return [Color.blue, Color.indigo]
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
