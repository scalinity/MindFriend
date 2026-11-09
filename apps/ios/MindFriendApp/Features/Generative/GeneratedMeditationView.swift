import SwiftUI

/// Full-screen meditation/breathing/affirmation player view
/// Features audio playback, text follow-along, rating, and favorites
struct GeneratedMeditationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let content: GeneratedContent
    @Environment(\.dismiss) private var dismiss
    @StateObject private var player = AudioPlayerViewModel()
    @State private var showTextFollowAlong = false
    @State private var showBackgroundSounds = false
    @State private var showSleepTimer = false
    @State private var showRatingSheet = false
    @State private var loadAttempt = 0
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

            VStack(spacing: SupportTheme.Spacing.l) {
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
            .padding(SupportTheme.Spacing.m)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(SupportTheme.textSecondary)
                        .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                        .accessibilityLabel("Close")
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
            SleepTimerView(selectedMinutes: $player.sleepTimerMinutes, usesBuiltInVoice: player.usesBuiltInVoice)
                .presentationDetents([.height(300)])
        }
        .sheet(isPresented: $showRatingSheet) {
            ContentRatingSheetView(content: content, onRated: {
                hasRated = true
            })
            .presentationDetents([.height(300)])
        }
        .task(id: "\(content.id)-\(loadAttempt)") {
            await player.load(content: content)
        }
        .onDisappear {
            player.cleanup()
        }
        .task(id: "\(content.id)-\(player.isPlaying)") {
            if !player.isPlaying && player.progress >= 0.95 && !hasRated {
                do { try await Task.sleep(nanoseconds: 500_000_000) }
                catch { return }
                showRatingSheet = true
            }
        }
    }

    // MARK: - Ambient Background

    private var ambientBackground: some View {
        SupportTheme.canvas
        .ignoresSafeArea()
        .opacity(0.3)
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: SupportTheme.Spacing.xs) {
            Image(systemName: content.contentType.icon)
                .font(.system(.largeTitle))
                .foregroundStyle(SupportTheme.accent)

            Text(content.title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text(content.contentType.displayName)
                .font(.subheadline)
                .foregroundStyle(SupportTheme.textSecondary)
        }
    }

    // MARK: - Main Content Area

    private var mainContentArea: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            // Duration indicator
            HStack(spacing: SupportTheme.Spacing.xs) {
                if let duration = content.duration {
                    Image(systemName: "clock")
                    Text("\(duration / 60) min")
                }
            }
            .font(.caption)
            .foregroundStyle(SupportTheme.textSecondary)

            if player.usesBuiltInVoice {
                Label("Built-in voice", systemImage: "speaker.wave.2")
                    .font(.caption)
                    .foregroundStyle(SupportTheme.textSecondary)
            }

            // Loading indicator
            if player.isLoading {
                ProgressView("Preparing audio...")
                    .padding(SupportTheme.Spacing.m)
            }

            // Error state
            if let error = player.error {
                VStack(spacing: SupportTheme.Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundStyle(SupportTheme.accent)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(SupportTheme.textSecondary)
                    Button("Try again") {
                        loadAttempt += 1
                    }
                    .buttonStyle(.supportSecondary)
                }
            }
        }
    }

    // MARK: - Player Controls

    private var playerControls: some View {
        VStack(spacing: SupportTheme.Spacing.m) {
            // Built-in speech reports reading progress without audio seeking.
            if player.usesBuiltInVoice {
                ProgressView(value: player.progress)
                    .tint(SupportTheme.accent)
            } else {
                Slider(
                    value: Binding(
                        get: { player.currentTime },
                        set: { player.seek(to: $0) }
                    ),
                    in: 0...max(player.duration, 1)
                )
                .tint(SupportTheme.accent)
                .disabled(!player.canSeek)
            }

            // Time labels
            HStack {
                Text(player.usesBuiltInVoice ? "\(Int(player.progress * 100))% read" : player.formattedCurrentTime)
                Spacer()
                if player.sleepTimerMinutes != nil {
                    HStack(spacing: SupportTheme.Spacing.xxs) {
                        Image(systemName: "timer")
                        Text(player.formattedSleepTimerRemaining)
                    }
                    .font(.caption)
                    .foregroundStyle(SupportTheme.accent)
                }
                Spacer()
                if !player.usesBuiltInVoice {
                    Text(player.formattedDuration)
                }
            }
            .font(.caption)
            .foregroundStyle(SupportTheme.textSecondary)

            // Playback controls
            HStack(spacing: SupportTheme.Spacing.xl) {
                Button {
                    player.skipBackward()
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title)
                    .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                    .accessibilityLabel("Back 15 seconds")
                }
                .disabled(!player.canSeek)

                Button {
                    player.togglePlayback()
                } label: {
                    Image(systemName: player.isPlaybackRequested ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(.largeTitle))
                        .foregroundStyle(SupportTheme.accent)
                        .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                }
                .disabled(!player.canPlay)
                .accessibilityLabel(player.isPlaybackRequested ? "Pause" : "Play")

                Button {
                    player.skipForward()
                } label: {
                    Image(systemName: "goforward.15")
                        .font(.title)
                    .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                    .accessibilityLabel("Forward 15 seconds")
                }
                .disabled(!player.canSeek)
            }
            .foregroundStyle(SupportTheme.textPrimary)
        }
    }

    // MARK: - Toolbar

    private var toolbarView: some View {
        HStack(spacing: SupportTheme.Spacing.l) {
            // Recorded audio supports adjustable playback speed.
            if !player.usesBuiltInVoice {
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
                    VStack(spacing: SupportTheme.Spacing.xxs) {
                        Image(systemName: "speedometer")
                        Text("\(player.playbackRate, specifier: "%.1f")x")
                            .font(.caption2)
                    }
                }
            }

            // Background sounds
            Button {
                showBackgroundSounds = true
            } label: {
                VStack(spacing: SupportTheme.Spacing.xxs) {
                    Image(systemName: player.backgroundSound != nil ? "waveform.circle.fill" : "waveform.circle")
                    Text("Sounds")
                        .font(.caption2)
                }
            }

            // Sleep timer
            Button {
                showSleepTimer = true
            } label: {
                VStack(spacing: SupportTheme.Spacing.xxs) {
                    Image(systemName: player.sleepTimerMinutes != nil ? "timer.circle.fill" : "timer")
                    Text("Timer")
                        .font(.caption2)
                }
            }

            // Text toggle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showTextFollowAlong.toggle()
                }
            } label: {
                VStack(spacing: SupportTheme.Spacing.xxs) {
                    Image(systemName: showTextFollowAlong ? "text.alignleft.fill" : "text.alignleft")
                    Text("Text")
                        .font(.caption2)
                }
            }

            // Favorite
            Button {
                toggleFavorite()
            } label: {
                VStack(spacing: SupportTheme.Spacing.xxs) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(isFavorite ? .red : SupportTheme.textPrimary)
                    Text("Save")
                        .font(.caption2)
                }
            }
        }
        .font(.title3)
        .foregroundStyle(SupportTheme.textPrimary)
    }

    // MARK: - Text Follow Along

    private var textFollowAlongView: some View {
        ScrollView {
            Text(content.textContent)
                .font(.body)
                .lineSpacing(8)
                .padding(SupportTheme.Spacing.m)
        }
        .frame(maxHeight: 200)
        .background(SupportTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: SupportTheme.controlRadius))
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Actions

    private func toggleFavorite() {
        print("[GeneratedMeditationView] toggleFavorite called, current state: \(isFavorite)")
        isFavorite.toggle()

        Task {
            do {
                let service = GeneratedContentService(supabase: supabase)
                let newState = try await service.toggleFavorite(contentId: content.id)
                print("[GeneratedMeditationView] toggleFavorite succeeded, new state: \(newState)")
            } catch {
                print("[GeneratedMeditationView] toggleFavorite failed: \(error)")
                // Revert on failure
                await MainActor.run {
                    isFavorite.toggle()
                }
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
        VStack(spacing: SupportTheme.Spacing.l) {
            Text("How was this \(content.contentType.displayName.lowercased())?")
                .font(.headline)

            HStack(spacing: SupportTheme.Spacing.xs) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        rating = star
                    } label: {
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.largeTitle)
                            .foregroundStyle(star <= rating ? .yellow : SupportTheme.textSecondary)
                            .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                            .accessibilityLabel("\(star) stars")
                    }
                }
            }

            HStack(spacing: SupportTheme.Spacing.m) {
                Button("Skip") {
                    dismiss()
                }
                .buttonStyle(.supportSecondary)

                Button {
                    submitRating()
                } label: {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Text("Submit")
                    }
                }
                .buttonStyle(.supportPrimary)
                .disabled(rating == 0 || isSubmitting)
            }
        }
        .padding(SupportTheme.Spacing.m)
    }

    private func submitRating() {
        isSubmitting = true

        Task {
            do {
                print("[ContentRatingSheet] Submitting rating \(rating) for content \(content.id)")
                let service = GeneratedContentService(supabase: supabase)
                let response = try await service.rateContent(contentId: content.id, rating: rating)
                print("[ContentRatingSheet] Rating submitted successfully: \(response.message)")
                onRated()
                dismiss()
            } catch {
                print("[ContentRatingSheet] ERROR submitting rating: \(error)")
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
            return [SupportTheme.accent.opacity(0.3), SupportTheme.accent.opacity(0.2)]
        case .sleepStory:
            return [SupportTheme.accent.opacity(0.4), SupportTheme.accent.opacity(0.2)]
        case .breathing:
            return [SupportTheme.accent.opacity(0.3), SupportTheme.accent.opacity(0.2)]
        case .affirmation:
            return [SupportTheme.accent.opacity(0.3), SupportTheme.accent.opacity(0.2)]
        case .grounding:
            return [SupportTheme.accent.opacity(0.3), SupportTheme.accent.opacity(0.2)]
        case .cbt:
            return [SupportTheme.accent.opacity(0.3), SupportTheme.accent.opacity(0.2)]
        case .journaling:
            return [SupportTheme.accent.opacity(0.3), SupportTheme.accent.opacity(0.2)]
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
