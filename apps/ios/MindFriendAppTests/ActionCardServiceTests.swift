import XCTest
@testable import MindFriendApp

final class ActionCardServiceTests: XCTestCase {
    var sut: ActionCardService!
    var mockSupabase: MockSupabaseClient!

    override func setUp() {
        super.setUp()
        mockSupabase = MockSupabaseClient()
        sut = ActionCardService(supabase: mockSupabase)
    }

    override func tearDown() {
        sut = nil
        mockSupabase = nil
        super.tearDown()
    }

    func testGenerateActionCards_Success() async throws {
        let expectation = XCTestExpectation(description: "Generate action cards successfully")

        let request = GenerateActionCardsRequest(
            conversationId: UUID().uuidString,
            messageId: UUID().uuidString,
            messageContent: "I feel really anxious right now",
            messageIntent: nil,
            userContext: UserContext(
                completedExerciseIds: [],
                currentStreak: 5,
                lastMoodLog: nil,
                activeQuestId: nil,
                isPremium: false
            )
        )

        let response = try await sut.generateActionCards(request)

        XCTAssertFalse(response.cards.isEmpty)
        expectation.fulfill()
    }

    func testRecordActionTaken_Success() async throws {
        let expectation = XCTestExpectation(description: "Record action taken successfully")

        let request = CardActionRequest(
            cardId: UUID().uuidString,
            actionType: "tap",
            additionalData: nil
        )

        try await sut.recordActionTaken(request)

        XCTAssertTrue(mockSupabase.functionsInvokeCalled)
        XCTAssertEqual(mockSupabase.lastFunctionName, "card-action-taken")
        expectation.fulfill()
    }

    func testDismissCard_Success() async throws {
        let expectation = XCTestExpectation(description: "Dismiss card successfully")

        let request = DismissCardRequest(
            cardId: UUID().uuidString,
            reason: "not_interested",
            snoozeMinutes: nil,
            suppressSimilar: false
        )

        try await sut.dismissCard(request)

        XCTAssertTrue(mockSupabase.functionsInvokeCalled)
        XCTAssertEqual(mockSupabase.lastFunctionName, "dismiss-card")
        expectation.fulfill()
    }
}

// MARK: - Mock Supabase Client

final class MockSupabaseClient: SupabaseClient {
    var functionsInvokeCalled = false
    var lastFunctionName: String?
    var mockResponse: Decodable?

    override init() {
        super.init()
    }

    override var functions: SupabaseFunctionsClient {
        MockFunctionsClient(testCase: self)
    }
}

final class MockFunctionsClient: SupabaseFunctionsClient {
    weak var testCase: ActionCardServiceTests?

    init(testCase: ActionCardServiceTests) {
        self.testCase = testCase
        super.init()
    }

    override func invoke<T>(_ function: String, options: FunctionInvokeOptions?) async throws -> SupabaseFunctionsClient.Response<T> where T: Decodable {
        testCase?.functionsInvokeCalled = true
        testCase?.lastFunctionName = function

        let mockResponse = GenerateActionCardsResponse(
            cards: [
                ActionCardDTO(
                    id: UUID().uuidString,
                    cardType: .exercise,
                    title: "Test Card",
                    description: "Test description",
                    icon: "wind",
                    estimatedMinutes: 3,
                    actionDestination: ActionDestinationDTO(type: "exercise", id: "test", params: nil),
                    metadata: CardMetadataDTO(isPremium: false, priority: 90, conditions: nil)
                )
            ],
            generatedAt: ISO8601DateFormatter().string(from: Date())
        )

        return Response(request: URLRequest(url: URL(string: "http://test")!), data: try JSONEncoder().encode(mockResponse))
    }
}
