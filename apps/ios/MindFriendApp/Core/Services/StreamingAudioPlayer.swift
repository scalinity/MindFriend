import Foundation
import AVFoundation
import Combine

/// Streaming audio player with progressive download support
@MainActor
final class StreamingAudioPlayer: ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var isPlaying = false
    @Published private(set) var isLoading = false
    @Published private(set) var isBuffering = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var bufferedTime: TimeInterval = 0
    @Published private(set) var playbackRate: Float = 1.0
    @Published private(set) var error: String?
    @Published var volume: Float = 1.0

    // MARK: - Private Properties

    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var bufferObserver: NSKeyValueObservation?
    private var cancellables = Set<AnyCancellable>()

    private let prefetchQueue = DispatchQueue(label: "com.mindfriend.prefetch", qos: .utility)
    private var prefetchTask: Task<Void, Never>?

    // MARK: - Configuration

    /// Minimum buffer duration before allowing playback (seconds)
    private var minBufferDuration: TimeInterval = 5.0

    /// Preferred buffer duration for smooth playback (seconds)
    private var preferredBufferDuration: TimeInterval = 15.0

    // MARK: - Setup

    /// Load audio from URL with streaming support
    func load(url: URL, prefetch: Bool = true) {
        cleanup()
        isLoading = true
        error = nil

        // Create player item
        let asset = AVURLAsset(url: url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: true
        ])

        playerItem = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: playerItem)

        setupObservers()

        // Prefetch if requested
        if prefetch {
            prefetchContent()
        }
    }

    /// Load audio with custom prefetch settings
    func load(url: URL, prefetch: Bool, minBuffer: TimeInterval, preferredBuffer: TimeInterval) {
        minBufferDuration = minBuffer
        preferredBufferDuration = preferredBuffer
        load(url: url, prefetch: prefetch)
    }

    // MARK: - Playback Control

    func play() {
        guard let player = player else { return }

        // Wait for minimum buffer
        if bufferedTime < minBufferDuration && isBuffering {
            return
        }

        player.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func stop() {
        pause()
        seek(to: 0)
    }

    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
    }

    func skip(seconds: Double) {
        let newTime = max(0, min(duration, currentTime + seconds))
        seek(to: newTime)
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        player?.rate = rate
    }

    // MARK: - Private Methods

    private func setupObservers() {
        guard let playerItem = playerItem, let player = player else { return }

        // Time observer
        let interval = CMTime(seconds: 0.25, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            self?.currentTime = time.seconds
        }

        // Status observer
        statusObserver = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                self?.handleStatusChange(item.status)
            }
        }

        // Buffer observer
        bufferObserver = playerItem.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                self?.isBuffering = item.isPlaybackBufferEmpty
            }
        }

        // Playback end notification
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: playerItem)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handlePlaybackEnd()
            }
            .store(in: &cancellables)

        // Loaded time range observer for buffering progress
        playerItem.publisher(for: \.loadedTimeRanges)
            .receive(on: DispatchQueue.main)
            .compactMap { ranges -> TimeInterval? in
                guard let range = ranges.first?.timeRangeValue else { return nil }
                return CMTimeGetSeconds(range.start) + CMTimeGetSeconds(range.duration)
            }
            .sink { [weak self] buffered in
                self?.bufferedTime = buffered
            }
            .store(in: &cancellables)
    }

    private func handleStatusChange(_ status: AVPlayerItem.Status) {
        switch status {
        case .readyToPlay:
            isLoading = false
            if let duration = playerItem?.duration.seconds, !duration.isNaN {
                self.duration = duration
            }
        case .failed:
            isLoading = false
            error = playerItem?.error?.localizedDescription ?? "Failed to load audio"
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    private func handlePlaybackEnd() {
        isPlaying = false
        seek(to: 0)
    }

    private func prefetchContent() {
        prefetchTask?.cancel()
        prefetchTask = Task {
            await prefetchAsset()
        }
    }

    private func prefetchAsset() async {
        guard playerItem != nil else { return }
        // AVPlayerItem doesn't have a public cancelLoading API
        // Prefetching is handled automatically by AVFoundation
    }

    private func cleanup() {
        prefetchTask?.cancel()
        prefetchTask = nil

        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }

        statusObserver?.invalidate()
        statusObserver = nil

        bufferObserver?.invalidate()
        bufferObserver = nil

        cancellables.removeAll()

        player?.pause()
        player = nil
        playerItem = nil

        isPlaying = false
        isLoading = false
        isBuffering = false
        currentTime = 0
        duration = 0
        bufferedTime = 0
    }

    deinit {
        Task { @MainActor in
            cleanup()
        }
    }
}

// MARK: - Voice Preview Player

/// Dedicated player for voice preview samples
@MainActor
final class VoicePreviewPlayer: ObservableObject {
    static let shared = VoicePreviewPlayer()

    @Published private(set) var isPlaying = false
    @Published private(set) var currentVoiceId: String?
    @Published private(set) var progress: Double = 0

    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var currentURL: URL?

    private init() {}

    /// Play a voice preview (simple interface using basic types)
    func playPreview(
        id: String,
        previewUrl: String?,
        sampleText: String?
    ) {
        if let previewUrl = previewUrl, let url = URL(string: previewUrl) {
            play(url: url, voiceId: id)
        } else if let sampleText = sampleText {
            playTTSPreview(id: id, sampleText: sampleText)
        }
    }

    /// Play TTS-generated preview as fallback
    private func playTTSPreview(id: String, sampleText: String) {
        // Generate TTS preview URL (ElevenLabs TTS endpoint with sample text)
        let encodedText = sampleText.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) ?? sampleText
        let ttsUrl = "https://api.elevenlabs.io/v1/text-to-speech/\(id)?output_format=mp3_44100&text=\(encodedText)&voice_settings={\"stability\":0.5,\"similarity_boost\":0.8}"

        guard let url = URL(string: ttsUrl) else { return }
        play(url: url, voiceId: id)
    }

    private func play(url: URL, voiceId: String) {
        stop()

        currentURL = url
        currentVoiceId = voiceId

        playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem!)

        // Setup time observer
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self = self,
                      let duration = self.player?.currentItem?.duration,
                      duration.seconds > 0 else { return }
                self.progress = time.seconds / duration.seconds
            }
        }

        // Handle completion
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handlePlaybackEnd()
            }
        }

        player?.play()
        isPlaying = true
    }

    func stop() {
        player?.pause()
        player = nil
        playerItem = nil

        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }

        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: playerItem)

        isPlaying = false
        currentVoiceId = nil
        progress = 0
    }

    private func handlePlaybackEnd() {
        stop()
    }

    deinit {
        Task { @MainActor in
            stop()
        }
    }
}
