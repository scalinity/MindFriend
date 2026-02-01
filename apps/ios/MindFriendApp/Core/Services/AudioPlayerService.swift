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
    @Published var isLoopingEnabled: Bool = false

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
    
    // PERF-CRIT-002: Clean up resources
    // Note: Since this is @MainActor, cleanup happens via stop() method
    // which is called when view disappears. The nonisolated deinit
    // cannot safely access MainActor properties.
    
    /// Call this method to clean up all resources when the service is no longer needed
    func cleanup() {
        // Cancel sleep timer
        sleepTimer?.invalidate()
        sleepTimer = nil
        
        // Remove time observer
        if let observer = timeObserver, let player = player {
            player.removeTimeObserver(observer)
        }
        timeObserver = nil
        
        // Cancel Combine subscriptions
        cancellables.removeAll()
        
        // Stop playback
        player?.pause()
        player = nil
        playerItem = nil
    }

    // MARK: - Audio Session Setup

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            Log.media.error("Audio session setup failed", error: error)
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
        state.currentTrack = track
        state.isBuffering = true
        state.error = nil

        // Record playback start in background
        Task {
            await recordPlaybackStart(track, context: context)
        }

        // Check if offline available
        guard let audioUrl = cacheManager.getCachedURL(for: track) ?? URL(string: track.audioUrl) else {
            state.error = "Invalid audio URL"
            return
        }

        let asset = AVURLAsset(url: audioUrl)
        playerItem = AVPlayerItem(asset: asset)

        player = AVPlayer(playerItem: playerItem)

        // Observe player item status
        playerItem?.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                switch status {
                case .readyToPlay:
                    self?.state.isBuffering = false
                    self?.state.duration = self?.playerItem?.duration.seconds ?? 0
                    self?.player?.play()
                    self?.state.isPlaying = true
                    self?.updateNowPlayingInfo()
                case .failed:
                    if let itemError = self?.playerItem?.error {
                        self?.state.error = "Failed to load audio: \(itemError.localizedDescription)"
                    } else {
                        self?.state.error = "Failed to load audio"
                    }
                    self?.state.isBuffering = false
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

    func setPlaybackSpeed(_ speed: Float) {
        player?.rate = speed
        state.playbackRate = speed
    }

    // MARK: - Sleep Timer

    func setSleepTimer(_ duration: SleepTimerDuration) {
        sleepTimer?.invalidate()
        sleepTimerDuration = duration

        if duration == .endOfTrack {
            // Timer handled by playback end
            return
        }

        let seconds = TimeInterval(duration.rawValue * 60)
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
        fadeOutAndStopWithDuration(3.0)
    }

    /// Fade out and stop with configurable duration
    /// - Parameter duration: Fade duration in seconds (default 3, sleep uses 30)
    /// - Parameter completion: Optional completion handler called when fade finishes
    func fadeOutAndStopWithDuration(_ duration: TimeInterval, completion: (() -> Void)? = nil) {
        let fadeSteps = max(20, Int(duration * 2)) // 2 steps per second for smooth fade
        let fadeInterval = duration / Double(fadeSteps)
        var currentStep = 0

        isSleepFading = true

        Timer.scheduledTimer(withTimeInterval: fadeInterval, repeats: true) { [weak self] timer in
            currentStep += 1
            // Use quadratic fade curve for more natural audio perception
            let progress = Double(currentStep) / Double(fadeSteps)
            let volume = Float(pow(1.0 - progress, 2))
            self?.player?.volume = volume

            if currentStep >= fadeSteps {
                timer.invalidate()
                self?.isSleepFading = false
                self?.stop()
                self?.player?.volume = 1.0
                completion?()
            }
        }
    }

    /// Whether a sleep fade is currently in progress
    private(set) var isSleepFading: Bool = false

    /// Cancel an in-progress sleep fade and stop immediately
    func cancelSleepFade() {
        isSleepFading = false
        stop()
        player?.volume = 1.0
    }

    // MARK: - Now Playing Info

    private func updateNowPlayingInfo() {
        guard let track = state.currentTrack else { return }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyPlaybackDuration: state.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: state.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: state.isPlaying ? 1.0 : 0.0,
        ]

        if let authorName = track.authorName {
            info[MPMediaItemPropertyArtist] = authorName
        }

        info[MPMediaItemPropertyMediaType] = MPMediaType.podcast.rawValue

        if let imageUrl = track.imageUrl, let url = URL(string: imageUrl) {
            Task {
                if let data = try? await URLSession.shared.data(from: url).0,
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
        // Ensure we have a valid session before making authenticated API calls
        guard let _ = try? await supabase.auth.session,
              let userId = supabase.auth.currentUser?.id else { return }

        let body: [String: AudioPlayerServiceAnyEncodable] = [
            "trackId": AudioPlayerServiceAnyEncodable(track.id),
            "eventType": AudioPlayerServiceAnyEncodable("start"),
            "positionSeconds": AudioPlayerServiceAnyEncodable(0),
            "source": AudioPlayerServiceAnyEncodable(context),
        ]

        do {
            let response: [String: String] = try await supabase.functions
                .invoke("record-playback", options: .init(body: body))
            currentSessionId = response["playbackSessionId"]
        } catch {
            Log.media.error("Failed to record playback start", error: error)
        }
    }

    private func recordPlaybackComplete() async {
        guard let track = state.currentTrack else { return }
        
        // Ensure we have a valid session before making authenticated API calls
        guard let _ = try? await supabase.auth.session else { return }

        let body: [String: AudioPlayerServiceAnyEncodable] = [
            "trackId": AudioPlayerServiceAnyEncodable(track.id),
            "eventType": AudioPlayerServiceAnyEncodable("complete"),
            "positionSeconds": AudioPlayerServiceAnyEncodable(Int(state.currentTime)),
            "durationListenedSeconds": AudioPlayerServiceAnyEncodable(Int(state.currentTime)),
        ]

        do {
            let _: [String: String] = try await supabase.functions
                .invoke("record-playback", options: .init(body: body))
        } catch {
            Log.media.error("Failed to record playback complete", error: error)
        }
    }

    private func handlePlaybackEnd() async {
        await recordPlaybackComplete()
        
        // Loop if enabled, otherwise stop
        if isLoopingEnabled {
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
                Log.media.error("Failed to load favorites", error: error)
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
        let localPath = cacheDirectory.appendingPathComponent("\(track.id).m4a")
        return FileManager.default.fileExists(atPath: localPath.path) ? localPath : nil
    }

    func isDownloaded(_ track: AudioTrack) -> Bool {
        getCachedURL(for: track) != nil
    }

    func download(_ track: AudioTrack) async throws {
        let localPath = cacheDirectory.appendingPathComponent("\(track.id).m4a")

        if FileManager.default.fileExists(atPath: localPath.path) {
            return  // Already cached
        }

        // Check cache size before download
        if totalSize() > maxCacheSizeBytes * 90 / 100 {
            evictLRU()
        }

        guard let url = URL(string: track.audioUrl) else {
            throw NSError(domain: "AudioCache", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid audio URL"])
        }
        let (tempURL, _) = try await URLSession.shared.download(from: url)
        try FileManager.default.moveItem(at: tempURL, to: localPath)
    }

    func delete(_ track: AudioTrack) throws {
        let localPath = cacheDirectory.appendingPathComponent("\(track.id).m4a")
        try FileManager.default.removeItem(at: localPath)
    }

    func totalSize() -> Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var size: Int64 = 0
        for file in files {
            if let fileSize = try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64 {
                size += fileSize
            }
        }
        return size
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

// MARK: - Helper
private struct AudioPlayerServiceAnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init<T: Encodable>(_ wrapped: T) { _encode = wrapped.encode }
    func encode(to encoder: Encoder) throws { try _encode(encoder) }
}
