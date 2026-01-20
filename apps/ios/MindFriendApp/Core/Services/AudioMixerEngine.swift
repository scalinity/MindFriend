import Foundation
import AVFoundation
import Combine

/// Audio engine for mixing generated voice content with background sounds
@MainActor
final class AudioMixerEngine: ObservableObject {
    private var voicePlayer: AVPlayer?
    private var backgroundPlayer: AVPlayer?  // Changed from AVAudioPlayer to AVPlayer
    private var backgroundAsset: AVAsset?
    private var backgroundPlayerItem: AVPlayerItem?

    @Published var isPlaying = false
    @Published var voiceVolume: Float = 0.8
    @Published var backgroundVolume: Float = 0.3
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0

    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Setup

    /// Configure voice player with generated audio URL
    func setupVoicePlayer(url: URL) {
        cleanupVoicePlayer()

        let playerItem = AVPlayerItem(url: url)
        voicePlayer = AVPlayer(playerItem: playerItem)

        // Observe duration
        playerItem.publisher(for: \.duration)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] duration in
                self?.duration = duration.seconds.isNaN ? 0 : duration.seconds
            }
            .store(in: &cancellables)

        // Setup time observer
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = voicePlayer?.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            self?.currentTime = time.seconds
        }

        // Handle playback end
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: playerItem)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handlePlaybackEnd()
            }
            .store(in: &cancellables)
    }

    /// Load background sound from bundled or remote audio
    func loadBackgroundSound(named soundName: String) {
        cleanupBackgroundPlayer()

        // Try to load from bundle first
        if let url = Bundle.main.url(forResource: soundName, withExtension: "mp3") {
            loadBackgroundSoundFrom(url: url, isLoopable: true)
            return
        }

        // Try to load from common background sound names
        let remoteURLs: [String: URL?] = [
            "rain": URL(string: "https://assets.mindfriend.app/audio/background/rain.mp3"),
            "ocean": URL(string: "https://assets.mindfriend.app/audio/background/ocean.mp3"),
            "forest": URL(string: "https://assets.mindfriend.app/audio/background/forest.mp3"),
            "fireplace": URL(string: "https://assets.mindfriend.app/audio/background/fireplace.mp3"),
            "white_noise": URL(string: "https://assets.mindfriend.app/audio/background/whitenoise.mp3"),
        ]

        if let soundURL = remoteURLs[soundName], let url = soundURL {
            loadBackgroundSoundFrom(url: url, isLoopable: true)
        }
    }

    /// Load background sound from URL
    private func loadBackgroundSoundFrom(url: URL, isLoopable: Bool) {
        do {
#if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
#endif
            backgroundAsset = AVAsset(url: url)
            backgroundPlayerItem = AVPlayerItem(asset: backgroundAsset!)
            backgroundPlayer = AVPlayer(playerItem: backgroundPlayerItem!)

            if isLoopable {
                backgroundPlayer?.actionAtItemEnd = .none
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(backgroundPlayerDidFinishPlaying),
                    name: .AVPlayerItemDidPlayToEndTime,
                    object: backgroundPlayerItem
                )
            }
        } catch {
            print("Failed to load background sound: \(error)")
        }
    }

    @objc private func backgroundPlayerDidFinishPlaying() {
        backgroundPlayer?.seek(to: .zero)
        if isPlaying {
            backgroundPlayer?.play()
        }
    }

    // MARK: - Playback Control

    /// Start playback of both voice and background
    func play() {
        voicePlayer?.play()
        backgroundPlayer?.play()
        isPlaying = true
    }

    /// Pause playback
    func pause() {
        voicePlayer?.pause()
        backgroundPlayer?.pause()
        isPlaying = false
    }

    /// Toggle play/pause
    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    /// Stop all playback
    func stop() {
        pause()
        voicePlayer?.seek(to: .zero)
        backgroundPlayer?.seek(to: .zero)
        currentTime = 0
    }

    /// Seek to specific time
    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        voicePlayer?.seek(to: cmTime)
    }

    /// Skip forward/backward
    func skip(seconds: Double) {
        let newTime = max(0, min(duration, currentTime + seconds))
        seek(to: newTime)
    }

    /// Set playback rate
    func setRate(_ rate: Float) {
        voicePlayer?.rate = rate
    }

    // MARK: - Volume Control

    /// Update voice volume
    func setVoiceVolume(_ volume: Float) {
        voiceVolume = max(0, min(1, volume))
    }

    /// Update background volume
    func setBackgroundVolume(_ volume: Float) {
        backgroundVolume = max(0, min(1, volume))
        backgroundPlayer?.volume = backgroundVolume
    }

    // MARK: - Private

    private func handlePlaybackEnd() {
        // Loop voice if it finished (for short content)
        voicePlayer?.seek(to: .zero)
        if isPlaying {
            voicePlayer?.play()
        }
    }

    private func cleanupVoicePlayer() {
        if let observer = timeObserver {
            voicePlayer?.removeTimeObserver(observer)
            timeObserver = nil
        }
        cancellables.removeAll()
        voicePlayer?.pause()
        voicePlayer = nil
    }

    private func cleanupBackgroundPlayer() {
        backgroundPlayer?.pause()
        if let playerItem = backgroundPlayerItem {
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: playerItem)
        }
        backgroundPlayer = nil
        backgroundPlayerItem = nil
        backgroundAsset = nil
    }

    deinit {
        if let observer = timeObserver {
            voicePlayer?.removeTimeObserver(observer)
        }
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Audio Session Helper

enum AudioSessionHelper {
    /// Configure audio session for voice playback with background sounds
    static func configureForPlayback() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }

    /// Configure audio session for ambient/background playback
    static func configureForBackground() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default)
            try session.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }
}

// MARK: - Sound File Downloader

/// Manages downloading and caching background sound files
actor BackgroundSoundCache {
    static let shared = BackgroundSoundCache()

    private var cachedURLs: [String: URL] = [:]
    private let fileManager = FileManager.default

    private var cacheDirectory: URL {
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("BackgroundSounds", isDirectory: true)
    }

    private init() {
        createCacheDirectoryIfNeeded()
    }

    private func createCacheDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }

    /// Get cached sound URL or download if not cached
    func getSoundURL(for name: String) async -> URL? {
        // Check memory cache
        if let url = cachedURLs[name] {
            return url
        }

        let fileURL = cacheDirectory.appendingPathComponent("\(name).mp3")

        // Check file system
        if fileManager.fileExists(atPath: fileURL.path) {
            cachedURLs[name] = fileURL
            return fileURL
        }

        // Download
        let remoteURLs: [String: URL] = [
            "rain": URL(string: "https://assets.mindfriend.app/audio/background/rain.mp3")!,
            "ocean": URL(string: "https://assets.mindfriend.app/audio/background/ocean.mp3")!,
            "forest": URL(string: "https://assets.mindfriend.app/audio/background/forest.mp3")!,
            "fireplace": URL(string: "https://assets.mindfriend.app/audio/background/fireplace.mp3")!,
            "white_noise": URL(string: "https://assets.mindfriend.app/audio/background/whitenoise.mp3")!,
        ]

        guard let downloadURL = remoteURLs[name] else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: downloadURL)
            try data.write(to: fileURL)
            cachedURLs[name] = fileURL
            return fileURL
        } catch {
            print("Failed to download background sound \(name): \(error)")
            return nil
        }
    }

    /// Clear all cached sounds
    func clearCache() {
        try? fileManager.removeItem(at: cacheDirectory)
        cachedURLs.removeAll()
    }

    /// Get total cache size in bytes
    func getCacheSize() async throws -> Int64 {
        var totalSize: Int64 = 0

        if let enumerator = fileManager.enumerator(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                let fileAttributes = try fileManager.attributesOfItem(atPath: fileURL.path)
                if let size = fileAttributes[.size] as? Int64 {
                    totalSize += size
                }
            }
        }

        return totalSize
    }
}
