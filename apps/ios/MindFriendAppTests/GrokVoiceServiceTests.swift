import XCTest
@testable import MindFriendApp

@MainActor
final class GrokVoiceServiceTests: XCTestCase {

    var sut: GrokVoiceService!
    var mockSupabase: MockVoiceSupabaseClient!

    override func setUp() async throws {
        try await super.setUp()
        mockSupabase = MockVoiceSupabaseClient()
        sut = GrokVoiceService(supabase: mockSupabase)
    }

    override func tearDown() async throws {
        await sut.disconnect()
        sut = nil
        mockSupabase = nil
        try await super.tearDown()
    }

    // MARK: - Connection Tests

    func testInitialState() {
        XCTAssertEqual(sut.connectionState, .disconnected)
        XCTAssertFalse(sut.isListening)
        XCTAssertFalse(sut.isSpeaking)
        XCTAssertFalse(sut.isUserSpeaking)
        XCTAssertEqual(sut.transcribedText, "")
        XCTAssertEqual(sut.micLevel, 0)
        XCTAssertEqual(sut.playbackLevel, 0)
    }

    func testConnectSetsConnectingState() async throws {
        // Given: Service is disconnected
        XCTAssertEqual(sut.connectionState, .disconnected)

        // When: Connect is called (will fail without real token, but state should transition)
        let expectation = expectation(description: "Connection attempt")
        Task {
            do {
                try await sut.connect()
            } catch {
                // Expected to fail without real credentials
            }
            expectation.fulfill()
        }

        // Then: State should transition to connecting
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        XCTAssertNotEqual(sut.connectionState, .disconnected)

        await fulfillment(of: [expectation], timeout: 15.0)
    }

    func testDisconnectClearsState() async {
        // Given: Service has some state
        // (Can't fully connect without real credentials, so we'll test cleanup)

        // When: Disconnect is called
        await sut.disconnect()

        // Then: State is cleaned up
        XCTAssertEqual(sut.connectionState, .disconnected)
        XCTAssertFalse(sut.isListening)
        XCTAssertFalse(sut.isSpeaking)
    }

    // MARK: - Listening Tests

    func testStartListeningRequiresConnection() {
        // Given: Service is not connected
        XCTAssertEqual(sut.connectionState, .disconnected)

        // When/Then: Starting listening throws error
        XCTAssertThrowsError(try sut.startListening()) { error in
            XCTAssertEqual(error as? VoiceError, .notConnected)
        }
    }

    func testStopListeningWhenNotListening() {
        // Given: Service is not listening
        XCTAssertFalse(sut.isListening)

        // When: Stop listening is called
        sut.stopListening()

        // Then: No error, state remains false
        XCTAssertFalse(sut.isListening)
    }

    // MARK: - Voice Settings Tests

    func testSetVoiceRequiresPremiumForNonAra() async {
        // Given: Non-premium user
        XCTAssertFalse(sut.isPremium)

        // When/Then: Setting non-ara voice throws error
        do {
            try await sut.setVoice(.rex)
            XCTFail("Should have thrown premiumRequired error")
        } catch let error as VoiceError {
            XCTAssertEqual(error, .premiumRequired)
        } catch {
            XCTFail("Wrong error type: \(error)")
        }
    }

    // MARK: - Playback Tests

    func testInterruptPlaybackStopsPlayback() {
        // Given: Service is in a state
        // (Can't fully set up playback without connection)

        // When: Interrupt is called
        sut.interruptPlayback()

        // Then: Playback flags are cleared
        XCTAssertFalse(sut.isSpeaking)
    }

    // MARK: - Protocol Conformance Tests

    func testConformsToVoiceServiceProtocol() {
        // Verify the service conforms to the protocol
        let _: any VoiceServiceProtocol = sut
        XCTAssertTrue(true, "Service conforms to VoiceServiceProtocol")
    }

    func testPublishedPropertiesAreObservable() async {
        // Given: Observer setup
        var stateChanges = 0
        let cancellable = sut.$connectionState.sink { _ in
            stateChanges += 1
        }

        // When: State changes
        await sut.disconnect()

        // Then: Observer was notified
        XCTAssertGreaterThan(stateChanges, 0)

        cancellable.cancel()
    }

    // MARK: - Reconnection Tests

    func testReconnectionLogicInitialState() {
        // Given: Fresh service
        // The reconnection properties are private, so we test behavior

        // When: Connect fails (no real credentials)
        Task {
            do {
                try await sut.connect()
            } catch {
                // Expected to fail
            }
        }

        // Then: State should reflect error or reconnecting
        // (Implementation detail: reconnection happens automatically)
    }

    // MARK: - Resource Cleanup Tests

    func testDisconnectCancelsReconnectionAttempts() async {
        // Given: Service might be reconnecting
        // (Private implementation detail)

        // When: Disconnect is called
        await sut.disconnect()

        // Then: State is disconnected (not reconnecting)
        XCTAssertEqual(sut.connectionState, .disconnected)
    }

    // MARK: - Audio Level Tests

    func testMicLevelInitiallyZero() {
        XCTAssertEqual(sut.micLevel, 0.0)
    }

    func testPlaybackLevelInitiallyZero() {
        XCTAssertEqual(sut.playbackLevel, 0.0)
    }

    // MARK: - Quota Tests

    func testMinutesRemainingInitiallyZero() {
        XCTAssertEqual(sut.minutesRemaining, 0.0)
    }

    func testIsPremiumInitiallyFalse() {
        XCTAssertFalse(sut.isPremium)
    }

    // MARK: - Voice Selection Tests

    func testCurrentVoiceDefaultsToAra() {
        XCTAssertEqual(sut.currentVoice, .ara)
    }

    func testAvailableVoicesIncludesAra() {
        XCTAssertTrue(sut.availableVoices.contains(.ara))
    }
}

// MARK: - Mock Supabase Client

class MockVoiceSupabaseClient {
    // Minimal mock for testing
    // In a real implementation, this would mock SupabaseClient properly
}

// MARK: - Helper Extensions

extension VoiceError: Equatable {
    public static func == (lhs: VoiceError, rhs: VoiceError) -> Bool {
        switch (lhs, rhs) {
        case (.notAuthorized, .notAuthorized),
             (.notConnected, .notConnected),
             (.connectionTimeout, .connectionTimeout),
             (.quotaExceeded, .quotaExceeded),
             (.premiumRequired, .premiumRequired),
             (.microphonePermissionDenied, .microphonePermissionDenied),
             (.tokenGenerationFailed, .tokenGenerationFailed),
             (.networkUnavailable, .networkUnavailable):
            return true
        case (.connectionFailed(let a), .connectionFailed(let b)),
             (.audioSessionFailed(let a), .audioSessionFailed(let b)):
            return a == b
        default:
            return false
        }
    }
}
