import AVFoundation
import Combine
import Foundation

/// ViewModel for managing AVFoundation audio playback for generated wellness content
/// Supports playback speed control, sleep timer with fade-out, and background sound mixing
@MainActor
final class AudioPlayerViewModel: ObservableObject {
    // MARK: - Published State

    @Published private(set) var isLoading = false
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published var error: String?

    @Published var playbackRate: Float = 1.0 {
        didSet {
            player?.rate = isPlaying ? playbackRate : 0
        }
    }

    @Published var sleepTimerMinutes: Int? = nil {
        didSet {
            if let minutes = sleepTimerMinutes {
                startSleepTimer(minutes: minutes)
            } else {
                cancelSleepTimer()
            }
        }
    }

    @Published var sleepTimerRemaining: TimeInterval = 0
    @Published var backgroundSound: BackgroundSoundType? = nil {
        didSet {
            updateBackgroundSound()
        }
    }
    @Published var backgroundSoundVolume: Float = 0.3

    // MARK: - Private Properties

    private var player: AVPlayer?
    private var backgroundPlayer: AVAudioPlayer?
    private var timeObserver: Any?
    private var sleepTimerTask: Task<Void, Never>?
    private var fadeOutTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        setupAudioSession()
    }

    deinit {
        // Note: cleanup() is MainActor isolated, so we do minimal cleanup here
        // The view should call cleanup() in onDisappear
        sleepTimerTask?.cancel()
        fadeOutTask?.cancel()
    }

    // MARK: - Audio Session Setup

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
            try session.setActive(true)

            // Handle interruptions (phone calls, alarms)
            NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
                .sink { [weak self] notification in
                    self?.handleInterruption(notification)
                }
                .store(in: &cancellables)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            pause()
        case .ended:
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    play()
                }
            }
        @unknown default:
            break
        }
    }

    // MARK: - Playback Control

    /// Load audio from URL
    func load(audioURL: URL) async throws {
        isLoading = true
        error = nil

        print("[AudioPlayerViewModel] Loading audio from URL: \(audioURL)")

        // Create asset with options for better error reporting
        let asset = AVURLAsset(url: audioURL, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true
        ])

        // First check if the asset is playable
        do {
            let isPlayable = try await asset.load(.isPlayable)
            print("[AudioPlayerViewModel] Asset isPlayable: \(isPlayable)")

            if !isPlayable {
                print("[AudioPlayerViewModel] ERROR: Asset is not playable")
                self.error = "Audio format not supported"
                isLoading = false
                return
            }
        } catch {
            print("[AudioPlayerViewModel] ERROR checking playability: \(error)")
            self.error = "Failed to load audio: \(error.localizedDescription)"
            isLoading = false
            return
        }

        // Wait for duration to be available
        do {
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            print("[AudioPlayerViewModel] Duration loaded: \(durationSeconds) seconds")
            self.duration = durationSeconds
        } catch {
            print("[AudioPlayerViewModel] ERROR loading duration: \(error)")
            self.duration = 0
        }

        // Create player item and player
        let playerItem = AVPlayerItem(asset: asset)

        // Observe player item status for errors
        playerItem.publisher(for: \.status)
            .sink { [weak self] status in
                Task { @MainActor in
                    switch status {
                    case .failed:
                        let errorMsg = playerItem.error?.localizedDescription ?? "Unknown error"
                        print("[AudioPlayerViewModel] PlayerItem failed: \(errorMsg)")
                        self?.error = "Playback error: \(errorMsg)"
                    case .readyToPlay:
                        print("[AudioPlayerViewModel] PlayerItem ready to play")
                    case .unknown:
                        print("[AudioPlayerViewModel] PlayerItem status unknown")
                    @unknown default:
                        break
                    }
                }
            }
            .store(in: &cancellables)

        player = AVPlayer(playerItem: playerItem)
        player?.actionAtItemEnd = .pause

        print("[AudioPlayerViewModel] Player created successfully")

        // Observe playback end
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: playerItem)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.handlePlaybackEnd()
                }
            }
            .store(in: &cancellables)

        // Setup time observer
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.currentTime = CMTimeGetSeconds(time)
            }
        }

        isLoading = false
    }

    /// Start or resume playback
    func play() {
        player?.rate = playbackRate
        isPlaying = true
        backgroundPlayer?.play()
    }

    /// Pause playback
    func pause() {
        player?.pause()
        isPlaying = false
        backgroundPlayer?.pause()
    }

    /// Seek to a specific time
    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player?.seek(to: cmTime)
    }

    /// Toggle play/pause
    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    /// Skip forward by seconds
    func skipForward(_ seconds: TimeInterval = 15) {
        let newTime = min(currentTime + seconds, duration)
        seek(to: newTime)
    }

    /// Skip backward by seconds
    func skipBackward(_ seconds: TimeInterval = 15) {
        let newTime = max(currentTime - seconds, 0)
        seek(to: newTime)
    }

    /// Cleanup resources
    func cleanup() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        player?.pause()
        player = nil
        backgroundPlayer?.stop()
        backgroundPlayer = nil
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        fadeOutTask?.cancel()
        fadeOutTask = nil
        cancellables.removeAll()
    }

    // MARK: - Sleep Timer

    private func startSleepTimer(minutes: Int) {
        cancelSleepTimer()

        let totalSeconds = TimeInterval(minutes * 60)
        sleepTimerRemaining = totalSeconds

        sleepTimerTask = Task {
            var remaining = totalSeconds

            while remaining > 0 && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                remaining -= 1
                await MainActor.run {
                    sleepTimerRemaining = remaining
                }

                // Start fade-out 30 seconds before timer ends
                if remaining == 30 {
                    await startFadeOut()
                }
            }

            if !Task.isCancelled {
                await MainActor.run {
                    pause()
                    sleepTimerMinutes = nil
                }
            }
        }
    }

    private func cancelSleepTimer() {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        fadeOutTask?.cancel()
        fadeOutTask = nil
        sleepTimerRemaining = 0

        // Reset volume if fade was in progress
        player?.volume = 1.0
    }

    private func startFadeOut() async {
        fadeOutTask = Task {
            let steps = 30 // 30 steps over 30 seconds
            for step in 0..<steps {
                if Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let volume = Float(steps - step - 1) / Float(steps)
                await MainActor.run {
                    player?.volume = volume
                    backgroundPlayer?.volume = volume * backgroundSoundVolume
                }
            }
        }
    }

    // MARK: - Background Sound

    private func updateBackgroundSound() {
        backgroundPlayer?.stop()
        backgroundPlayer = nil

        guard let soundType = backgroundSound, soundType != .silence else {
            return
        }

        // Get audio URL (prefers local bundle, falls back to remote)
        guard let url = soundType.audioUrl else {
            print("[AudioPlayerViewModel] Background sound not available: \(soundType.rawValue)")
            return
        }

        print("[AudioPlayerViewModel] Loading background sound from: \(url)")

        // Use AVAudioPlayer for local files, download for remote
        if soundType.localUrl != nil {
            // Local file - use AVAudioPlayer directly
            do {
                backgroundPlayer = try AVAudioPlayer(contentsOf: url)
                backgroundPlayer?.numberOfLoops = -1 // Loop indefinitely
                backgroundPlayer?.volume = backgroundSoundVolume
                if isPlaying {
                    backgroundPlayer?.play()
                }
            } catch {
                print("[AudioPlayerViewModel] Failed to load local background sound: \(error)")
            }
        } else {
            // Remote file - download to cache first, then play
            Task {
                await loadRemoteBackgroundSound(from: url, for: soundType)
            }
        }
    }

    /// Download and cache remote background sound, then play it
    private func loadRemoteBackgroundSound(from url: URL, for soundType: BackgroundSoundType) async {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BackgroundSounds")

        // Create cache directory if needed
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let cachedFile = cacheDir.appendingPathComponent("\(soundType.rawValue).mp3")

        // Check if already cached
        if FileManager.default.fileExists(atPath: cachedFile.path) {
            await playBackgroundSound(from: cachedFile)
            return
        }

        // Download the file
        do {
            let (tempUrl, _) = try await URLSession.shared.download(from: url)
            try? FileManager.default.removeItem(at: cachedFile)
            try FileManager.default.moveItem(at: tempUrl, to: cachedFile)
            await playBackgroundSound(from: cachedFile)
        } catch {
            print("[AudioPlayerViewModel] Failed to download background sound: \(error)")
        }
    }

    /// Play background sound from a local file URL
    private func playBackgroundSound(from url: URL) async {
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1 // Loop indefinitely
            player.volume = backgroundSoundVolume
            self.backgroundPlayer = player
            if isPlaying {
                player.play()
            }
        } catch {
            print("[AudioPlayerViewModel] Failed to play background sound: \(error)")
        }
    }

    /// Update background sound volume
    func setBackgroundSoundVolume(_ volume: Float) {
        backgroundSoundVolume = max(0, min(1, volume))
        backgroundPlayer?.volume = backgroundSoundVolume
    }

    // MARK: - Playback End

    private func handlePlaybackEnd() {
        isPlaying = false
        currentTime = duration

        // Cancel sleep timer if story ended naturally
        if sleepTimerMinutes != nil {
            cancelSleepTimer()
        }
    }

    // MARK: - Computed Properties

    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    var formattedCurrentTime: String {
        formatTime(currentTime)
    }

    var formattedDuration: String {
        formatTime(duration)
    }

    var formattedSleepTimerRemaining: String {
        formatTime(sleepTimerRemaining)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Supported playback speeds
    static let playbackSpeeds: [Float] = [0.75, 1.0, 1.25, 1.5]

    /// Sleep timer presets in minutes
    static let sleepTimerPresets: [Int?] = [nil, 15, 30, 45, 60]
}

// MARK: - Preview Helpers

#if DEBUG
extension AudioPlayerViewModel {
    static var preview: AudioPlayerViewModel {
        let vm = AudioPlayerViewModel()
        vm.duration = 600
        vm.currentTime = 120
        return vm
    }
}
#endif
