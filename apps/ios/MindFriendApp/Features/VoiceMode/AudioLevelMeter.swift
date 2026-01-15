import Foundation
import AVFoundation
import Combine

// MARK: - Audio Level Meter

/// Computes smoothed RMS levels from audio buffers for UI visualization
/// Uses exponential smoothing to prevent jitter while maintaining responsiveness
@MainActor
final class AudioLevelMeter: ObservableObject {

    // MARK: - Published Properties

    /// Smoothed microphone input level (0.0 - 1.0)
    @Published private(set) var micLevel: Float = 0

    /// Smoothed playback output level (0.0 - 1.0)
    @Published private(set) var playbackLevel: Float = 0

    /// Whether the meter is active
    @Published private(set) var isActive = false

    // MARK: - Configuration

    struct Configuration {
        /// Smoothing factor for level changes (0.0 = no smoothing, 1.0 = infinite smoothing)
        /// Higher values = smoother but slower response
        var smoothingFactor: Float = 0.85

        /// Floor level in dB below which we consider silence
        var noiseFloorDb: Float = -50

        /// Ceiling level in dB for normalization
        var ceilingDb: Float = -6

        /// Minimum decay rate per update to ensure levels drop smoothly
        var minDecayRate: Float = 0.05

        /// Attack coefficient (faster response to increases)
        var attackCoefficient: Float = 0.3

        /// Release coefficient (slower response to decreases)
        var releaseCoefficient: Float = 0.9

        static let `default` = Configuration()

        static let responsive = Configuration(
            smoothingFactor: 0.7,
            attackCoefficient: 0.2,
            releaseCoefficient: 0.85
        )

        static let smooth = Configuration(
            smoothingFactor: 0.92,
            attackCoefficient: 0.4,
            releaseCoefficient: 0.95
        )
    }

    private var config: Configuration

    // MARK: - Private Properties

    private var previousMicLevel: Float = 0
    private var previousPlaybackLevel: Float = 0
    private var decayTimer: Timer?

    // MARK: - Initialization

    init(config: Configuration = .default) {
        self.config = config
    }

    deinit {
        decayTimer?.invalidate()
    }

    // MARK: - Public Methods

    /// Start the level meter
    func start() {
        guard !isActive else { return }
        isActive = true
        startDecayTimer()
    }

    /// Stop the level meter
    func stop() {
        guard isActive else { return }
        isActive = false
        decayTimer?.invalidate()
        decayTimer = nil
        micLevel = 0
        playbackLevel = 0
        previousMicLevel = 0
        previousPlaybackLevel = 0
    }

    /// Process microphone audio buffer and update mic level
    func processMicBuffer(_ buffer: AVAudioPCMBuffer) {
        let rms = computeRMS(buffer)
        let normalizedLevel = normalizeLevel(rms)
        updateMicLevel(normalizedLevel)
    }

    /// Process microphone audio data (Int16 PCM) and update mic level
    func processMicData(_ data: Data, sampleRate: Double = 24000) {
        let rms = computeRMS(from: data)
        let normalizedLevel = normalizeLevel(rms)
        updateMicLevel(normalizedLevel)
    }

    /// Process playback audio buffer and update playback level
    func processPlaybackBuffer(_ buffer: AVAudioPCMBuffer) {
        let rms = computeRMS(buffer)
        let normalizedLevel = normalizeLevel(rms)
        updatePlaybackLevel(normalizedLevel)
    }

    /// Process playback audio data (Int16 PCM) and update playback level
    func processPlaybackData(_ data: Data) {
        let rms = computeRMS(from: data)
        let normalizedLevel = normalizeLevel(rms)
        updatePlaybackLevel(normalizedLevel)
    }

    /// Update configuration
    func updateConfig(_ config: Configuration) {
        self.config = config
    }

    // MARK: - RMS Computation

    private func computeRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else {
            // Try Int16 format
            if let int16Data = buffer.int16ChannelData {
                return computeRMS(int16Data: int16Data, frameCount: Int(buffer.frameLength))
            }
            return 0
        }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }

        var sumSquares: Float = 0
        let samples = channelData[0]

        for i in 0..<frameCount {
            let sample = samples[i]
            sumSquares += sample * sample
        }

        return sqrt(sumSquares / Float(frameCount))
    }

    private func computeRMS(int16Data: UnsafePointer<UnsafeMutablePointer<Int16>>, frameCount: Int) -> Float {
        guard frameCount > 0 else { return 0 }

        var sumSquares: Float = 0
        let samples = int16Data[0]
        let scale: Float = 1.0 / 32768.0  // Int16 to normalized float

        for i in 0..<frameCount {
            let sample = Float(samples[i]) * scale
            sumSquares += sample * sample
        }

        return sqrt(sumSquares / Float(frameCount))
    }

    private func computeRMS(from data: Data) -> Float {
        let sampleCount = data.count / 2  // Int16 = 2 bytes
        guard sampleCount > 0 else { return 0 }

        var sumSquares: Float = 0
        let scale: Float = 1.0 / 32768.0

        data.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                let sample = Float(samples[i]) * scale
                sumSquares += sample * sample
            }
        }

        return sqrt(sumSquares / Float(sampleCount))
    }

    // MARK: - Level Normalization

    private func normalizeLevel(_ rms: Float) -> Float {
        guard rms > 0 else { return 0 }

        // Convert to dB
        let db = 20 * log10(rms)

        // Map from [noiseFloor, ceiling] to [0, 1]
        let normalized = (db - config.noiseFloorDb) / (config.ceilingDb - config.noiseFloorDb)

        // Clamp to [0, 1]
        return max(0, min(1, normalized))
    }

    // MARK: - Level Updates with Smoothing

    private func updateMicLevel(_ newLevel: Float) {
        // Use different coefficients for attack (rising) vs release (falling)
        let coefficient: Float
        if newLevel > previousMicLevel {
            coefficient = config.attackCoefficient
        } else {
            coefficient = config.releaseCoefficient
        }

        // Exponential smoothing: level = prev * coefficient + new * (1 - coefficient)
        let smoothed = previousMicLevel * coefficient + newLevel * (1 - coefficient)

        previousMicLevel = smoothed
        micLevel = smoothed
    }

    private func updatePlaybackLevel(_ newLevel: Float) {
        let coefficient: Float
        if newLevel > previousPlaybackLevel {
            coefficient = config.attackCoefficient
        } else {
            coefficient = config.releaseCoefficient
        }

        let smoothed = previousPlaybackLevel * coefficient + newLevel * (1 - coefficient)

        previousPlaybackLevel = smoothed
        playbackLevel = smoothed
    }

    // MARK: - Decay Timer

    /// Timer to ensure levels decay even when no new audio is received
    private func startDecayTimer() {
        decayTimer?.invalidate()
        decayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.applyDecay()
            }
        }
    }

    private func applyDecay() {
        // Apply minimum decay rate when no new samples are processed
        let decayRate = config.minDecayRate

        if micLevel > 0 {
            micLevel = max(0, micLevel - decayRate)
            previousMicLevel = micLevel
        }

        if playbackLevel > 0 {
            playbackLevel = max(0, playbackLevel - decayRate)
            previousPlaybackLevel = playbackLevel
        }
    }
}

// MARK: - Level Meter Extensions

extension AudioLevelMeter {

    /// Get the current level for a given source
    func level(for source: LevelSource) -> Float {
        switch source {
        case .mic:
            return micLevel
        case .playback:
            return playbackLevel
        case .combined:
            return max(micLevel, playbackLevel)
        }
    }

    enum LevelSource {
        case mic
        case playback
        case combined
    }
}

// MARK: - Level History (for visualization)

/// Stores a rolling history of levels for waveform-style visualization
final class LevelHistory: ObservableObject {

    @Published private(set) var samples: [Float]
    let maxSamples: Int

    init(maxSamples: Int = 64) {
        self.maxSamples = maxSamples
        self.samples = Array(repeating: 0, count: maxSamples)
    }

    func addSample(_ level: Float) {
        samples.removeFirst()
        samples.append(level)
    }

    func reset() {
        samples = Array(repeating: 0, count: maxSamples)
    }
}
