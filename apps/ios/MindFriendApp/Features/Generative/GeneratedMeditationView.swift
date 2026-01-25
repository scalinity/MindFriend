import SwiftUI

/// Full-screen meditation/breathing/affirmation player view
/// Features audio playback, text follow-along, rating, and favorites
struct GeneratedMeditationView: View {
    let content: GeneratedContent
    @Environment(\.dismiss) private var dismiss
    @StateObject private var player = AudioPlayerViewModel()
    @State private var showTextFollowAlong = false
    @State private var showBackgroundSounds = false
    @State private var showSleepTimer = false
    @State private var showRatingSheet = false
    @State private var isFavorite: Bool
    @State private var hasRated = false

    init(content: GeneratedContent) {
        self.content = content
        _isFavorite = State(initialValue: content.isFavorite)
    }

    var body: some View {
        ZStack {
            // Ambient background
            ambientBackground

            VStack(spacing: 24) {
                // Header
                headerView

                Spacer()

                // Main content area
                mainContentArea

                Spacer()

                // Player controls
                playerControls

                // Toolbar
                toolbarView

                // Text follow-along (if enabled)
                if showTextFollowAlong {
                    textFollowAlongView
                }
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $showBackgroundSounds) {
            BackgroundSoundsSheet(
                selectedSound: $player.backgroundSound,
                volume: $player.backgroundSoundVolume
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showSleepTimer) {
            SleepTimerView(selectedMinutes: $player.sleepTimerMinutes)
                .presentationDetents([.height(300)])
        }
        .sheet(isPresented: $showRatingSheet) {
            ContentRatingSheetView(content: content, onRated: {
                hasRated = true
            })
            .presentationDetents([.height(300)])
        }
        .onAppear {
            loadAudio()
        }
        .onDisappear {
            player.cleanup()
        }
        .onChange(of: player.isPlaying) { _, isPlaying in
            if !isPlaying && player.progress >= 0.95 && !hasRated {
                // Show rating prompt after content ends
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showRatingSheet = true
                }
            }
        }
    }

    // MARK: - Ambient Background

    private var ambientBackground: some View {
        LinearGradient(
            colors: content.contentType.gradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .opacity(0.3)
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 8) {
            Image(systemName: content.contentType.icon)
                .font(.system(size: 48))
                .foregroundStyle(content.contentType.backgroundColor)

            Text(content.title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text(content.contentType.displayName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Main Content Area

    private var mainContentArea: some View {
        VStack(spacing: 16) {
            // Duration indicator
            HStack(spacing: 8) {
                if let duration = content.duration {
                    Image(systemName: "clock")
                    Text("\(duration / 60) min")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Loading indicator
            if player.isLoading {
                ProgressView("Loading audio...")
                    .padding()
            }

            // Error state
            if let error = player.error {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Generate Audio") {
                        // Re-synthesize
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: - Player Controls

    private var playerControls: some View {
        VStack(spacing: 16) {
            // Progress bar
            Slider(
                value: Binding(
                    get: { player.currentTime },
                    set: { player.seek(to: $0) }
                ),
                in: 0...max(player.duration, 1)
            )
            .tint(content.contentType.backgroundColor)

            // Time labels
            HStack {
                Text(player.formattedCurrentTime)
                Spacer()
                if player.sleepTimerMinutes != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                        Text(player.formattedSleepTimerRemaining)
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
                Spacer()
                Text(player.formattedDuration)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Playback controls
            HStack(spacing: 40) {
                Button {
                    player.skipBackward()
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title)
                }

                Button {
                    player.togglePlayback()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(content.contentType.backgroundColor)
                }
                .disabled(player.isLoading || content.audioUrl == nil)

                Button {
                    player.skipForward()
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.title)
                }
            }
            .foregroundStyle(.primary)
        }
    }

    // MARK: - Toolbar

    private var toolbarView: some View {
        HStack(spacing: 24) {
            // Speed control
            Menu {
                ForEach(AudioPlayerViewModel.playbackSpeeds, id: \.self) { speed in
                    Button {
                        player.playbackRate = speed
                    } label: {
                        HStack {
                            Text("\(speed, specifier: "%.2f")x")
                            if player.playbackRate == speed {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: "speedometer")
                    Text("\(player.playbackRate, specifier: "%.1f")x")
                        .font(.caption2)
                }
            }

            // Background sounds
            Button {
                showBackgroundSounds = true
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: player.backgroundSound != nil ? "waveform.circle.fill" : "waveform.circle")
                    Text("Sounds")
                        .font(.caption2)
                }
            }

            // Sleep timer
            Button {
                showSleepTimer = true
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: player.sleepTimerMinutes != nil ? "timer.circle.fill" : "timer")
                    Text("Timer")
                        .font(.caption2)
                }
            }

            // Text toggle
            Button {
                withAnimation {
                    showTextFollowAlong.toggle()
                }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: showTextFollowAlong ? "text.alignleft.fill" : "text.alignleft")
                    Text("Text")
                        .font(.caption2)
                }
            }

            // Favorite
            Button {
                toggleFavorite()
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(isFavorite ? .red : .primary)
                    Text("Save")
                        .font(.caption2)
                }
            }
        }
        .font(.title3)
        .foregroundStyle(.primary)
    }

    // MARK: - Text Follow Along

    private var textFollowAlongView: some View {
        ScrollView {
            Text(content.textContent)
                .font(.body)
                .lineSpacing(8)
                .padding()
        }
        .frame(maxHeight: 200)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Actions

    private func loadAudio() {
        guard let urlString = content.audioUrl,
              let url = URL(string: urlString) else {
            player.error = "No audio available"
            return
        }

        Task {
            do {
                try await player.load(audioURL: url)
            } catch {
                player.error = "Failed to load audio"
            }
        }
    }

    private func toggleFavorite() {
        isFavorite.toggle()

        Task {
            do {
                let service = GeneratedContentService(supabase: supabase)
                _ = try await service.toggleFavorite(contentId: content.id)
            } catch {
                // Revert on failure
                isFavorite.toggle()
            }
        }
    }
}

// MARK: - Content Rating Sheet

private struct ContentRatingSheetView: View {
    let content: GeneratedContent
    let onRated: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var rating: Int = 0
    @State private var isSubmitting = false

    var body: some View {
        VStack(spacing: 24) {
            Text("How was this \(content.contentType.displayName.lowercased())?")
                .font(.headline)

            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        rating = star
                    } label: {
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.largeTitle)
                            .foregroundStyle(star <= rating ? .yellow : .gray)
                    }
                }
            }

            HStack(spacing: 16) {
                Button("Skip") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button {
                    submitRating()
                } label: {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Text("Submit")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(rating == 0 || isSubmitting)
            }
        }
        .padding()
    }

    private func submitRating() {
        isSubmitting = true

        Task {
            do {
                let service = GeneratedContentService(supabase: supabase)
                _ = try await service.rateContent(contentId: content.id, rating: rating)
                onRated()
                dismiss()
            } catch {
                isSubmitting = false
            }
        }
    }
}

// MARK: - Extensions

private extension GeneratedContentType {
    var gradientColors: [Color] {
        switch self {
        case .meditation, .mindfulness:
            return [.purple.opacity(0.3), .blue.opacity(0.2)]
        case .sleepStory:
            return [.indigo.opacity(0.4), .purple.opacity(0.2)]
        case .breathing:
            return [.cyan.opacity(0.3), .blue.opacity(0.2)]
        case .affirmation:
            return [.pink.opacity(0.3), .orange.opacity(0.2)]
        case .grounding:
            return [.green.opacity(0.3), .teal.opacity(0.2)]
        case .cbt:
            return [.orange.opacity(0.3), .yellow.opacity(0.2)]
        case .journaling:
            return [.brown.opacity(0.3), .orange.opacity(0.2)]
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    NavigationStack {
        GeneratedMeditationView(content: .preview)
    }
}
#endif
