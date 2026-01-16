// MARK: - AudioPlayerService
// Manages audio playback using AVFoundation, background audio, sleep timer, and offline caching

import Foundation
import AVFoundation
import MediaPlayer
import Combine
import Supabase

@MainActor
final class AudioPlayerService: NSObject, ObservableObject {
    private let supabase: SupabaseClient
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()

    @Published private(set) var state = PlaybackState()
    @Published var favorites: Set<String> = []
    @Published var sleepTimer: Timer?
    @Published var sleepTimerRemaining: TimeInterval = 0
    @Published var isOfflineCached: Bool = false

    private var sleepTimerDuration: SleepTimerDuration?
    private var currentSessionId: String?
    private let cacheManager = AudioCacheManager.shared

    init(supabase: SupabaseClient) {
        self.supabase = supabase
        super.init()
        setupAudioSession()
        setupRemoteCommands()
        loadFavorites()
    }

    // MARK: - Audio Session Setup

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }

    // MARK: - Remote Commands (Lock Screen)

    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.play()
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }

        commandCenter.skipForwardCommand.preferredIntervals = [15]
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            self?.seekForward(15)
            return .success
        }

        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            self?.seekBackward(15)
            return .success
        }

        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self?.seek(to: event.positionTime)
            return .success
        }
    }

    // MARK: - Playback Control

    func play(_ track: AudioTrack, context: String = "browse") async {
        state.track = track
        state.isLoading = true
        state.error = nil

        // Record playback start in background
        Task {
            await recordPlaybackStart(track, context: context)
        }

        // Check if offline available
        let audioUrl = cacheManager.getCachedURL(for: track) ?? track.audioUrl

        let asset = AVURLAsset(url: audioUrl)
        playerItem = AVPlayerItem(asset: asset)

        player = AVPlayer(playerItem: playerItem)

        // Observe player item status
        playerItem?.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                switch status {
                case .readyToPlay:
                    self?.state.isLoading = false
                    self?.state.duration = self?.playerItem?.duration.seconds ?? 0
                    self?.player?.play()
                    self?.state.isPlaying = true
                    self?.updateNowPlayingInfo()
                case .failed:
                    self?.state.isLoading = false
                    self?.state.error = .decodingError
                default:
                    break
                }
            }
            .store(in: &cancellables)

        // Observe playback time
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            self?.state.currentTime = time.seconds
            self?.updateNowPlayingInfo()

            // Check for completion (95% played)
            if let duration = self?.state.duration,
               duration > 0,
               time.seconds / duration > 0.95 {
                Task {
                    await self?.recordPlaybackComplete()
                }
            }
        }

        // Observe playback end
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: playerItem)
            .sink { [weak self] _ in
                Task {
                    await self?.handlePlaybackEnd()
                }
            }
            .store(in: &cancellables)

        isOfflineCached = cacheManager.isDownloaded(track)
    }

    func play() {
        player?.play()
        state.isPlaying = true
    }

    func pause() {
        player?.pause()
        state.isPlaying = false
    }

    func togglePlayPause() {
        if state.isPlaying {
            pause()
        } else {
            play()
        }
    }

    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime)
        state.currentTime = time
    }

    func seekForward(_ seconds: TimeInterval) {
        let newTime = min(state.currentTime + seconds, state.duration)
        seek(to: newTime)
    }

    func seekBackward(_ seconds: TimeInterval) {
        let newTime = max(state.currentTime - seconds, 0)
        seek(to: newTime)
    }

    func stop() {
        player?.pause()
        player = nil
        playerItem = nil

        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        timeObserver = nil

        state = PlaybackState()
        cancellables.removeAll()

        clearNowPlayingInfo()
    }

    // MARK: - Sleep Timer

    func setSleepTimer(_ duration: SleepTimerDuration) {
        sleepTimer?.invalidate()
        sleepTimerDuration = duration

        if duration == .endOfTrack {
            // Timer handled by playback end
            return
        }

        let seconds = TimeInterval(duration.minutes * 60)
        sleepTimerRemaining = seconds

        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            self.sleepTimerRemaining -= 1

            if self.sleepTimerRemaining <= 0 {
                timer.invalidate()
                self.fadeOutAndStop()
            }
        }
    }

    func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerRemaining = 0
        sleepTimerDuration = nil
    }

    private func fadeOutAndStop() {
        let fadeSteps = 20
        let fadeInterval = 3.0 / Double(fadeSteps)
        var currentStep = 0

        Timer.scheduledTimer(withTimeInterval: fadeInterval, repeats: true) { [weak self] timer in
            currentStep += 1
            let volume = 1.0 - (Double(currentStep) / Double(fadeSteps))
            self?.player?.volume = Float(volume)

            if currentStep >= fadeSteps {
                timer.invalidate()
                self?.stop()
                self?.player?.volume = 1.0
            }
        }
    }

    // MARK: - Now Playing Info

    private func updateNowPlayingInfo() {
        guard let track = state.track else { return }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyPlaybackDuration: state.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: state.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: state.isPlaying ? 1.0 : 0.0,
        ]

        if let narrator = track.narrator {
            info[MPMediaItemPropertyArtist] = narrator.name
        }

        info[MPMediaItemPropertyMediaType] = MPMediaType.podcast.rawValue

        // Load artwork async
        if let coverUrl = track.coverImageUrl {
            Task {
                if let data = try? await URLSession.shared.data(from: coverUrl).0,
                   let image = UIImage(data: data) {
                    info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                }
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Playback Recording

    private func recordPlaybackStart(_ track: AudioTrack, context: String) async {
        guard let userId = supabase.auth.currentUser?.id else { return }

        let body: [String: Any] = [
            "trackId": track.id,
            "eventType": "start",
            "positionSeconds": 0,
            "source": context,
        ]

        do {
            let response: [String: String] = try await supabase.functions
                .invoke("record-playback", options: .init(body: body))
            currentSessionId = response["playbackSessionId"]
        } catch {
            print("Failed to record playback start: \(error)")
        }
    }

    private func recordPlaybackComplete() async {
        guard let track = state.track else { return }

        let body: [String: Any] = [
            "trackId": track.id,
            "eventType": "complete",
            "positionSeconds": Int(state.currentTime),
            "durationListenedSeconds": Int(state.currentTime),
        ]

        do {
            let _: [String: String] = try await supabase.functions
                .invoke("record-playback", options: .init(body: body))
        } catch {
            print("Failed to record playback complete: \(error)")
        }
    }

    private func handlePlaybackEnd() async {
        await recordPlaybackComplete()

        if let track = state.track, track.isLoopable {
            seek(to: 0)
            play()
        } else {
            stop()
        }
    }

    // MARK: - Favorites

    func isFavorite(_ track: AudioTrack) -> Bool {
        favorites.contains(track.id)
    }

    func toggleFavorite(_ track: AudioTrack) async {
        guard let userId = supabase.auth.currentUser?.id else { return }

        if favorites.contains(track.id) {
            favorites.remove(track.id)
            try? await supabase
                .from("user_audio_favorites")
                .delete()
                .eq("user_id", value: userId)
                .eq("track_id", value: track.id)
                .execute()
        } else {
            favorites.insert(track.id)
            try? await supabase
                .from("user_audio_favorites")
                .insert([
                    "user_id": userId.uuidString,
                    "track_id": track.id,
                ])
                .execute()
        }
    }

    func loadFavorites() {
        guard let userId = supabase.auth.currentUser?.id else { return }

        struct Favorite: Codable {
            let trackId: String
            enum CodingKeys: String, CodingKey {
                case trackId = "track_id"
            }
        }

        Task {
            do {
                let favs: [Favorite] = try await supabase
                    .from("user_audio_favorites")
                    .select("track_id")
                    .eq("user_id", value: userId)
                    .execute()
                    .value

                DispatchQueue.main.async {
                    self.favorites = Set(favs.map { $0.trackId })
                }
            } catch {
                print("Failed to load favorites: \(error)")
            }
        }
    }

    // MARK: - Offline Support

    func downloadForOffline(_ track: AudioTrack) async throws {
        try await cacheManager.download(track)
        isOfflineCached = true
    }

    func removeOfflineDownload(_ track: AudioTrack) throws {
        try cacheManager.delete(track)
        isOfflineCached = false
    }

    func isDownloadedOffline(_ track: AudioTrack) -> Bool {
        cacheManager.isDownloaded(track)
    }

    var totalCacheSize: Int64 {
        cacheManager.totalSize()
    }

    func clearCache() throws {
        try cacheManager.clearAll()
    }
}

// MARK: - Audio Cache Manager

final class AudioCacheManager {
    static let shared = AudioCacheManager()

    private let cacheDirectory: URL
    private let maxCacheSizeBytes: Int64 = 500_000_000  // 500 MB

    init() {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = paths[0].appendingPathComponent("AudioContent")

        try? FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
    }

    func getCachedURL(for track: AudioTrack) -> URL? {
        let localPath = cacheDirectory.appendingPathComponent("\(track.id).\(track.audioFormat)")
        return FileManager.default.fileExists(atPath: localPath.path) ? localPath : nil
    }

    func isDownloaded(_ track: AudioTrack) -> Bool {
        getCachedURL(for: track) != nil
    }

    func download(_ track: AudioTrack) async throws {
        let localPath = cacheDirectory.appendingPathComponent("\(track.id).\(track.audioFormat)")

        if FileManager.default.fileExists(atPath: localPath.path) {
            return  // Already cached
        }

        // Check cache size before download
        if totalSize() + (track.fileSizeBytes ?? 0) > maxCacheSizeBytes {
            evictLRU()
        }

        let (tempURL, _) = try await URLSession.shared.download(from: track.audioUrl)
        try FileManager.default.moveItem(at: tempURL, to: localPath)
    }

    func delete(_ track: AudioTrack) throws {
        let localPath = cacheDirectory.appendingPathComponent("\(track.id).\(track.audioFormat)")
        try FileManager.default.removeItem(at: localPath)
    }

    func totalSize() -> Int64 {
        guard let enumerator = FileManager.default.enumerator(atPath: cacheDirectory.path) else {
            return 0
        }

        var totalSize: Int64 = 0
        for case let file as String in enumerator {
            let filePath = cacheDirectory.appendingPathComponent(file)
            if let size = try? FileManager.default.attributesOfItem(atPath: filePath.path)[.size] as? Int64 {
                totalSize += size
            }
        }
        return totalSize
    }

    func clearAll() throws {
        try FileManager.default.removeItem(at: cacheDirectory)
        try FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
    }

    private func evictLRU() {
        guard let enumerator = FileManager.default.enumerator(atPath: cacheDirectory.path) else {
            return
        }

        var files: [(path: String, modificationDate: Date)] = []

        for case let file as String in enumerator {
            let filePath = cacheDirectory.appendingPathComponent(file)
            if let attrs = try? FileManager.default.attributesOfItem(atPath: filePath.path),
               let modDate = attrs[.modificationDate] as? Date {
                files.append((file, modDate))
            }
        }

        // Sort by modification date (oldest first)
        files.sort { $0.modificationDate < $1.modificationDate }

        // Delete oldest files until we're under 80% capacity
        let targetSize = maxCacheSizeBytes * 80 / 100
        var currentSize = totalSize()

        for file in files {
            if currentSize <= targetSize { break }

            let filePath = cacheDirectory.appendingPathComponent(file.path)
            if let size = try? FileManager.default.attributesOfItem(atPath: filePath.path)[.size] as? Int64 {
                try? FileManager.default.removeItem(at: filePath)
                currentSize -= size
            }
        }
    }
}
