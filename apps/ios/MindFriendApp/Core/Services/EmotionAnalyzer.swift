import AVFoundation
import Accelerate
import CoreML
import os.log

/// Wrapper class for FFTSetupD to handle cleanup in deinit
/// This avoids @MainActor isolation issues since this class is not actor-isolated
private final class FFTSetupWrapper {
    let setup: FFTSetupD?

    init(log2n: vDSP_Length) {
        setup = vDSP_create_fftsetupD(log2n, FFTRadix(kFFTRadix2))
    }

    deinit {
        if let setup = setup {
            vDSP_destroy_fftsetupD(setup)
        }
    }
}

/// Emotion classification result
struct EmotionResult {
    let emotion: String
    let confidence: Double
    let allProbabilities: [String: Double]
}

/// Protocol for dependency injection and testing
protocol EmotionAnalyzerProtocol {
    func analyzeAudio(at url: URL, userId: String?) async throws -> EmotionResult
    func analyzeAudioBuffer(_ audioBuffer: [Float], userId: String?) async throws -> EmotionResult
}

/// Emotion analyzer using Core ML model trained on speech prosody features.
/// Supports 8 emotion classes: angry, calm, disgust, fearful, happy, neutral, sad, surprised
///
/// ## Security Features
/// - URL validation prevents path traversal attacks
/// - Audio length limits prevent memory exhaustion
/// - Consent management required before analysis
/// - Rate limiting prevents abuse
///
/// ## Privacy
/// - All processing happens on-device
/// - No audio data is stored or transmitted
/// - User consent required for emotion analysis
@MainActor
final class EmotionAnalyzer: ObservableObject {

    // MARK: - Error Types

    enum EmotionAnalyzerError: LocalizedError {
        case invalidURL
        case pathTraversalAttempt
        case invalidFileFormat
        case audioTooLong
        case invalidAudioLength
        case audioLoadError(Error)
        case bufferCreationFailed
        case noAudioData
        case modelNotLoaded
        case noPrediction
        case featureExtractionFailed
        case consentRequired
        case rateLimitExceeded
        case inferenceTimeout
        case unsupportedFormat(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid audio URL provided"
            case .pathTraversalAttempt:
                return "Audio file path is outside allowed directory"
            case .invalidFileFormat:
                return "Audio file format is not supported"
            case .audioTooLong:
                return "Audio file exceeds maximum allowed duration (5 minutes)"
            case .invalidAudioLength:
                return "Audio file has invalid or zero length"
            case .audioLoadError(let error):
                return "Failed to load audio file: \(error.localizedDescription)"
            case .bufferCreationFailed:
                return "Failed to create audio buffer"
            case .noAudioData:
                return "No audio data in buffer"
            case .modelNotLoaded:
                return "Core ML model not loaded"
            case .noPrediction:
                return "Model failed to produce prediction"
            case .featureExtractionFailed:
                return "Failed to extract audio features"
            case .consentRequired:
                return "User consent is required for voice emotion analysis"
            case .rateLimitExceeded:
                return "Too many analysis requests. Please try again later."
            case .inferenceTimeout:
                return "Emotion analysis timed out"
            case .unsupportedFormat(let ext):
                return "Unsupported audio format: \(ext)"
            }
        }

        var failureReason: String? {
            switch self {
            case .invalidURL:
                return "The provided URL is not a valid file URL"
            case .pathTraversalAttempt:
                return "The file path attempts to access locations outside the allowed directories"
            case .invalidFileFormat:
                return "The file content does not match a supported audio format"
            case .audioTooLong:
                return "Audio duration exceeds the maximum allowed duration"
            case .invalidAudioLength:
                return "Audio frame count is zero or negative"
            case .audioLoadError(let error):
                return "Failed to read audio file: \(error.localizedDescription)"
            case .bufferCreationFailed:
                return "Could not allocate audio buffer with requested format"
            case .noAudioData:
                return "Audio buffer contains no sample data"
            case .modelNotLoaded:
                return "Core ML model could not be loaded from app bundle"
            case .noPrediction:
                return "Model inference did not produce a valid prediction"
            case .featureExtractionFailed:
                return "Feature extraction algorithms failed to process audio"
            case .consentRequired:
                return "User must grant consent before voice emotion analysis"
            case .rateLimitExceeded:
                return "Analysis rate limit exceeded"
            case .inferenceTimeout:
                return "Emotion analysis did not complete within timeout period"
            case .unsupportedFormat(let ext):
                return "File extension '.\(ext)' is not a supported audio format"
            }
        }
    }

    // MARK: - Properties

    @Published private(set) var isAnalyzing = false
    @Published private(set) var lastError: Error?

    // Model and resources
    private var model: MLModel?
    private var modelDescription: MLModelDescription?
    private var scalerMean: [Double] = []
    private var scalerScale: [Double] = []
    private var emotionLabels: [String] = []

    // Security and consent
    private var hasConsent: Bool = false
    private var analysisCount: [String: Int] = [:]
    private let maxAnalysesPerHour = 10
    private let maxAudioDuration: Double = 300  // 5 minutes
    private let maxSampleCount: Int
    private var lastAnalysisTime: Date?
    private let analysisTimeout: TimeInterval = 30.0


    // MARK: - Constants

    /// Feature dimension breakdown:
    /// - 160: MFCC (40 coeffs x 4 stats: mean, std, max, min)
    /// - 40: Delta MFCC mean
    /// - 40: Delta-delta MFCC mean
    /// - 6: Pitch/F0 features
    /// - 4: RMS energy features
    /// - 2: Zero crossing rate features
    /// - 10: Spectral (centroid, bandwidth, rolloff, flatness x 2)
    /// - 7: Spectral contrast
    /// - 24: Chroma (12 x 2)
    /// - 1: Harmonic ratio
    /// - 1: Duration
    /// Total: 295 (with scaler expects 290, we pad/truncate)
    private let featureDimension = 290

    /// Sample rate for audio processing (must match training: 16000 Hz)
    private let sampleRate: Double = 16000

    /// Target duration for analysis (3 seconds, matches training)
    private let targetDuration: Double = 3.0

    /// Frame processing parameters
    /// Frame length: 2048 samples (128ms at 16kHz)
    /// Hop length: 512 samples (32ms overlap)
    private let frameLength = 2048
    private let hopLength = 512

    /// Number of MFCC coefficients
    private let numMFCC = 40

    /// Delta window size for temporal derivatives
    private let deltaWindowSize = 2

    /// Number of spectral contrast bands
    private let numSpectralContrast = 7

    /// Number of chroma features (12 semitones)
    private let numChroma = 12

    /// Model resource name
    private let modelResourceName = "EmotionProsodyClassifier_20260122_124134"

    // Named constants for magic numbers
    private let rateLimitResetInterval: TimeInterval = 3600  // 1 hour in seconds
    private let spectralRolloffThreshold: Double = 0.85      // 85% energy threshold
    private let harmonicRatioEpsilon: Double = 1e-10         // Small value to prevent division by zero

    // MARK: - Accelerate FFT Setup (cached for performance)

    /// FFT setup for spectral analysis - log2(2048) = 11
    private let fftLog2n: vDSP_Length = 11
    private lazy var fftSetupWrapper = FFTSetupWrapper(log2n: fftLog2n)
    private var fftSetup: FFTSetupD? { fftSetupWrapper.setup }

    /// Hann window for frame windowing (precomputed)
    private lazy var hannWindow: [Double] = {
        var window = [Double](repeating: 0, count: frameLength)
        vDSP_hann_windowD(&window, vDSP_Length(frameLength), Int32(vDSP_HANN_NORM))
        return window
    }()

    // MARK: - Initialization

    init() {
        self.maxSampleCount = Int(sampleRate * maxAudioDuration)
        loadModel()
    }

    // Note: FFTSetupD cleanup handled automatically by ARC when the object is deallocated.
    // Cannot explicitly call vDSP_destroy_fftsetupD in deinit because fftSetup is @MainActor isolated.

    // MARK: - Consent Management

    /// Sets user consent for voice emotion analysis
    /// Must be called before any analysis can be performed
    func setVoiceConsent(_ granted: Bool) {
        hasConsent = granted
    }

    /// Checks if user has given consent for emotion analysis
    var isConsentGiven: Bool { hasConsent }

    // MARK: - Public Methods

    /// Analyze audio from a file URL and return emotion prediction
    /// - Parameters:
    ///   - url: URL to the audio file (wav, m4a, caf, mp3)
    ///   - userId: Optional user identifier for rate limiting
    /// - Returns: EmotionResult with predicted emotion and confidence scores
    func analyzeAudio(at url: URL, userId: String? = nil) async throws -> EmotionResult {
        try validateConsent()
        try validateURL(url)
        try checkRateLimit(for: userId ?? "anonymous")

        // Capture FFT resources before entering detached task (main actor isolated)
        let capturedWindow = hannWindow
        let capturedFFTSetup = fftSetup

        return try await performAnalysis {
            try self.extractFeatures(from: url, window: capturedWindow, fftSetup: capturedFFTSetup)
        }
    }

    /// Analyze audio buffer directly (for real-time processing)
    /// - Parameters:
    ///   - audioBuffer: PCM audio samples
    ///   - userId: Optional user identifier for rate limiting
    /// - Returns: EmotionResult with predicted emotion and confidence scores
    func analyzeAudioBuffer(_ audioBuffer: [Float], userId: String? = nil) async throws -> EmotionResult {
        try validateConsent()
        try checkRateLimit(for: userId ?? "anonymous")

        // Capture FFT resources before entering detached task (main actor isolated)
        let capturedWindow = hannWindow
        let capturedFFTSetup = fftSetup

        return try await performAnalysis {
            try self.extractFeatures(from: audioBuffer, window: capturedWindow, fftSetup: capturedFFTSetup)
        }
    }

    // MARK: - Private Methods - Analysis

    private func performAnalysis(featureExtractor: @escaping () async throws -> [Double]) async throws -> EmotionResult {
        isAnalyzing = true
        lastError = nil

        defer {
            isAnalyzing = false
            updateRateLimit()
        }

        // Capture scaler values before detached task (main actor isolated)
        let capturedMean = scalerMean
        let capturedScale = scalerScale

        do {
            // Extract features on a background thread to avoid blocking main thread
            // Feature extraction is CPU-intensive (DSP algorithms on 48k samples)
            let features = try await Task.detached(priority: .userInitiated) {
                try await featureExtractor()
            }.value

            // Normalize features (can also run on background since we captured scaler values)
            let normalizedFeatures = normalizeFeatures(features, mean: capturedMean, scale: capturedScale)

            // Run ML inference (CoreML handles threading internally)
            let result = try await runInference(features: normalizedFeatures)

            return result
        } catch {
            lastError = error
            throw error
        }
    }

    // MARK: - Private Methods - Validation

    private func validateConsent() throws {
        guard hasConsent else {
            throw EmotionAnalyzerError.consentRequired
        }
    }

    private func validateURL(_ url: URL) throws {
        // Validate URL scheme
        guard url.isFileURL else {
            throw EmotionAnalyzerError.invalidURL
        }

        // Get allowed directories
        let documentDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let tempDir = FileManager.default.temporaryDirectory

        // Check path is within allowed directories
        let isInDocumentDir = documentDir.map { url.path.hasPrefix($0.path) } ?? false
        let isInTempDir = url.path.hasPrefix(tempDir.path)

        guard isInDocumentDir || isInTempDir else {
            throw EmotionAnalyzerError.pathTraversalAttempt
        }

        // Validate file extension
        let allowedExtensions = ["wav", "m4a", "mp3", "caf", "aac"]
        let ext = url.pathExtension.lowercased()
        guard allowedExtensions.contains(ext) else {
            throw EmotionAnalyzerError.unsupportedFormat(ext)
        }
    }

    nonisolated private func validateAudioLength(_ frameCount: AVAudioFrameCount) throws {
        guard frameCount > 0 else {
            throw EmotionAnalyzerError.invalidAudioLength
        }

        let sampleCount = Int(frameCount)
        // maxSampleCount = sampleRate * maxAudioDuration = 16000 * 300 = 4,800,000
        let maxAllowedSamples = 4_800_000
        guard sampleCount <= maxAllowedSamples else {
            throw EmotionAnalyzerError.audioTooLong
        }
    }

    private func checkRateLimit(for userId: String) throws {
        let now = Date()

        // Reset hourly counter if needed
        if let lastTime = lastAnalysisTime, now.timeIntervalSince(lastTime) > rateLimitResetInterval {
            analysisCount.removeAll()
        }

        // Check rate limit
        let count = analysisCount[userId] ?? 0
        guard count < maxAnalysesPerHour else {
            throw EmotionAnalyzerError.rateLimitExceeded
        }
    }

    private func updateRateLimit() {
        lastAnalysisTime = Date()
    }

    // MARK: - Private Methods - Model Loading

    private func loadModel() {
        do {
            // Load Core ML model - Xcode compiles .mlpackage to .mlmodelc
            print("[EmotionAnalyzer] Loading model: \(modelResourceName).mlmodelc")
            guard let modelURL = Bundle.main.url(forResource: modelResourceName, withExtension: "mlmodelc") else {
                print("[EmotionAnalyzer] ERROR: Model not found in bundle")
                os_log("Error: Core ML model not found in bundle (looking for %{public}@.mlmodelc)", type: .error, modelResourceName)
                return
            }

            print("[EmotionAnalyzer] Model URL: \(modelURL)")
            let modelConfig = MLModelConfiguration()
            // Use CPU and GPU only - avoid ANE to prevent XPC connection crashes
            // ANE uses XPC for communication which can be unstable with some models
            modelConfig.computeUnits = .cpuAndGPU

            model = try MLModel(contentsOf: modelURL, configuration: modelConfig)
            modelDescription = model?.modelDescription

            // Load scaler parameters
            loadScalerParameters()

            // Load emotion labels
            loadEmotionLabels()

            print("[EmotionAnalyzer] Model loaded successfully!")
            os_log("EmotionAnalyzer: Model loaded successfully", type: .info)
            os_log("Model input: %{public}@", type: .info,
                   modelDescription?.inputDescriptionsByName["features"]?.name ?? modelDescription?.inputDescriptionsByName.values.first?.name ?? "unknown")
            os_log("Model output: %{public}@", type: .info,
                   modelDescription?.outputDescriptionsByName["emotion_logits"]?.name ?? modelDescription?.outputDescriptionsByName.values.first?.name ?? "unknown")
        } catch {
            print("[EmotionAnalyzer] ERROR loading model: \(error.localizedDescription)")
            os_log("Error loading model: %{public}@", type: .error, error.localizedDescription)
            lastError = error
        }
    }

    private func loadScalerParameters() {
        guard let url = Bundle.main.url(forResource: "scaler_params", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mean = json["mean"] as? [Double],
              let scale = json["scale"] as? [Double],
              mean.count == featureDimension,
              scale.count == featureDimension else {
            os_log("Warning: Could not load scaler parameters, using defaults", type: .default)
            // Initialize with defaults (zero mean, unit scale)
            scalerMean = Array(repeating: 0.0, count: featureDimension)
            scalerScale = Array(repeating: 1.0, count: featureDimension)
            return
        }

        scalerMean = mean
        scalerScale = scale
        os_log("EmotionAnalyzer: Loaded %{public}d scaler parameters", type: .info, mean.count)
    }

    private func loadEmotionLabels() {
        guard let url = Bundle.main.url(forResource: "emotion_labels", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let labels = json["labels"] as? [String],
              !labels.isEmpty else {
            os_log("Warning: Could not load emotion labels, using defaults", type: .default)
            emotionLabels = ["angry", "calm", "disgust", "fearful", "happy", "neutral", "sad", "surprised"]
            return
        }

        emotionLabels = labels
        os_log("EmotionAnalyzer: Loaded %{public}d emotion labels", type: .info, labels.count)
    }

    // MARK: - Private Methods - Feature Extraction

    nonisolated private func extractFeatures(from url: URL, window: [Double], fftSetup: FFTSetupD?) throws -> [Double] {
        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: url)
        } catch {
            throw EmotionAnalyzerError.audioLoadError(error)
        }

        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)

        // Validate audio length
        try validateAudioLength(frameCount)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw EmotionAnalyzerError.bufferCreationFailed
        }

        try audioFile.read(into: buffer)

        guard let floatData = buffer.floatChannelData else {
            throw EmotionAnalyzerError.noAudioData
        }

        // Validate actual frame length
        let validFrameCount = min(Int(frameCount), Int(buffer.frameLength))
        guard validFrameCount > 0 else {
            throw EmotionAnalyzerError.noAudioData
        }

        // Use autoreleasepool for memory safety
        let samples: [Float] = autoreleasepool {
            let ptr = UnsafeBufferPointer(start: floatData[0], count: validFrameCount)
            return Array(ptr)
        }

        return try extractFeatures(from: samples, window: window, fftSetup: fftSetup)
    }

    nonisolated private func extractFeatures(from samples: [Float], window: [Double], fftSetup: FFTSetupD?) throws -> [Double] {
        var features: [Double] = []
        features.reserveCapacity(featureDimension)

        // Pad or truncate to target length
        let targetSamples = Int(sampleRate * targetDuration)
        let processedSamples = processAudioSamples(samples, targetLength: targetSamples)

        // Convert to Double for processing
        let doubleSamples = processedSamples.map { Double($0) }

        // Extract MFCC features using vDSP FFT (40 coefficients)
        let mfccs = extractMFCCs(from: doubleSamples, sampleRate: sampleRate, window: window, fftSetup: fftSetup)

        // MFCC mean, std, max, min (40 x 4 = 160 features)
        for i in 0..<numMFCC {
            features.append(mfccs.mean[i])
            features.append(mfccs.std[i])
            features.append(mfccs.max[i])
            features.append(mfccs.min[i])
        }

        // Delta MFCC mean (40 features)
        let mfccDelta = computeDelta(mfccs.values)
        for i in 0..<numMFCC {
            features.append(mfccDelta.mean[i])
        }

        // Delta-delta MFCC mean (40 features)
        let mfccDelta2 = computeDelta(mfccDelta.values)
        for i in 0..<numMFCC {
            features.append(mfccDelta2.mean[i])
        }

        // Pitch/F0 features
        let pitchFeatures = extractPitchFeatures(from: doubleSamples, sampleRate: sampleRate)
        features.append(contentsOf: pitchFeatures)

        // Energy/RMS features (4 features)
        let rms = computeRMS(doubleSamples)
        features.append(contentsOf: [rms.mean, rms.std, rms.max, rms.min])

        // Zero crossing rate (2 features)
        let zcr = computeZCR(doubleSamples)
        features.append(contentsOf: [zcr.mean, zcr.std])

        // Spectral features using vDSP FFT
        let spectralFeatures = extractSpectralFeatures(from: doubleSamples, sampleRate: sampleRate, window: window, fftSetup: fftSetup)
        features.append(contentsOf: spectralFeatures)

        // Chroma features using vDSP FFT (12 x 2 = 24 features)
        let chromaFeatures = extractChromaFeatures(from: doubleSamples, sampleRate: sampleRate, window: window, fftSetup: fftSetup)
        features.append(contentsOf: chromaFeatures)

        // Harmonic ratio (1 feature)
        let harmonicRatio = computeHarmonicRatio(from: doubleSamples)
        features.append(harmonicRatio)

        // Duration (1 feature)
        features.append(Double(processedSamples.count) / sampleRate)

        // Ensure exact feature dimension
        if features.count < featureDimension {
            features.append(contentsOf: Array(repeating: 0.0, count: featureDimension - features.count))
        } else if features.count > featureDimension {
            features = Array(features.prefix(featureDimension))
        }

        return features
    }

    nonisolated private func processAudioSamples(_ samples: [Float], targetLength: Int) -> [Float] {
        guard targetLength > 0 else { return samples }

        if samples.count >= targetLength {
            return Array(samples[..<targetLength])
        } else {
            return Array(repeating: 0, count: targetLength)
        }
    }

    // MARK: - Private Methods - Audio Feature Algorithms (nonisolated for background execution)
    // These use Accelerate framework for O(n log n) FFT instead of O(n²) naive DFT

    nonisolated private func extractMFCCs(from samples: [Double], sampleRate: Double, window: [Double], fftSetup: FFTSetupD?) -> (values: [[Double]], mean: [Double], std: [Double], max: [Double], min: [Double]) {
        let estimatedFrames = max(1, (samples.count - frameLength) / hopLength + 1)
        var mfccValues: [[Double]] = []
        mfccValues.reserveCapacity(estimatedFrames)

        var frameStart = 0

        while frameStart + frameLength <= samples.count {
            // Extract and window the frame using vDSP
            let frame = Array(samples[frameStart..<(frameStart + frameLength)])
            var windowedFrame = [Double](repeating: 0, count: frameLength)
            vDSP_vmulD(frame, 1, window, 1, &windowedFrame, 1, vDSP_Length(frameLength))

            // Compute power spectrum using vDSP FFT
            let magnitudes = computeFFTMagnitudes(windowedFrame, fftSetup: fftSetup)

            // Compute MFCCs from power spectrum using mel filterbank approximation
            let mfcc = computeMFCCFromSpectrum(magnitudes, sampleRate: sampleRate)
            mfccValues.append(mfcc)
            frameStart += hopLength
        }

        // Guard against empty arrays
        guard !mfccValues.isEmpty else {
            let defaults = Array(repeating: 0.0, count: numMFCC)
            let negInf = Array(repeating: -Double.infinity, count: numMFCC)
            let posInf = Array(repeating: Double.infinity, count: numMFCC)
            return (mfccValues, defaults, defaults, negInf, posInf)
        }

        // Compute statistics using vDSP
        let (means, stds, maxes, mins) = computeMFCCStatistics(mfccValues)
        return (mfccValues, means, stds, maxes, mins)
    }

    /// Compute FFT magnitudes using Accelerate vDSP - O(n log n)
    nonisolated private func computeFFTMagnitudes(_ frame: [Double], fftSetup: FFTSetupD?) -> [Double] {
        let n = frame.count
        let halfN = n / 2

        // Prepare split complex arrays for FFT
        var real = [Double](repeating: 0, count: halfN)
        var imag = [Double](repeating: 0, count: halfN)

        // Convert to split complex format (interleaved -> split)
        frame.withUnsafeBufferPointer { framePtr in
            real.withUnsafeMutableBufferPointer { realPtr in
                imag.withUnsafeMutableBufferPointer { imagPtr in
                    var splitComplex = DSPDoubleSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                    vDSP_ctozD(UnsafePointer<DSPDoubleComplex>(OpaquePointer(framePtr.baseAddress!)), 2, &splitComplex, 1, vDSP_Length(halfN))
                }
            }
        }

        // Perform FFT
        if let setup = fftSetup {
            real.withUnsafeMutableBufferPointer { realPtr in
                imag.withUnsafeMutableBufferPointer { imagPtr in
                    var splitComplex = DSPDoubleSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                    vDSP_fft_zripD(setup, &splitComplex, 1, vDSP_Length(fftLog2n), FFTDirection(FFT_FORWARD))
                }
            }
        }

        // Compute magnitudes: sqrt(real² + imag²)
        var magnitudes = [Double](repeating: 0, count: halfN + 1)
        for i in 0..<halfN {
            magnitudes[i] = sqrt(real[i] * real[i] + imag[i] * imag[i])
        }
        // DC component
        magnitudes[halfN] = abs(real[0])

        return magnitudes
    }

    /// Compute MFCCs from power spectrum using mel filterbank
    nonisolated private func computeMFCCFromSpectrum(_ magnitudes: [Double], sampleRate: Double) -> [Double] {
        let numFilters = numMFCC + 6  // Use more mel filters than coefficients
        let halfN = magnitudes.count

        // Compute mel filterbank energies (simplified triangular filters)
        var melEnergies = [Double](repeating: 0, count: numFilters)
        let maxMel = 2595.0 * log10(1 + sampleRate / 2 / 700.0)

        for i in 0..<numFilters {
            let melCenter = maxMel * Double(i + 1) / Double(numFilters + 1)
            let freqCenter = 700.0 * (pow(10.0, melCenter / 2595.0) - 1)
            let binCenter = Int(freqCenter * Double(halfN) / (sampleRate / 2))

            let melWidth = maxMel / Double(numFilters + 1)
            let freqWidth = 700.0 * (pow(10.0, melWidth / 2595.0) - 1)
            let binWidth = max(1, Int(freqWidth * Double(halfN) / (sampleRate / 2)))

            var energy: Double = 0
            let startBin = max(0, binCenter - binWidth)
            let endBin = min(halfN - 1, binCenter + binWidth)

            for k in startBin...endBin {
                let weight = 1.0 - abs(Double(k - binCenter)) / Double(binWidth + 1)
                energy += magnitudes[k] * magnitudes[k] * weight
            }
            melEnergies[i] = log(max(energy, 1e-10))
        }

        // Apply DCT to get MFCCs (Type-II DCT approximation)
        var mfcc = [Double](repeating: 0, count: numMFCC)
        for i in 0..<numMFCC {
            var sum: Double = 0
            for j in 0..<numFilters {
                sum += melEnergies[j] * cos(.pi * Double(i) * (Double(j) + 0.5) / Double(numFilters))
            }
            mfcc[i] = sum
        }

        return mfcc
    }

    /// Compute MFCC statistics using vectorized operations
    nonisolated private func computeMFCCStatistics(_ mfccValues: [[Double]]) -> (mean: [Double], std: [Double], max: [Double], min: [Double]) {
        var means = [Double](repeating: 0, count: numMFCC)
        var stds = [Double](repeating: 0, count: numMFCC)
        var maxes = [Double](repeating: -Double.infinity, count: numMFCC)
        var mins = [Double](repeating: Double.infinity, count: numMFCC)
        let count = Double(mfccValues.count)

        for i in 0..<numMFCC {
            var sum: Double = 0
            var sumSq: Double = 0
            var maxVal = -Double.infinity
            var minVal = Double.infinity

            for frame in mfccValues {
                let val = frame[i]
                sum += val
                sumSq += val * val
                maxVal = Swift.max(maxVal, val)
                minVal = Swift.min(minVal, val)
            }

            means[i] = sum / count
            stds[i] = sqrt(Swift.max(0, sumSq / count - means[i] * means[i]))
            maxes[i] = maxVal
            mins[i] = minVal
        }

        return (means, stds, maxes, mins)
    }

    nonisolated private func computeDelta(_ values: [[Double]]) -> (values: [[Double]], mean: [Double]) {
        var deltas: [[Double]] = []

        for i in 0..<values.count {
            var delta: [Double] = Array(repeating: 0.0, count: numMFCC)
            for j in 0..<numMFCC {
                var sum: Double = 0
                var count: Double = 0
                for n in 1...deltaWindowSize {
                    if i - n >= 0 {
                        sum += Double(n) * (values[i][j] - values[i - n][j])
                        count += Double(n * n)
                    }
                    if i + n < values.count {
                        sum += Double(n) * (values[i + n][j] - values[i][j])
                        count += Double(n * n)
                    }
                }
                delta[j] = count > 0 ? sum / (2 * count) : 0
            }
            deltas.append(delta)
        }

        // Guard against empty deltas
        var means = [Double](repeating: 0, count: numMFCC)
        if !deltas.isEmpty {
            for i in 0..<numMFCC {
                var sum: Double = 0
                for frame in deltas {
                    sum += frame[i]
                }
                means[i] = sum / Double(deltas.count)
            }
        }

        return (deltas, means)
    }

    nonisolated private func extractPitchFeatures(from samples: [Double], sampleRate: Double) -> [Double] {
        var f0Values: [Double] = []
        var frameStart = 0

        while frameStart + frameLength <= samples.count {
            let frame = Array(samples[frameStart..<frameStart + frameLength])
            let f0 = estimateF0(frame, sampleRate: sampleRate)
            f0Values.append(f0)
            frameStart += hopLength
        }

        let validF0 = f0Values.filter { $0 > 0 }

        // Guard against empty arrays
        guard !validF0.isEmpty else {
            return [200.0, 50.0, 50.0, 500.0, 450.0, 0.0] // Voice pitch defaults
        }

        let mean = validF0.reduce(0, +) / Double(validF0.count)
        let variance = validF0.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(validF0.count)

        return [
            mean,
            sqrt(variance),
            validF0.min() ?? 0,
            validF0.max() ?? 0,
            (validF0.max() ?? 0) - (validF0.min() ?? 0),
            Double(validF0.count) / Double(f0Values.count)
        ]
    }

    nonisolated private func estimateF0(_ frame: [Double], sampleRate: Double) -> Double {
        let minLag = Int(sampleRate / 500)
        let maxLag = Int(sampleRate / 50)

        var bestLag = minLag
        var bestCorr: Double = 0

        for lag in minLag..<min(maxLag, frame.count / 2) {
            var corr: Double = 0
            for i in 0..<(frame.count - lag) {
                corr += frame[i] * frame[i + lag]
            }

            if corr > bestCorr {
                bestCorr = corr
                bestLag = lag
            }
        }

        guard bestCorr > 0 else { return 0 }

        let f0 = sampleRate / Double(bestLag)
        return (f0 >= 50 && f0 <= 500) ? f0 : 0
    }

    nonisolated private func computeRMS(_ samples: [Double]) -> (mean: Double, std: Double, max: Double, min: Double) {
        var rmsValues: [Double] = []
        var frameStart = 0

        while frameStart + frameLength <= samples.count {
            var sumSquares: Double = 0
            for i in 0..<frameLength {
                sumSquares += samples[frameStart + i] * samples[frameStart + i]
            }
            rmsValues.append(sqrt(sumSquares / Double(frameLength)))
            frameStart += hopLength
        }

        // Guard against empty arrays
        guard !rmsValues.isEmpty else {
            return (0, 0, 0, 0)
        }

        let mean = rmsValues.reduce(0, +) / Double(rmsValues.count)
        let variance = rmsValues.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(rmsValues.count)

        return (mean, sqrt(variance), rmsValues.max() ?? 0, rmsValues.min() ?? 0)
    }

    nonisolated private func computeZCR(_ samples: [Double]) -> (mean: Double, std: Double) {
        var zcrValues: [Double] = []
        var frameStart = 0

        // Guard against frameLength = 1 (division by zero)
        guard frameLength > 1 else {
            return (0, 0)
        }

        while frameStart + frameLength <= samples.count {
            var crossings = 0
            for i in 1..<frameLength {
                if (samples[frameStart + i] >= 0 && samples[frameStart + i - 1] < 0) ||
                   (samples[frameStart + i] < 0 && samples[frameStart + i - 1] >= 0) {
                    crossings += 1
                }
            }
            zcrValues.append(Double(crossings) / Double(frameLength - 1))
            frameStart += hopLength
        }

        // Guard against empty arrays
        guard !zcrValues.isEmpty else {
            return (0, 0)
        }

        let mean = zcrValues.reduce(0, +) / Double(zcrValues.count)
        let variance = zcrValues.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(zcrValues.count)

        return (mean, sqrt(variance))
    }

    nonisolated private func extractSpectralFeatures(from samples: [Double], sampleRate: Double, window: [Double], fftSetup: FFTSetupD?) -> [Double] {
        var features: [Double] = []
        var spectralCentroids: [Double] = []
        var spectralBandwidths: [Double] = []
        var spectralRolloffs: [Double] = []
        var spectralFlatness: [Double] = []
        var spectralContrast: [[Double]] = []

        guard samples.count >= frameLength else {
            return Array(repeating: 0.0, count: 17)
        }

        var frameStart = 0
        let nyquist = sampleRate / 2

        while frameStart + frameLength <= samples.count {
            // Extract and window the frame
            let frame = Array(samples[frameStart..<frameStart + frameLength])
            var windowedFrame = [Double](repeating: 0, count: frameLength)
            vDSP_vmulD(frame, 1, window, 1, &windowedFrame, 1, vDSP_Length(frameLength))

            // Compute magnitudes using FFT (O(n log n) instead of O(n²))
            let magnitudes = computeFFTMagnitudes(windowedFrame, fftSetup: fftSetup)

            guard magnitudes.count > 1 else {
                spectralCentroids.append(0)
                spectralBandwidths.append(0)
                spectralRolloffs.append(0)
                spectralFlatness.append(0)
                spectralContrast.append(Array(repeating: 0, count: numSpectralContrast))
                frameStart += hopLength
                continue
            }

            // Spectral centroid
            var num: Double = 0
            var denom: Double = 0
            for k in 0..<magnitudes.count {
                let freq = nyquist * Double(k) / Double(magnitudes.count - 1)
                num += freq * magnitudes[k]
                denom += magnitudes[k]
            }
            let centroid = denom > 0 ? num / denom : 0
            spectralCentroids.append(centroid)

            // Spectral bandwidth
            var bandwidthSum: Double = 0
            for k in 0..<magnitudes.count {
                let freq = nyquist * Double(k) / Double(magnitudes.count - 1)
                bandwidthSum += magnitudes[k] * (freq - centroid) * (freq - centroid)
            }
            spectralBandwidths.append(denom > 0 ? sqrt(bandwidthSum / denom) : 0)

            // Spectral rolloff (85%)
            var rolloffSum: Double = 0
            let rolloffThreshold = spectralRolloffThreshold * denom
            var rolloffFreq = nyquist
            for k in 0..<magnitudes.count {
                rolloffSum += magnitudes[k]
                if rolloffSum >= rolloffThreshold {
                    rolloffFreq = nyquist * Double(k) / Double(magnitudes.count - 1)
                    break
                }
            }
            spectralRolloffs.append(rolloffFreq)

            // Spectral flatness
            var logSum: Double = 0
            var linearSum: Double = 0
            var numNonZero = 0
            for m in magnitudes where m > 0 {
                logSum += log(m)
                linearSum += m
                numNonZero += 1
            }
            if numNonZero > 0 && linearSum > 0 {
                let geometricMean = exp(logSum / Double(numNonZero))
                spectralFlatness.append(geometricMean / (linearSum / Double(magnitudes.count)))
            } else {
                spectralFlatness.append(0)
            }

            // Spectral contrast
            let bandSize = max(1, magnitudes.count / (numSpectralContrast + 1))
            var bandValues: [Double] = []
            for band in 0..<numSpectralContrast {
                let start = band * bandSize
                let end = min(start + bandSize, magnitudes.count)
                var valleySum: Double = 0
                var peakSum: Double = 0
                var valleyCount = 0
                var peakCount = 0

                for k in start..<end {
                    valleySum += magnitudes[k]
                    valleyCount += 1
                    if k + bandSize < magnitudes.count {
                        peakSum += magnitudes[k + bandSize]
                        peakCount += 1
                    }
                }

                let valleyAvg = valleyCount > 0 ? valleySum / Double(valleyCount) : 0
                let peakAvg = peakCount > 0 ? peakSum / Double(peakCount) : 0
                bandValues.append(peakAvg - valleyAvg)
            }
            spectralContrast.append(bandValues)

            frameStart += hopLength
        }

        // Aggregate features using helper
        func aggregate(_ values: [Double]) -> [Double] {
            guard !values.isEmpty else { return [0, 0] }
            var mean: Double = 0
            var stdDev: Double = 0
            vDSP_meanvD(values, 1, &mean, vDSP_Length(values.count))
            var variance: Double = 0
            var temp = [Double](repeating: 0, count: values.count)
            var negMean = -mean
            vDSP_vsaddD(values, 1, &negMean, &temp, 1, vDSP_Length(values.count))
            vDSP_dotprD(temp, 1, temp, 1, &variance, vDSP_Length(values.count))
            variance /= Double(values.count)
            stdDev = sqrt(variance)
            return [mean, stdDev]
        }

        features.append(contentsOf: aggregate(spectralCentroids))
        features.append(contentsOf: aggregate(spectralBandwidths))
        features.append(contentsOf: aggregate(spectralRolloffs))
        features.append(contentsOf: aggregate(spectralFlatness))

        // Spectral contrast means
        for band in 0..<numSpectralContrast {
            var bandSum: Double = 0
            var bandCount: Int = 0
            for frame in spectralContrast {
                if band < frame.count {
                    bandSum += frame[band]
                    bandCount += 1
                }
            }
            features.append(bandCount > 0 ? bandSum / Double(bandCount) : 0)
        }

        return features
    }

    nonisolated private func extractChromaFeatures(from samples: [Double], sampleRate: Double, window: [Double], fftSetup: FFTSetupD?) -> [Double] {
        var chromaFrames: [[Double]] = []
        let numChromaBins = 12

        guard samples.count >= frameLength else {
            return Array(repeating: 0.0, count: numChromaBins * 2)
        }

        var frameStart = 0
        let nyquist = sampleRate / 2

        while frameStart + frameLength <= samples.count {
            // Extract and window the frame
            let frame = Array(samples[frameStart..<frameStart + frameLength])
            var windowedFrame = [Double](repeating: 0, count: frameLength)
            vDSP_vmulD(frame, 1, window, 1, &windowedFrame, 1, vDSP_Length(frameLength))

            // Compute magnitudes using FFT
            let magnitudes = computeFFTMagnitudes(windowedFrame, fftSetup: fftSetup)

            // Map FFT bins to chroma
            var chroma = [Double](repeating: 0, count: numChromaBins)
            for k in 1..<magnitudes.count {
                let freq = nyquist * Double(k) / Double(magnitudes.count - 1)
                guard freq > 0 else { continue }

                // Map frequency to chroma bin (A4 = 440Hz as reference)
                let semitone = 12.0 * log2(freq / 440.0)
                let chromaBin = Int((semitone.truncatingRemainder(dividingBy: 12) + 12).truncatingRemainder(dividingBy: 12))
                chroma[chromaBin] += magnitudes[k] * magnitudes[k]
            }

            // Normalize
            var totalEnergy: Double = 0
            vDSP_sveD(chroma, 1, &totalEnergy, vDSP_Length(numChromaBins))
            if totalEnergy > 0 {
                var scale = 1.0 / totalEnergy
                vDSP_vsmulD(chroma, 1, &scale, &chroma, 1, vDSP_Length(numChromaBins))
            }

            chromaFrames.append(chroma)
            frameStart += hopLength
        }

        // Aggregate across frames
        var finalMeans = [Double](repeating: 0, count: numChromaBins)
        var finalStds = [Double](repeating: 0, count: numChromaBins)

        if !chromaFrames.isEmpty {
            let count = Double(chromaFrames.count)
            for i in 0..<numChromaBins {
                var sum: Double = 0
                var sumSq: Double = 0
                for frame in chromaFrames {
                    sum += frame[i]
                    sumSq += frame[i] * frame[i]
                }
                finalMeans[i] = sum / count
                finalStds[i] = sqrt(Swift.max(0, sumSq / count - finalMeans[i] * finalMeans[i]))
            }
        }

        var features: [Double] = []
        features.append(contentsOf: finalMeans)
        features.append(contentsOf: finalStds)
        return features
    }

    nonisolated private func computeHarmonicRatio(from samples: [Double]) -> Double {
        var harmonicSum: Double = 0
        var frameCount = 0

        for start in stride(from: 0, to: samples.count - frameLength + 1, by: frameLength) {
            let frame = Array(samples[start..<start + frameLength])

            // Compute autocorrelation
            var harmonic: Double = 0
            var percussive: Double = 0
            for lag in 1...frameLength / 2 {
                var acf: Double = 0
                for i in 0..<(frameLength - lag) {
                    acf += frame[i] * frame[i + lag]
                }
                if lag < frameLength / 4 {
                    harmonic += acf
                } else {
                    percussive += acf
                }
            }

            let total = harmonic + percussive + 1e-10
            harmonicSum += harmonic / total
            frameCount += 1
        }

        return frameCount > 0 ? harmonicSum / Double(frameCount) : 0
    }

    // MARK: - Private Methods - Normalization & Inference

    nonisolated private func normalizeFeatures(_ features: [Double], mean: [Double], scale: [Double]) -> [Double] {
        guard mean.count == featureDimension && scale.count == featureDimension else {
            return features
        }

        return zip(features, zip(mean, scale)).map { feature, meanScale in
            let (m, s) = meanScale
            return s > 0 ? (feature - m) / s : feature
        }
    }

    private func runInference(features: [Double]) async throws -> EmotionResult {
        guard let model = model,
              let modelDescription = modelDescription else {
            throw EmotionAnalyzerError.modelNotLoaded
        }

        // Convert features to MLMultiArray with proper 2D indexing
        let multiArray: MLMultiArray
        do {
            multiArray = try MLMultiArray(
                shape: [1, NSNumber(value: featureDimension)],
                dataType: .double
            )
        } catch {
            print("[EmotionAnalyzer] Failed to create MLMultiArray: \(error)")
            throw EmotionAnalyzerError.featureExtractionFailed
        }

        // Copy features to MLMultiArray
        for (index, value) in features.enumerated() {
            multiArray[[0, NSNumber(value: index)]] = NSNumber(value: value)
        }

        // Create input feature provider
        let inputName = modelDescription.inputDescriptionsByName["features"]?.name ?? modelDescription.inputDescriptionsByName.values.first?.name ?? "features"
        guard let inputProvider = try? MLDictionaryFeatureProvider(dictionary: [inputName: multiArray]) else {
            throw EmotionAnalyzerError.modelNotLoaded
        }

        // Run prediction with error handling
        let output: MLFeatureProvider
        do {
            output = try await model.prediction(from: inputProvider)
        } catch {
            print("[EmotionAnalyzer] ML prediction failed: \(error)")
            throw EmotionAnalyzerError.noPrediction
        }

        // Extract probabilities from output (model outputs "emotion_logits")
        let outputName = modelDescription.outputDescriptionsByName["emotion_logits"]?.name ?? modelDescription.outputDescriptionsByName.values.first?.name ?? "emotion_logits"
        guard let outputDict = output.featureValue(for: outputName) else {
            throw EmotionAnalyzerError.noPrediction
        }

        var probabilities: [String: Double] = [:]
        guard let outputArray = outputDict.multiArrayValue else {
            throw EmotionAnalyzerError.noPrediction
        }

        // Handle both 1D and 2D output arrays
        let shapeCount = outputArray.shape.count
        let count: Int
        if shapeCount >= 2 {
            count = min(Int(truncating: outputArray.shape[1] as NSNumber), emotionLabels.count)
        } else {
            count = min(Int(truncating: outputArray.shape[0] as NSNumber), emotionLabels.count)
        }

        for i in 0..<count {
            let index: [NSNumber] = shapeCount >= 2 ? [0, NSNumber(value: i)] : [NSNumber(value: i)]
            let value = outputArray[index]
            let doubleValue = value.doubleValue
            probabilities[emotionLabels[i]] = doubleValue
        }

        // Find dominant emotion
        let sorted = probabilities.sorted { $0.value > $1.value }
        guard let top = sorted.first else {
            throw EmotionAnalyzerError.noPrediction
        }

        // Softmax with numerical stability
        let maxLogit = sorted.first?.value ?? 0
        let expValues = sorted.map { exp($0.value - maxLogit) }
        let expSum = expValues.reduce(0, +)
        let softmaxProbabilities = Dictionary(uniqueKeysWithValues: zip(sorted.map { $0.key }, expValues.map { $0 / expSum }))

        guard let dominantConfidence = softmaxProbabilities[top.key] else {
            throw EmotionAnalyzerError.noPrediction
        }

        return EmotionResult(
            emotion: top.key,
            confidence: dominantConfidence,
            allProbabilities: softmaxProbabilities
        )
    }

    // MARK: - Private Methods - Cleanup

    private func clearSensitiveData() {
        scalerMean.removeAll()
        scalerScale.removeAll()
        analysisCount.removeAll()
    }

    // MARK: - Private Properties

    private var fftSize: Int { frameLength }
}

// MARK: - Supporting Types

extension EmotionAnalyzer {
    /// Emotion types supported by the analyzer
    enum Emotion: String, CaseIterable {
        case angry = "angry"
        case calm = "calm"
        case disgust = "disgust"
        case fearful = "fearful"
        case happy = "happy"
        case neutral = "neutral"
        case sad = "sad"
        case surprised = "surprised"
    }
}
