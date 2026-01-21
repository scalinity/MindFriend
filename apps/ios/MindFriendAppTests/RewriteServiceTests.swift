import XCTest
@testable import MindFriendApp

final class RewriteServiceTests: XCTestCase {
    var sut: RewriteService!
    var mockSupabase: MockSupabaseClient!

    override func setUp() {
        super.setUp()
        mockSupabase = MockSupabaseClient()
        sut = RewriteService(supabase: mockSupabase)
    }

    override func tearDown() {
        sut = nil
        mockSupabase = nil
        super.tearDown()
    }

    func testRewriteType_IsPremium() {
        XCTAssertFalse(RewriteType.lessCatastrophic.isPremium)
        XCTAssertFalse(RewriteType.moreBalanced.isPremium)
        XCTAssertTrue(RewriteType.moreActionable.isPremium)
        XCTAssertTrue(RewriteType.moreCompassionate.isPremium)
    }

    func testRewriteType_DisplayName() {
        XCTAssertEqual(RewriteType.lessCatastrophic.displayName, "Less Catastrophic")
        XCTAssertEqual(RewriteType.moreBalanced.displayName, "More Balanced")
        XCTAssertEqual(RewriteType.moreActionable.displayName, "More Actionable")
        XCTAssertEqual(RewriteType.moreCompassionate.displayName, "More Self-Compassionate")
    }

    func testRewriteQuota_remainingForFreeUser() {
        let quota = RewriteQuota(dailyCount: 3, lastResetAt: Date(), isPremium: false)
        XCTAssertEqual(quota.remaining, 2)
    }

    func testRewriteQuota_remainingForPremiumUser() {
        let quota = RewriteQuota(dailyCount: 100, lastResetAt: Date(), isPremium: true)
        XCTAssertEqual(quota.remaining, -1)
    }

    func testRewriteOption_Codable() throws {
        let option = RewriteOption(id: "test-id", text: "Test text", explanation: "Test explanation")
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(option)
        let decoded = try decoder.decode(RewriteOption.self, from: data)

        XCTAssertEqual(option.id, decoded.id)
        XCTAssertEqual(option.text, decoded.text)
        XCTAssertEqual(option.explanation, decoded.explanation)
    }
}

// MARK: - Mock Supabase Client

final class MockSupabaseClient: SupabaseClient {
    var functionsInvokeCalled = false
    var lastFunctionName: String?

    override init() {
        super.init()
    }

    override var functions: SupabaseFunctionsClient {
        MockFunctionsClient(testCase: self)
    }

    override var auth: SupabaseAuthClient {
        MockAuthClient()
    }

    override func from(_ table: String) -> SupabaseQueryBuilder {
        MockQueryBuilder()
    }
}

final class MockFunctionsClient: SupabaseFunctionsClient {
    weak var testCase: RewriteServiceTests?

    init(testCase: MockSupabaseClient) {
        self.testCase = nil
        super.init()
    }

    override func invoke<T>(_ function: String, options: FunctionInvokeOptions?) async throws -> SupabaseFunctionsClient.Response<T> where T: Decodable {
        testCase?.functionsInvokeCalled = true
        testCase?.lastFunctionName = function

        let mockResponse = GenerateRewritesResponse(
            rewrites: [
                RewriteOption(id: UUID().uuidString, text: "Test rewrite", explanation: "Test explanation")
            ],
            remainingQuota: 4,
            isPremiumUser: false,
            historyId: UUID().uuidString
        )

        return Response(request: URLRequest(url: URL(string: "http://test")!), data: try JSONEncoder().encode(mockResponse))
    }
}

final class MockAuthClient: SupabaseAuthClient {
    override func user() async throws -> User {
        User(id: UUID().uuidString, email: "test@example.com")
    }

    override func session() async throws -> Session {
        Session(accessToken: "test-token", refreshToken: "refresh", tokenType: "bearer", expiresAt: Date().timeIntervalSince1970 + 3600)
    }
}

final class MockQueryBuilder: SupabaseQueryBuilder {
    override func select(_ columns: String, head: Bool, count: CountQuery?) -> SupabaseQueryBuilder {
        self
    }

    override func eq(_ column: String, value: Any) -> SupabaseQueryBuilder {
        self
    }

    override func `in`(_ column: String, value: [Any]) -> SupabaseQueryBuilder {
        self
    }

    override func single() async throws -> (data: Data, count: Int?) {
        (Data(), nil)
    }
}
