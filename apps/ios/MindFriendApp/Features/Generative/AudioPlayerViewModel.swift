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
    @Published private(set) var isPlaybackRequested = false
    @Published private(set) var usesBuiltInVoice = false
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
    private var backgroundLoadTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var playbackCancellables = Set<AnyCancellable>()
    private var loadID = UUID()
    private var backgroundLoadID = UUID()
    private var resumeAfterInterruption = false
    private var speechText: String?
    private var speechSettings = NativeTTSService.VoiceSettings.calm
    private let speech: any NativeSpeechPlaying
    private let resolveAudioURL: @MainActor (URL) async throws -> URL

    // MARK: - Initialization

    init(speech: (any NativeSpeechPlaying)? = nil,
         resolveAudioURL: @escaping @MainActor (URL) async throws -> URL = {
             try await SupabaseStorageMedia.resolve($0)
         }) {
        self.speech = speech ?? NativeTTSService()
        self.resolveAudioURL = resolveAudioURL
        setupAudioSession()
    }

    deinit {
        // Note: cleanup() is MainActor isolated, so we do minimal cleanup here
        // The view should call cleanup() in onDisappear
        sleepTimerTask?.cancel()
        fadeOutTask?.cancel()
        backgroundLoadTask?.cancel()
    }

    // MARK: - Audio Session Setup

    private func setupAudioSession() {
        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .sink { [weak self] notification in
                Task { @MainActor in self?.handleInterruption(notification) }
            }
            .store(in: &cancellables)
    }

    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            let wasPlaybackRequested = isPlaybackRequested
            pause()
            resumeAfterInterruption = wasPlaybackRequested
        case .ended:
            let shouldResume = resumeAfterInterruption
            resumeAfterInterruption = false
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if shouldResume && options.contains(.shouldResume) {
                    play()
                }
            }
        @unknown default:
            break
        }
    }

    // MARK: - Playback Control

    /// The Home hub, history and favorites all use this same playback choice.
    func load(content: GeneratedContent) async {
        if let value = content.audioUrl, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let url = URL(string: value), url.scheme != nil else {
                cleanup()
                error = "Unable to open this audio. Try again."
                return
            }
            try? await load(audioURL: url)
        } else {
            loadSpeech(text: content.textContent, contentType: content.contentType.rawValue)
        }
    }

    private func loadSpeech(text: String, contentType: String) {
        cleanup()
        guard !Task.isCancelled else { return }
        usesBuiltInVoice = true
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error = "There is no text to read aloud."
            return
        }
        speechText = text
        speechSettings = NativeTTSService.settingsForContentType(contentType)
        // Reading progress has no seekable audio timeline.
        duration = 1
        let requestID = loadID
        speech.playbackStates.sink { [weak self] state in
            guard let self, self.loadID == requestID else { return }
            self.currentTime = state.progress
            self.isLoading = state.isPreparing
            self.isPlaying = state.isSpeaking && !state.isPaused
            if let error = state.error {
                self.failPlayback(error)
            } else if !state.isSpeaking && state.progress >= 1 {
                self.handlePlaybackEnd()
            }
        }
        .store(in: &playbackCancellables)
    }

    /// Resolve private media before loading; a Play tap while preparing is retained.
    func load(audioURL: URL) async throws {
        cleanup()
        guard !Task.isCancelled else { return }
        let requestID = loadID
        isLoading = true

        do {
            let accessURL = try await resolveAudioURL(audioURL)
            guard loadID == requestID else { return }
            try Task.checkCancellation()
            let asset = AVURLAsset(url: accessURL, options: [
                AVURLAssetPreferPreciseDurationAndTimingKey: true
            ])
            let playable = try await asset.load(.isPlayable)
            guard loadID == requestID else { return }
            try Task.checkCancellation()
            guard playable else {
                failPlayback("Audio format not supported. Try again.")
                return
            }
            let assetDuration = try await asset.load(.duration)
            guard loadID == requestID else { return }
            try Task.checkCancellation()
            let seconds = CMTimeGetSeconds(assetDuration)
            duration = seconds.isFinite && seconds > 0 ? seconds : 0

            let item = AVPlayerItem(asset: asset)
            let newPlayer = AVPlayer(playerItem: item)
            newPlayer.actionAtItemEnd = .pause
            player = newPlayer

            item.publisher(for: \.status).sink { [weak self] status in
                Task { @MainActor in
                    guard let self, self.loadID == requestID else { return }
                    switch status {
                    case .failed:
                        self.failPlayback("Unable to load this audio. Try again.")
                    case .readyToPlay:
                        self.isLoading = false
                        if self.isPlaybackRequested { self.play() }
                    default:
                        break
                    }
                }
            }
            .store(in: &playbackCancellables)

            NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime, object: item)
                .sink { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.loadID == requestID else { return }
                        self.handlePlaybackEnd()
                    }
                }
                .store(in: &playbackCancellables)

            let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                Task { @MainActor in
                    guard let self, self.loadID == requestID else { return }
                    let seconds = CMTimeGetSeconds(time)
                    if seconds.isFinite { self.currentTime = seconds }
                }
            }
        } catch {
            guard loadID == requestID else { return }
            if Task.isCancelled {
                cleanup()
                return
            }
            failPlayback("Unable to open this audio. Try again.")
        }
    }

    var canPlay: Bool {
        error == nil && (isLoading || speechText != nil || player != nil)
    }

    var canSeek: Bool {
        !usesBuiltInVoice && !isLoading && player != nil && error == nil
    }

    /// Start or resume playback, including a request made while audio is preparing.
    func play() {
        guard canPlay else { return }
        isPlaybackRequested = true
        if usesBuiltInVoice {
            if speech.isPaused {
                speech.resume()
            } else if !speech.isSpeaking, let speechText {
                speech.speak(speechText, settings: speechSettings)
            }
            // Starting speech resets the previous utterance's completion state synchronously.
            isPlaybackRequested = error == nil
            if isPlaying { backgroundPlayer?.play() }
            return
        }
        guard !isLoading, let player else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            failPlayback("Unable to start audio. Try again.")
            return
        }
        if duration > 0 && currentTime >= duration {
            player.seek(to: .zero)
            currentTime = 0
        }
        player.playImmediately(atRate: playbackRate)
        isPlaying = true
        backgroundPlayer?.play()
    }

    /// Explicit pause and timer cutoff also cancel interrupted or pending playback.
    func pause() {
        resumeAfterInterruption = false
        isPlaybackRequested = false
        player?.pause()
        speech.pause()
        isPlaying = false
        backgroundPlayer?.pause()
    }

    private func failPlayback(_ message: String) {
        pause()
        isLoading = false
        error = message
    }

    /// Seek to a specific time
    func seek(to time: TimeInterval) {
        guard canSeek, time.isFinite else { return }
        let target = max(0, min(time, duration))
        let cmTime = CMTime(seconds: target, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player?.seek(to: cmTime)
        currentTime = target
    }

    /// Toggle play/pause
    func togglePlayback() {
        if isPlaybackRequested {
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
        loadID = UUID()
        backgroundLoadID = UUID()
        playbackCancellables.removeAll()
        speech.stop()
        speechText = nil
        resumeAfterInterruption = false
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
        backgroundLoadTask?.cancel()
        backgroundLoadTask = nil
        sleepTimerMinutes = nil
        isLoading = false
        isPlaying = false
        isPlaybackRequested = false
        usesBuiltInVoice = false
        currentTime = 0
        duration = 0
        error = nil
    }

    // MARK: - Sleep Timer

    private func startSleepTimer(minutes: Int) {
        cancelSleepTimer()

        let totalSeconds = TimeInterval(minutes * 60)
        sleepTimerRemaining = totalSeconds

        sleepTimerTask = Task {
            var remaining = totalSeconds

            while remaining > 0 && !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 1_000_000_000) }
                catch { return }
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
                do { try await Task.sleep(nanoseconds: 1_000_000_000) }
                catch { return }
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
        backgroundLoadID = UUID()
        backgroundLoadTask?.cancel()
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
            let requestID = backgroundLoadID
            backgroundLoadTask = Task { [weak self] in
                await self?.loadRemoteBackgroundSound(from: url, for: soundType, requestID: requestID)
            }
        }
    }

    /// Download and cache remote background sound, then play it
    private func loadRemoteBackgroundSound(from url: URL, for soundType: BackgroundSoundType, requestID: UUID) async {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BackgroundSounds")

        // Create cache directory if needed
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let cachedFile = cacheDir.appendingPathComponent("\(soundType.rawValue).mp3")

        // Check if already cached
        if FileManager.default.fileExists(atPath: cachedFile.path) {
            guard backgroundLoadID == requestID, !Task.isCancelled else { return }
            await playBackgroundSound(from: cachedFile)
            return
        }

        // Download the file
        do {
            let (tempUrl, _) = try await URLSession.shared.download(from: url)
            guard backgroundLoadID == requestID, !Task.isCancelled else { return }
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
        isPlaybackRequested = false
        isPlaying = false
        backgroundPlayer?.pause()
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
