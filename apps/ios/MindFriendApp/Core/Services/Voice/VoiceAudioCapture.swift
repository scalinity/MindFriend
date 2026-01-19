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
    private let audioGain: Float = 3.0  // Boost mic input for better VAD

    // Audio level tracking
    private var previousMicLevel: Float = 0
    private let levelAttackCoeff: Float = 0.3
    private let levelReleaseCoeff: Float = 0.1
    private let noiseFloorDb: Float = -60.0
    private let ceilingDb: Float = -10.0

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
        }

        let rms = sqrt(sumSquares / Float(frameCount))
        let rmsDb = 20 * log10(max(rms, 1) / 32768.0)

        // Update mic level with smoothing
        let normalizedLevel = normalizeAudioLevel(rmsDb)
        updateMicLevel(normalizedLevel)

        // Send audio data
        onAudioData?(amplifiedData)
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
