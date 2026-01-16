import SwiftUI
import MediaPlayer

/// Full-screen audio player view with controls, progress, and sleep timer
struct AudioPlayerView: View {
    let track: AudioTrack

    @EnvironmentObject private var container: DependencyContainer
    @ObservedObject private var playerService: AudioPlayerService

    @Environment(\.dismiss) private var dismiss
    @State private var showSleepTimerMenu = false
    @State private var showNarratorInfo = false
    @State private var isFavorite = false

    init(track: AudioTrack) {
        self.track = track
        // Note: playerService is injected via environmentObject in parent
        _playerService = ObservedObject(initialValue: AudioPlayerService(supabase: SupabaseClient(
            supabaseURL: URL(string: "https://localhost:54321")!,
            supabaseKey: "example-key"
        )))
    }

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.2),
                    Color(.systemBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                headerView

                Spacer()

                // Cover art
                VStack(spacing: 40) {
                    coverArtView

                    // Track info
                    trackInfoView

                    // Progress and time
                    progressView
                }
                .padding(.horizontal, 20)

                Spacer()

                // Controls
                controlsView

                // Sleep timer status
                if let remaining = getSleepTimerDisplay() {
                    sleepTimerStatusView(remaining)
                }
            }
        }
        .task {
            await playerService.play(track, context: "player")
            isFavorite = playerService.isFavorite(track)
        }
        .onDisappear {
            // Keep playing when view dismisses
        }
    }

    // MARK: - Components

    private var headerView: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 16, weight: .semibold))
            }

            Spacer()

            Text("Now Playing")
                .font(.subheadline)
                .fontWeight(.semibold)

            Spacer()

            Menu {
                Button(action: { showNarratorInfo = true }) {
                    Label("Narrator Info", systemImage: "person.circle")
                }

                Button(action: { Task { await toggleFavorite() } }) {
                    Label(isFavorite ? "Remove from Favorites" : "Add to Favorites",
                          systemImage: isFavorite ? "heart.fill" : "heart")
                }

                Button(role: .destructive, action: { playerService.stop() }) {
                    Label("Stop Playback", systemImage: "stop.circle")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
            }
        }
        .padding()
        .background(Color(.systemBackground).opacity(0.8))
        .sheet(isPresented: $showNarratorInfo) {
            narratorInfoSheet
        }
    }

    private var coverArtView: some View {
        ZStack {
            if let coverUrl = track.coverImageUrl {
                AsyncImage(url: coverUrl) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Image(systemName: "music.note")
                            .font(.system(size: 60))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(.tertiary))
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 60))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.tertiary))
            }
        }
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(radius: 20)
    }

    private var trackInfoView: some View {
        VStack(spacing: 12) {
            Text(track.title)
                .font(.title2)
                .fontWeight(.bold)
                .lineLimit(2)

            if let narrator = track.narrator {
                HStack(spacing: 8) {
                    if let avatarUrl = narrator.avatarUrl {
                        AsyncImage(url: avatarUrl) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 32, height: 32)
                                    .clipShape(Circle())
                            default:
                                Image(systemName: "person.circle")
                                    .font(.system(size: 32))
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Narrator")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(narrator.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }

                    Spacer()

                    Button(action: { showNarratorInfo = true }) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.blue)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            if let description = track.description {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
    }

    private var progressView: some View {
        VStack(spacing: 12) {
            // Progress bar
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.tertiarySystemBackground))
                    .frame(height: 4)

                Capsule()
                    .fill(Color.blue)
                    .frame(width: CGFloat(playerService.state.progress) * 280, height: 4)
            }
            .frame(height: 4)
            .gesture(
                DragGesture()
                    .onEnded { value in
                        let width = 280.0
                        let percentage = Double(value.location.x / width)
                        let newTime = percentage * playerService.state.duration
                        playerService.seek(to: newTime)
                    }
            )

            // Time display
            HStack {
                Text(playerService.state.formattedCurrentTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Spacer()

                Text(playerService.state.formattedRemainingTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var controlsView: some View {
        VStack(spacing: 20) {
            // Playback controls
            HStack(spacing: 40) {
                Button(action: { playerService.seekBackward(15) }) {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 24))
                        .foregroundStyle(.blue)
                }
                .accessibilityLabel("Rewind 15 seconds")

                Button(action: { playerService.togglePlayPause() }) {
                    Image(systemName: playerService.state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.blue)
                }
                .accessibilityLabel(playerService.state.isPlaying ? "Pause" : "Play")

                Button(action: { playerService.seekForward(15) }) {
                    Image(systemName: "goforward.15")
                        .font(.system(size: 24))
                        .foregroundStyle(.blue)
                }
                .accessibilityLabel("Skip forward 15 seconds")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            // Sleep timer and more options
            HStack(spacing: 12) {
                Menu {
                    ForEach(SleepTimerDuration.allCases, id: \.self) { duration in
                        Button(action: { playerService.setSleepTimer(duration) }) {
                            Label(duration.displayName, systemImage: "timer")
                        }
                    }

                    if playerService.sleepTimer != nil {
                        Divider()
                        Button(role: .destructive, action: { playerService.cancelSleepTimer() }) {
                            Label("Cancel Timer", systemImage: "xmark")
                        }
                    }
                } label: {
                    Image(systemName: "timer")
                        .font(.system(size: 18))
                        .foregroundStyle(.blue)
                        .frame(width: 44, height: 44)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Sleep timer")

                Spacer()

                // Playback speed control
                Menu {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5], id: \.self) { speed in
                        Button(action: {
                            // TODO: Implement playback speed control in AVPlayer
                        }) {
                            Text("\(String(format: "%.2f", speed))x")
                        }
                    }
                } label: {
                    Text("1x")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Playback speed")

                Button(action: { Task { await toggleFavorite() } }) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 18))
                        .foregroundStyle(isFavorite ? .red : .blue)
                        .frame(width: 44, height: 44)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Circle())
                }
                .accessibilityLabel(isFavorite ? "Favorited" : "Add to favorites")
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 20)
        .background(Color(.systemBackground).opacity(0.8))
    }

    @ViewBuilder
    private func sleepTimerStatusView(_ remaining: String) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "timer")
                    .font(.caption)
                    .foregroundStyle(.blue)

                Text("Sleep Timer: \(remaining)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: { playerService.cancelSleepTimer() }) {
                    Text("Cancel")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
        }
        .padding()
    }

    @ViewBuilder
    private var narratorInfoSheet: some View {
        if let narrator = track.narrator {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Avatar
                        if let avatarUrl = narrator.avatarUrl {
                            AsyncImage(url: avatarUrl) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(height: 200)
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                case .failure:
                                    Image(systemName: "person.crop.circle")
                                        .font(.system(size: 60))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 200)
                                        .background(Color(.tertiary))
                                default:
                                    ProgressView()
                                        .frame(height: 200)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text(narrator.name)
                                .font(.title2)
                                .fontWeight(.bold)

                            if let style = narrator.voiceStyle {
                                Label(style.capitalized, systemImage: "speaker.wave.2")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let bio = narrator.bio {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("About")
                                    .font(.headline)

                                Text(bio)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()
                    }
                    .padding()
                }
                .navigationTitle("Narrator")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    // MARK: - Helpers

    private func getSleepTimerDisplay() -> String? {
        guard playerService.sleepTimerRemaining > 0 else { return nil }

        let minutes = Int(playerService.sleepTimerRemaining) / 60
        let seconds = Int(playerService.sleepTimerRemaining) % 60

        if minutes > 0 {
            return "\(minutes):\(String(format: "%02d", seconds))"
        } else {
            return "\(seconds)s"
        }
    }

    private func toggleFavorite() async {
        await container.audioPlayerService.toggleFavorite(track)
        isFavorite.toggle()
    }
}

// MARK: - Preview

#Preview {
    AudioPlayerView(track: AudioTrack(
        id: "preview-1",
        title: "Calm Meditation",
        slug: "calm-meditation",
        description: "A soothing meditation for relaxation",
        category: .meditation,
        subcategory: nil,
        tags: ["relaxation", "sleep"],
        audioUrl: URL(string: "https://example.com/audio.mp3")!,
        duration: 600,
        audioFormat: "mp3",
        audioQuality: "high",
        fileSizeBytes: 15000000,
        previewUrl: nil,
        coverImageUrl: URL(string: "https://via.placeholder.com/400")!,
        backgroundImageUrl: nil,
        primaryColor: nil,
        secondaryColor: nil,
        narrator: Narrator(
            id: "narrator-1",
            name: "Sarah Lee",
            slug: "sarah-lee",
            bio: "Experienced meditation guide",
            avatarUrl: URL(string: "https://via.placeholder.com/100")!,
            voiceType: "female",
            voiceGender: "female",
            voiceStyle: "calm"
        ),
        creatorType: .professional,
        language: "en",
        isLoopable: true,
        hasBackgroundMusic: true,
        energyLevel: .calming,
        isPremium: false,
        isFeatured: true,
        playCount: 1500,
        completionCount: 800,
        averageRating: 4.8,
        ratingCount: 500
    ))
    .environmentObject(DependencyContainer())
}
