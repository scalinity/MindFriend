import AVFoundation
import Accelerate
import CoreML

/// Emotion analyzer using Core ML model trained on speech prosody features.
/// Supports 8 emotion classes: angry, calm, disgust, fearful, happy, neutral, sad, surprised
@MainActor
final class EmotionAnalyzer: ObservableObject {
    // MARK: - Types

    struct EmotionResult {
        let emotion: String
        let confidence: Double
        let allProbabilities: [String: Double]
    }

    // MARK: - Properties

    @Published private(set) var isAnalyzing = false
    @Published private(set) var lastError: Error?

    private var model: EmotionProsodyClassifier_20260122_124134?
    private var scalerMean: [Double] = []
    private var scalerScale: [Double] = []
    private var emotionLabels: [String] = []

    // MARK: - Constants

    /// Sample rate for audio processing (must match training)
    private let sampleRate: Double = 16000

    /// Target duration for analysis (3 seconds, matches training)
    private let targetDuration: Double = 3.0

    /// Number of MFCC coefficients
    private let numMFCC = 40

    /// Number of spectral contrast bands
    private let numSpectralContrast = 7

    /// Number of chroma features
    private let numChroma = 12

    /// Total feature dimension
    private let featureDimension = 290

    // MARK: - Initialization

    init() {
        loadModel()
    }

    // MARK: - Public Methods

    /// Analyze audio from a file URL and return emotion prediction
    /// - Parameter url: URL to the audio file (wav, m4a, etc.)
    /// - Returns: EmotionResult with predicted emotion and confidence scores
    func analyzeAudio(at url: URL) async throws -> EmotionResult {
        isAnalyzing = true
        lastError = nil

        defer { isAnalyzing = false }

        do {
            // Extract features from audio
            let features = try extractFeatures(from: url)

            // Normalize features
            let normalizedFeatures = normalizeFeatures(features)

            // Run ML inference
            let prediction = try await runInference(features: normalizedFeatures)

            return prediction
        } catch {
            lastError = error
            throw error
        }
    }

    /// Analyze audio buffer directly (for real-time processing)
    /// - Parameter audioBuffer: PCM audio samples
    /// - Returns: EmotionResult with predicted emotion and confidence scores
    func analyzeAudioBuffer(_ audioBuffer: [Float]) async throws -> EmotionResult {
        isAnalyzing = true
        lastError = nil

        defer { isAnalyzing = false }

        do {
            // Extract features from buffer
            let features = try extractFeatures(from: audioBuffer)

            // Normalize features
            let normalizedFeatures = normalizeFeatures(features)

            // Run ML inference
            let prediction = try await runInference(features: normalizedFeatures)

            return prediction
        } catch {
            lastError = error
            throw error
        }
    }

    // MARK: - Private Methods

    private func loadModel() {
        do {
            // Load Core ML model
            let modelURL = Bundle.main.url(forResource: "EmotionProsodyClassifier_20260122_124134", withExtension: "mlpackage")
            guard let modelURL = modelURL else {
                print("Error: Core ML model not found in bundle")
                return
            }

            let compiledURL = try MLModel.compileModel(at: modelURL)
            model = try EmotionProsodyClassifier_20260122_124134(contentsOf: compiledURL)

            // Load scaler parameters
            loadScalerParameters()

            // Load emotion labels
            loadEmotionLabels()

            print("EmotionAnalyzer: Model loaded successfully")
        } catch {
            print("Error loading model: \(error)")
            lastError = error
        }
    }

    private func loadScalerParameters() {
        guard let url = Bundle.main.url(forResource: "scaler_params", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mean = json["mean"] as? [Double],
              let scale = json["scale"] as? [Double] else {
            print("Warning: Could not load scaler parameters, using defaults")
            return
        }

        scalerMean = mean
        scalerScale = scale
        print("EmotionAnalyzer: Loaded \(mean.count) scaler parameters")
    }

    private func loadEmotionLabels() {
        guard let url = Bundle.main.url(forResource: "emotion_labels", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let labels = json["labels"] as? [String] else {
            print("Warning: Could not load emotion labels")
            return
        }

        emotionLabels = labels
    }

    private func extractFeatures(from url: URL) throws -> [Double] {
        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: url)
        } catch {
            throw EmotionAnalyzerError.audioLoadError(error)
        }

        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw EmotionAnalyzerError.bufferCreationFailed
        }

        try audioFile.read(into: buffer)

        guard let floatData = buffer.floatChannelData else {
            throw EmotionAnalyzerError.noAudioData
        }

        let samples = UnsafeBufferPointer(start: floatData[0], count: Int(frameCount))
        let sampleArray = Array(samples)

        return try extractFeatures(from: sampleArray)
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
        features.append(contentsOf: [
            rms.mean,
            rms.std,
            rms.max,
            rms.min
        ])

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

        // Verify feature count
        guard features.count == featureDimension else {
            print("Warning: Expected \(featureDimension) features, got \(features.count)")
        }

        return features
    }

    private func processAudioSamples(_ samples: [Float], targetLength: Int) -> [Float] {
        if samples.count >= targetLength {
            return Array(samples[..<targetLength])
        } else {
            var padded = samples
            while padded.count < targetLength {
                padded.append(0)
            }
            return padded
        }
    }

    private func extractMFCCs(from samples: [Double], sampleRate: Double) -> (values: [[Double]], mean: [Double], std: [Double], max: [Double], min: [Double]) {
        let frameLength = 2048
        let hopLength = 512

        var mfccValues: [[Double]] = Array(repeating: Array(repeating: 0.0, count: numMFCC), count: 0)
        var frameStart = 0

        while frameStart + frameLength <= samples.count {
            var frame = Array(samples[frameStart..<frameStart + frameLength])

            // Compute MFCC for frame
            var mfcc = [Double](repeating: 0, count: numMFCC)
            var config: vDSP_DFT_Setup?
            var magnitude = [Double](repeating: 0, count: frameLength / 2 + 1)

            // Simple MFCC approximation using DCT
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

        // Compute statistics across all frames
        var means = [Double](repeating: 0, count: numMFCC)
        var stds = [Double](repeating: 0, count: numMFCC)
        var maxes = [Double](repeating: -Double.infinity, count: numMFCC)
        var mins = [Double](repeating: Double.infinity, count: numMFCC)

        for i in 0..<numMFCC {
            var sum: Double = 0
            for frame in mfccValues {
                sum += frame[i]
                maxes[i] = max(maxes[i], frame[i])
                mins[i] = min(mins[i], frame[i])
            }
            means[i] = sum / Double(mfccValues.count)

            var varianceSum: Double = 0
            for frame in mfccValues {
                varianceSum += (frame[i] - means[i]) * (frame[i] - means[i])
            }
            stds[i] = sqrt(varianceSum / Double(mfccValues.count))
        }

        return (mfccValues, means, stds, maxes, mins)
    }

    private func computeDelta(_ values: [[Double]]) -> (values: [[Double]], mean: [Double]) {
        var deltas: [[Double]] = []
        let N = 2

        for i in 0..<values.count {
            var delta: [Double] = Array(repeating: 0.0, count: numMFCC)
            for j in 0..<numMFCC {
                var sum: Double = 0
                var count: Double = 0
                for n in 1...N {
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

        var means = [Double](repeating: 0, count: numMFCC)
        for i in 0..<numMFCC {
            var sum: Double = 0
            for frame in deltas {
                sum += frame[i]
            }
            means[i] = sum / Double(deltas.count)
        }

        return (deltas, means)
    }

    private func extractPitchFeatures(from samples: [Double], sampleRate: Double) -> [Double] {
        // Simplified pitch extraction using autocorrelation
        let frameLength = 2048
        let hopLength = 512

        var f0Values: [Double] = []
        var frameStart = 0

        while frameStart + frameLength <= samples.count {
            let frame = Array(samples[frameStart..<frameStart + frameLength])
            let f0 = estimateF0(frame, sampleRate: sampleRate)
            f0Values.append(f0)
            frameStart += hopLength
        }

        let validF0 = f0Values.filter { $0 > 0 }

        if validF0.isEmpty {
            return [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
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
        // Autocorrelation-based F0 estimation
        let minLag = Int(sampleRate / 500) // Max F0 = 500 Hz
        let maxLag = Int(sampleRate / 50)  // Min F0 = 50 Hz

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
        let frameLength = 2048
        let hopLength = 512

        var frameStart = 0
        while frameStart + frameLength <= samples.count {
            var sumSquares: Double = 0
            for i in 0..<frameLength {
                sumSquares += samples[frameStart + i] * samples[frameStart + i]
            }
            rmsValues.append(sqrt(sumSquares / Double(frameLength)))
            frameStart += hopLength
        }

        let mean = rmsValues.reduce(0, +) / Double(rmsValues.count)
        let variance = rmsValues.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(rmsValues.count)

        return (
            mean,
            sqrt(variance),
            rmsValues.max() ?? 0,
            rmsValues.min() ?? 0
        )
    }

    private func computeZCR(_ samples: [Double]) -> (mean: Double, std: Double) {
        var zcrValues: [Double] = []
        let frameLength = 2048
        let hopLength = 512

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

        let mean = zcrValues.reduce(0, +) / Double(zcrValues.count)
        let variance = zcrValues.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(zcrValues.count)

        return (mean, sqrt(variance))
    }

    private func extractSpectralFeatures(from samples: [Double], sampleRate: Double) -> [Double] {
        var features: [Double] = []

        let frameLength = 2048
        let hopLength = 512

        var spectralCentroids: [Double] = []
        var spectralBandwidths: [Double] = []
        var spectralRolloffs: [Double] = []
        var spectralFlatness: [Double] = []
        var spectralContrast: [[Double]] = Array(repeating: Array(repeating: 0, count: numSpectralContrast), count: 0)

        var frameStart = 0
        while frameStart + frameLength <= samples.count {
            let frame = Array(samples[frameStart..<frameStart + frameLength])

            // Compute FFT magnitude
            let fftSize = frameLength
            var realPart = frame
            var imagPart = [Double](repeating: 0, count: fftSize)

            // Simple DFT for spectral analysis
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
            let rolloffThreshold = 0.85 * denom
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

            // Spectral flatness (ratio of geometric to arithmetic mean)
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

            // Spectral contrast (7 bands)
            let bandSize = magnitudes.count / (numSpectralContrast + 1)
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
                spectralContrast[spectralContrast.count - 1].append(peakAvg - valleyAvg)
            }

            frameStart += hopLength
        }

        // Aggregate spectral features
        func aggregate(_ values: [Double]) -> [Double] {
            if values.isEmpty { return [0, 0] }
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
            var bandValues: [Double] = []
            for frame in spectralContrast {
                if band < frame.count {
                    bandValues.append(frame[band])
                }
            }
            features.append(bandValues.isEmpty ? 0 : bandValues.reduce(0, +) / Double(bandValues.count))
        }

        return features
    }

    private func extractChromaFeatures(from samples: [Double], sampleRate: Double) -> [Double] {
        let frameLength = 2048
        let hopLength = 512

        var chromaMeans: [[Double]] = Array(repeating: Array(repeating: 0, count: numChroma), count: 0)
        var chromaStds: [[Double]] = Array(repeating: Array(repeating: 0, count: numChroma), count: 0)

        var frameStart = 0
        while frameStart + frameLength <= samples.count {
            let frame = Array(samples[frameStart..<frameStart + frameLength])

            // Compute DFT
            let fftSize = frameLength
            var chroma = [Double](repeating: 0, count: numChroma)

            // Map FFT bins to chroma bins (12 semitones)
            let nyquist = sampleRate / 2
            let binsPerChroma = Double(fftSize / 2) / (2 * numChroma)

            for k in 1..<(fftSize / 2) {
                let freq = nyquist * Double(k) / Double(fftSize / 2)
                let chromaBin = Int(freq / 110.0 * numChroma / 12) % numChroma
                var magnitude = 0.0
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

            // Compute statistics for this frame
            var means = [Double](repeating: 0, count: numChroma)
            var stds = [Double](repeating: 0, count: numChroma)

            for i in 0..<numChroma {
                let windowStart = max(0, chromaMeans.count - 5)
                var windowSum: Double = 0
                var windowCount = 0
                for j in windowStart..<chromaMeans.count {
                    if i < chromaMeans[j].count {
                        windowSum += chromaMeans[j][i]
                        windowCount += 1
                    }
                }
                means[i] = windowCount > 0 ? windowSum / Double(windowCount) : chroma[i]

                var varSum: Double = 0
                for j in windowStart..<chromaMeans.count {
                    if i < chromaMeans[j].count {
                        varSum += (chromaMeans[j][i] - means[i]) * (chromaMeans[j][i] - means[i])
                    }
                }
                stds[i] = windowCount > 0 ? sqrt(varSum / Double(windowCount)) : 0
            }

            chromaMeans.append(chroma)
            chromaStds.append(stds)

            frameStart += hopLength
        }

        // Aggregate across all frames
        var finalMeans: [Double] = []
        var finalStds: [Double] = []

        for i in 0..<numChroma {
            var meanSum: Double = 0
            var stdSum: Double = 0
            for j in 0..<chromaMeans.count {
                if i < chromaMeans[j].count {
                    meanSum += chromaMeans[j][i]
                }
                if i < chromaStds[j].count {
                    stdSum += chromaStds[j][i]
                }
            }
            finalMeans.append(meanSum / Double(max(1, chromaMeans.count)))
            finalStds.append(stdSum / Double(max(1, chromaStds.count)))
        }

        var features: [Double] = []
        features.append(contentsOf: finalMeans)
        features.append(contentsOf: finalStds)

        return features
    }

    private func computeHarmonicRatio(from samples: [Double]) -> Double {
        // Harmonic ratio using autocorrelation
        let frameLength = 2048
        var harmonicSum: Double = 0
        var percussiveSum: Double = 0

        for start in stride(from: 0, to: samples.count - frameLength, by: frameLength) {
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
            percussiveSum += percussive / total
        }

        return harmonicSum / Double(samples.count / frameLength)
    }

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
        guard let model = model else {
            throw EmotionAnalyzerError.modelNotLoaded
        }

        // Convert features to MLMultiArray
        let multiArray = try MLMultiArray(
            shape: [1, NSNumber(value: featureDimension)],
            dataType: .double
        )

        for (index, value) in features.enumerated() {
            multiArray[index] = NSNumber(value: value)
        }

        // Create input
        let input = EmotionProsodyClassifier_20260122_124134Input(features: multiArray)

        // Run prediction
        let output = try await model.prediction(input: input)

        // Extract probabilities
        let outputArray = output.output

        var probabilities: [String: Double] = [:]
        for i in 0..<min(emotionLabels.count, 10) {
            let indexPath = [0, i]
            if let value = outputArray[indexPath] as? Double {
                probabilities[emotionLabels[i]] = value
            }
        }

        // Find dominant emotion
        let sorted = probabilities.sorted { $0.value > $1.value }
        guard let top = sorted.first else {
            throw EmotionAnalyzerError.noPrediction
        }

        // Softmax to get proper probabilities
        let expValues = sorted.map { exp($0.value) }
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
}

// MARK: - Errors

enum EmotionAnalyzerError: LocalizedError {
    case audioLoadError(Error)
    case bufferCreationFailed
    case noAudioData
    case modelNotLoaded
    case noPrediction
    case featureExtractionFailed

    var errorDescription: String? {
        switch self {
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
        }
    }
}
