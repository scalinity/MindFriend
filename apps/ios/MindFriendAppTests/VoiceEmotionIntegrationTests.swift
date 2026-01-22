import XCTest
@testable import MindFriendApp

/// Tests for Voice Mode emotion integration
/// Covers EmotionSnapshot, EmotionSummary, EmotionSettings models and VoiceStateMachine emotion events
final class VoiceEmotionIntegrationTests: XCTestCase {

    // MARK: - EmotionSnapshot Tests

    func testEmotionSnapshot_InitWithExplicitValues_StoresCorrectly() {
        let snapshot = EmotionSnapshot(
            emotion: "happy",
            confidence: 0.85,
            allProbabilities: ["happy": 0.85, "calm": 0.10, "neutral": 0.05],
            timestamp: 30.5,
            transcriptSegment: "I feel great today"
        )

        XCTAssertEqual(snapshot.emotion, "happy")
        XCTAssertEqual(snapshot.confidence, 0.85, accuracy: 0.001)
        XCTAssertEqual(snapshot.timestamp, 30.5, accuracy: 0.001)
        XCTAssertEqual(snapshot.transcriptSegment, "I feel great today")
        XCTAssertEqual(snapshot.allProbabilities["happy"], 0.85)
    }

    func testEmotionSnapshot_DefaultProbabilities_IsEmpty() {
        let snapshot = EmotionSnapshot(
            emotion: "neutral",
            confidence: 0.5,
            timestamp: 0
        )

        XCTAssertTrue(snapshot.allProbabilities.isEmpty)
    }

    func testEmotionSnapshot_GeneratesUniqueIds() {
        let snapshot1 = EmotionSnapshot(emotion: "happy", confidence: 0.8, timestamp: 0)
        let snapshot2 = EmotionSnapshot(emotion: "happy", confidence: 0.8, timestamp: 0)

        XCTAssertNotEqual(snapshot1.id, snapshot2.id)
    }

    func testEmotionSnapshot_Equatable_ComparesAllFields() {
        let id = UUID()
        let snapshot1 = EmotionSnapshot(
            id: id,
            emotion: "sad",
            confidence: 0.7,
            timestamp: 10
        )
        let snapshot2 = EmotionSnapshot(
            id: id,
            emotion: "sad",
            confidence: 0.7,
            timestamp: 10
        )

        XCTAssertEqual(snapshot1, snapshot2)
    }

    func testEmotionSnapshot_Equatable_DifferentEmotions() {
        let id = UUID()
        let snapshot1 = EmotionSnapshot(id: id, emotion: "happy", confidence: 0.7, timestamp: 10)
        let snapshot2 = EmotionSnapshot(id: id, emotion: "sad", confidence: 0.7, timestamp: 10)

        XCTAssertNotEqual(snapshot1, snapshot2)
    }

    func testEmotionSnapshot_Hashable_CanBeStoredInSet() {
        let snapshot1 = EmotionSnapshot(emotion: "happy", confidence: 0.8, timestamp: 0)
        let snapshot2 = EmotionSnapshot(emotion: "sad", confidence: 0.7, timestamp: 10)

        var set: Set<EmotionSnapshot> = []
        set.insert(snapshot1)
        set.insert(snapshot2)

        XCTAssertEqual(set.count, 2)
    }

    func testEmotionSnapshot_Codable_EncodesAndDecodes() throws {
        let original = EmotionSnapshot(
            emotion: "fearful",
            confidence: 0.65,
            allProbabilities: ["fearful": 0.65, "surprised": 0.20, "neutral": 0.15],
            timestamp: 45.0,
            transcriptSegment: "I'm worried about this"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(EmotionSnapshot.self, from: data)

        XCTAssertEqual(decoded.emotion, original.emotion)
        XCTAssertEqual(decoded.confidence, original.confidence, accuracy: 0.001)
        XCTAssertEqual(decoded.timestamp, original.timestamp, accuracy: 0.001)
        XCTAssertEqual(decoded.transcriptSegment, original.transcriptSegment)
    }

    func testEmotionSnapshot_Codable_UsesSnakeCaseKeys() throws {
        let snapshot = EmotionSnapshot(
            emotion: "happy",
            confidence: 0.8,
            allProbabilities: ["happy": 0.8],
            timestamp: 10,
            transcriptSegment: "test"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(snapshot)
        let json = String(data: data, encoding: .utf8) ?? ""

        XCTAssertTrue(json.contains("all_probabilities"))
        XCTAssertTrue(json.contains("transcript_segment"))
    }

    // MARK: - EmotionSnapshot UI Helpers Tests

    func testEmotionSnapshot_Icon_MapsCorrectlyForAllEmotions() {
        let emotions = ["angry", "fearful", "sad", "happy", "surprised", "disgust", "calm", "neutral"]
        let expectedIcons = [
            "exclamationmark.triangle.fill",
            "eye.fill",
            "drop.fill",
            "face.smiling.fill",
            "star.fill",
            "hand.raised.fill",
            "wind",
            "circle.fill"
        ]

        for (emotion, expectedIcon) in zip(emotions, expectedIcons) {
            let snapshot = EmotionSnapshot(emotion: emotion, confidence: 0.8, timestamp: 0)
            XCTAssertEqual(snapshot.icon, expectedIcon, "Emotion \(emotion) should have icon \(expectedIcon)")
        }
    }

    func testEmotionSnapshot_Emoji_MapsCorrectlyForAllEmotions() {
        let emotions = ["angry", "fearful", "sad", "happy", "surprised", "disgust", "calm", "neutral"]
        let expectedEmojis = ["😠", "😨", "😢", "😊", "😲", "🤢", "😌", "😐"]

        for (emotion, expectedEmoji) in zip(emotions, expectedEmojis) {
            let snapshot = EmotionSnapshot(emotion: emotion, confidence: 0.8, timestamp: 0)
            XCTAssertEqual(snapshot.emoji, expectedEmoji, "Emotion \(emotion) should have emoji \(expectedEmoji)")
        }
    }

    func testEmotionSnapshot_ColorHex_MapsCorrectlyForAllEmotions() {
        let emotions = ["angry", "fearful", "sad", "happy", "surprised", "disgust", "calm", "neutral"]
        let expectedColors = ["#FF3B30", "#FF9500", "#5856D6", "#34C759", "#FFCC00", "#AF52DE", "#007AFF", "#8E8E93"]

        for (emotion, expectedColor) in zip(emotions, expectedColors) {
            let snapshot = EmotionSnapshot(emotion: emotion, confidence: 0.8, timestamp: 0)
            XCTAssertEqual(snapshot.colorHex, expectedColor, "Emotion \(emotion) should have color \(expectedColor)")
        }
    }

    func testEmotionSnapshot_ConfidenceLevel_High() {
        let snapshot = EmotionSnapshot(emotion: "happy", confidence: 0.85, timestamp: 0)
        XCTAssertEqual(snapshot.confidenceLevel, "high")

        let exactThreshold = EmotionSnapshot(emotion: "happy", confidence: 0.8, timestamp: 0)
        XCTAssertEqual(exactThreshold.confidenceLevel, "high")
    }

    func testEmotionSnapshot_ConfidenceLevel_Medium() {
        let snapshot = EmotionSnapshot(emotion: "happy", confidence: 0.7, timestamp: 0)
        XCTAssertEqual(snapshot.confidenceLevel, "medium")

        let exactThreshold = EmotionSnapshot(emotion: "happy", confidence: 0.6, timestamp: 0)
        XCTAssertEqual(exactThreshold.confidenceLevel, "medium")
    }

    func testEmotionSnapshot_ConfidenceLevel_Low() {
        let snapshot = EmotionSnapshot(emotion: "happy", confidence: 0.5, timestamp: 0)
        XCTAssertEqual(snapshot.confidenceLevel, "low")

        let veryLow = EmotionSnapshot(emotion: "happy", confidence: 0.2, timestamp: 0)
        XCTAssertEqual(veryLow.confidenceLevel, "low")
    }

    func testEmotionSnapshot_FormattedTimestamp_SecondsOnly() {
        let snapshot = EmotionSnapshot(emotion: "happy", confidence: 0.8, timestamp: 45)
        XCTAssertEqual(snapshot.formattedTimestamp(), "45s")
    }

    func testEmotionSnapshot_FormattedTimestamp_MinutesAndSeconds() {
        let snapshot = EmotionSnapshot(emotion: "happy", confidence: 0.8, timestamp: 125)
        XCTAssertEqual(snapshot.formattedTimestamp(), "2m 5s")
    }

    func testEmotionSnapshot_FormattedTimestamp_ExactMinute() {
        let snapshot = EmotionSnapshot(emotion: "happy", confidence: 0.8, timestamp: 60)
        XCTAssertEqual(snapshot.formattedTimestamp(), "1m 0s")
    }

    func testEmotionSnapshot_FormattedTimestamp_Zero() {
        let snapshot = EmotionSnapshot(emotion: "happy", confidence: 0.8, timestamp: 0)
        XCTAssertEqual(snapshot.formattedTimestamp(), "0s")
    }

    // MARK: - EmotionSummary Tests

    func testEmotionSummary_EmptyHistory_ReturnsDefaults() {
        let summary = EmotionSummary(from: [])

        XCTAssertEqual(summary.dominantEmotion, "neutral")
        XCTAssertEqual(summary.averageConfidence, 0)
        XCTAssertTrue(summary.emotionDistribution.isEmpty)
        XCTAssertEqual(summary.totalDetections, 0)
    }

    func testEmotionSummary_SingleEntry_ComputesCorrectly() {
        let history = [
            EmotionSnapshot(emotion: "happy", confidence: 0.8, timestamp: 0)
        ]
        let summary = EmotionSummary(from: history)

        XCTAssertEqual(summary.dominantEmotion, "happy")
        XCTAssertEqual(summary.averageConfidence, 0.8, accuracy: 0.001)
        XCTAssertEqual(summary.emotionDistribution["happy"], 1)
        XCTAssertEqual(summary.totalDetections, 1)
    }

    func testEmotionSummary_MultipleEntries_FindsDominant() {
        let history = [
            EmotionSnapshot(emotion: "happy", confidence: 0.7, timestamp: 0),
            EmotionSnapshot(emotion: "happy", confidence: 0.8, timestamp: 10),
            EmotionSnapshot(emotion: "happy", confidence: 0.75, timestamp: 20),
            EmotionSnapshot(emotion: "sad", confidence: 0.6, timestamp: 30),
            EmotionSnapshot(emotion: "calm", confidence: 0.9, timestamp: 40)
        ]
        let summary = EmotionSummary(from: history)

        XCTAssertEqual(summary.dominantEmotion, "happy") // 3 occurrences
        XCTAssertEqual(summary.totalDetections, 5)
        XCTAssertEqual(summary.emotionDistribution["happy"], 3)
        XCTAssertEqual(summary.emotionDistribution["sad"], 1)
        XCTAssertEqual(summary.emotionDistribution["calm"], 1)
    }

    func testEmotionSummary_AverageConfidence_CalculatesCorrectly() {
        let history = [
            EmotionSnapshot(emotion: "happy", confidence: 0.6, timestamp: 0),
            EmotionSnapshot(emotion: "happy", confidence: 0.8, timestamp: 10),
            EmotionSnapshot(emotion: "sad", confidence: 1.0, timestamp: 20)
        ]
        let summary = EmotionSummary(from: history)

        // (0.6 + 0.8 + 1.0) / 3 = 0.8
        XCTAssertEqual(summary.averageConfidence, 0.8, accuracy: 0.001)
    }

    func testEmotionSummary_ExplicitInit_StoresValues() {
        let summary = EmotionSummary(
            dominantEmotion: "calm",
            averageConfidence: 0.75,
            emotionDistribution: ["calm": 5, "happy": 3],
            totalDetections: 8
        )

        XCTAssertEqual(summary.dominantEmotion, "calm")
        XCTAssertEqual(summary.averageConfidence, 0.75)
        XCTAssertEqual(summary.emotionDistribution["calm"], 5)
        XCTAssertEqual(summary.totalDetections, 8)
    }

    func testEmotionSummary_Codable_EncodesAndDecodes() throws {
        let original = EmotionSummary(
            dominantEmotion: "happy",
            averageConfidence: 0.82,
            emotionDistribution: ["happy": 4, "calm": 2],
            totalDetections: 6
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(EmotionSummary.self, from: data)

        XCTAssertEqual(decoded.dominantEmotion, original.dominantEmotion)
        XCTAssertEqual(decoded.averageConfidence, original.averageConfidence, accuracy: 0.001)
        XCTAssertEqual(decoded.totalDetections, original.totalDetections)
    }

    func testEmotionSummary_Codable_UsesSnakeCaseKeys() throws {
        let summary = EmotionSummary(
            dominantEmotion: "happy",
            averageConfidence: 0.8,
            emotionDistribution: ["happy": 1],
            totalDetections: 1
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(summary)
        let json = String(data: data, encoding: .utf8) ?? ""

        XCTAssertTrue(json.contains("dominant_emotion"))
        XCTAssertTrue(json.contains("average_confidence"))
        XCTAssertTrue(json.contains("emotion_distribution"))
        XCTAssertTrue(json.contains("total_detections"))
    }

    // MARK: - EmotionSettings Tests

    func testEmotionSettings_Defaults_AreCorrect() {
        let defaults = EmotionSettings.defaults

        XCTAssertFalse(defaults.isEnabled) // Disabled by default for privacy
        XCTAssertEqual(defaults.sensitivityThreshold, 0.6, accuracy: 0.001)
        XCTAssertTrue(defaults.showBadges)
        XCTAssertTrue(defaults.includeInPrompts)
        XCTAssertTrue(defaults.saveHistory)
    }

    func testEmotionSettings_ExplicitInit_StoresValues() {
        let settings = EmotionSettings(
            isEnabled: true,
            sensitivityThreshold: 0.7,
            showBadges: false,
            includeInPrompts: false,
            saveHistory: true
        )

        XCTAssertTrue(settings.isEnabled)
        XCTAssertEqual(settings.sensitivityThreshold, 0.7, accuracy: 0.001)
        XCTAssertFalse(settings.showBadges)
        XCTAssertFalse(settings.includeInPrompts)
        XCTAssertTrue(settings.saveHistory)
    }

    func testEmotionSettings_Equatable() {
        let settings1 = EmotionSettings.defaults
        let settings2 = EmotionSettings.defaults

        XCTAssertEqual(settings1, settings2)
    }

    func testEmotionSettings_Equatable_DifferentValues() {
        var settings1 = EmotionSettings.defaults
        var settings2 = EmotionSettings.defaults
        settings2.isEnabled = true

        XCTAssertNotEqual(settings1, settings2)
    }

    func testEmotionSettings_Codable_EncodesAndDecodes() throws {
        let original = EmotionSettings(
            isEnabled: true,
            sensitivityThreshold: 0.75,
            showBadges: true,
            includeInPrompts: false,
            saveHistory: true
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(EmotionSettings.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testEmotionSettings_Codable_UsesSnakeCaseKeys() throws {
        let settings = EmotionSettings.defaults

        let encoder = JSONEncoder()
        let data = try encoder.encode(settings)
        let json = String(data: data, encoding: .utf8) ?? ""

        XCTAssertTrue(json.contains("emotion_analysis_enabled"))
        XCTAssertTrue(json.contains("emotion_sensitivity"))
        XCTAssertTrue(json.contains("show_emotion_badges"))
        XCTAssertTrue(json.contains("include_emotion_in_prompts"))
        XCTAssertTrue(json.contains("save_emotion_history"))
    }

    // MARK: - VoiceStateMachine Emotion Event Tests

    func testVoiceStateMachine_EmotionDetected_NoStateTransition() {
        var machine = VoiceStateMachine(initialState: .speaking)
        let originalState = machine.state

        let newState = machine.send(.emotionDetected("happy", 0.85))

        // Emotion detection should not cause state transitions
        XCTAssertEqual(newState, originalState)
        XCTAssertEqual(machine.state, .speaking)
    }

    func testVoiceStateMachine_EmotionDetected_WorksInAnyState() {
        let states: [VoiceStateMachine.State] = [
            .idle, .ready, .listening, .userSpeaking, .thinking, .speaking, .muted
        ]

        for state in states {
            var machine = VoiceStateMachine(initialState: state)
            let newState = machine.send(.emotionDetected("calm", 0.7))

            // Should remain in the same state
            XCTAssertEqual(newState, state, "Emotion detected should not change state from \(state)")
        }
    }

    func testVoiceStateMachine_EmotionDetected_Event_Description() {
        let event = VoiceStateMachine.Event.emotionDetected("happy", 0.85)
        let description = event.description

        XCTAssertTrue(description.contains("happy"))
        XCTAssertTrue(description.contains("0.85"))
    }

    func testVoiceStateMachine_EmotionDetected_Event_Equatable() {
        let event1 = VoiceStateMachine.Event.emotionDetected("happy", 0.85)
        let event2 = VoiceStateMachine.Event.emotionDetected("happy", 0.85)
        let event3 = VoiceStateMachine.Event.emotionDetected("sad", 0.85)

        XCTAssertEqual(event1, event2)
        XCTAssertNotEqual(event1, event3)
    }

    // MARK: - Integration Scenario Tests

    func testEmotionHistory_BuildsCorrectly() {
        var history: [EmotionSnapshot] = []
        let sessionStart = Date()

        // Simulate multiple emotion detections during a session
        history.append(EmotionSnapshot(emotion: "neutral", confidence: 0.6, timestamp: 0))
        history.append(EmotionSnapshot(emotion: "happy", confidence: 0.75, timestamp: 15))
        history.append(EmotionSnapshot(emotion: "happy", confidence: 0.82, timestamp: 30))
        history.append(EmotionSnapshot(emotion: "calm", confidence: 0.68, timestamp: 45))

        XCTAssertEqual(history.count, 4)

        let summary = EmotionSummary(from: history)
        XCTAssertEqual(summary.dominantEmotion, "happy")
        XCTAssertEqual(summary.totalDetections, 4)
    }

    func testEmotionThresholdFiltering() {
        let snapshots = [
            EmotionSnapshot(emotion: "happy", confidence: 0.4, timestamp: 0),
            EmotionSnapshot(emotion: "sad", confidence: 0.6, timestamp: 10),
            EmotionSnapshot(emotion: "calm", confidence: 0.8, timestamp: 20),
            EmotionSnapshot(emotion: "angry", confidence: 0.55, timestamp: 30)
        ]

        let threshold = 0.6
        let aboveThreshold = snapshots.filter { $0.confidence >= threshold }

        XCTAssertEqual(aboveThreshold.count, 2)
        XCTAssertTrue(aboveThreshold.contains { $0.emotion == "sad" })
        XCTAssertTrue(aboveThreshold.contains { $0.emotion == "calm" })
    }

    // MARK: - Edge Case Tests

    func testEmotionSnapshot_UnknownEmotion_UsesDefaultIcon() {
        let snapshot = EmotionSnapshot(emotion: "unknown_emotion", confidence: 0.5, timestamp: 0)
        XCTAssertEqual(snapshot.icon, "circle.fill")
        XCTAssertEqual(snapshot.emoji, "😐")
        XCTAssertEqual(snapshot.colorHex, "#8E8E93")
    }

    func testEmotionSummary_TiedEmotions_PicksOne() {
        let history = [
            EmotionSnapshot(emotion: "happy", confidence: 0.8, timestamp: 0),
            EmotionSnapshot(emotion: "sad", confidence: 0.7, timestamp: 10)
        ]
        let summary = EmotionSummary(from: history)

        // When tied, picks one consistently (implementation dependent)
        XCTAssertTrue(summary.dominantEmotion == "happy" || summary.dominantEmotion == "sad")
        XCTAssertEqual(summary.totalDetections, 2)
    }

    func testEmotionSnapshot_ZeroConfidence() {
        let snapshot = EmotionSnapshot(emotion: "neutral", confidence: 0.0, timestamp: 0)
        XCTAssertEqual(snapshot.confidenceLevel, "low")
        XCTAssertEqual(snapshot.confidence, 0.0)
    }

    func testEmotionSnapshot_MaxConfidence() {
        let snapshot = EmotionSnapshot(emotion: "happy", confidence: 1.0, timestamp: 0)
        XCTAssertEqual(snapshot.confidenceLevel, "high")
        XCTAssertEqual(snapshot.confidence, 1.0)
    }

    func testEmotionSettings_MutableProperties() {
        var settings = EmotionSettings.defaults

        settings.isEnabled = true
        settings.sensitivityThreshold = 0.5
        settings.showBadges = false

        XCTAssertTrue(settings.isEnabled)
        XCTAssertEqual(settings.sensitivityThreshold, 0.5)
        XCTAssertFalse(settings.showBadges)
    }
}
