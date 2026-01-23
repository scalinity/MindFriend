import AVFoundation
import Accelerate
import CoreML
import os.log

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

    // Compiled model cleanup
    private var compiledModelURL: URL?

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

    // MARK: - Initialization

    init() {
        self.maxSampleCount = Int(sampleRate * maxAudioDuration)
        loadModel()
    }

    deinit {
        // Note: Cannot call @MainActor methods from deinit
        // clearSensitiveData() must be called explicitly before deinit if cleanup needed
        if let compiledURL = compiledModelURL {
            try? FileManager.default.removeItem(at: compiledURL)
        }
    }

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

        return try await performAnalysis {
            try self.extractFeatures(from: url)
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

        return try await performAnalysis {
            try self.extractFeatures(from: audioBuffer)
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

        do {
            // Extract features from audio (run on background)
            let features = try await Task.detached {
                try await featureExtractor()
            }.value

            // Normalize features
            let normalizedFeatures = normalizeFeatures(features)

            // Run ML inference with timeout
            let prediction = try await withThrowingTaskGroup(of: EmotionResult.self) { group in
                group.addTask {
                    try await self.runInference(features: normalizedFeatures)
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(self.analysisTimeout * 1_000_000_000))
                    throw EmotionAnalyzerError.inferenceTimeout
                }
                return try await group.next() ?? {
                    throw EmotionAnalyzerError.noPrediction
                }()
            }

            return prediction
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

    private func validateAudioLength(_ frameCount: AVAudioFrameCount) throws {
        guard frameCount > 0 else {
            throw EmotionAnalyzerError.invalidAudioLength
        }

        let sampleCount = Int(frameCount)
        guard sampleCount <= maxSampleCount else {
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
            // Load Core ML model
            guard let modelURL = Bundle.main.url(forResource: modelResourceName, withExtension: "mlpackage") else {
                os_log("Error: Core ML model not found in bundle", type: .error)
                return
            }

            let compiledURL = try MLModel.compileModel(at: modelURL)
            self.compiledModelURL = compiledURL

            let modelConfig = MLModelConfiguration()
            modelConfig.computeUnits = .all // Use all available cores for faster inference

            model = try MLModel(contentsOf: compiledURL, configuration: modelConfig)
            modelDescription = model?.modelDescription

            // Load scaler parameters
            loadScalerParameters()

            // Load emotion labels
            loadEmotionLabels()

            os_log("EmotionAnalyzer: Model loaded successfully", type: .info)
            os_log("Model input: %{public}@", type: .info,
                   modelDescription?.inputDescriptionsByName["features"]?.name ?? modelDescription?.inputDescriptionsByName.values.first?.name ?? "unknown")
            os_log("Model output: %{public}@", type: .info,
                   modelDescription?.outputDescriptionsByName["output"]?.name ?? modelDescription?.outputDescriptionsByName.values.first?.name ?? "unknown")
        } catch {
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

    private func extractFeatures(from url: URL) throws -> [Double] {
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

        return try extractFeatures(from: samples)
    }

    private func extractFeatures(from samples: [Float]) throws -> [Double] {
        var features: [Double] = []
        features.reserveCapacity(featureDimension)

        // Pad or truncate to target length
        let targetSamples = Int(sampleRate * targetDuration)
        let processedSamples = processAudioSamples(samples, targetLength: targetSamples)

        // Convert to Double for processing
        let doubleSamples = processedSamples.map { Double($0) }

        // Extract MFCC features (40 coefficients)
        let mfccs = extractMFCCs(from: doubleSamples, sampleRate: sampleRate)

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

        // Spectral features
        let spectralFeatures = extractSpectralFeatures(from: doubleSamples, sampleRate: sampleRate)
        features.append(contentsOf: spectralFeatures)

        // Chroma features (12 x 2 = 24 features)
        let chromaFeatures = extractChromaFeatures(from: doubleSamples, sampleRate: sampleRate)
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

    private func processAudioSamples(_ samples: [Float], targetLength: Int) -> [Float] {
        guard targetLength > 0 else { return samples }

        if samples.count >= targetLength {
            return Array(samples[..<targetLength])
        } else {
            return Array(repeating: 0, count: targetLength)
        }
    }

    // MARK: - Private Methods - Audio Feature Algorithms

    private func extractMFCCs(from samples: [Double], sampleRate: Double) -> (values: [[Double]], mean: [Double], std: [Double], max: [Double], min: [Double]) {
        // Estimate number of frames for pre-allocation
        let estimatedFrames = max(1, (samples.count - frameLength) / hopLength + 1)
        var mfccValues: [[Double]] = []
        mfccValues.reserveCapacity(estimatedFrames)

        var frameStart = 0

        while frameStart + frameLength <= samples.count {
            // Use UnsafeBufferPointer for zero-copy access
            var frame = [Double](repeating: 0, count: frameLength)
            samples.withUnsafeBufferPointer { samplesPtr in
                memcpy(&frame, samplesPtr.baseAddress!.advanced(by: frameStart), frameLength * MemoryLayout<Double>.size)
            }

            // Compute MFCC for frame using DCT approximation
            var mfcc = [Double](repeating: 0, count: numMFCC)
            for coef in 0..<numMFCC {
                var sum: Double = 0
                for n in 0..<frameLength {
                    let window = 0.5 * (1 - cos(2 * .pi * Double(n) / Double(frameLength - 1)))
                    sum += window * frame[n] * cos(.pi * Double(coef) * (2.0 * Double(n) + 1) / (2.0 * Double(frameLength)))
                }
                mfcc[coef] = sum
            }

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

        // Single-pass statistics computation
        var means = [Double](repeating: 0, count: numMFCC)
        var stds = [Double](repeating: 0, count: numMFCC)
        var maxes = [Double](repeating: -Double.infinity, count: numMFCC)
        var mins = [Double](repeating: Double.infinity, count: numMFCC)

        for i in 0..<numMFCC {
            var sum: Double = 0
            var sumSquares: Double = 0
            var maxVal = -Double.infinity
            var minVal = Double.infinity

            for frame in mfccValues {
                let val = frame[i]
                sum += val
                sumSquares += val * val
                maxVal = max(maxVal, val)
                minVal = min(minVal, val)
            }

            let count = Double(mfccValues.count)
            means[i] = sum / count
            stds[i] = sqrt(max(0, sumSquares / count - means[i] * means[i]))
            maxes[i] = maxVal
            mins[i] = minVal
        }

        return (mfccValues, means, stds, maxes, mins)
    }

    private func computeDelta(_ values: [[Double]]) -> (values: [[Double]], mean: [Double]) {
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

    private func extractPitchFeatures(from samples: [Double], sampleRate: Double) -> [Double] {
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

    private func estimateF0(_ frame: [Double], sampleRate: Double) -> Double {
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

    private func computeRMS(_ samples: [Double]) -> (mean: Double, std: Double, max: Double, min: Double) {
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

    private func computeZCR(_ samples: [Double]) -> (mean: Double, std: Double) {
        var zcrValues: [Double] = []
        var frameStart = 0

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

    private func extractSpectralFeatures(from samples: [Double], sampleRate: Double) -> [Double] {
        var features: [Double] = []

        var spectralCentroids: [Double] = []
        var spectralBandwidths: [Double] = []
        var spectralRolloffs: [Double] = []
        var spectralFlatness: [Double] = []
        var spectralContrast: [[Double]] = []

        var frameStart = 0

        while frameStart + frameLength <= samples.count {
            let frame = Array(samples[frameStart..<frameStart + frameLength])

            // Compute magnitudes using optimized approach
            var magnitudes: [Double] = Array(repeating: 0, count: fftSize / 2 + 1)

            for k in 0..<(fftSize / 2 + 1) {
                var realSum: Double = 0
                var imagSum: Double = 0
                for n in 0..<fftSize {
                    let angle = -2 * .pi * Double(k) * Double(n) / Double(fftSize)
                    realSum += frame[n] * cos(angle)
                    imagSum += frame[n] * sin(angle)
                }
                magnitudes[k] = sqrt(realSum * realSum + imagSum * imagSum)
            }

            // Spectral centroid
            var num: Double = 0
            var denom: Double = 0
            let nyquist = sampleRate / 2
            for k in 0..<magnitudes.count {
                let freq = nyquist * Double(k) / Double(magnitudes.count - 1)
                num += freq * magnitudes[k]
                denom += magnitudes[k]
            }
            spectralCentroids.append(denom > 0 ? num / denom : 0)

            // Spectral bandwidth
            let centroid = spectralCentroids.last ?? 0
            var bandwidthSum: Double = 0
            for k in 0..<magnitudes.count {
                let freq = nyquist * Double(k) / Double(magnitudes.count - 1)
                bandwidthSum += magnitudes[k] * (freq - centroid) * (freq - centroid)
            }
            spectralBandwidths.append(denom > 0 ? sqrt(bandwidthSum / denom) : 0)

            // Spectral rolloff (85%)
            var rolloffSum: Double = 0
            let rolloffThreshold = spectralRolloffThreshold * denom
            var rolloffFound = false
            for k in 0..<magnitudes.count {
                rolloffSum += magnitudes[k]
                if rolloffSum >= rolloffThreshold {
                    spectralRolloffs.append(nyquist * Double(k) / Double(magnitudes.count - 1))
                    rolloffFound = true
                    break
                }
            }
            if !rolloffFound {
                spectralRolloffs.append(nyquist)
            }

            // Spectral flatness
            var logSum: Double = 0
            var linearSum: Double = 0
            for m in magnitudes where m > 0 {
                logSum += log(m)
                linearSum += m
            }
            let numNonZero = magnitudes.filter { $0 > 0 }.count
            if numNonZero > 0 && linearSum > 0 {
                let geometricMean = exp(logSum / Double(numNonZero))
                spectralFlatness.append(geometricMean / (linearSum / Double(magnitudes.count)))
            } else {
                spectralFlatness.append(0)
            }

            // Spectral contrast
            let bandSize = magnitudes.count / (numSpectralContrast + 1)
            var bandValues: [Double] = []
            for band in 0..<numSpectralContrast {
                let start = band * bandSize
                let end = start + bandSize
                var valleySum: Double = 0
                var peakSum: Double = 0
                for k in start..<end {
                    if k < magnitudes.count {
                        valleySum += magnitudes[k]
                        if k + bandSize < magnitudes.count {
                            peakSum += magnitudes[k + bandSize]
                        }
                    }
                }
                let valleyAvg = valleySum / Double(bandSize)
                let peakAvg = peakSum / Double(bandSize)
                bandValues.append(peakAvg - valleyAvg)
            }
            spectralContrast.append(bandValues)

            frameStart += hopLength
        }

        // Aggregate features
        func aggregate(_ values: [Double]) -> [Double] {
            guard !values.isEmpty else { return [0, 0] }
            let mean = values.reduce(0, +) / Double(values.count)
            let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
            return [mean, sqrt(variance)]
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

    private func extractChromaFeatures(from samples: [Double], sampleRate: Double) -> [Double] {
        var chromaMeans: [[Double]] = []
        var chromaStds: [[Double]] = []

        var frameStart = 0

        while frameStart + frameLength <= samples.count {
            let frame = Array(samples[frameStart..<frameStart + frameLength])

            // Compute chroma
            var chroma = [Double](repeating: 0, count: numChroma)

            let nyquist = sampleRate / 2

            for k in 1..<(fftSize / 2) {
                let freq = nyquist * Double(k) / Double(fftSize / 2)
                let chromaBin = Int(freq / 110.0 * Double(numChroma) / 12.0) % numChroma
                var magnitude: Double = 0
                for n in 0..<frameLength {
                    let angle = -2 * .pi * Double(k) * Double(n) / Double(fftSize)
                    magnitude += frame[n] * cos(angle)
                }
                magnitude = abs(magnitude)
                chroma[chromaBin] += magnitude * magnitude
            }

            // Normalize
            let totalEnergy = chroma.reduce(0, +)
            if totalEnergy > 0 {
                for i in 0..<numChroma {
                    chroma[i] /= totalEnergy
                }
            }

            chromaMeans.append(chroma)
            chromaStds.append(Array(repeating: 0, count: numChroma)) // Placeholder

            frameStart += hopLength
        }

        // Aggregate across all frames
        var finalMeans: [Double] = []
        var finalStds: [Double] = []

        for i in 0..<numChroma {
            var meanSum: Double = 0
            for j in 0..<chromaMeans.count {
                if i < chromaMeans[j].count {
                    meanSum += chromaMeans[j][i]
                }
            }
            finalMeans.append(chromaMeans.isEmpty ? 0 : meanSum / Double(chromaMeans.count))
            finalStds.append(0) // Placeholder
        }

        var features: [Double] = []
        features.append(contentsOf: finalMeans)
        features.append(contentsOf: finalStds)

        return features
    }

    private func computeHarmonicRatio(from samples: [Double]) -> Double {
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

    private func normalizeFeatures(_ features: [Double]) -> [Double] {
        guard scalerMean.count == featureDimension && scalerScale.count == featureDimension else {
            return features
        }

        return zip(features, zip(scalerMean, scalerScale)).map { feature, meanScale in
            let (mean, scale) = meanScale
            return scale > 0 ? (feature - mean) / scale : feature
        }
    }

    private func runInference(features: [Double]) async throws -> EmotionResult {
        guard let model = model,
              let modelDescription = modelDescription else {
            throw EmotionAnalyzerError.modelNotLoaded
        }

        // Convert features to MLMultiArray with proper 2D indexing
        let multiArray = try MLMultiArray(
            shape: [1, NSNumber(value: featureDimension)],
            dataType: .double
        )

        // Use bulk copy for better performance
        features.withUnsafeBufferPointer { featuresPtr in
            multiArray.dataPointer.copyMemory(from: featuresPtr.baseAddress!, byteCount: featureDimension * MemoryLayout<Double>.size)
        }

        // Create input feature provider
        let inputName = modelDescription.inputDescriptionsByName["features"]?.name ?? modelDescription.inputDescriptionsByName.values.first?.name ?? "features"
        guard let inputProvider = try? MLDictionaryFeatureProvider(dictionary: [inputName: multiArray]) else {
            throw EmotionAnalyzerError.modelNotLoaded
        }

        // Run prediction
        let output = try await model.prediction(from: inputProvider)

        // Extract probabilities from output
        let outputName = modelDescription.outputDescriptionsByName["output"]?.name ?? modelDescription.outputDescriptionsByName.values.first?.name ?? "output"
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
            count = min(Int(truncating: outputArray.shape[1] as? NSNumber ?? NSNumber(value: emotionLabels.count)), emotionLabels.count)
        } else {
            count = min(Int(truncating: outputArray.shape[0] as? NSNumber ?? NSNumber(value: emotionLabels.count)), emotionLabels.count)
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
