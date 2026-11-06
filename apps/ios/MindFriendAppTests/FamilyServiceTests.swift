import XCTest
import Supabase
@testable import MindFriendApp

@MainActor
final class FamilyServiceTests: XCTestCase {
    func testBirthDateEncodingPreservesSelectedLocalCalendarDate() throws {
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2010-07-01T02:30:00Z"))
        XCTAssertEqual(FamilyService.birthDateString(instant, timeZone: try XCTUnwrap(TimeZone(identifier: "America/New_York"))), "2010-06-30")
        XCTAssertEqual(FamilyService.birthDateString(instant, timeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))), "2010-07-01")
        XCTAssertFalse(FamilyService.birthDateString(instant).contains("T"))
    }

    private func service() -> FamilyService {
        FamilyFixtureURLProtocol.fixture.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FamilyFixtureURLProtocol.self]
        let client = SupabaseClient(supabaseURL: URL(string: "https://family-fixture.invalid")!, supabaseKey: "synthetic-anon",
            options: .init(auth: .init(storage: FamilyFixtureStorage(), autoRefreshToken: false),
                           global: .init(session: URLSession(configuration: config))))
        return FamilyService(supabase: client, currentUserId: { FamilyFixtureHTTP.owner })
    }

    func testMemberGroupBecomesSelectedBeforeDependentQueries() async throws {
        let service = service()
        let family = try await service.fetchFamilyGroup()
        XCTAssertEqual(family?.id, FamilyFixtureHTTP.family.uuidString.lowercased())
        XCTAssertEqual(service.familyGroup, family)
        _ = try await service.fetchFamilyMembers()
        _ = try await service.fetchChallenges()
        let requests = FamilyFixtureURLProtocol.fixture.requests
        let group = try XCTUnwrap(requests.first { $0.url?.lastPathComponent == "family_groups" })
        let groupQuery = URLComponents(url: group.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(groupQuery.first { $0.name == "id" }?.value?.lowercased(), "eq.\(FamilyFixtureHTTP.family.uuidString.lowercased())")
        XCTAssertNil(groupQuery.first { $0.name == "admin_user_id" })
        let dependent = requests.filter { request in
            (URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).contains { $0.name == "family_id" }
        }
        XCTAssertEqual(dependent.count, 2, "Member/challenge queries must use the resolved group")
    }

    func testNoMembershipOrAdminGroupClearsPreviousSelection() async throws {
        let service = service()
        _ = try await service.fetchFamilyGroup()
        FamilyFixtureURLProtocol.fixture.setHasFamily(false)
        let missing = try await service.fetchFamilyGroup()
        XCTAssertNil(missing)
        XCTAssertNil(service.familyGroup)
        let requestsBefore = FamilyFixtureURLProtocol.fixture.requests.count
        let members = try await service.fetchFamilyMembers()
        XCTAssertTrue(members.isEmpty)
        XCTAssertEqual(FamilyFixtureURLProtocol.fixture.requests.count, requestsBefore)
    }
}

private struct FamilyFixtureStorage: AuthLocalStorage {
    func store(key: String, value: Data) throws {}
    func retrieve(key: String) throws -> Data? { nil }
    func remove(key: String) throws {}
}
private final class FamilyFixtureURLProtocol: URLProtocol {
    static let fixture = FamilyFixtureHTTP()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "family-fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let data = Self.fixture.respond(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
private final class FamilyFixtureHTTP: @unchecked Sendable {
    static let owner = UUID(uuidString: "AAAAAAAA-1111-4111-8111-111111111111")!
    static let family = UUID(uuidString: "BBBBBBBB-2222-4222-8222-222222222222")!
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private var hasFamily = true
    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return recorded }
    func reset() { lock.lock(); defer { lock.unlock() }; recorded = []; hasFamily = true }
    func setHasFamily(_ value: Bool) { lock.lock(); defer { lock.unlock() }; hasFamily = value }
    func respond(_ request: URLRequest) -> Data {
        lock.lock(); defer { lock.unlock() }
        recorded.append(request)
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let body: [[String: Any]]
        if !hasFamily { body = [] }
        else if request.url!.lastPathComponent == "family_members", query.contains(where: { $0.name == "select" && $0.value == "family_id" }) {
            body = [["family_id": Self.family.uuidString.lowercased()]]
        } else if request.url!.lastPathComponent == "family_groups" {
            body = [["id": Self.family.uuidString.lowercased(), "name": "Synthetic Family", "admin_user_id": UUID().uuidString.lowercased(),
                     "created_at": "2026-01-01T00:00:00Z", "updated_at": "2026-01-01T00:00:00Z"]]
        } else { body = [] }
        return try! JSONSerialization.data(withJSONObject: body)
    }
}
