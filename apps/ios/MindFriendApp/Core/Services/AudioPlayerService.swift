// MARK: - AudioPlayerService
// Manages audio playback using AVFoundation, background audio, sleep timer, and offline caching

import Foundation
import AVFoundation
import MediaPlayer
import Combine
import Supabase

/// One completion attempt per playback, with one deliberate retry at its end
/// only when the server explicitly rejected the earlier attempt.
struct PlaybackCompletionGate {
    private var attempted = false
    private var rejected = false
    private var retryAvailable = true

    mutating func claim(retryRejected: Bool = false) -> Bool {
        if attempted {
            guard retryRejected && rejected && retryAvailable else { return false }
            retryAvailable = false
        }
        attempted = true
        rejected = false
        return true
    }

    mutating func markRejected() { rejected = true }
}

@MainActor
final class AudioPlayerService: NSObject, ObservableObject {
    private let supabase: SupabaseClient
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var loadGeneration = UUID()
    private var loadTask: Task<URL, Error>?
    private var playbackStartTask: Task<Void, Never>?
    private var completionGate = PlaybackCompletionGate()
    private var fadeTimer: Timer?
    private var wantsPlayback = false
    private var cancellables = Set<AnyCancellable>()

    @Published private(set) var state = PlaybackState()
    @Published var favorites: Set<String> = []
    @Published var sleepTimer: Timer?
    @Published var sleepTimerRemaining: TimeInterval = 0
    @Published var isOfflineCached: Bool = false
    @Published var isLoopingEnabled: Bool = false

    private(set) var sleepTimerDuration: SleepTimerDuration?
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
        
        stop()
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
        stop()
        let generation = loadGeneration
        wantsPlayback = true
        state.currentTrack = track
        state.isBuffering = true
        state.error = nil

        // Record playback start in background
        playbackStartTask = Task {
            await recordPlaybackStart(track, context: context, generation: generation)
        }

        // Check if offline available
        guard let audioUrl = cacheManager.getCachedURL(for: track) ?? URL(string: track.audioUrl) else {
            state.isBuffering = false
            state.error = "Invalid audio URL"
            return
        }

        let resolution = Task { try await SupabaseStorageMedia.resolve(audioUrl) }
        loadTask = resolution
        let resolvedURL: URL
        do {
            resolvedURL = try await withTaskCancellationHandler {
                try await resolution.value
            } onCancel: {
                resolution.cancel()
            }
            try Task.checkCancellation()
            guard generation == loadGeneration else { return }
            loadTask = nil
        } catch {
            guard generation == loadGeneration else { return }
            loadTask = nil
            state.isBuffering = false
            if !Task.isCancelled && !resolution.isCancelled {
                state.error = "Unable to open this audio. Please try again."
            }
            return
        }
        let asset = AVURLAsset(url: resolvedURL)
        let item = AVPlayerItem(asset: asset)
        playerItem = item
        player = AVPlayer(playerItem: item)

        // Observe player item status
        playerItem?.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak item] status in
                guard let self, generation == self.loadGeneration,
                      let item, self.playerItem === item else { return }
                switch status {
                case .readyToPlay:
                    self.state.isBuffering = false
                    self.state.duration = item.duration.seconds.isFinite ? item.duration.seconds : 0
                    if self.wantsPlayback {
                        self.player?.play()
                        self.state.isPlaying = true
                    }
                    self.updateNowPlayingInfo()
                case .failed:
                    if let itemError = item.error {
                        self.state.error = "Failed to load audio: \(itemError.localizedDescription)"
                    } else {
                        self.state.error = "Failed to load audio"
                    }
                    self.state.isBuffering = false
                    self.state.isPlaying = false
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
            MainActor.assumeIsolated {
                guard let self, generation == self.loadGeneration else { return }
                self.state.currentTime = time.seconds
                self.updateNowPlayingInfo()

                // Check for completion (95% played)
                let duration = self.state.duration
                if duration > 0,
                   time.seconds / duration > 0.95 {
                    Task {
                        await self.recordPlaybackComplete(generation: generation)
                    }
                }
            }
        }

        // Observe playback end
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: playerItem)
            .sink { [weak self] _ in
                Task {
                    guard let self, generation == self.loadGeneration else { return }
                    await self.handlePlaybackEnd()
                }
            }
            .store(in: &cancellables)

        isOfflineCached = cacheManager.isDownloaded(track)
    }

    func play() {
        wantsPlayback = true
        guard let player, playerItem?.status == .readyToPlay else { return }
        player.play()
        state.isPlaying = true
    }

    func pause() {
        wantsPlayback = false
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
        cancelSleepTimer()
        loadGeneration = UUID()
        loadTask?.cancel()
        loadTask = nil
        playbackStartTask?.cancel()
        playbackStartTask = nil
        currentSessionId = nil
        completionGate = PlaybackCompletionGate()
        wantsPlayback = false
        player?.pause()
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        timeObserver = nil
        player = nil
        playerItem = nil

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
        cancelSleepTimer()
        sleepTimerDuration = duration

        if duration == .endOfTrack {
            // Timer handled by playback end
            return
        }

        let seconds = TimeInterval(duration.rawValue * 60)
        sleepTimerRemaining = seconds

        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
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
    }

    func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerRemaining = 0
        sleepTimerDuration = nil
        fadeTimer?.invalidate()
        fadeTimer = nil
        isSleepFading = false
        player?.volume = 1.0
    }

    private func fadeOutAndStop() {
        fadeOutAndStopWithDuration(3.0)
    }

    /// Fade out and stop with configurable duration
    /// - Parameter duration: Fade duration in seconds (default 3, sleep uses 30)
    /// - Parameter completion: Optional completion handler called when fade finishes
    func fadeOutAndStopWithDuration(_ duration: TimeInterval, completion: (() -> Void)? = nil) {
        fadeTimer?.invalidate()
        guard duration.isFinite, duration > 0 else {
            stop()
            completion?()
            return
        }
        let generation = loadGeneration
        let fadingPlayer = player
        let fadeSteps = max(20, Int(duration * 2)) // 2 steps per second for smooth fade
        let fadeInterval = duration / Double(fadeSteps)
        var currentStep = 0

        isSleepFading = true

        fadeTimer = Timer.scheduledTimer(withTimeInterval: fadeInterval, repeats: true) { [weak self, weak fadingPlayer] timer in
            MainActor.assumeIsolated {
                guard let self, generation == self.loadGeneration,
                      self.fadeTimer === timer, self.player === fadingPlayer else {
                    timer.invalidate()
                    return
                }
                currentStep += 1
                // Use quadratic fade curve for more natural audio perception
                let progress = Double(currentStep) / Double(fadeSteps)
                let volume = Float(pow(1.0 - progress, 2))
                fadingPlayer?.volume = volume

                if currentStep >= fadeSteps {
                    timer.invalidate()
                    self.fadeTimer = nil
                    self.isSleepFading = false
                    self.stop()
                    completion?()
                }
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

    private struct PlaybackStartResponse: Decodable {
        let playbackSessionId: String
    }

    struct PlaybackCompletionResponse: Decodable {
        let success: Bool
    }

    private func recordPlaybackStart(_ track: AudioTrack, context: String, generation: UUID) async {
        // Ensure we have a valid session before making authenticated API calls
        guard let _ = try? await supabase.auth.session,
              let _ = supabase.auth.currentUser?.id else { return }

        let body: [String: AudioPlayerServiceAnyEncodable] = [
            "trackId": AudioPlayerServiceAnyEncodable(track.id),
            "eventType": AudioPlayerServiceAnyEncodable("start"),
            "positionSeconds": AudioPlayerServiceAnyEncodable(0),
            "source": AudioPlayerServiceAnyEncodable(context),
        ]

        do {
            let response: PlaybackStartResponse = try await supabase.functions
                .invoke("record-playback", options: .init(body: body))
            guard generation == loadGeneration else { return }
            currentSessionId = response.playbackSessionId
        } catch {
            Log.media.error("Failed to record playback start", error: error)
        }
    }

    private func recordPlaybackComplete(generation: UUID, retryRejected: Bool = false) async {
        guard generation == loadGeneration,
              let track = state.currentTrack,
              completionGate.claim(retryRejected: retryRejected) else { return }
        let position = Int(state.currentTime)
        await playbackStartTask?.value
        guard generation == loadGeneration, currentSessionId != nil else { return }
        
        // Ensure we have a valid session before making authenticated API calls
        guard let _ = try? await supabase.auth.session else { return }

        let body: [String: AudioPlayerServiceAnyEncodable] = [
            "trackId": AudioPlayerServiceAnyEncodable(track.id),
            "eventType": AudioPlayerServiceAnyEncodable("complete"),
            "positionSeconds": AudioPlayerServiceAnyEncodable(position),
            "durationListenedSeconds": AudioPlayerServiceAnyEncodable(position),
        ]

        do {
            let response: PlaybackCompletionResponse = try await supabase.functions
                .invoke("record-playback", options: .init(body: body))
            if !response.success {
                if generation == loadGeneration { completionGate.markRejected() }
                Log.media.error("Playback completion was not accepted")
            }
        } catch FunctionsError.httpError(let status, _) where (400..<500).contains(status) {
            if generation == loadGeneration { completionGate.markRejected() }
            Log.media.error("Playback completion request was rejected")
        } catch {
            Log.media.error("Failed to record playback complete", error: error)
        }
    }

    func handlePlaybackEnd() async {
        let generation = loadGeneration
        await recordPlaybackComplete(generation: generation, retryRejected: true)
        guard generation == loadGeneration else { return }
        
        // An explicit end-of-track timer takes precedence over looping.
        if isLoopingEnabled && sleepTimerDuration != .endOfTrack {
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
            _ = try? await supabase
                .from("user_audio_favorites")
                .delete()
                .eq("user_id", value: userId)
                .eq("track_id", value: track.id)
                .execute()
        } else {
            favorites.insert(track.id)
            _ = try? await supabase
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
        let resolvedURL = try await SupabaseStorageMedia.resolve(url)
        let (tempURL, response) = try await URLSession.shared.download(from: resolvedURL)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
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
