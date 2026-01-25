import XCTest
@testable import MindFriendApp

/// Tests for Generative Wellness Features
@MainActor
final class GenerativeViewsTests: XCTestCase {
    
    // MARK: - AudioPlayerViewModel Tests
    
    func testAudioPlayerInitialState() {
        let player = AudioPlayerViewModel()
        
        XCTAssertFalse(player.isLoading)
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.currentTime, 0)
        XCTAssertEqual(player.duration, 0)
        XCTAssertNil(player.error)
        XCTAssertEqual(player.playbackRate, 1.0)
        XCTAssertNil(player.sleepTimerMinutes)
        XCTAssertNil(player.backgroundSound)
        XCTAssertEqual(player.backgroundSoundVolume, 0.3)
    }
    
    func testPlaybackRateChange() {
        let player = AudioPlayerViewModel()
        
        player.playbackRate = 1.5
        XCTAssertEqual(player.playbackRate, 1.5)
        
        player.playbackRate = 0.75
        XCTAssertEqual(player.playbackRate, 0.75)
    }
    
    func testPlaybackSpeedsContainsExpectedValues() {
        let speeds = AudioPlayerViewModel.playbackSpeeds
        
        XCTAssertTrue(speeds.contains(0.75))
        XCTAssertTrue(speeds.contains(1.0))
        XCTAssertTrue(speeds.contains(1.25))
        XCTAssertTrue(speeds.contains(1.5))
    }
    
    func testSleepTimerPresetsContainsExpectedValues() {
        let presets = AudioPlayerViewModel.sleepTimerPresets
        
        XCTAssertTrue(presets.contains(nil))
        XCTAssertTrue(presets.contains(15))
        XCTAssertTrue(presets.contains(30))
        XCTAssertTrue(presets.contains(45))
        XCTAssertTrue(presets.contains(60))
    }
    
    func testProgressCalculation() {
        let player = AudioPlayerViewModel()
        
        // When duration is 0, progress should be 0
        XCTAssertEqual(player.progress, 0)
    }
    
    func testFormattedTimeOutput() {
        let player = AudioPlayerViewModel()
        
        XCTAssertEqual(player.formattedCurrentTime, "0:00")
        XCTAssertEqual(player.formattedDuration, "0:00")
    }
    
    func testBackgroundSoundVolumeClampedToValidRange() {
        let player = AudioPlayerViewModel()
        
        player.setBackgroundSoundVolume(0.5)
        XCTAssertEqual(player.backgroundSoundVolume, 0.5)
        
        player.setBackgroundSoundVolume(-0.5)
        XCTAssertEqual(player.backgroundSoundVolume, 0)
        
        player.setBackgroundSoundVolume(1.5)
        XCTAssertEqual(player.backgroundSoundVolume, 1.0)
    }
    
    // MARK: - BackgroundSoundType Tests
    
    func testBackgroundSoundTypeDisplayNames() {
        XCTAssertEqual(BackgroundSoundType.rain.displayName, "Rain")
        XCTAssertEqual(BackgroundSoundType.ocean.displayName, "Ocean Waves")
        XCTAssertEqual(BackgroundSoundType.forest.displayName, "Forest")
        XCTAssertEqual(BackgroundSoundType.fireplace.displayName, "Fireplace")
        XCTAssertEqual(BackgroundSoundType.whiteNoise.displayName, "White Noise")
        XCTAssertEqual(BackgroundSoundType.brownNoise.displayName, "Brown Noise")
        XCTAssertEqual(BackgroundSoundType.pinkNoise.displayName, "Pink Noise")
        XCTAssertEqual(BackgroundSoundType.silence.displayName, "Silence")
    }
    
    func testBackgroundSoundTypeIcons() {
        XCTAssertEqual(BackgroundSoundType.rain.icon, "cloud.rain.fill")
        XCTAssertEqual(BackgroundSoundType.ocean.icon, "water.waves")
        XCTAssertEqual(BackgroundSoundType.silence.icon, "speaker.slash.fill")
    }
    
    func testBackgroundSoundTypeRawValues() {
        XCTAssertEqual(BackgroundSoundType.whiteNoise.rawValue, "white_noise")
        XCTAssertEqual(BackgroundSoundType.brownNoise.rawValue, "brown_noise")
        XCTAssertEqual(BackgroundSoundType.pinkNoise.rawValue, "pink_noise")
    }
    
    // MARK: - GeneratedContentType Tests
    
    func testGeneratedContentTypeDefaults() {
        XCTAssertEqual(GeneratedContentType.sleepStory.defaultDuration, 20)
        XCTAssertEqual(GeneratedContentType.meditation.defaultDuration, 10)
        XCTAssertEqual(GeneratedContentType.breathing.defaultDuration, 5)
        XCTAssertEqual(GeneratedContentType.affirmation.defaultDuration, 3)
    }
    
    func testGeneratedContentTypeIcons() {
        XCTAssertEqual(GeneratedContentType.sleepStory.icon, "moon.stars.fill")
        XCTAssertEqual(GeneratedContentType.meditation.icon, "brain.head.profile")
        XCTAssertEqual(GeneratedContentType.breathing.icon, "wind")
    }
    
    func testGeneratedContentTypeSupportsAudio() {
        for type in GeneratedContentType.allCases {
            XCTAssertTrue(type.supportsAudio, "\(type) should support audio")
        }
    }
    
    // MARK: - VoiceOption Tests
    
    func testVoiceOptionInitialization() {
        let voice = VoiceOption(
            id: "test-id",
            name: "Test Voice",
            gender: .female,
            style: "calm",
            language: .english,
            accent: "American",
            isPremium: true,
            previewUrl: nil,
            sampleText: "Hello world"
        )
        
        XCTAssertEqual(voice.id, "test-id")
        XCTAssertEqual(voice.name, "Test Voice")
        XCTAssertEqual(voice.gender, .female)
        XCTAssertEqual(voice.accent, "American")
        XCTAssertTrue(voice.isPremium)
    }
    
    func testDefaultVoicesExist() {
        let voices = DefaultVoice.all
        
        XCTAssertFalse(voices.isEmpty)
        XCTAssertTrue(voices.count >= 5, "Should have at least 5 default voices")
    }
    
    func testVoicesByLanguage() {
        let englishVoices = DefaultVoice.voices(for: .english)
        let spanishVoices = DefaultVoice.voices(for: .spanish)
        
        XCTAssertFalse(englishVoices.isEmpty)
        XCTAssertFalse(spanishVoices.isEmpty)
        
        for voice in englishVoices {
            XCTAssertEqual(voice.language, .english)
        }
    }
    
    func testVoiceById() {
        let sarah = DefaultVoice.voice(for: "EXAVITQu4vr4xnSDxMaL")
        
        XCTAssertNotNil(sarah)
        XCTAssertEqual(sarah?.name, "Sarah")
    }
    
    // MARK: - ContentQuotaStatus Tests
    
    func testQuotaStatusCalculations() {
        let quota = ContentQuotaStatus(
            used: 2,
            limit: 3,
            isPremium: false,
            resetsAt: Date().addingTimeInterval(86400)
        )
        
        XCTAssertEqual(quota.remaining, 1)
        XCTAssertEqual(quota.percentUsed, 2.0/3.0, accuracy: 0.01)
        XCTAssertFalse(quota.isExhausted)
    }
    
    func testQuotaExhausted() {
        let exhaustedQuota = ContentQuotaStatus(
            used: 3,
            limit: 3,
            isPremium: false,
            resetsAt: nil
        )
        
        XCTAssertTrue(exhaustedQuota.isExhausted)
        XCTAssertEqual(exhaustedQuota.remaining, 0)
    }
    
    func testPremiumQuota() {
        let premiumQuota = ContentQuotaStatus(
            used: 50,
            limit: 999,
            isPremium: true,
            resetsAt: nil
        )
        
        XCTAssertTrue(premiumQuota.isPremium)
        XCTAssertFalse(premiumQuota.isExhausted)
        XCTAssertEqual(premiumQuota.remaining, 949)
    }
}
