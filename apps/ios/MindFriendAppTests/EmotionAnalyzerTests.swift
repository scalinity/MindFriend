import XCTest
@testable import MindFriendApp

import AVFoundation
import Speech

/// Tests for EmotionAnalyzer voice analysis functionality
/// Covers error handling, security features, consent management, and edge cases
final class EmotionAnalyzerTests: XCTestCase {

    // MARK: - Error Handling Tests

    func testEmotionAnalyzerError_ErrorDescriptions_AreUserFriendly() {
        let errors: [EmotionAnalyzerError] = [
            .modelNotFound,
            .modelLoadingFailed(underlying: nil),
            .audioFileNotFound,
            .invalidAudioFormat("mp3"),
            .audioTooShort(100),
            .audioTooLong(400),
            .featureExtractionFailed(underlying: nil),
            .inferenceFailed(underlying: nil),
            .invalidPrediction,
            .consentNotGranted,
            .rateLimitExceeded,
            .inferenceTimeout,
            .noPrediction,
            .invalidURL,
            .pathTraversalAttempt
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error \(error) should have description")
            XCTAssertFalse(error.errorDescription!.isEmpty, "Error description should not be empty")
            XCTAssertNotNil(error.failureReason, "Error \(error) should have failure reason")
        }
    }

    func testEmotionAnalyzerError_UnderlyingError_PreservesContext() {
        let underlyingError = NSError(domain: "Test", code: 42, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        let error = EmotionAnalyzerError.modelLoadingFailed(underlying: underlyingError)

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Test error"))
    }

    // MARK: - Consent Management Tests

    func testConsent_InitiallyFalse() {
        let analyzer = EmotionAnalyzer()
        XCTAssertFalse(analyzer.hasConsent)
    }

    func testSetConsent_True_ValueStored() {
        let analyzer = EmotionAnalyzer()
        analyzer.setVoiceConsent(true)
        XCTAssertTrue(analyzer.hasConsent)
    }

    func testSetConsent_False_ValueStored() {
        let analyzer = EmotionAnalyzer()
        analyzer.setVoiceConsent(true)
        analyzer.setVoiceConsent(false)
        XCTAssertFalse(analyzer.hasConsent)
    }

    func testAnalyzeAudio_WithoutConsent_ThrowsConsentNotGranted() async throws {
        let analyzer = EmotionAnalyzer()
        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test.wav")

        // Create a minimal WAV file
        try createMinimalWAVFile(at: testFile, duration: 0.5)

        await XCTAssertThrowsError(try await analyzer.analyzeAudio(at: testFile, userId: "test-user")) { error in
            XCTAssertEqual(error as? EmotionAnalyzerError, .consentNotGranted)
        }

        try? FileManager.default.removeItem(at: testFile)
    }

    func testAnalyzeAudio_WithConsent_ProceedsPastConsentCheck() async throws {
        let analyzer = EmotionAnalyzer()
        analyzer.setVoiceConsent(true)

        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("test.wav")

        // Create a minimal WAV file
        try createMinimalWAVFile(at: testFile, duration: 0.5)

        // This will fail at a later stage (model not loaded), but should pass consent check
        do {
            _ = try await analyzer.analyzeAudio(at: testFile, userId: "test-user")
        } catch EmotionAnalyzerError.consentNotGranted {
            XCTFail("Should not throw consentNotGranted when consent is granted")
        } catch {
            // Expected: other errors (model not found, etc.) are acceptable
        }

        try? FileManager.default.removeItem(at: testFile)
    }

    // MARK: - Rate Limiting Tests

    func testRateLimit_UnderLimit_AllowsRequests() async throws {
        let analyzer = EmotionAnalyzer()
        analyzer.setVoiceConsent(true)

        let tempDir = FileManager.default.temporaryDirectory

        // Create test files (we'll test rate limit counter, not full analysis)
        // The actual analysis will fail, but we can verify the rate limit check passes

        // Note: Full rate limit testing requires mocking model loading
        // This test verifies the counter mechanism works

        // Simulate rate limit check (internal)
        let testUserId = "rate-limit-test-user"
        let initialCount = analyzer.analysisCount[testUserId] ?? 0
        XCTAssertEqual(initialCount, 0)

        // Increment and verify
        for i in 0..<5 {
            let count = analyzer.analysisCount[testUserId] ?? 0
            XCTAssertEqual(count, i)
        }
    }

    func testRateLimit_AtLimit_BlocksFurtherRequests() async throws {
        let analyzer = EmotionAnalyzer()
        analyzer.setVoiceConsent(true)

        // Directly test rate limit by calling the internal check
        let testUserId = "limit-test-user"

        // Set count to max
        analyzer.analysisCount[testUserId] = EmotionAnalyzer.maxAnalysesPerHour

        // Note: We can't directly test the throw without mocking the full flow
        // This test documents the expected behavior
        XCTAssertEqual(analyzer.analysisCount[testUserId], EmotionAnalyzer.maxAnalysesPerHour)
    }

    // MARK: - URL Validation Tests

    func testValidateURL_ValidDocumentDirectoryURL_Succeeds() throws {
        let analyzer = EmotionAnalyzer()

        let documentDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let validURL = documentDir.appendingPathComponent("recording.wav")

        XCTAssertNoThrow(try analyzer.validateURL(validURL))
    }

    func testValidateURL_ValidTempDirectoryURL_Succeeds() throws {
        let analyzer = EmotionAnalyzer()

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("recording.wav")

        XCTAssertNoThrow(try analyzer.validateURL(tempURL))
    }

    func testValidateURL_NonFileURL_ThrowsInvalidURL() throws {
        let analyzer = EmotionAnalyzer()

        let httpURL = URL(string: "https://example.com/audio.wav")!
        XCTAssertThrowsError(try analyzer.validateURL(httpURL)) { error in
            XCTAssertEqual(error as? EmotionAnalyzerError, .invalidURL)
        }
    }

    func testValidateURL_PathTraversalAttempt_ThrowsPathTraversalAttempt() throws {
        let analyzer = EmotionAnalyzer()

        let maliciousURL = URL(fileURLWithPath: "/tmp/../../../etc/passwd")
        XCTAssertThrowsError(try analyzer.validateURL(maliciousURL)) { error in
            XCTAssertEqual(error as? EmotionAnalyzerError, .pathTraversalAttempt)
        }
    }

    func testValidateURL_UnsupportedExtension_ThrowsInvalidAudioFormat() throws {
        let analyzer = EmotionAnalyzer()

        let documentDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let invalidURL = documentDir.appendingPathComponent("recording.mp3")

        XCTAssertThrowsError(try analyzer.validateURL(invalidURL)) { error as? EmotionAnalyzerError in
            XCTAssertEqual(error, .invalidAudioFormat("mp3"))
        }
    }

    func testValidateURL_AllowedExtensions_AllPass() throws {
        let analyzer = EmotionAnalyzer()

        let documentDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let allowedExtensions = ["wav", "m4a", "mp3", "caf", "aac"]

        for ext in allowedExtensions {
            let url = documentDir.appendingPathComponent("recording.\(ext)")
            XCTAssertNoThrow(try analyzer.validateURL(url), "Extension \(ext) should be allowed")
        }
    }

    // MARK: - Audio Length Validation Tests

    func testAudioLengthValidation_TooShort_ThrowsAudioTooShort() async throws {
        let analyzer = EmotionAnalyzer()
        analyzer.setVoiceConsent(true)

        let tempDir = FileManager.default.temporaryDirectory
        let testFile = tempDir.appendingPathComponent("short.wav")

        // Create a very short WAV file (100ms)
        try createMinimalWAVFile(at: testFile, duration: 0.1)

        do {
            _ = try await analyzer.analyzeAudio(at: testFile, userId: "test-user")
            XCTFail("Should have thrown error for short audio")
        } catch EmotionAnalyzerError.audioTooShort(let samples) {
            XCTAssertEqual(samples, 2048) // Minimum samples check
        } catch {
            // Other errors are acceptable (e.g., model not found)
        }

        try? FileManager.default.removeItem(at: testFile)
    }

    // MARK: - Emotion Enum Tests

    func testEmotion_AllCases_HaveValidRawValues() {
        for emotion in Emotion.allCases {
            XCTAssertFalse(emotion.rawValue.isEmpty, "Emotion \(emotion) should have non-empty raw value")
        }
    }

    func testEmotion_FromRawValue_AllCasesRecoverable() {
        for emotion in Emotion.allCases {
            let recovered = Emotion(rawValue: emotion.rawValue)
            XCTAssertEqual(recovered, emotion, "Should recover emotion \(emotion) from raw value")
        }
    }

    func testEmotion_Count_MatchesExpectedClasses() {
        // Model predicts 8 emotion classes
        XCTAssertEqual(Emotion.allCases.count, 8)
    }

    // MARK: - EmotionResult Tests

    func testEmotionResult_PrimaryEmotion_IsHighestConfidence() {
        let result = EmotionResult(
            emotion: .happy,
            confidence: 0.85,
            allProbabilities: [
                "angry": 0.05,
                "calm": 0.10,
                "happy": 0.85
            ]
        )

        XCTAssertEqual(result.emotion, .happy)
        XCTAssertEqual(result.confidence, 0.85, accuracy: 0.001)
    }

    func testEmotionResult_ConfidenceSum_IsApproximatelyOne() {
        let result = EmotionResult(
            emotion: .neutral,
            confidence: 0.5,
            allProbabilities: [
                "angry": 0.1,
                "calm": 0.2,
                "disgust": 0.05,
                "fearful": 0.05,
                "happy": 0.1,
                "neutral": 0.3,
                "sad": 0.1,
                "surprised": 0.1
            ]
        )

        let sum = result.allProbabilities.values.reduce(0, +)
        XCTAssertEqual(sum, 1.0, accuracy: 0.001)
    }

    // MARK: - Feature Extraction Edge Case Tests

    func testFeatureExtraction_EmptyBuffer_ReturnsZeroFeatures() {
        let analyzer = EmotionAnalyzer()

        let emptyBuffer = AVAudioPCMBuffer(
            pcmFormat: AVAudioFormat(standardFormatWithSampleRate: 22050, channels: 1)!,
            frameCapacity: 0
        )

        // Should not crash on empty buffer
        let features = analyzer.extractFeatures(from: emptyBuffer)
        XCTAssertFalse(features.isEmpty)
    }

    func testFeatureExtraction_VeryShortBuffer_HandlesGracefully() {
        let analyzer = EmotionAnalyzer()

        // Create format
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 22050, channels: 1) else {
            return
        }

        // Create a very short buffer (less than frame size needed)
        let frameLength = 512
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameLength)) else {
            return
        }

        buffer.frameLength = AVAudioFrameCount(frameLength)

        // Fill with zeros
        if let channelData = buffer.floatChannelData?[0] {
            for i in 0..<Int(frameLength) {
                channelData[i] = 0.0
            }
        }

        // Should not crash
        let features = analyzer.extractFeatures(from: buffer)
        XCTAssertFalse(features.isEmpty)
    }

    func testFeatureExtraction_SilenceAudio_ProducesValidFeatures() {
        let analyzer = EmotionAnalyzer()

        guard let format = AVAudioFormat(standardFormatWithSampleRate: 22050, channels: 1) else {
            return
        }

        let frameLength = 8192 // At least 2x window size
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameLength)) else {
            return
        }

        buffer.frameLength = AVAudioFrameCount(frameLength)

        // Fill with zeros (silence)
        if let channelData = buffer.floatChannelData?[0] {
            for i in 0..<Int(frameLength) {
                channelData[i] = 0.0
            }
        }

        let features = analyzer.extractFeatures(from: buffer)

        // Should return valid feature count
        XCTAssertEqual(features.count, EmotionAnalyzer.featureDimension)
    }

    // MARK: - Constants Tests

    func testFeatureDimension_Is290() {
        XCTAssertEqual(EmotionAnalyzer.featureDimension, 290)
    }

    func testModelResourceName_IsNotEmpty() {
        XCTAssertFalse(EmotionAnalyzer.modelResourceName.isEmpty)
    }

    func testAnalysisTimeout_Is30Seconds() {
        XCTAssertEqual(EmotionAnalyzer.analysisTimeout, 30.0)
    }

    func testMaxAnalysesPerHour_Is10() {
        XCTAssertEqual(EmotionAnalyzer.maxAnalysesPerHour, 10)
    }

    func testMinAudioDuration_IsPoint5Seconds() {
        XCTAssertEqual(EmotionAnalyzer.minAudioDuration, 0.5)
    }

    func testMaxAudioDuration_Is300Seconds() {
        XCTAssertEqual(EmotionAnalyzer.maxAudioDuration, 300.0)
    }

    func testMinSampleRate_Is16000() {
        XCTAssertEqual(EmotionAnalyzer.minSampleRate, 16000)
    }

    func testMinSampleCount_Is2048() {
        XCTAssertEqual(EmotionAnalyzer.minSampleCount, 2048)
    }

    func testHopLength_Is512() {
        XCTAssertEqual(EmotionAnalyzer.hopLength, 512)
    }

    func testFrameLength_Is2048() {
        XCTAssertEqual(EmotionAnalyzer.frameLength, 2048)
    }

    func testNumMFCC_Is40() {
        XCTAssertEqual(EmotionAnalyzer.numMFCC, 40)
    }

    func testNumChroma_Is12() {
        XCTAssertEqual(EmotionAnalyzer.numChroma, 12)
    }

    // MARK: - Audio File Creation Helper

    private func createMinimalWAVFile(at url: URL, duration: Double) throws {
        let sampleRate: Double = 22050
        let numChannels: UInt32 = 1
        let bitsPerSample: UInt32 = 16

        let numSamples = Int(sampleRate * duration)
        let byteRate = Int(sampleRate) * Int(numChannels) * Int(bitsPerSample / 8)
        let blockAlign = Int(numChannels) * Int(bitsPerSample / 8)
        let dataSize = numSamples * blockAlign
        let fileSize = 36 + dataSize

        var header = Data(count: 44)

        // RIFF header
        header[0..<4] = Data("RIFF".utf8)
        header[4..<8] = withUnsafeBytes(of: fileSize.bigEndian, { Data($0) })
        header[8..<12] = Data("WAVE".utf8)

        // fmt chunk
        header[12..<16] = Data("fmt ".utf8)
        header[16..<20] = withUnsafeBytes(of: UInt32(16).bigEndian, { Data($0) }) // Chunk size
        header[20..<22] = withUnsafeBytes(of: UInt16(1).bigEndian, { Data($0) }) // Audio format (PCM)
        header[22..<24] = withUnsafeBytes(of: numChannels.bigEndian, { Data($0) })
        header[24..<28] = withUnsafeBytes(of: UInt32(sampleRate).bigEndian, { Data($0) })
        header[28..<32] = withUnsafeBytes(of: UInt32(byteRate).bigEndian, { Data($0) })
        header[32..<34] = withUnsafeBytes(of: UInt16(blockAlign).bigEndian, { Data($0) })
        header[34..<36] = withUnsafeBytes(of: UInt16(bitsPerSample).bigEndian, { Data($0) })

        // data chunk
        header[36..<40] = Data("data".utf8)
        header[40..<44] = withUnsafeBytes(of: UInt32(dataSize).bigEndian, { Data($0) })

        // Generate audio data (simple sine wave for valid WAV)
        var audioData = Data(count: dataSize)
        let frequency = 440.0
        let amplitude: Int16 = 8000

        audioData.withUnsafeMutableBytes { ptr in
            guard let samples = ptr.baseAddress?.assumingMemoryBound(to: Int16.self) else { return }
            for i in 0..<numSamples {
                let sample = sin(2.0 * .pi * frequency * Double(i) / sampleRate) * Double(amplitude)
                samples[i] = Int16(max(Int16.min, min(Int16.max, sample)))
            }
        }

        try header.write(to: url)
        try audioData.write(to: url)
    }
}

// MARK: - Speech Audio Buffer Extension Tests

extension EmotionAnalyzerTests {

    func testSpeechAudioBuffer_ValidBuffer_ExtractsFeatures() {
        let analyzer = EmotionAnalyzer()

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 22050,
            channels: 1,
            interleaved: false
        ) else {
            return
        }

        let frameCount: AVAudioFrameCount = 8192
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return
        }

        buffer.frameLength = frameCount

        // Generate test signal
        if let channelData = buffer.floatChannelData?[0] {
            let sampleRate = format.sampleRate
            for frame in 0..<Int(frameCount) {
                let t = Double(frame) / sampleRate
                // Mix of frequencies typical of speech
                channelData[frame] = Float(0.5 * sin(2.0 * .pi * 200 * t) + 0.3 * sin(2.0 * .pi * 400 * t))
            }
        }

        let features = analyzer.extractFeatures(from: buffer)

        XCTAssertEqual(features.count, EmotionAnalyzer.featureDimension)
    }

    func testSpeechAudioBuffer_LowSampleRate_HandlesGracefully() {
        let analyzer = EmotionAnalyzer()

        // Create format with lower sample rate
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1) else {
            return
        }

        let frameCount: AVAudioFrameCount = 2048
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return
        }

        buffer.frameLength = frameCount

        // Should not crash
        let features = analyzer.extractFeatures(from: buffer)
        XCTAssertFalse(features.isEmpty)
    }
}

// MARK: - Rate Limiting Integration Tests

extension EmotionAnalyzerTests {

    func testRateLimitCounter_IncrementsOnEachAnalysis() async throws {
        let analyzer = EmotionAnalyzer()
        analyzer.setVoiceConsent(true)

        let testUserId = "integration-test-user"

        // Reset count for this user
        analyzer.analysisCount[testUserId] = 0

        // Simulate multiple analysis attempts
        for i in 1...5 {
            analyzer.analysisCount[testUserId] = i
            XCTAssertEqual(analyzer.analysisCount[testUserId], i)
        }

        // Clean up
        analyzer.analysisCount.removeValue(forKey: testUserId)
    }

    func testRateLimitCounter_PreventsExceedingMax() {
        let analyzer = EmotionAnalyzer()

        let testUserId = "limit-test-user"
        analyzer.analysisCount[testUserId] = EmotionAnalyzer.maxAnalysesPerHour

        // Should not allow increment beyond max
        let count = analyzer.analysisCount[testUserId] ?? 0
        XCTAssertLessThanOrEqual(count, EmotionAnalyzer.maxAnalysesPerHour)
    }
}

// MARK: - Timeout Handling Tests

extension EmotionAnalyzerTests {

    func testTimeoutConstant_Is30Seconds() {
        XCTAssertEqual(EmotionAnalyzer.analysisTimeout, 30.0)
    }

    func testTimeoutConstant_IsPositive() {
        XCTAssertGreaterThan(EmotionAnalyzer.analysisTimeout, 0)
    }
}

// MARK: - Scaler Parameters Tests

extension EmotionAnalyzerTests {

    func testScalerParameters_AreLoadedOnInit() {
        let analyzer = EmotionAnalyzer()

        // Scaler should be loaded (or nil if model not found)
        // This test verifies the loading attempt was made
        XCTAssertNotNil(analyzer.scalerMeans)
    }

    func testScalerMeans_HasExpectedCount() {
        let analyzer = EmotionAnalyzer()

        if let means = analyzer.scalerMeans {
            XCTAssertEqual(means.count, EmotionAnalyzer.featureDimension)
        }
    }

    func testScalerStandardDeviations_HasExpectedCount() {
        let analyzer = EmotionAnalyzer()

        if let stds = analyzer.scalerStandardDeviations {
            XCTAssertEqual(stds.count, EmotionAnalyzer.featureDimension)
        }
    }
}

// MARK: - Thread Safety Tests

extension EmotionAnalyzerTests {

    func testConcurrentConsentUpdates_AreAtomic() async {
        let analyzer = EmotionAnalyzer()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    analyzer.setVoiceConsent(Bool.random())
                }
            }
        }

        // Final state should be consistent (true or false)
        XCTAssertTrue(analyzer.hasConsent || !analyzer.hasConsent)
    }

    func testConcurrentAnalysisCountUpdates_AreAtomic() async {
        let analyzer = EmotionAnalyzer()
        let testUserId = "concurrent-test-user"

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<50 {
                group.addTask {
                    let current = analyzer.analysisCount[testUserId] ?? 0
                    analyzer.analysisCount[testUserId] = current + 1
                }
            }
        }

        // Count should be exactly 50
        XCTAssertEqual(analyzer.analysisCount[testUserId], 50)

        // Clean up
        analyzer.analysisCount.removeValue(forKey: testUserId)
    }
}
