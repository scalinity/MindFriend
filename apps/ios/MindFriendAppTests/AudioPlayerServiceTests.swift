import XCTest
import Supabase
@testable import MindFriendApp

@MainActor
final class AudioPlayerServiceTests: XCTestCase {
    private func makeService() -> AudioPlayerService {
        AudioPlayerService(supabase: SupabaseClient(
            supabaseURL: URL(string: "http://127.0.0.1:1")!,
            supabaseKey: "synthetic-test-key"
        ))
    }

    func testEndOfTrackTimerOverridesLoopingAndClearsTimer() async {
        let service = makeService()
        defer { service.cleanup() }
        service.isLoopingEnabled = true
        service.setSleepTimer(.endOfTrack)
        await service.handlePlaybackEnd()
        XCTAssertNil(service.sleepTimerDuration)
        XCTAssertFalse(service.state.isPlaying)
    }

    func testReplacingTimedSleepWithEndOfTrackClearsCountdown() {
        let service = makeService()
        defer { service.cleanup() }
        service.setSleepTimer(.minutes15)
        XCTAssertEqual(service.sleepTimerRemaining, 900)
        service.setSleepTimer(.endOfTrack)
        XCTAssertEqual(service.sleepTimerRemaining, 0)
        XCTAssertNil(service.sleepTimer)
        XCTAssertEqual(service.sleepTimerDuration, .endOfTrack)
    }

    func testCancellingFadePreventsItsCompletionFromStoppingLaterPlayback() async throws {
        let service = makeService()
        defer { service.cleanup() }
        var completed = false
        service.fadeOutAndStopWithDuration(0.05) { completed = true }
        XCTAssertTrue(service.isSleepFading)
        service.cancelSleepTimer()
        service.setSleepTimer(.minutes15)
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertFalse(completed)
        XCTAssertFalse(service.isSleepFading)
        XCTAssertEqual(service.sleepTimerDuration, .minutes15)
    }

    func testStopInvalidatesFadeAndSleepCountdown() async throws {
        let service = makeService()
        defer { service.cleanup() }
        var completed = false
        service.setSleepTimer(.minutes15)
        service.fadeOutAndStopWithDuration(0.05) { completed = true }
        service.stop()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertFalse(completed)
        XCTAssertFalse(service.isSleepFading)
        XCTAssertNil(service.sleepTimer)
        XCTAssertNil(service.sleepTimerDuration)
    }

    func testCompletionDecodesBooleanServerContract() throws {
        let result = try JSONDecoder().decode(
            AudioPlayerService.PlaybackCompletionResponse.self,
            from: Data(#"{"success":true}"#.utf8)
        )
        XCTAssertTrue(result.success)
    }

    func testCompletionCrossingThresholdAndEndingClaimsOnlyOneAttempt() {
        var gate = PlaybackCompletionGate()
        XCTAssertTrue(gate.claim())
        for _ in 0..<20 { XCTAssertFalse(gate.claim()) }
        XCTAssertFalse(gate.claim(retryRejected: true))
    }

    func testCompletionRetriesOnlyConfirmedRejectionOnceAtEnd() {
        var gate = PlaybackCompletionGate()
        XCTAssertTrue(gate.claim())
        gate.markRejected()
        XCTAssertFalse(gate.claim())
        XCTAssertTrue(gate.claim(retryRejected: true))
        gate.markRejected()
        XCTAssertFalse(gate.claim(retryRejected: true))
    }
}
