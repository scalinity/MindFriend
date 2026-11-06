import XCTest
import Supabase
@testable import MindFriendApp

@MainActor
final class InterventionEfficacyEngineTests: XCTestCase {
    private func makeEngine() -> InterventionEfficacyEngine {
        EfficacyRequestRecorder.shared.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EfficacyBlockedURLProtocol.self]
        let client = SupabaseClient(
            supabaseURL: URL(string: "https://efficacy.invalid")!, supabaseKey: "synthetic-key",
            options: .init(auth: .init(storage: EfficacyAuthStorage(), autoRefreshToken: false),
                           global: .init(session: URLSession(configuration: configuration)))
        )
        return InterventionEfficacyEngine(tracker: TrajectoryTracker(supabase: client),
            calculator: EfficacyCalculator(), recommender: EfficacyBasedRecommender(supabase: client), supabase: client)
    }

    func testNoObservationsReturnsUnavailableAndAllowsNextSession() async throws {
        let engine = makeEngine()
        for _ in 0..<2 {
            try await engine.startSession(sessionId: UUID(), exerciseId: UUID(), userId: UUID())
            XCTAssertTrue(engine.isTrackingSession)
            let efficacy = try await engine.endSession()
            XCTAssertNil(efficacy)
            XCTAssertFalse(engine.isTrackingSession)
            XCTAssertFalse(engine.tracker.isTracking)
            XCTAssertTrue(engine.tracker.currentTrajectory.isEmpty)
        }
        XCTAssertEqual(EfficacyRequestRecorder.shared.count, 0, "No observations must create no trajectory or efficacy requests")
    }

    func testDuplicateStartAndAbsentSessionAreRejected() async throws {
        let engine = makeEngine()
        do {
            _ = try await engine.endSession()
            XCTFail("An inactive session must not end")
        } catch EfficacyError.noActiveSession {}
        try await engine.startSession(sessionId: UUID(), exerciseId: UUID(), userId: UUID())
        do {
            try await engine.startSession(sessionId: UUID(), exerciseId: UUID(), userId: UUID())
            XCTFail("An active session must not be replaced")
        } catch EfficacyError.sessionAlreadyActive {}
        _ = try await engine.endSession()
    }

    func testOrdinaryExerciseCompletesWithoutPhysiologicalOrEfficacyWrites() async throws {
        let engine = makeEngine()
        let service = EfficacyExerciseService()
        let exercise = Exercise(id: UUID().uuidString, type: .breathing,
            title: "Synthetic exercise", description: "Synthetic fixture", durationSeconds: 60,
            contentKind: .text, contentText: nil, audioUrl: nil, instructions: nil,
            evidenceBasis: nil, therapistReviewed: nil, reviewDate: nil, methodologyNote: nil)
        let player = LibraryExercisePlayerViewModel(exercise: exercise, dataService: service, efficacyEngine: engine)
        await player.startSession()
        let sessionID = try XCTUnwrap(player.session?.id)
        // Exercise tracking normally starts after authentication; use the fixture's known owner.
        try await engine.startSession(sessionId: try XCTUnwrap(UUID(uuidString: sessionID)),
                                      exerciseId: try XCTUnwrap(UUID(uuidString: exercise.id)), userId: UUID())
        player.isTrackingEfficacy = true
        player.completeExercise()
        for _ in 0..<100 {
            if player.showCompletion { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(player.showCompletion, "Missing measurements must not prevent the completion sheet")
        XCTAssertFalse(engine.isTrackingSession)
        XCTAssertFalse(player.isTrackingEfficacy)
        XCTAssertTrue(engine.tracker.currentTrajectory.isEmpty)
        let confirmed = try await player.submitCompletion()
        XCTAssertEqual(confirmed, sessionID)
        XCTAssertEqual(service.completed, [sessionID])
        XCTAssertEqual(service.rewarded, [sessionID])
        XCTAssertEqual(EfficacyRequestRecorder.shared.count, 0,
                       "An ordinary session must not save invented physiological samples or efficacy")
    }
}

@MainActor
private final class EfficacyExerciseService: LibraryExerciseSessionService {
    var completed: [String] = []
    var rewarded: [String] = []
    func startExerciseSession(exerciseId: String) async throws -> String { UUID().uuidString }
    func completeExerciseSession(sessionId: String, rating: Int?, note: String?) async throws { completed.append(sessionId) }
    func awardXP(activity: XPActivity, exerciseSessionId: String?) async throws -> XPAward {
        rewarded.append(try XCTUnwrap(exerciseSessionId))
        return XPAward(amount: 30, newTotal: 30, newLevel: 1, newTitle: "Synthetic", leveledUp: false)
    }
}

private final class EfficacyAuthStorage: AuthLocalStorage, @unchecked Sendable {
    func store(key: String, value: Data) {}
    func retrieve(key: String) -> Data? { nil }
    func remove(key: String) {}
}

private final class EfficacyRequestRecorder: @unchecked Sendable {
    static let shared = EfficacyRequestRecorder()
    private let lock = NSLock()
    private var requests = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return requests }
    func record() { lock.lock(); defer { lock.unlock() }; requests += 1 }
    func reset() { lock.lock(); defer { lock.unlock() }; requests = 0 }
}

private final class EfficacyBlockedURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        EfficacyRequestRecorder.shared.record()
        client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
    }
    override func stopLoading() {}
}
