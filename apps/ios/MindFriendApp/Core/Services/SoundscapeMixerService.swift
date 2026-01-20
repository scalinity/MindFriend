// MARK: - SoundscapeMixerService
// Multi-track audio mixer using AVAudioEngine for layered soundscapes

import Foundation
import AVFoundation
import MediaPlayer
import Combine
import Supabase

// MARK: - Service Constants

private enum SoundscapeMixerServiceConstants {
    static let fadeOutDuration: TimeInterval = 30.0
    static let cacheDirectoryName = "SoundscapeContent"
}

// MARK: - Sound Layer (Internal)

/// Represents a single audio layer in the mixer
/// Note: This class is accessed only from @MainActor context via the service
@MainActor
final class SoundLayer: Identifiable {
    let id: UUID
    let sound: SoundscapeSound
    let playerNode: AVAudioPlayerNode
    var audioFile: AVAudioFile?
    var volume: Float = SoundscapeConstants.defaultVolume {
        didSet { playerNode.volume = volume }
    }
    var pan: Float = 0.0 {
        didSet { playerNode.pan = pan }
    }
    var isLoaded: Bool = false
    var isPlaying: Bool = false
    var loadError: String?
    var loadTask: Task<Void, Never>?

    init(sound: SoundscapeSound) {
        self.id = UUID()
        self.sound = sound
        self.playerNode = AVAudioPlayerNode()
        self.playerNode.volume = SoundscapeConstants.defaultVolume
    }

    /// Schedule seamless looping playback
    func scheduleLoop() {
        guard let audioFile = audioFile else { return }

        // Schedule the buffer for looping
        playerNode.scheduleFile(audioFile, at: nil) { [weak self] in
            Task { @MainActor in
                guard let self = self, self.isPlaying else { return }
                self.scheduleLoop()
            }
        }
    }

    /// Convert to state representation for UI
    func toState() -> SoundLayerState {
        SoundLayerState(
            id: id,
            sound: sound,
            volume: volume,
            pan: pan,
            isLoaded: isLoaded,
            isPlaying: isPlaying,
            loadError: loadError
        )
    }
}

// MARK: - SoundscapeMixerService

@MainActor
final class SoundscapeMixerService: NSObject, ObservableObject {
    // MARK: - Dependencies

    private let supabase: SupabaseClient
    private let cacheManager = AudioCacheManager.shared

    // MARK: - Audio Engine

    private var audioEngine: AVAudioEngine?
    private var layers: [SoundLayer] = []
    private var sleepTimer: Timer?
    private var fadeTimer: Timer?

    // MARK: - Lookup Caches

    private var soundLookup: [String: SoundscapeSound] = [:]

    // MARK: - Convenience Accessors

    private var maxLayers: Int { SoundscapeConstants.maxLayers }
    private var fadeOutDuration: TimeInterval { SoundscapeMixerServiceConstants.fadeOutDuration }

    // MARK: - Published State

    @Published private(set) var state = SoundscapeMixerState()
    @Published private(set) var availableSounds: [SoundscapeCategory: [SoundscapeSound]] = [:]
    @Published private(set) var savedMixes: [SavedMix] = []

    // MARK: - Initialization

    init(supabase: SupabaseClient) {
        self.supabase = supabase
        super.init()
        setupAudioSession()
        setupNotifications()
    }

    deinit {
        // Capture values needed for cleanup - deinit is nonisolated
        let engine = audioEngine
        let layerNodes = layers.map { $0.playerNode }
        let timers = (sleepTimer, fadeTimer)
        
        // Schedule cleanup on main thread since timers must be invalidated there
        DispatchQueue.main.async {
            timers.0?.invalidate()
            timers.1?.invalidate()
            for node in layerNodes {
                node.stop()
                engine?.detach(node)
            }
            engine?.stop()
            NotificationCenter.default.removeObserver(self as AnyObject)
        }
    }

    // MARK: - Audio Session Setup

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            Log.media.error("Audio session setup failed", error: error)
            state.error = "Failed to configure audio: \(error.localizedDescription)"
        }
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        Task { @MainActor in
            switch type {
            case .began:
                self.pause()
            case .ended:
                if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if options.contains(.shouldResume) {
                        // Reactivate audio session before resuming
                        try? AVAudioSession.sharedInstance().setActive(true)
                        try? self.play()
                    }
                }
            @unknown default:
                break
            }
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        Task { @MainActor in
            switch reason {
            case .oldDeviceUnavailable:
                self.pause()
            default:
                break
            }
        }
    }

    // MARK: - Sound Library

    /// Fetch available sounds from Supabase
    func fetchAvailableSounds() async throws {
        let sounds: [SoundscapeSound] = try await supabase
            .from("soundscape_sounds")
            .select()
            .eq("is_active", value: true)
            .order("sort_order")
            .execute()
            .value
        
        // Group by category
        var grouped: [SoundscapeCategory: [SoundscapeSound]] = [:]
        for category in SoundscapeCategory.allCases {
            grouped[category] = sounds.filter { $0.category == category }
        }
        availableSounds = grouped
        
        // Build O(1) lookup dictionary
        soundLookup = Dictionary(uniqueKeysWithValues: sounds.map { ($0.id, $0) })
    }

    /// Get sounds for a specific category
    func getSounds(for category: SoundscapeCategory) -> [SoundscapeSound] {
        availableSounds[category] ?? []
    }

    /// Find a sound by ID
    func getSound(byId id: String) -> SoundscapeSound? {
        soundLookup[id]  // O(1) lookup
    }

    // MARK: - Layer Management

    /// Add a new sound layer to the mix
    @discardableResult
    func addLayer(sound: SoundscapeSound) throws -> UUID {
        guard layers.count < maxLayers else {
            throw SoundscapeMixerError.maxLayersReached
        }

        let layer = SoundLayer(sound: sound)
        layers.append(layer)

        // Setup audio engine if needed
        if audioEngine == nil {
            setupAudioEngine()
        }

        // Attach player node to engine
        guard let engine = audioEngine else {
            throw SoundscapeMixerError.engineStartFailed("Audio engine not available")
        }

        engine.attach(layer.playerNode)
        engine.connect(layer.playerNode, to: engine.mainMixerNode, format: nil)

        // Load audio file asynchronously
        layer.loadTask = Task {
            await loadAudioForLayer(layer)
        }

        updateState()
        return layer.id
    }

    /// Remove a layer from the mix
    func removeLayer(id: UUID) {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
        let layer = layers[index]
        
        // Cancel any pending load task
        layer.loadTask?.cancel()
        
        layer.playerNode.stop()
        audioEngine?.detach(layer.playerNode)
        layers.remove(at: index)
        updateState()
        updateNowPlayingInfo()
    }

    /// Set volume for a specific layer
    func setLayerVolume(layerId: UUID, volume: Float) {
        guard let layer = layers.first(where: { $0.id == layerId }) else { return }
        layer.volume = max(0, min(1, volume))
        updateState()
    }

    /// Set pan position for a specific layer
    func setLayerPan(layerId: UUID, pan: Float) {
        guard let layer = layers.first(where: { $0.id == layerId }) else { return }
        layer.pan = max(-1, min(1, pan))
        updateState()
    }

    // MARK: - Audio Loading

    private func loadAudioForLayer(_ layer: SoundLayer) async {
        guard let url = URL(string: layer.sound.audioUrl),
              url.scheme == "https" else {
            layer.loadError = "Invalid or insecure audio URL"
            updateState()
            return
        }
        
        do {
            let localURL: URL
            
            // Check cache first
            if let cachedURL = getCachedURL(for: layer.sound),
               FileManager.default.fileExists(atPath: cachedURL.path) {
                localURL = cachedURL
            } else {
                // Download to temp location
                let (downloadURL, _) = try await URLSession.shared.download(from: url)
                
                // Check if task was cancelled during download
                try Task.checkCancellation()
                
                // Move to permanent cache location
                let cacheDir = getCacheDirectory()
                try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
                
                let fileExtension = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
                let permanentURL = cacheDir.appendingPathComponent("\(layer.sound.id).\(fileExtension)")
                
                // Remove existing file if any
                try? FileManager.default.removeItem(at: permanentURL)
                try FileManager.default.moveItem(at: downloadURL, to: permanentURL)
                localURL = permanentURL
            }
            
            // Check cancellation again before loading
            try Task.checkCancellation()
            
            let audioFile = try AVAudioFile(forReading: localURL)
            layer.audioFile = audioFile
            layer.isLoaded = true
            
            // Connect with proper format
            if let engine = audioEngine {
                engine.connect(layer.playerNode, to: engine.mainMixerNode, format: audioFile.processingFormat)
            }
            
            // If mixer is already playing, start this layer
            if state.isPlaying {
                layer.scheduleLoop()
                layer.playerNode.play()
                layer.isPlaying = true
            }
            
            updateState()
            
        } catch is CancellationError {
            // Task was cancelled, don't update state
            return
        } catch {
            layer.loadError = error.localizedDescription
            updateState()
            Log.media.error("Failed to load audio for layer", error: error)
        }
    }
    
    private func getCacheDirectory() -> URL {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent(SoundscapeMixerServiceConstants.cacheDirectoryName)
    }
    
    private func getCachedURL(for sound: SoundscapeSound) -> URL? {
        guard let url = URL(string: sound.audioUrl) else { return nil }
        let fileExtension = url.pathExtension.isEmpty ? "m4a" : url.pathExtension
        let cacheDir = getCacheDirectory()
        let localPath = cacheDir.appendingPathComponent("\(sound.id).\(fileExtension)")
        return FileManager.default.fileExists(atPath: localPath.path) ? localPath : nil
    }

    // MARK: - Audio Engine Setup

    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
    }

    private func cleanupAudioEngine() {
        audioEngine?.stop()
        audioEngine = nil
    }

    // MARK: - Playback Control

    /// Start playback of all layers
    func play() throws {
        guard !layers.isEmpty else { return }

        state.isPreparing = true
        state.error = nil

        do {
            guard let engine = audioEngine else {
                throw SoundscapeMixerError.engineStartFailed("No audio engine")
            }

            // Prepare and start engine
            engine.prepare()
            try engine.start()

            // Start all loaded layers
            for layer in layers where layer.isLoaded {
                layer.scheduleLoop()
                layer.playerNode.play()
                layer.isPlaying = true
            }

            state.isPlaying = true
            state.isPreparing = false
            updateNowPlayingInfo()
            updateState()
        } catch {
            state.isPreparing = false
            state.error = error.localizedDescription
            throw SoundscapeMixerError.engineStartFailed(error.localizedDescription)
        }
    }

    /// Pause playback of all layers
    func pause() {
        for layer in layers {
            layer.playerNode.pause()
            layer.isPlaying = false
        }
        state.isPlaying = false
        updateNowPlayingInfo()
        updateState()
    }

    /// Stop playback and reset
    func stop() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        fadeTimer?.invalidate()
        fadeTimer = nil

        for layer in layers {
            layer.playerNode.stop()
            layer.isPlaying = false
        }

        audioEngine?.stop()

        state.isPlaying = false
        state.isFading = false
        state.sleepTimerRemaining = nil
        clearNowPlayingInfo()
        updateState()
    }

    /// Set master volume for the mix
    func setMasterVolume(_ volume: Float) {
        state.masterVolume = max(0, min(1, volume))
        audioEngine?.mainMixerNode.outputVolume = state.masterVolume
        updateState()
    }

    // MARK: - Sleep Timer

    /// Set sleep timer with specified duration
    func setSleepTimer(_ duration: SleepTimerDuration) {
        cancelSleepTimer()

        state.sleepTimerDuration = duration

        guard duration != .endOfTrack else {
            // End of track doesn't apply to looping soundscapes
            return
        }

        let seconds = TimeInterval(duration.rawValue * 60)
        state.sleepTimerRemaining = seconds

        sleepTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            Task { @MainActor in
                self.state.sleepTimerRemaining? -= 1

                if let remaining = self.state.sleepTimerRemaining, remaining <= self.fadeOutDuration {
                    // Start fade out
                    timer.invalidate()
                    self.sleepTimer = nil
                    self.startFadeOut()
                }

                self.updateState()
            }
        }
    }

    /// Cancel active sleep timer
    func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        fadeTimer?.invalidate()
        fadeTimer = nil
        state.sleepTimerDuration = nil
        state.sleepTimerRemaining = nil
        state.isFading = false

        // Restore volume if it was fading
        audioEngine?.mainMixerNode.outputVolume = state.masterVolume
        updateState()
    }

    /// Formatted remaining time for sleep timer
    var formattedSleepTimerRemaining: String? {
        state.formattedSleepTimerRemaining
    }

    private func startFadeOut() {
        state.isFading = true

        let fadeSteps = Int(fadeOutDuration * 2) // 2 steps per second
        let fadeInterval = fadeOutDuration / Double(fadeSteps)
        var currentStep = 0

        fadeTimer = Timer.scheduledTimer(withTimeInterval: fadeInterval, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            currentStep += 1
            let progress = Double(currentStep) / Double(fadeSteps)
            // Quadratic fade curve for natural perception
            let volume = Float(pow(1.0 - progress, 2)) * self.state.masterVolume

            Task { @MainActor in
                self.audioEngine?.mainMixerNode.outputVolume = volume
                self.state.sleepTimerRemaining = self.fadeOutDuration * (1.0 - progress)

                if currentStep >= fadeSteps {
                    timer.invalidate()
                    self.fadeTimer = nil
                    self.stop()
                }
            }
        }
    }

    // MARK: - Now Playing Info

    private func updateNowPlayingInfo() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: generateMixTitle(),
            MPMediaItemPropertyArtist: "MindFriend",
            MPNowPlayingInfoPropertyPlaybackRate: state.isPlaying ? 1.0 : 0.0,
            MPMediaItemPropertyMediaType: MPMediaType.music.rawValue
        ]

        // Use first layer's thumbnail if available
        if let firstLayer = layers.first,
           let thumbnailUrl = firstLayer.sound.thumbnailUrl,
           let url = URL(string: thumbnailUrl) {
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

    private func generateMixTitle() -> String {
        if layers.count == 1 {
            return layers[0].sound.title
        } else if layers.count > 1 {
            return "Custom Mix (\(layers.count) sounds)"
        }
        return "Soundscape Mix"
    }

    // MARK: - Mix Persistence

    /// Save current mix configuration
    func saveMix(name: String) async throws -> SavedMix {
        // Validate mix name
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            throw SoundscapeMixerError.invalidMixName("Name cannot be empty")
        }
        guard trimmedName.count <= 100 else {
            throw SoundscapeMixerError.invalidMixName("Name must be 100 characters or less")
        }

        guard let userId = supabase.auth.currentUser?.id else {
            throw SoundscapeMixerError.notAuthenticated
        }

        let mixLayers = layers.map { layer in
            SavedMixLayer(soundId: layer.sound.id, volume: layer.volume, pan: layer.pan)
        }

        let createDTO = CreateSavedMixDTO(
            userId: userId.uuidString,
            name: name,
            layers: mixLayers
        )

        let savedMix: SavedMix = try await supabase
            .from("soundscape_mixes")
            .insert(createDTO)
            .select()
            .single()
            .execute()
            .value

        // Refresh saved mixes list
        try await fetchSavedMixes()

        return savedMix
    }

    /// Load a saved mix configuration
    func loadMix(_ mix: SavedMix) async throws {
        // Verify ownership
        guard let userId = supabase.auth.currentUser?.id,
              mix.userId == userId.uuidString else {
            throw SoundscapeMixerError.notAuthenticated
        }
        
        // Clear existing layers - copy IDs first to avoid mutating during iteration
        let existingLayerIds = layers.map { $0.id }
        for layerId in existingLayerIds {
            removeLayer(id: layerId)
        }
        
        // Add layers from saved mix
        for savedLayer in mix.layers {
            if let sound = getSound(byId: savedLayer.soundId) {
                do {
                    let layerId = try addLayer(sound: sound)
                    setLayerVolume(layerId: layerId, volume: savedLayer.volume)
                    setLayerPan(layerId: layerId, pan: savedLayer.pan)
                } catch {
                    Log.media.warning("Failed to add layer from saved mix: \(error.localizedDescription)")
                }
            } else {
                Log.media.warning("Sound not found for saved layer: \(savedLayer.soundId)")
            }
        }
    }

    /// Delete a saved mix
    func deleteMix(id: String) async throws {
        guard supabase.auth.currentUser != nil else {
            throw SoundscapeMixerError.notAuthenticated
        }

        try await supabase
            .from("soundscape_mixes")
            .delete()
            .eq("id", value: id)
            .execute()

        // Refresh saved mixes list
        try await fetchSavedMixes()
    }

    /// Fetch user's saved mixes
    func fetchSavedMixes() async throws {
        guard let userId = supabase.auth.currentUser?.id else {
            savedMixes = []
            return
        }

        savedMixes = try await supabase
            .from("soundscape_mixes")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("updated_at", ascending: false)
            .execute()
            .value
    }

    // MARK: - State Management

    private func updateState() {
        state.layers = layers.map { $0.toState() }
    }

    // MARK: - Cleanup

    /// Clean up all resources
    func cleanup() {
        stop()
        for layer in layers {
            audioEngine?.detach(layer.playerNode)
        }
        layers.removeAll()
        cleanupAudioEngine()
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - Remote Command Support

extension SoundscapeMixerService {
    /// Setup remote command center for lock screen controls
    func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.addTarget { [weak self] _ in
            try? self?.play()
            return .success
        }

        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }

        commandCenter.stopCommand.addTarget { [weak self] _ in
            self?.stop()
            return .success
        }

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            if self.state.isPlaying {
                self.pause()
            } else {
                try? self.play()
            }
            return .success
        }
    }
}
