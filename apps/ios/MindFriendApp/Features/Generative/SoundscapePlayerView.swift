import SwiftUI
import AVFoundation

/// Player view for standalone soundscape playback
struct SoundscapePlayerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let soundscape: BackgroundSoundType
    @Environment(\.dismiss) private var dismiss
    @StateObject private var audioPlayer = SoundscapeAudioPlayer()
    @State private var volume: Double = 0.7

    var body: some View {
        VStack(spacing: SupportTheme.Spacing.xl) {
            Spacer()

            // Soundscape icon and info
            VStack(spacing: SupportTheme.Spacing.m) {
                ZStack {
                    Circle()
                        .fill(SupportTheme.accent.opacity(0.2))
                        .frame(width: 160, height: 160)

                    Circle()
                        .fill(SupportTheme.accent.opacity(0.1))
                        .frame(width: 200, height: 200)
                        .scaleEffect(reduceMotion ? 1 : (audioPlayer.isPlaying ? 1.1 : 1.0))
                        .animation(reduceMotion ? nil : .easeInOut(duration: 2).repeatForever(autoreverses: true), value: audioPlayer.isPlaying)

                    Image(systemName: soundscape.icon)
                        .font(.system(.largeTitle))
                        .foregroundStyle(SupportTheme.accent)
                }

                Text(soundscape.displayName)
                    .font(.title)
                    .fontWeight(.semibold)

                Text(soundscapeDescription)
                    .font(.subheadline)
                    .foregroundStyle(SupportTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, SupportTheme.Spacing.xl)
            }

            Spacer()

            // Volume control
            VStack(spacing: SupportTheme.Spacing.xs) {
                HStack {
                    Image(systemName: "speaker.fill")
                        .foregroundStyle(SupportTheme.textSecondary)
                    Slider(value: $volume, in: 0...1)
                        .tint(SupportTheme.accent)
                        .onChange(of: volume) { _, newValue in
                            audioPlayer.setVolume(Float(newValue))
                        }
                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundStyle(SupportTheme.textSecondary)
                }
                .padding(.horizontal, SupportTheme.Spacing.xl)
            }

            // Play/Pause button
            Button {
                if audioPlayer.isPlaying {
                    audioPlayer.pause()
                } else {
                    audioPlayer.play(soundscape: soundscape, volume: Float(volume))
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(SupportTheme.accent)
                        .frame(width: 80, height: 80)

                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title)
                        .foregroundStyle(SupportTheme.textPrimary)
                        .offset(x: audioPlayer.isPlaying ? 0 : 2)
                }
                .frame(minWidth: SupportTheme.minimumTarget, minHeight: SupportTheme.minimumTarget)
                .accessibilityLabel(audioPlayer.isPlaying ? "Pause" : "Play")
            }
            .padding(.bottom, SupportTheme.Spacing.xl)

            // Loop indicator
            HStack(spacing: SupportTheme.Spacing.xs) {
                Image(systemName: "repeat")
                    .foregroundStyle(SupportTheme.accent)
                Text("Loops continuously")
                    .font(.footnote)
                    .foregroundStyle(SupportTheme.textSecondary)
            }

            Spacer()
        }
        .supportScreen()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    audioPlayer.stop()
                    dismiss()
                }
            }
        }
        .onDisappear {
            audioPlayer.stop()
        }
    }

    private var soundscapeDescription: String {
        switch soundscape {
        case .rain:
            return "Gentle rain sounds to help you relax and unwind"
        case .ocean:
            return "Calming ocean waves washing onto the shore"
        case .forest:
            return "Peaceful forest ambience with birds and rustling leaves"
        case .fireplace:
            return "Warm crackling fireplace for a cozy atmosphere"
        case .whiteNoise:
            return "Consistent white noise to mask distractions"
        case .brownNoise:
            return "Deep, low-frequency noise for better sleep"
        case .pinkNoise:
            return "Balanced noise scientifically shown to improve sleep"
        case .silence:
            return "No background sound"
        }
    }
}

// MARK: - Soundscape Audio Player

@MainActor
class SoundscapeAudioPlayer: ObservableObject {
    @Published var isPlaying = false
    @Published var isLoading = false

    private var audioPlayer: AVAudioPlayer?
    private var currentSoundscape: BackgroundSoundType?

    func play(soundscape: BackgroundSoundType, volume: Float) {
        guard soundscape != .silence else { return }

        // If same soundscape, just resume
        if currentSoundscape == soundscape, let player = audioPlayer {
            player.play()
            isPlaying = true
            return
        }

        // Load new soundscape
        currentSoundscape = soundscape
        isLoading = true

        Task {
            await loadAndPlay(soundscape: soundscape, volume: volume)
        }
    }

    private func loadAndPlay(soundscape: BackgroundSoundType, volume: Float) async {
        guard let url = soundscape.audioUrl else {
            isLoading = false
            return
        }

        do {
            // Configure audio session
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)

            // Check if it's a remote URL that needs downloading
            if soundscape.localUrl == nil, let remoteUrl = soundscape.remoteUrl {
                // Download to cache first
                let cachedUrl = try await downloadToCache(url: remoteUrl, soundscape: soundscape)
                audioPlayer = try AVAudioPlayer(contentsOf: cachedUrl)
            } else {
                audioPlayer = try AVAudioPlayer(contentsOf: url)
            }

            audioPlayer?.numberOfLoops = -1 // Loop indefinitely
            audioPlayer?.volume = volume
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()

            isPlaying = true
            isLoading = false
        } catch {
            print("Failed to play soundscape: \(error)")
            isLoading = false
        }
    }

    private func downloadToCache(url: URL, soundscape: BackgroundSoundType) async throws -> URL {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let cachedFile = cacheDir.appendingPathComponent("soundscape_\(soundscape.rawValue).mp3")

        // Use cached file if it exists
        if FileManager.default.fileExists(atPath: cachedFile.path) {
            return cachedFile
        }

        // Download the file
        let (data, _) = try await URLSession.shared.data(from: url)
        try data.write(to: cachedFile)
        return cachedFile
    }

    func pause() {
        audioPlayer?.pause()
        isPlaying = false
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        currentSoundscape = nil
    }

    func setVolume(_ volume: Float) {
        audioPlayer?.volume = volume
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Rain") {
    NavigationStack {
        SoundscapePlayerView(soundscape: .rain)
    }
}

#Preview("Fireplace (Premium)") {
    NavigationStack {
        SoundscapePlayerView(soundscape: .fireplace)
    }
}
#endif
