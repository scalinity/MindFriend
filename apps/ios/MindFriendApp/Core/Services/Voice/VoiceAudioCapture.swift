import Foundation
import AVFoundation
import OSLog

/// Identifies one successful capture start. Every buffer, level and byte that capture produces is
/// stamped with the generation that produced it, so work queued by an earlier start can never be
/// delivered into a later one.
typealias VoiceCaptureGeneration = UInt64

// MARK: - Hardware seam

/// The only place capture touches `AVAudioSession` / `AVAudioEngine`. Injectable so start-failure
/// cleanup can be verified deterministically without a microphone.
@MainActor
protocol VoiceCaptureHardware: AnyObject {
    /// Configure the session for recording and activate it.
    func activateSession() throws
    /// Native input format of the activated route. Throws when the route has no usable input.
    func nativeInputFormat() throws -> AVAudioFormat
    func installTap(format: AVAudioFormat, handler: @escaping @Sendable (AVAudioPCMBuffer) -> Void)
    /// Safe to call when no tap is installed.
    func removeTap()
    func startEngine() throws
    /// Safe to call when the engine is not running.
    func stopEngine()
    /// Safe to call when the session is not active; failures are not fatal.
    func deactivateSession()
}

/// Production hardware: one input engine plus the shared audio session.
@MainActor
final class SystemVoiceCaptureHardware: VoiceCaptureHardware {
    private let audioEngine = AVAudioEngine()

    func activateSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
    }

    func nativeInputFormat() throws -> AVAudioFormat {
        // Note: isVoiceProcessingEnabled is read-only and automatically enabled in .voiceChat mode.
        let format = audioEngine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw VoiceError.audioSessionFailed("Invalid audio format") }
        return format
    }

    func installTap(format: AVAudioFormat, handler: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        audioEngine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            handler(buffer)
        }
    }

    func removeTap() {
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    func startEngine() throws {
        audioEngine.prepare()
        try audioEngine.start()
    }

    func stopEngine() {
        if audioEngine.isRunning { audioEngine.stop() }
    }

    func deactivateSession() {
        // Release hardware so other apps can use the microphone and to reduce battery use.
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            #if DEBUG
            Log.voice.debug("[AudioCapture] Audio session deactivation failed (category only)")
            #endif
        }
        #endif
    }

    deinit {
        // Manual cleanup - can't call @MainActor isolated methods from deinit.
        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning {
            audioEngine.stop()
        }
    }
}

// MARK: - Capture

/// Manages audio capture and processing for voice input.
///
/// Lifecycle guarantees:
/// - `startCapture()` that fails at ANY step removes the tap, stops the engine and deactivates the
///   session before rethrowing, even though `isCapturing` was never set, so a retry starts clean.
/// - `stopCapture()` and `forceStop()` are idempotent. `forceStop()` is the central halt: it always
///   unwinds the hardware regardless of flags.
@MainActor
final class VoiceAudioCapture {

    // MARK: - Properties

    private let hardware: any VoiceCaptureHardware
    private var audioFormat: AVAudioFormat?
    private var isCapturing = false
    private var generationCounter: VoiceCaptureGeneration = 0
    /// The generation allowed to deliver audio. Cleared BEFORE the hardware is torn down.
    private var activeGeneration: VoiceCaptureGeneration?
    /// True from the moment any hardware mutation may have happened until teardown completes.
    private var hardwareMayBeActive = false
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

    // Callbacks. Both run synchronously on the main actor and carry the producing generation.
    var onAudioData: ((Data, VoiceCaptureGeneration) -> Void)?
    var onMicLevelUpdate: ((Float, VoiceCaptureGeneration) -> Void)?

    // MARK: - Initialization

    /// - Parameter hardware: Audio hardware boundary. `nil` uses the real session and engine.
    init(hardware: (any VoiceCaptureHardware)? = nil) {
        self.hardware = hardware ?? SystemVoiceCaptureHardware()
        setupAudioComponents()
    }

    /// Whether capture is currently running (the tap is delivering buffers).
    var isRunning: Bool { isCapturing }

    /// The generation currently allowed to deliver audio, or nil when capture is not running.
    var currentGeneration: VoiceCaptureGeneration? { activeGeneration }

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

    /// Starts capture and returns the new generation. Starting while already running returns the
    /// running generation unchanged.
    @discardableResult
    func startCapture() throws -> VoiceCaptureGeneration {
        if isCapturing, let running = activeGeneration { return running }

        #if DEBUG
        Log.voice.debug("[AudioCapture] Starting")
        #endif

        hardwareMayBeActive = true
        generationCounter += 1
        let generation = generationCounter
        do {
            try hardware.activateSession()

            let nativeFormat = try hardware.nativeInputFormat()
            guard let targetFormat = audioFormat else {
                throw VoiceError.audioSessionFailed("Invalid audio format")
            }
            // Create converter for sample rate conversion
            guard let converter = AVAudioConverter(from: nativeFormat, to: targetFormat) else {
                throw VoiceError.audioSessionFailed("Failed to create audio converter")
            }

            hardware.installTap(format: nativeFormat) { [weak self] buffer in
                // Deferred to the main actor. The task carries the generation that installed this
                // tap, so work queued before a stop/restart is rejected when it finally runs.
                Task { @MainActor in
                    guard let self else { return }
                    self.handleTap(buffer, converter: converter, targetFormat: targetFormat, generation: generation)
                }
            }

            try hardware.startEngine()

            isCapturing = true
            activeGeneration = generation
            audioTapBufferCount = 0
        } catch {
            // The tap/session may already be installed even though capture never began.
            teardownHardware()
            throw Self.narrowed(error)
        }

        #if DEBUG
        Log.voice.debug("[AudioCapture] Started")
        #endif
        return generation
    }

    /// Stops capture if it is (or may be) active. Idempotent.
    func stopCapture() {
        guard isCapturing || hardwareMayBeActive else { return }
        #if DEBUG
        Log.voice.debug("[AudioCapture] Stopping")
        #endif
        teardownHardware()
    }

    /// Unconditional unwind used by the central stop path: tap, engine and session are released
    /// whatever the flags say. Idempotent.
    func forceStop() {
        teardownHardware()
    }

    private func teardownHardware() {
        // Invalidate first: anything already queued by the old tap is rejected from here on.
        activeGeneration = nil
        hardware.removeTap()
        hardware.stopEngine()
        isCapturing = false
        hardware.deactivateSession()
        hardwareMayBeActive = false
        previousMicLevel = 0
    }

    private static func narrowed(_ error: Error) -> Error {
        if error is VoiceError { return error }
        return VoiceError.audioSessionFailed("The microphone could not be started.")
    }

    // MARK: - Audio Processing

    private func handleTap(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat,
        generation: VoiceCaptureGeneration
    ) {
        // A tap callback queued by an earlier capture must not be processed by a later one, even
        // though `isCapturing` is true again by the time it runs.
        guard isCapturing, activeGeneration == generation else { return }
        audioTapBufferCount += 1
        processAndConvertAudioBuffer(buffer, converter: converter, targetFormat: targetFormat, generation: generation)
    }

    private func processAndConvertAudioBuffer(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat,
        generation: VoiceCaptureGeneration
    ) {
        guard buffer.format.sampleRate > 0 else { return }

        // Calculate output buffer capacity
        let inputFrames = AVAudioFrameCount(buffer.frameLength)
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrames = AVAudioFrameCount(ceil(Double(inputFrames) * ratio))

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrames) else {
            return
        }

        var error: NSError?
        nonisolated(unsafe) var inputConsumed = false

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

        if error != nil { return }

        processAudioBuffer(outputBuffer, generation: generation)
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, generation: VoiceCaptureGeneration) {
        guard isCapturing, activeGeneration == generation else { return }

        guard let channelData = buffer.int16ChannelData else { return }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        // Apply gain amplification
        let samples = channelData[0]
        var amplifiedData = Data(capacity: frameCount * 2)
        var sumSquares: Float = 0

        for i in 0..<frameCount {
            let originalSample = samples[i]
            let amplified = Int32(Float(originalSample) * audioGain)
            let clippedSample = Int16(clamping: amplified)

            sumSquares += Float(clippedSample) * Float(clippedSample)

            var sample = clippedSample
            amplifiedData.append(Data(bytes: &sample, count: 2))
        }

        let rms = sqrt(sumSquares / Float(frameCount))
        let rmsDb = 20 * log10(max(rms, 1) / 32768.0)

        // Update mic level with smoothing
        let normalizedLevel = normalizeAudioLevel(rmsDb)
        updateMicLevel(normalizedLevel, generation: generation)

        // Deliver audio, stamped with the generation that produced it
        onAudioData?(amplifiedData, generation)
    }

    /// Convert Float samples (normalized -1 to 1) to PCM16 Data for WebSocket transmission
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

    private func updateMicLevel(_ newLevel: Float, generation: VoiceCaptureGeneration) {
        // Smooth level changes with attack/release coefficients
        let coeff = newLevel > previousMicLevel ? levelAttackCoeff : levelReleaseCoeff
        let smoothedLevel = previousMicLevel + coeff * (newLevel - previousMicLevel)
        previousMicLevel = smoothedLevel

        onMicLevelUpdate?(smoothedLevel, generation)
    }
}
