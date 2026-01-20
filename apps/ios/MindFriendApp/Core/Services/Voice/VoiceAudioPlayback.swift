import Foundation
import AVFoundation
import OSLog

/// Manages audio playback for TTS voice output
@MainActor
final class VoiceAudioPlayback {

    // MARK: - Properties

    private let audioEngine = AVAudioEngine()
    private var audioPlayer: AVAudioPlayerNode?
    private var audioFormat: AVAudioFormat?
    private var playbackBuffer: [Data] = []
    private var isPlaying = false
    private var isPlayerPlaying = false

    // Playback configuration
    private let sampleRate: Double = 24000.0
    private let channelCount: AVAudioChannelCount = 1
    private let maxPlaybackBufferSize = 50

    // Audio level tracking
    private var previousPlaybackLevel: Float = 0
    private let levelAttackCoeff: Float = 0.3
    private let levelReleaseCoeff: Float = 0.1
    private let noiseFloorDb: Float = -60.0
    private let ceilingDb: Float = -10.0

    // Echo suppression: brief cooldown after playback to filter residual echo
    // iOS voiceChat mode provides AEC, so we only need a short cooldown
    private(set) var lastPlaybackEndTime: Date?
    let echoCooldownSeconds: TimeInterval = 0.3

    // Callbacks
    var onPlaybackStart: (() -> Void)?
    var onPlaybackEnd: (() -> Void)?
    var onPlaybackLevelUpdate: ((Float) -> Void)?

    // MARK: - Initialization

    init() {
        setupAudioComponents()
    }

    // MARK: - Setup

    private func setupAudioComponents() {
        audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: true
        )

        audioPlayer = AVAudioPlayerNode()
        if let player = audioPlayer, let format = audioFormat {
            audioEngine.attach(player)
            audioEngine.connect(player, to: audioEngine.mainMixerNode, format: format)
            player.volume = 1.0
        }
    }

    // MARK: - Playback Control

    func queueAudioChunk(_ audioData: Data) {
        playbackBuffer.append(audioData)

        // Prevent buffer overflow
        if playbackBuffer.count > maxPlaybackBufferSize {
            playbackBuffer.removeFirst()
            #if DEBUG
            Log.voice.debug("[AudioPlayback] Buffer overflow, dropped oldest chunk")
            #endif
        }

        // Start playback if not already playing
        if !isPlaying {
            playNextChunk()
        }
    }

    func stop() {
        #if DEBUG
        Log.voice.debug("[AudioPlayback] Stopping")
        #endif

        audioPlayer?.stop()

        if audioEngine.isRunning {
            audioEngine.stop()
        }

        playbackBuffer.removeAll()
        isPlaying = false
        isPlayerPlaying = false
    }

    // MARK: - Private Methods

    private func playNextChunk() {
        guard let player = audioPlayer,
              let format = audioFormat else {
            isPlaying = false
            return
        }

        guard !playbackBuffer.isEmpty else {
            return
        }

        isPlaying = true

        // Notify playback start
        if !isPlayerPlaying {
            onPlaybackStart?()
        }

        // Start player if needed
        if !isPlayerPlaying {
            #if DEBUG
            Log.voice.debug("[AudioPlayback] Starting playback engine")
            #endif

            if !audioEngine.isRunning {
                do {
                    audioEngine.prepare()
                    try audioEngine.start()
                    #if DEBUG
                    Log.voice.debug("[AudioPlayback] Engine started")
                    #endif
                } catch {
                    #if DEBUG
                    Log.voice.error("[AudioPlayback] Engine start error: \(error)")
                    #endif

                    // Clean up state
                    playbackBuffer.removeAll()
                    isPlaying = false
                    isPlayerPlaying = false
                    return
                }
            }

            player.play()
            isPlayerPlaying = true
        }

        // Schedule all available buffers
        var scheduledCount = 0
        while !playbackBuffer.isEmpty {
            let audioData = playbackBuffer.removeFirst()
            let frameCount = AVAudioFrameCount(audioData.count / 2)

            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
                  let channelData = buffer.int16ChannelData else {
                continue
            }

            buffer.frameLength = frameCount

            audioData.withUnsafeBytes { rawBufferPointer in
                let source = rawBufferPointer.bindMemory(to: Int16.self)
                let destination = channelData[0]
                destination.update(from: source.baseAddress!, count: Int(frameCount))
            }

            // Schedule with completion handler for last buffer
            let isLastBuffer = playbackBuffer.isEmpty
            player.scheduleBuffer(buffer) { [weak self] in
                if isLastBuffer {
                    Task { @MainActor in
                        self?.onPlaybackChunkComplete()
                    }
                }
            }

            scheduledCount += 1
        }

        #if DEBUG
        Log.voice.debug("[AudioPlayback] Scheduled \(scheduledCount) buffers")
        #endif
    }

    private func onPlaybackChunkComplete() {
        if !playbackBuffer.isEmpty {
            playNextChunk()
        } else {
            // All done - record end time for echo suppression
            #if DEBUG
            Log.voice.debug("[AudioPlayback] Playback complete, starting echo cooldown")
            #endif

            lastPlaybackEndTime = Date()
            isPlaying = false
            isPlayerPlaying = false

            onPlaybackEnd?()
        }
    }

    // MARK: - Level Calculation

    func calculatePlaybackLevel(for audioData: Data) -> Float {
        let frameCount = audioData.count / 2
        guard frameCount > 0 else { return 0 }

        var sumSquares: Float = 0

        audioData.withUnsafeBytes { rawBufferPointer in
            let samples = rawBufferPointer.bindMemory(to: Int16.self)
            for i in 0..<frameCount {
                let sample = Float(samples[i])
                sumSquares += sample * sample
            }
        }

        let rms = sqrt(sumSquares / Float(frameCount))
        let rmsDb = 20 * log10(max(rms, 1) / 32768.0)
        let normalized = normalizeAudioLevel(rmsDb)

        // Apply smoothing
        let coeff = normalized > previousPlaybackLevel ? levelAttackCoeff : levelReleaseCoeff
        let smoothedLevel = previousPlaybackLevel + coeff * (normalized - previousPlaybackLevel)
        previousPlaybackLevel = smoothedLevel

        onPlaybackLevelUpdate?(smoothedLevel)

        return smoothedLevel
    }

    private func normalizeAudioLevel(_ db: Float) -> Float {
        let normalized = (db - noiseFloorDb) / (ceilingDb - noiseFloorDb)
        return max(0, min(1, normalized))
    }

    // MARK: - Cleanup

    deinit {
        // Manual cleanup - can't call @MainActor isolated methods from deinit
        audioPlayer?.stop()
        if audioEngine.isRunning {
            audioEngine.stop()
        }
    }
}
