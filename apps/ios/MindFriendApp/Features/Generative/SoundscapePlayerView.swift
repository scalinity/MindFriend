import SwiftUI
import AVFoundation

/// Player view for standalone soundscape playback
struct SoundscapePlayerView: View {
    let soundscape: BackgroundSoundType
    @Environment(\.dismiss) private var dismiss
    @StateObject private var audioPlayer = SoundscapeAudioPlayer()
    @State private var volume: Double = 0.7

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Soundscape icon and info
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(soundscape.themeColor.opacity(0.2))
                        .frame(width: 160, height: 160)

                    Circle()
                        .fill(soundscape.themeColor.opacity(0.1))
                        .frame(width: 200, height: 200)
                        .scaleEffect(audioPlayer.isPlaying ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: audioPlayer.isPlaying)

                    Image(systemName: soundscape.icon)
                        .font(.system(size: 64))
                        .foregroundStyle(soundscape.themeColor)
                }

                Text(soundscape.displayName)
                    .font(.title)
                    .fontWeight(.semibold)

                Text(soundscapeDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            // Volume control
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "speaker.fill")
                        .foregroundStyle(.secondary)
                    Slider(value: $volume, in: 0...1)
                        .tint(soundscape.themeColor)
                        .onChange(of: volume) { _, newValue in
                            audioPlayer.setVolume(Float(newValue))
                        }
                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 32)
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
                        .fill(soundscape.themeColor)
                        .frame(width: 80, height: 80)

                    Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                        .offset(x: audioPlayer.isPlaying ? 0 : 2)
                }
            }
            .padding(.bottom, 32)

            // Loop indicator
            HStack(spacing: 8) {
                Image(systemName: "repeat")
                    .foregroundStyle(soundscape.themeColor)
                Text("Loops continuously")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
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
