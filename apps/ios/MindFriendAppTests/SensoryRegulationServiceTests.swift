//
//  SensoryRegulationServiceTests.swift
//  MindFriendAppTests
//
//  Tests for SensoryRegulationService
//

import XCTest
@testable import MindFriendApp

@MainActor
final class SensoryRegulationServiceTests: XCTestCase {
    var service: SensoryRegulationService!
    var mockSupabase: MockSupabaseDataService!
    var mockTactileService: MockTactilePatternService!
    var mockVisualService: MockVisualAnimationService!
    var mockAudioService: MockAudioSoundscapeService!
    var mockAchievementService: MockAchievementService!

    override func setUp() async throws {
        try await super.setUp()

        mockSupabase = MockSupabaseDataService()
        mockTactileService = MockTactilePatternService()
        mockVisualService = MockVisualAnimationService()
        mockAudioService = MockAudioSoundscapeService()
        mockAchievementService = MockAchievementService()

        service = SensoryRegulationService(
            supabase: mockSupabase,
            tactileService: mockTactileService,
            visualService: mockVisualService,
            audioService: mockAudioService,
            achievementService: mockAchievementService
        )
    }

    override func tearDown() async throws {
        service = nil
        mockSupabase = nil
        mockTactileService = nil
        mockVisualService = nil
        mockAudioService = nil
        mockAchievementService = nil
        try await super.tearDown()
    }

    // MARK: - Start Session Tests

    func testStartSession_Success_FreePattern() async throws {
        // Given
        mockSupabase.premiumAccessResult = false
        mockSupabase.createSessionResult = SensorySession.mockTactileSession

        // When
        try await service.startSession(
            modality: .tactile,
            patternId: "heartbeat",
            speed: .medium,
            loop: true
        )

        // Then
        XCTAssertNotNil(service.currentSession)
        XCTAssertTrue(service.isSessionActive)
        XCTAssertEqual(service.elapsedSeconds, 0)
        XCTAssertTrue(mockTactileService.playPatternCalled)
    }

    func testStartSession_PremiumPattern_WithAccess_Success() async throws {
        // Given
        mockSupabase.premiumAccessResult = true
        mockSupabase.createSessionResult = SensorySession.mockTactileSession

        // When
        try await service.startSession(
            modality: .tactile,
            patternId: "earth_pulse",  // Premium pattern
            speed: .slow,
            loop: true
        )

        // Then
        XCTAssertNotNil(service.currentSession)
        XCTAssertTrue(service.isSessionActive)
        XCTAssertTrue(mockSupabase.checkPremiumAccessCalled)
    }

    func testStartSession_PremiumPattern_NoAccess_ThrowsError() async throws {
        // Given
        mockSupabase.premiumAccessResult = false

        // When/Then
        do {
            try await service.startSession(
                modality: .tactile,
                patternId: "earth_pulse",  // Premium pattern
                speed: .slow,
                loop: true
            )
            XCTFail("Expected premiumRequired error")
        } catch let error as SensoryError {
            XCTAssertEqual(error, .premiumRequired)
        }

        XCTAssertNil(service.currentSession)
        XCTAssertFalse(service.isSessionActive)
    }

    func testStartSession_AlreadyActive_ThrowsError() async throws {
        // Given
        mockSupabase.premiumAccessResult = false
        mockSupabase.createSessionResult = SensorySession.mockTactileSession
        try await service.startSession(
            modality: .tactile,
            patternId: "heartbeat",
            speed: .medium,
            loop: true
        )

        // When/Then
        do {
            try await service.startSession(
                modality: .visual,
                patternId: "expanding_circle",
                speed: .fast,
                loop: true
            )
            XCTFail("Expected sessionInProgress error")
        } catch let error as SensoryError {
            XCTAssertEqual(error, .sessionInProgress)
        }
    }

    func testStartSession_TactileModality_CallsTactileService() async throws {
        // Given
        mockSupabase.createSessionResult = SensorySession.mockTactileSession

        // When
        try await service.startSession(
            modality: .tactile,
            patternId: "heartbeat",
            speed: .medium,
            loop: true
        )

        // Then
        XCTAssertTrue(mockTactileService.playPatternCalled)
        XCTAssertEqual(mockTactileService.lastPatternId, "heartbeat")
        XCTAssertEqual(mockTactileService.lastSpeed, .medium)
    }

    func testStartSession_VisualModality_CallsVisualService() async throws {
        // Given
        mockSupabase.createSessionResult = SensorySession.mockVisualSession

        // When
        try await service.startSession(
            modality: .visual,
            patternId: "expanding_circle",
            speed: .fast,
            loop: true
        )

        // Then
        XCTAssertTrue(mockVisualService.startAnimationCalled)
        XCTAssertEqual(mockVisualService.lastAnimationId, "expanding_circle")
        XCTAssertEqual(mockVisualService.lastSpeed, .fast)
    }

    func testStartSession_AudioModality_CallsAudioService() async throws {
        // Given
        mockSupabase.createSessionResult = SensorySession.mockAudioSession

        // When
        try await service.startSession(
            modality: .audio,
            patternId: "rain",
            speed: .slow,
            loop: true
        )

        // Then
        XCTAssertTrue(mockAudioService.playSoundCalled)
        XCTAssertEqual(mockAudioService.lastSoundId, "rain")
        XCTAssertTrue(mockAudioService.lastLoop)
    }

    // MARK: - Pause/Resume Tests

    func testPauseSession_Success() async throws {
        // Given
        mockSupabase.createSessionResult = SensorySession.mockTactileSession
        try await service.startSession(
            modality: .tactile,
            patternId: "heartbeat",
            speed: .medium,
            loop: true
        )

        // When
        await service.pauseSession()

        // Then
        XCTAssertNotNil(service.currentSession)
        XCTAssertEqual(service.currentSession?.status, .paused)
        XCTAssertTrue(mockTactileService.stopPatternCalled)
    }

    func testResumeSession_Success() async throws {
        // Given
        mockSupabase.createSessionResult = SensorySession.mockTactileSession
        try await service.startSession(
            modality: .tactile,
            patternId: "heartbeat",
            speed: .medium,
            loop: true
        )
        await service.pauseSession()

        // Reset mock flags
        mockTactileService.playPatternCalled = false

        // When
        try await service.resumeSession()

        // Then
        XCTAssertNotNil(service.currentSession)
        XCTAssertEqual(service.currentSession?.status, .active)
        XCTAssertTrue(mockTactileService.playPatternCalled)
    }

    func testResumeSession_ExceededMaxDuration_ThrowsError() async throws {
        // Given
        mockSupabase.createSessionResult = SensorySession.mockTactileSession
        try await service.startSession(
            modality: .tactile,
            patternId: "heartbeat",
            speed: .medium,
            loop: true
        )

        // Simulate 30 minutes elapsed
        service.elapsedSeconds = 1800

        await service.pauseSession()

        // When/Then
        do {
            try await service.resumeSession()
            XCTFail("Expected maxDurationExceeded error")
        } catch let error as SensoryError {
            XCTAssertEqual(error, .maxDurationExceeded)
        }

        XCTAssertNil(service.currentSession)
        XCTAssertFalse(service.isSessionActive)
    }

    // MARK: - End Session Tests

    func testEndSession_Success() async throws {
        // Given
        mockSupabase.createSessionResult = SensorySession.mockTactileSession
        mockSupabase.completeSessionResult = []

        try await service.startSession(
            modality: .tactile,
            patternId: "heartbeat",
            speed: .medium,
            loop: true
        )

        // When
        await service.endSession(interrupted: false)

        // Then
        XCTAssertNil(service.currentSession)
        XCTAssertFalse(service.isSessionActive)
        XCTAssertEqual(service.elapsedSeconds, 0)
        XCTAssertTrue(mockTactileService.stopPatternCalled)
        XCTAssertTrue(mockSupabase.completeSessionCalled)
    }

    func testEndSession_WithAchievements_NotifiesAchievementService() async throws {
        // Given
        let achievement = UserBadge.mockFirstSession
        mockSupabase.createSessionResult = SensorySession.mockTactileSession
        mockSupabase.completeSessionResult = [achievement]

        try await service.startSession(
            modality: .tactile,
            patternId: "heartbeat",
            speed: .medium,
            loop: true
        )

        // When
        await service.endSession(interrupted: false)

        // Then
        XCTAssertTrue(mockAchievementService.checkAchievementsCalled)
    }

    // MARK: - Timer Tests

    func testSessionTimer_IncrementsElapsedSeconds() async throws {
        // Given
        mockSupabase.createSessionResult = SensorySession.mockTactileSession

        try await service.startSession(
            modality: .tactile,
            patternId: "heartbeat",
            speed: .medium,
            loop: true
        )

        let initialElapsed = service.elapsedSeconds

        // When
        try await Task.sleep(nanoseconds: 2_100_000_000)  // 2.1 seconds

        // Then
        XCTAssertGreaterThan(service.elapsedSeconds, initialElapsed)
        XCTAssertGreaterThanOrEqual(service.elapsedSeconds, 2)
    }

    // MARK: - Settings Tests

    func testFetchSettings_Success() async throws {
        // Given
        let expectedSettings = SensorySettings(
            defaultSpeed: .fast,
            hapticIntensity: 0.7,
            enableAutoPause: false,
            defaultSessionDuration: 900
        )
        mockSupabase.sensorySettingsResult = expectedSettings

        // When
        let settings = try await service.fetchSettings()

        // Then
        XCTAssertEqual(settings.defaultSpeed, .fast)
        XCTAssertEqual(settings.hapticIntensity, 0.7)
        XCTAssertEqual(settings.enableAutoPause, false)
        XCTAssertEqual(settings.defaultSessionDuration, 900)
    }

    func testUpdateSettings_Success() async throws {
        // Given
        let newSettings = SensorySettings(
            defaultSpeed: .slow,
            hapticIntensity: 0.5,
            enableAutoPause: true,
            defaultSessionDuration: 1200
        )

        // When
        let result = try await service.updateSettings(newSettings)

        // Then
        XCTAssertTrue(mockSupabase.updateSensorySettingsCalled)
        XCTAssertNotNil(result)
    }
}

// MARK: - Mock Services

class MockSupabaseDataService {
    var premiumAccessResult = false
    var createSessionResult: SensorySession?
    var completeSessionResult: [UserBadge] = []
    var sensorySettingsResult: SensorySettings?

    var checkPremiumAccessCalled = false
    var createSessionCalled = false
    var completeSessionCalled = false
    var updateSensorySettingsCalled = false

    func checkPremiumAccess() async throws -> Bool {
        checkPremiumAccessCalled = true
        return premiumAccessResult
    }

    func getCurrentUserId() async throws -> UUID {
        return UUID()
    }
}

class MockTactilePatternService {
    var playPatternCalled = false
    var stopPatternCalled = false
    var lastPatternId: String?
    var lastSpeed: SpeedPreset?
    var lastLoop: Bool?

    func playPattern(id: String, speed: SpeedPreset, loop: Bool) async throws {
        playPatternCalled = true
        lastPatternId = id
        lastSpeed = speed
        lastLoop = loop
    }

    func stopPattern() async {
        stopPatternCalled = true
    }
}

class MockVisualAnimationService {
    var startAnimationCalled = false
    var stopAnimationCalled = false
    var lastAnimationId: String?
    var lastSpeed: SpeedPreset?

    func startAnimation(id: String, speed: SpeedPreset) async throws {
        startAnimationCalled = true
        lastAnimationId = id
        lastSpeed = speed
    }

    func stopAnimation() async {
        stopAnimationCalled = true
    }
}

class MockAudioSoundscapeService {
    var playSoundCalled = false
    var stopSoundCalled = false
    var lastSoundId: String?
    var lastLoop: Bool?

    func playSound(id: String, loop: Bool) async throws {
        playSoundCalled = true
        lastSoundId = id
        lastLoop = loop
    }

    func stopSound() async {
        stopSoundCalled = true
    }
}

class MockAchievementService {
    var checkAchievementsCalled = false

    func checkAchievements(event: AchievementEvent, metadata: [String: String]) async throws {
        checkAchievementsCalled = true
    }
}

// MARK: - Mock Data Extensions

extension SensorySession {
    static var mockTactileSession: SensorySession {
        SensorySession(
            id: UUID(),
            userId: UUID(),
            modality: .tactile,
            patternId: "heartbeat",
            startedAt: Date(),
            completedAt: nil,
            durationSeconds: nil,
            interrupted: false,
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    static var mockVisualSession: SensorySession {
        SensorySession(
            id: UUID(),
            userId: UUID(),
            modality: .visual,
            patternId: "expanding_circle",
            startedAt: Date(),
            completedAt: nil,
            durationSeconds: nil,
            interrupted: false,
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    static var mockAudioSession: SensorySession {
        SensorySession(
            id: UUID(),
            userId: UUID(),
            modality: .audio,
            patternId: "rain",
            startedAt: Date(),
            completedAt: nil,
            durationSeconds: nil,
            interrupted: false,
            status: .active,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

extension UserBadge {
    static var mockFirstSession: UserBadge {
        UserBadge(
            id: UUID(),
            userId: UUID(),
            badgeId: UUID(),
            earnedAt: Date(),
            code: "sensory_first_session",
            title: "First Steps",
            description: "Complete your first sensory session",
            iconName: "🌟",
            category: "getting_started"
        )
    }
}
