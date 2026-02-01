import Foundation
import AVFoundation
import OSLog

/// Manages audio capture and processing for voice input
@MainActor
final class VoiceAudioCapture {

    // MARK: - Properties

    private let audioEngine = AVAudioEngine()
    private var audioFormat: AVAudioFormat?
    private var isCapturing = false
    private var audioTapBufferCount = 0

    // Audio processing configuration
    private let sampleRate: Double = 24000.0
    private let channelCount: AVAudioChannelCount = 1
    private let audioGain: Float = 1.8  // Reduced from 3.0 to minimize echo amplification

    // Audio level tracking
    private var previousMicLevel: Float = 0
    private let levelAttackCoeff: Float = 0.3
    private let levelReleaseCoeff: Float = 0.1
    private let noiseFloorDb: Float = -60.0
    private let ceilingDb: Float = -10.0

    // MARK: - Emotion Analysis Support

    /// Rolling buffer of recent audio samples for emotion analysis
    /// Uses circular buffer pattern to avoid O(n) array shifts
    private var rollingAudioBuffer: [Float] = []
    private var bufferWriteIndex: Int = 0
    private var bufferIsFull: Bool = false

    /// Whether emotion analysis buffer accumulation is enabled
    /// When false, skips buffer work entirely for better performance
    /// TEMPORARILY HARDCODED TO FALSE - emotion analysis disabled
    var emotionBufferEnabled: Bool = false {
        didSet { /* Ignored - emotion analysis disabled */ }
    }

    /// Maximum buffer duration in seconds (keep last 5 seconds)
    private let maxBufferDuration: Double = 5.0

    /// Maximum samples to keep in buffer (5s at 24kHz = 120,000 samples)
    private var maxBufferSamples: Int { Int(sampleRate * maxBufferDuration) }

    // Callbacks
    var onAudioData: ((Data) -> Void)?
    var onMicLevelUpdate: ((Float) -> Void)?

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
    }

    // MARK: - Capture Control

    func startCapture() throws {
        guard !isCapturing else {
            #if DEBUG
            Log.voice.debug("[AudioCapture] Already capturing")
            #endif
            return
        }

        #if DEBUG
        Log.voice.debug("[AudioCapture] Starting...")
        #endif

        // Configure audio session for recording
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

        let inputNode = audioEngine.inputNode
        // Note: isVoiceProcessingEnabled is read-only and automatically enabled in .voiceChat mode

        let nativeFormat = inputNode.outputFormat(forBus: 0)
        guard let targetFormat = audioFormat,
              nativeFormat.sampleRate > 0 else {
            throw VoiceError.audioSessionFailed("Invalid audio format")
        }

        // Create converter for sample rate conversion
        guard let converter = AVAudioConverter(from: nativeFormat, to: targetFormat) else {
            throw VoiceError.audioSessionFailed("Failed to create audio converter")
        }

        // Install audio tap
        inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: nativeFormat
        ) { [weak self] buffer, time in
            guard let self = self else { return }

            // Process on MainActor to avoid data races
            Task { @MainActor in
                self.audioTapBufferCount += 1
                #if DEBUG
                if self.audioTapBufferCount == 1 || self.audioTapBufferCount % 50 == 0 {
                    Log.voice.debug("[AudioCapture] Buffer #\(self.audioTapBufferCount), frames: \(buffer.frameLength)")
                }
                #endif

                self.processAndConvertAudioBuffer(buffer, converter: converter, targetFormat: targetFormat)
            }
        }

        audioEngine.prepare()
        try audioEngine.start()

        isCapturing = true
        audioTapBufferCount = 0

        #if DEBUG
        Log.voice.debug("[AudioCapture] Started, engine running: \(self.audioEngine.isRunning)")
        #endif
    }

    func stopCapture() {
        guard isCapturing else { return }

        #if DEBUG
        Log.voice.debug("[AudioCapture] Stopping")
        #endif

        audioEngine.inputNode.removeTap(onBus: 0)

        if audioEngine.isRunning {
            audioEngine.stop()
        }

        isCapturing = false

        // Deactivate audio session to release hardware resources
        // This allows other apps to use the microphone and reduces battery usage
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            #if DEBUG
            Log.voice.debug("[AudioCapture] Audio session deactivated")
            #endif
        } catch {
            #if DEBUG
            Log.voice.debug("[AudioCapture] Failed to deactivate audio session: \(error)")
            #endif
        }
        #endif
    }

    // MARK: - Audio Processing

    private func processAndConvertAudioBuffer(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) {
        guard buffer.format.sampleRate > 0 else {
            #if DEBUG
            Log.voice.debug("[AudioCapture] Invalid buffer sample rate: 0")
            #endif
            return
        }

        // Calculate output buffer capacity
        let inputFrames = AVAudioFrameCount(buffer.frameLength)
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrames = AVAudioFrameCount(ceil(Double(inputFrames) * ratio))

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrames) else {
            #if DEBUG
            Log.voice.debug("[AudioCapture] Failed to create output buffer")
            #endif
            return
        }

        var error: NSError?
        var inputConsumed = false

        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)

        if let error = error {
            #if DEBUG
            Log.voice.debug("[AudioCapture] Conversion error: \(error)")
            #endif
            return
        }

        processAudioBuffer(outputBuffer)
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // Early exit if capture was stopped (Tasks in flight may still call this)
        guard isCapturing else { return }

        guard let channelData = buffer.int16ChannelData else {
            #if DEBUG
            Log.voice.debug("[AudioCapture] No int16 channel data")
            #endif
            return
        }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else {
            #if DEBUG
            Log.voice.debug("[AudioCapture] Buffer has 0 frames")
            #endif
            return
        }

        // Apply gain amplification
        let samples = channelData[0]
        var amplifiedData = Data(capacity: frameCount * 2)
        var sumSquares: Float = 0
        var maxSample: Int16 = 0

        // Only accumulate float samples if emotion buffer is enabled
        var floatSamples: [Float]? = emotionBufferEnabled ? [] : nil
        floatSamples?.reserveCapacity(frameCount)

        for i in 0..<frameCount {
            let originalSample = samples[i]
            let amplified = Int32(Float(originalSample) * audioGain)
            let clippedSample = Int16(clamping: amplified)

            sumSquares += Float(clippedSample) * Float(clippedSample)
            let absSample = Int16(clamping: abs(Int32(clippedSample)))
            if absSample > maxSample {
                maxSample = absSample
            }

            var sample = clippedSample
            amplifiedData.append(Data(bytes: &sample, count: 2))

            // Normalize to [-1, 1] for emotion analysis buffer (only if enabled)
            if emotionBufferEnabled {
                floatSamples?.append(Float(clippedSample) / 32768.0)
            }
        }

        // Add to rolling buffer for emotion analysis (only if enabled)
        if let samples = floatSamples {
            appendToRollingBuffer(samples)
        }

        let rms = sqrt(sumSquares / Float(frameCount))
        let rmsDb = 20 * log10(max(rms, 1) / 32768.0)

        // Update mic level with smoothing
        let normalizedLevel = normalizeAudioLevel(rmsDb)
        updateMicLevel(normalizedLevel)

        // Send audio data
        onAudioData?(amplifiedData)
    }

    // MARK: - Rolling Buffer Management (Circular Buffer)

    /// Append audio samples using circular buffer pattern (O(1) instead of O(n))
    private func appendToRollingBuffer(_ samples: [Float]) {
        // Initialize buffer to full size on first use (pre-allocate)
        if rollingAudioBuffer.isEmpty {
            rollingAudioBuffer = [Float](repeating: 0, count: maxBufferSamples)
            bufferWriteIndex = 0
            bufferIsFull = false
        }

        // Write samples to circular buffer
        for sample in samples {
            rollingAudioBuffer[bufferWriteIndex] = sample
            bufferWriteIndex += 1

            if bufferWriteIndex >= maxBufferSamples {
                bufferWriteIndex = 0
                bufferIsFull = true
            }
        }
    }

    /// Get recent audio buffer for emotion analysis
    /// - Parameter duration: Duration in seconds (must be <= maxBufferDuration)
    /// - Returns: Array of Float samples at 24kHz, or nil if insufficient data
    func getRecentAudioBuffer(duration: Double = 3.0) -> [Float]? {
        let requiredSamples = Int(sampleRate * duration)

        // Calculate available samples
        let availableSamples = bufferIsFull ? maxBufferSamples : bufferWriteIndex

        guard availableSamples >= requiredSamples else {
            #if DEBUG
            Log.voice.debug("[AudioCapture] Insufficient buffer: \(availableSamples) samples, need \(requiredSamples)")
            #endif
            return nil
        }

        // Read from circular buffer - get most recent samples
        var result = [Float](repeating: 0, count: requiredSamples)
        var readIndex = bufferWriteIndex - requiredSamples
        if readIndex < 0 {
            readIndex += maxBufferSamples
        }

        for i in 0..<requiredSamples {
            result[i] = rollingAudioBuffer[readIndex]
            readIndex += 1
            if readIndex >= maxBufferSamples {
                readIndex = 0
            }
        }

        return result
    }

    /// Get the current buffer duration in seconds
    var currentBufferDuration: Double {
        let availableSamples = bufferIsFull ? maxBufferSamples : bufferWriteIndex
        return Double(availableSamples) / sampleRate
    }

    /// Clear the rolling audio buffer
    func clearRollingBuffer() {
        bufferWriteIndex = 0
        bufferIsFull = false
        // Keep the pre-allocated buffer, just reset indices
    }

    /// Resample audio buffer from capture rate (24kHz) to emotion analysis rate (16kHz)
    /// - Parameter inputBuffer: Audio at 24kHz
    /// - Returns: Audio resampled to 16kHz
    func resampleForEmotionAnalysis(_ inputBuffer: [Float]) -> [Float] {
        // Guard against empty input to prevent division issues
        guard !inputBuffer.isEmpty else {
            return []
        }

        let inputRate: Double = sampleRate       // 24000
        let outputRate: Double = 16000.0         // EmotionAnalyzer rate
        let ratio = inputRate / outputRate       // 1.5

        let outputLength = Int(Double(inputBuffer.count) / ratio)
        
        // Guard against degenerate case where output would be empty
        guard outputLength > 0 else {
            return []
        }
        
        var outputBuffer = [Float](repeating: 0, count: outputLength)

        // Simple linear interpolation resampling
        for i in 0..<outputLength {
            let sourceIndex = Double(i) * ratio
            let lowerIndex = Int(sourceIndex)
            let upperIndex = min(lowerIndex + 1, inputBuffer.count - 1)
            let fraction = Float(sourceIndex - Double(lowerIndex))

            outputBuffer[i] = inputBuffer[lowerIndex] * (1 - fraction) + inputBuffer[upperIndex] * fraction
        }

        return outputBuffer
    }

    /// Convert Float samples (normalized -1 to 1) to PCM16 Data for WebSocket transmission
    /// Used when flushing buffered audio after idle reconnection
    /// - Parameter samples: Float samples normalized to [-1, 1]
    /// - Returns: Data containing little-endian Int16 samples
    func convertToData(_ samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * 2)
        for sample in samples {
            // Scale and clamp to Int16 range
            let scaled = Int16(clamping: Int32(sample * 32767))
            withUnsafeBytes(of: scaled.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }

    // MARK: - Level Processing

    private func normalizeAudioLevel(_ db: Float) -> Float {
        let normalized = (db - noiseFloorDb) / (ceilingDb - noiseFloorDb)
        return max(0, min(1, normalized))
    }

    private func updateMicLevel(_ newLevel: Float) {
        // Smooth level changes with attack/release coefficients
        let coeff = newLevel > previousMicLevel ? levelAttackCoeff : levelReleaseCoeff
        let smoothedLevel = previousMicLevel + coeff * (newLevel - previousMicLevel)
        previousMicLevel = smoothedLevel

        onMicLevelUpdate?(smoothedLevel)
    }

    // MARK: - Cleanup

    deinit {
        // Manual cleanup - can't call @MainActor isolated methods from deinit
        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning {
            audioEngine.stop()
        }
    }
}
