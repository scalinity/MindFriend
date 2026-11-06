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

    private func togetherService() async throws -> FamilyService {
        TogetherURLProtocol.fixture.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TogetherURLProtocol.self]
        let client = SupabaseClient(supabaseURL: URL(string: "https://together-fixture.invalid")!, supabaseKey: "synthetic-anon",
            options: .init(auth: .init(storage: FamilyFixtureStorage(), autoRefreshToken: false),
                           global: .init(session: URLSession(configuration: config))))
        let service = FamilyService(supabase: client, currentUserId: { TogetherHTTP.owner })
        _ = try await service.fetchFamilyGroup()
        return service
    }

    func testStartTogetherReturnsActualSavedSession() async throws {
        let service = try await togetherService()
        let session = try await service.startTogetherSession(templateId: "template", title: "Requested title")
        XCTAssertEqual(session.status, .pending)
        XCTAssertEqual(session.title, "Saved family activity")
        XCTAssertEqual(session.minimumParticipants, 2)
        XCTAssertEqual(session.durationSeconds, 240)
        XCTAssertNil(session.startedAt)
    }

    func testTogetherJoinUpdatesOnlyCurrentMembersParticipant() async throws {
        let service = try await togetherService()
        try await service.joinTogetherSession(sessionId: TogetherHTTP.sessionId)
        let update = try XCTUnwrap(TogetherURLProtocol.fixture.requests.first { $0.httpMethod == "PATCH" && $0.url?.lastPathComponent == "together_participants" })
        let query = URLComponents(url: update.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(query.first { $0.name == "id" }?.value, "eq.\(TogetherHTTP.ownParticipantId)")
        XCTAssertEqual(query.first { $0.name == "member_id" }?.value, "eq.\(TogetherHTTP.ownMemberId)")
        XCTAssertEqual(service.currentSessionParticipants.first { $0.id == TogetherHTTP.ownParticipantId }?.status, .joined)
    }

    func testTogetherBeginsAfterMinimumParticipationAndConfirmsCompletion() async throws {
        let service = try await togetherService()
        do {
            try await service.beginTogetherSession(sessionId: TogetherHTTP.sessionId)
            XCTFail("Activity began before the minimum joined")
        } catch FamilyServiceError.notEnoughParticipants { }
        try await service.joinTogetherSession(sessionId: TogetherHTTP.sessionId)
        try await service.beginTogetherSession(sessionId: TogetherHTTP.sessionId)
        let active = try await service.fetchTogetherSession(sessionId: TogetherHTTP.sessionId)
        XCTAssertEqual(active.status, .inProgress)
        try await service.completeTogetherSession(sessionId: TogetherHTTP.sessionId)
        let completed = try await service.fetchTogetherSession(sessionId: TogetherHTTP.sessionId)
        XCTAssertEqual(completed.status, .completed)
        do {
            try await service.completeTogetherSession(sessionId: TogetherHTTP.sessionId)
            XCTFail("A zero-row update must not report completion")
        } catch FamilyServiceError.sessionUnavailable { }
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

private final class TogetherURLProtocol: URLProtocol {
    static let fixture = TogetherHTTP()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let data = Self.fixture.respond(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
private final class TogetherHTTP: @unchecked Sendable {
    static let owner = UUID(uuidString: "AAAAAAAA-1111-4111-8111-111111111111")!
    static let familyId = "bbbbbbbb-2222-4222-8222-222222222222"
    static let sessionId = "cccccccc-3333-4333-8333-333333333333"
    static let ownMemberId = "dddddddd-4444-4444-8444-444444444444"
    static let ownParticipantId = "eeeeeeee-5555-4555-8555-555555555555"
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private var ownJoined = false
    private var status = "pending"
    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return recorded }
    func reset() { lock.lock(); defer { lock.unlock() }; recorded=[];ownJoined=false;status="pending" }
    func respond(_ original: URLRequest) -> Data {
        lock.lock(); defer { lock.unlock() }
        var request = original
        if request.httpBody == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data=Data();var buffer=[UInt8](repeating:0,count:1024)
            while stream.hasBytesAvailable { let count=stream.read(&buffer,maxLength:buffer.count);if count<=0 { break };data.append(buffer,count:count) }
            request.httpBody=data
        }
        recorded.append(request)
        let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ key: String) -> String? { query.first { $0.name == key }?.value }
        let session: [String: Any] = ["id":Self.sessionId,"family_id":Self.familyId,"title":"Saved family activity","status":status,"sync_mode":"realtime","minimum_participants":2,"duration_seconds":240,"created_by":Self.owner.uuidString.lowercased(),"created_at":"2026-01-01T00:00:00Z"]
        func participant(id: String, member: String, joined: Bool) -> [String: Any] {
            ["id":id,"session_id":Self.sessionId,"member_id":member,"status":joined ? "joined" : "invited","turn_completed":false,"created_at":"2026-01-01T00:00:00Z"]
        }
        let own = participant(id:Self.ownParticipantId,member:Self.ownMemberId,joined:ownJoined)
        let foreign = participant(id:"foreign-participant",member:"foreign-member",joined:true)
        let body: Any
        switch request.url!.lastPathComponent {
        case "family_groups": body=[["id":Self.familyId,"name":"Family","admin_user_id":Self.owner.uuidString,"created_at":"2026-01-01T00:00:00Z","updated_at":"2026-01-01T00:00:00Z"]]
        case "family_members": body=value("select")=="family_id" ? [["family_id":Self.familyId]] : [["id":Self.ownMemberId]]
        case "start-together-session": body=["success":true,"session":["id":Self.sessionId,"familyId":Self.familyId,"title":"Saved family activity","status":"pending"]]
        case "together_participants":
            if request.httpMethod=="PATCH" {
                ownJoined=true
                body=[participant(id:Self.ownParticipantId,member:Self.ownMemberId,joined:true)]
            } else { body=value("member_id")==nil ? [foreign,own] : [own] }
        case "together_sessions":
            if request.httpMethod=="PATCH" {
                if value("status")=="eq.\(status)",value("created_by")?.lowercased()=="eq.\(Self.owner.uuidString.lowercased())",
                   let update=try? JSONSerialization.jsonObject(with:request.httpBody ?? Data()) as? [String:Any],let next=update["status"] as? String {
                    status=next;var updated=session;updated["status"]=next;body=[updated]
                } else { body=[] as [[String:Any]] }
            } else if request.value(forHTTPHeaderField:"Accept")?.contains("vnd.pgrst.object")==true { body=session }
            else { body=[session] }
        default: body=[] as [[String:Any]]
        }
        return try! JSONSerialization.data(withJSONObject:body)
    }
}
