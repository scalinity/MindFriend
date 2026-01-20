import XCTest
@testable import MindFriendApp

final class RitualServiceTests: XCTestCase {

    var sut: RitualService!
    var mockSupabase: MockSupabaseClient!

    override func setUp() {
        super.setUp()
        mockSupabase = MockSupabaseClient()
        sut = RitualService(supabase: mockSupabase)
    }

    override func tearDown() {
        sut = nil
        mockSupabase = nil
        super.tearDown()
    }

    // MARK: - createRitual Tests

    func testCreateRitual_success() async throws {
        let circleId = UUID()
        let ritualId = UUID()

        mockSupabase.mockInvokeResult = CreateRitualResponse.mock(ritualId: ritualId)

        let result = try await sut.createRitual(
            circleId: circleId,
            title: "Morning Gratitude",
            ritualType: .gratitude,
            startNow: true
        )

        XCTAssertEqual(result.id, ritualId)
        XCTAssertEqual(result.title, "Morning Gratitude")
    }

    func testCreateRitual_scheduled() async throws {
        let circleId = UUID()
        let scheduledFor = Date().addingTimeInterval(3600)

        mockSupabase.mockInvokeResult = CreateRitualResponse.mock()

        _ = try await sut.createRitual(
            circleId: circleId,
            title: "Evening Reflection",
            ritualType: .wins,
            startNow: false,
            scheduledFor: scheduledFor
        )

        // Verify request structure
        let capturedRequest = mockSupabase.capturedRequest as? RitualService.CreateRitualRequest
        XCTAssertEqual(capturedRequest?.startOption, "scheduled")
    }

    // MARK: - joinRitual Tests

    func testJoinRitual_success() async throws {
        let ritualId = UUID()

        mockSupabase.mockInvokeResult = JoinRitualResponse.mock(
            ritualId: ritualId,
            currentStep: .init(stepIndex: 0, prompt: "Test prompt", timeRemaining: 60, completed: false)
        )

        let result = try await sut.joinRitual(ritualId: ritualId)

        XCTAssertEqual(result.ritual.id, ritualId)
        XCTAssertEqual(result.currentStep?.stepIndex, 0)
        XCTAssertEqual(result.attendees.count, 1)
    }

    func testJoinRitual_updatesPublishedState() async throws {
        let ritualId = UUID()

        mockSupabase.mockInvokeResult = JoinRitualResponse.mock(ritualId: ritualId)

        _ = try await sut.joinRitual(ritualId: ritualId)

        XCTAssertEqual(sut.currentRitual?.id, ritualId)
        XCTAssertEqual(sut.attendees.count, 1)
    }

    func testJoinRitual_multipleAttendees() async throws {
        let ritualId = UUID()

        mockSupabase.mockInvokeResult = JoinRitualResponse.mock(
            ritualId: ritualId,
            attendees: [
                .init(userId: UUID(), displayName: "Alice", joinedAt: Date().ISO8601Format()),
                .init(userId: UUID(), displayName: "Bob", joinedAt: Date().ISO8601Format()),
                .init(userId: UUID(), displayName: "Charlie", joinedAt: Date().ISO8601Format())
            ]
        )

        let result = try await sut.joinRitual(ritualId: ritualId)

        XCTAssertEqual(result.attendees.count, 3)
    }

    // MARK: - completeRitual Tests

    func testCompleteRitual_success() async throws {
        let ritualId = UUID()
        let recapPostId = UUID()

        mockSupabase.mockInvokeResult = CompleteRitualResponse.mock(
            attendeeCount: 3,
            recapPostId: recapPostId
        )

        let result = try await sut.completeRitual(ritualId: ritualId)

        XCTAssertEqual(result.attendeeCount, 3)
        XCTAssertEqual(result.recapPostId, recapPostId)
    }

    func testCompleteRitual_noRecap() async throws {
        let ritualId = UUID()

        mockSupabase.mockInvokeResult = CompleteRitualResponse.mock(
            attendeeCount: 0,
            recapPostId: nil
        )

        let result = try await sut.completeRitual(ritualId: ritualId)

        XCTAssertEqual(result.attendeeCount, 0)
        XCTAssertNil(result.recapPostId)
    }

    // MARK: - addReflection Tests

    func testAddReflection_success() async throws {
        let ritualId = UUID()
        let reflectionId = UUID()

        mockSupabase.mockInvokeResult = AddReflectionResponse.mock(reflectionId: reflectionId)

        let result = try await sut.addReflection(
            ritualId: ritualId,
            content: "My reflection content"
        )

        XCTAssertEqual(result.id, reflectionId)
        XCTAssertEqual(result.content, "My reflection content")
    }

    // MARK: - fetchUpcomingRituals Tests

    func testFetchUpcomingRituals_success() async throws {
        let circleId = UUID()

        mockSupabase.mockQueryResult = [CircleRitual.mock()]

        let result = try await sut.fetchUpcomingRituals(circleId: circleId)

        XCTAssertEqual(result.count, 1)
    }

    func testFetchUpcomingRituals_empty() async throws {
        let circleId = UUID()

        mockSupabase.mockQueryResult = [CircleRitual]()

        let result = try await sut.fetchUpcomingRituals(circleId: circleId)

        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Realtime Subscription Tests

    func testSubscribeToRitual_setsUpChannel() async {
        let ritualId = UUID()

        await sut.subscribeToRitual(
            ritualId: ritualId,
            onUserJoined: { _ in },
            onUserLeft: { _ in },
            onCompleted: { _, _ in },
            onReflectionAdded: { _ in }
        )

        XCTAssertNotNil(sut.realtimeChannel)
    }

    func testUnsubscribeFromRitual_clearsChannel() async {
        let ritualId = UUID()

        await sut.subscribeToRitual(
            ritualId: ritualId,
            onUserJoined: { _ in },
            onUserLeft: { _ in },
            onCompleted: { _, _ in },
            onReflectionAdded: { _ in }
        )

        await sut.unsubscribeFromRitual()

        XCTAssertNil(sut.realtimeChannel)
    }
}

// MARK: - Mock Supabase Client

final class MockSupabaseClient: SupabaseClient {
    var mockInvokeResult: Data?
    var mockQueryResult: [Any] = []
    var capturedRequest: Any?

    override func invoke(function name: String, options: SupabaseFunctionInvokeOptions?) async throws -> Data {
        // Capture the request for verification
        if let body = options?.body {
            capturedRequest = body
        }
        guard let result = mockInvokeResult else {
            throw NSError(domain: "MockError", code: 1, userInfo: [NSLocalizedDescriptionKey: "No mock result set"])
        }
        return result
    }

    override func from(_ table: String) -> SupabaseQueryBuilder {
        MockQueryBuilder(mockResults: mockQueryResult)
    }

    override var realtimeV2: RealtimeClientV2 {
        MockRealtimeClientV2()
    }
}

final class MockQueryBuilder: SupabaseQueryBuilder {
    private let mockResults: [Any]

    init(mockResults: [Any]) {
        self.mockResults = mockResults
        super.init(url: URL(string: "http://localhost")!, headers: [:])
    }

    override func select(columns: String?) -> Self {
        self
    }

    override func eq(column: String, value: Any) -> Self {
        self
    }

    override func single() async throws -> Row {
        Row(data: [:])
    }

    override func execute() async throws -> SupabaseResponse {
        SupabaseResponse(data: try JSONEncoder().encode(mockResults))
    }
}

final class MockRealtimeClientV2: RealtimeClientV2 {
    var subscribedChannels: [String: RealtimeChannelV2] = [:]

    func channel(_ id: String) -> RealtimeChannelV2 {
        if let existing = subscribedChannels[id] {
            return existing
        }
        let channel = MockRealtimeChannel()
        subscribedChannels[id] = channel
        return channel
    }
}

final class MockRealtimeChannel: RealtimeChannelV2 {
    var subscribed = false

    func subscribe() async {
        subscribed = true
    }

    func unsubscribe() async {
        subscribed = false
    }

    func broadcastStream(event: String) -> AsyncStream<[String: Any]> {
        AsyncStream { _ in }
    }
}

// MARK: - Response Mocks

extension CreateRitualResponse {
    static func mock(ritualId: UUID = UUID()) -> Data {
        let response: [String: Any] = [
            "ritual": [
                "id": ritualId.uuidString,
                "circle_id": UUID().uuidString,
                "created_by": UUID().uuidString,
                "title": "Test Ritual",
                "ritual_type": "gratitude",
                "scheduled_for": Date().ISO8601Format(),
                "duration_seconds": 180,
                "status": "active",
                "created_at": Date().ISO8601Format()
            ]
        ]
        return try! JSONSerialization.data(withJSONObject: response)
    }
}

extension JoinRitualResponse {
    static func mock(
        ritualId: UUID = UUID(),
        currentStep: CurrentStepResponse? = nil,
        attendees: [AttendeeResponse] = []
    ) -> Data {
        var response: [String: Any] = [
            "ritual": [
                "id": ritualId.uuidString,
                "title": "Test",
                "ritual_type": "gratitude",
                "status": "active",
                "scheduled_for": Date().ISO8601Format(),
                "duration_seconds": 180
            ],
            "attendees": attendees.map { attendee in
                [
                    "user_id": attendee.userId.uuidString,
                    "display_name": attendee.displayName,
                    "joined_at": attendee.joinedAt
                ]
            }
        ]

        if let step = currentStep {
            response["currentStep"] = [
                "stepIndex": step.stepIndex,
                "prompt": step.prompt,
                "timeRemaining": step.timeRemaining,
                "completed": step.completed
            ]
        }

        return try! JSONSerialization.data(withJSONObject: response)
    }
}

extension CompleteRitualResponse {
    static func mock(attendeeCount: Int, recapPostId: UUID?) -> Data {
        let response: [String: Any] = [
            "ritual": [
                "id": UUID().uuidString,
                "status": "completed",
                "completed_at": Date().ISO8601Format(),
                "attendee_count": attendeeCount
            ],
            "recap_post_id": recapPostId?.uuidString ?? ""
        ]
        return try! JSONSerialization.data(withJSONObject: response)
    }
}

extension AddReflectionResponse {
    static func mock(reflectionId: UUID = UUID()) -> Data {
        let response: [String: Any] = [
            "reflection": [
                "id": reflectionId.uuidString,
                "ritual_id": UUID().uuidString,
                "user_id": UUID().uuidString,
                "body_text": "Test reflection",
                "created_at": Date().ISO8601Format()
            ],
            "updated": false
        ]
        return try! JSONSerialization.data(withJSONObject: response)
    }
}

extension CircleRitual {
    static func mock() -> CircleRitual {
        CircleRitual(
            id: UUID(),
            circleId: UUID(),
            createdBy: UUID(),
            title: "Test Ritual",
            ritualType: .gratitude,
            scheduledFor: Date(),
            durationSeconds: 180,
            status: .active,
            createdAt: Date(),
            completedAt: nil
        )
    }
}
