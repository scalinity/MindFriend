import XCTest
import Supabase
@testable import MindFriendApp

@MainActor
final class TrajectoryTrackerTests: XCTestCase {
    private func makeTracker() -> TrajectoryTracker {
        TrajectoryTracker(supabase: SupabaseClient(
            supabaseURL: URL(string: "https://measurements.invalid")!, supabaseKey: "synthetic-key"
        ))
    }

    func testSessionDoesNotInventInitialOrFinalMeasurements() async throws {
        let tracker = makeTracker()
        tracker.startTracking(sessionId: UUID(), exerciseId: UUID(), userId: UUID())
        XCTAssertTrue(tracker.isTracking)
        XCTAssertTrue(tracker.currentTrajectory.isEmpty)
        let trajectory = try await tracker.stopTracking()
        XCTAssertTrue(trajectory.isEmpty)
        XCTAssertTrue(tracker.currentTrajectory.isEmpty)
        XCTAssertFalse(tracker.isTracking)
    }

    func testRepeatedSessionsStayUnavailableWithoutObservations() async throws {
        let tracker = makeTracker()
        for _ in 0..<3 {
            tracker.startTracking(sessionId: UUID(), exerciseId: UUID(), userId: UUID())
            let trajectory = try await tracker.stopTracking()
            XCTAssertTrue(trajectory.isEmpty)
        }
    }

    func testStopWithoutStartingReturnsNoMeasurements() async throws {
        let tracker = makeTracker()
        let trajectory = try await tracker.stopTracking()
        XCTAssertTrue(trajectory.isEmpty)
        XCTAssertFalse(tracker.isTracking)
    }
}
