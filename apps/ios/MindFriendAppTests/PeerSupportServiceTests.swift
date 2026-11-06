import XCTest
import Supabase
@testable import MindFriendApp

@MainActor
final class PeerSupportServiceTests: XCTestCase {
    private func service(userId: UUID = PeerHTTP.seeker, status: String = "active") -> PeerSupportService {
        PeerURLProtocol.fixture.reset(status: status)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PeerURLProtocol.self]
        let client = SupabaseClient(supabaseURL: URL(string: "https://peer-fixture.invalid")!, supabaseKey: "synthetic-anon",
            options: .init(auth: .init(storage: PeerFixtureStorage(), autoRefreshToken: false), global: .init(session: URLSession(configuration: config))))
        return PeerSupportService(supabase: client, currentUserId: { userId })
    }

    func testConversationLoadsTimestampedMessagesAndSendsVerifiedSeekerRole() async throws {
        let service = service()
        let existing = try await service.fetchSessionMessages(sessionId: PeerHTTP.sessionId)
        XCTAssertEqual(existing.count, 1)
        XCTAssertEqual(existing.first?.senderType, .listener)
        let saved = try await service.sendMessage(sessionId: PeerHTTP.sessionId, content: "  I would like to talk  ")
        XCTAssertEqual(saved.content, "I would like to talk")
        XCTAssertEqual(saved.senderType, .seeker)
        let insert = try XCTUnwrap(PeerURLProtocol.fixture.requests.first { $0.httpMethod == "POST" })
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: insert.httpBody!) as? [String: String])
        XCTAssertEqual(body["sender_type"], "seeker")
        XCTAssertEqual(body["session_id"]?.lowercased(), PeerHTTP.sessionId.uuidString.lowercased())
    }

    func testEmptyAndClosedConversationMessagesNeverWrite() async throws {
        let service = service(status: "completed")
        do { _ = try await service.sendMessage(sessionId: PeerHTTP.sessionId, content: "   "); XCTFail("Empty message accepted") }
        catch PeerSupportError.emptyMessage { }
        do { _ = try await service.sendMessage(sessionId: PeerHTTP.sessionId, content: "Hello"); XCTFail("Closed conversation accepted a message") }
        catch PeerSupportError.sessionUnavailable { }
        XCTAssertFalse(PeerURLProtocol.fixture.requests.contains { $0.httpMethod == "POST" })
    }

    func testOnlyAssignedListenerCanBeginAndSendAsListener() async throws {
        let seeker = service(status: "matched")
        do { _ = try await seeker.startSession(sessionId: PeerHTTP.sessionId); XCTFail("Seeker started listener's match") }
        catch PeerSupportError.sessionUnavailable { }
        XCTAssertFalse(PeerURLProtocol.fixture.requests.contains { $0.httpMethod == "PATCH" })
        let listener = service(userId: PeerHTTP.listenerUser, status: "matched")
        let started = try await listener.startSession(sessionId: PeerHTTP.sessionId)
        XCTAssertEqual(started.status, .active)
        let message = try await listener.sendMessage(sessionId: PeerHTTP.sessionId, content: "I am listening")
        XCTAssertEqual(message.senderType, .listener)
        let ended = try await listener.endSession(sessionId: PeerHTTP.sessionId, moodAfter: nil)
        XCTAssertEqual(ended.status, .completed)
    }

    func testForeignParticipantAndUnconfirmedUpdateFail() async throws {
        let stranger = service(userId: UUID())
        do { _ = try await stranger.sendMessage(sessionId: PeerHTTP.sessionId, content: "Hello"); XCTFail("Unknown participant sent a message") }
        catch PeerSupportError.sessionNotFound { }
        XCTAssertFalse(PeerURLProtocol.fixture.requests.contains { $0.httpMethod == "POST" })
        let seeker = service()
        PeerURLProtocol.fixture.denyUpdates()
        do { _ = try await seeker.endSession(sessionId: PeerHTTP.sessionId, moodAfter: nil); XCTFail("Zero-row update reported completion") }
        catch PeerSupportError.sessionUnavailable { }
    }

    func testPendingRequestCancellationReturnsConfirmedState() async throws {
        let service = service(status: "pending")
        let saved = try await service.cancelSession(sessionId: PeerHTTP.sessionId)
        XCTAssertEqual(saved.status, .cancelled)
    }
}

private struct PeerFixtureStorage: AuthLocalStorage {
    func store(key: String, value: Data) throws {}
    func retrieve(key: String) throws -> Data? { nil }
    func remove(key: String) throws {}
}
private final class PeerURLProtocol: URLProtocol {
    static let fixture = PeerHTTP()
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
private final class PeerHTTP: @unchecked Sendable {
    static let seeker = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    static let listenerUser = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    static let listenerId = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
    static let sessionId = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private var status = "active"
    private var updateDenied = false
    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return recorded }
    func reset(status: String) { lock.lock(); defer { lock.unlock() }; self.status=status;recorded=[];updateDenied=false }
    func denyUpdates() { lock.lock(); defer { lock.unlock() }; updateDenied=true }
    func respond(_ original: URLRequest) -> Data {
        lock.lock(); defer { lock.unlock() }
        var request=original
        if request.httpBody == nil,let stream=request.httpBodyStream {
            stream.open();defer { stream.close() };var data=Data();var buffer=[UInt8](repeating:0,count:1024)
            while stream.hasBytesAvailable { let count=stream.read(&buffer,maxLength:buffer.count);if count<=0 { break };data.append(buffer,count:count) }
            request.httpBody=data
        }
        recorded.append(request)
        let query=URLComponents(url:request.url!,resolvingAgainstBaseURL:false)?.queryItems ?? []
        func value(_ key: String)->String? { query.first { $0.name==key }?.value }
        let session: [String:Any] = ["id":Self.sessionId.uuidString,"seeker_id":Self.seeker.uuidString,"listener_id":Self.listenerId.uuidString,"session_type":"quick","status":status,"requested_at":"2026-01-01T00:00:00Z","was_escalated":false,"is_anonymous":true,"created_at":"2026-01-01T00:00:00Z"]
        let body: Any
        switch request.url!.lastPathComponent {
        case "support_sessions":
            if request.httpMethod=="PATCH" {
                if !updateDenied,value("status")=="eq.\(status)",let update=try? JSONSerialization.jsonObject(with:request.httpBody ?? Data()) as? [String:Any],let next=update["status"] as? String {
                    status=next;var saved=session;saved["status"]=next;body=[saved]
                } else { body=[] as [[String:Any]] }
            } else { body=session }
        case "listeners":
            body=value("user_id")?.lowercased()=="eq.\(Self.listenerUser.uuidString.lowercased())" ? [["id":Self.listenerId.uuidString]] : []
        case "support_messages":
            var message: [String:Any] = ["id":"55555555-5555-4555-8555-555555555555","session_id":Self.sessionId.uuidString,"sender_type":"listener","content":"Welcome","is_flagged":false,"sent_at":"2026-01-01T00:00:01.123Z"]
            if request.httpMethod=="POST",let sent=try? JSONSerialization.jsonObject(with:request.httpBody ?? Data()) as? [String:Any] {
                message.merge(sent) { _,new in new };message["id"]=UUID().uuidString;body=message
            } else { body=[message] }
        default: body=[] as [[String:Any]]
        }
        return try! JSONSerialization.data(withJSONObject:body)
    }
}
