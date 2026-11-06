import XCTest
import Supabase
@testable import MindFriendApp

@MainActor
final class MentorshipServiceTests: XCTestCase {
    private let owner = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let profileID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

    private var profileJSON: String {
        """
        {"id":"\(profileID)","user_id":"\(owner)","is_mentor_available":false,"expertise_areas":[],"seeking_areas":["stress"],"bio":null,"availability_hours_week":2,"languages":["en"],"timezone":"America/New_York","verified":true,"created_at":"2026-11-06T12:00:00Z","updated_at":"2026-11-06T12:00:00Z"}
        """
    }

    private func service(ownerProvider: (@MainActor () -> UUID?)? = nil) -> MentorshipDataService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MentorshipFixtureURLProtocol.self]
        let client = SupabaseClient(supabaseURL: URL(string: "https://mentorship-fixture.invalid")!, supabaseKey: "synthetic-anon",
            options: .init(auth: .init(storage: MentorshipFixtureStorage(), autoRefreshToken: false),
                           global: .init(session: URLSession(configuration: configuration))))
        return MentorshipDataService(supabase: client, userIdProvider: ownerProvider ?? { self.owner })
    }

    func testSignedOutServiceNeverUsesRandomPrincipalOrSendsRequest() async {
        MentorshipFixtureURLProtocol.fixture.prepare([])
        do { _ = try await service(ownerProvider: { nil }).fetchProfile(); XCTFail("Sign-in required") }
        catch { XCTAssertTrue(error is MentorshipError) }
        XCTAssertTrue(MentorshipFixtureURLProtocol.fixture.requests.isEmpty)
    }

    func testAccountChangeRejectsLateProfileResponse() async throws {
        let requested = expectation(description: "Owner A request started")
        MentorshipFixtureURLProtocol.fixture.prepare([(200, "[\(profileJSON)]")], hold: true, onRequest: { requested.fulfill() })
        var currentOwner: UUID? = owner
        let data = service(ownerProvider: { currentOwner })
        let pending = Task { try await data.fetchProfile() }
        await fulfillment(of: [requested], timeout: 2)
        currentOwner = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        data.resetForAccountChange()
        MentorshipFixtureURLProtocol.fixture.release()
        do { _ = try await pending.value; XCTFail("An old account result cannot reach UI state") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(MentorshipFixtureURLProtocol.fixture.requests.count, 1)
    }

    func testDiscoveryIdentityComesFromMentorIdentifier() throws {
        let json = #"{"success":true,"matches":[{"mentor_id":"22222222-2222-4222-8222-222222222222","mentor_name":"Mentor","mentor_alias":"","expertise_areas":["stress"],"availability_hours_week":2,"languages":["en"],"timezone":"America/New_York","compatibility_score":87.5,"match_reasons":["Shared expertise"],"is_verified":true}],"count":1,"timestamp":"2026-11-06T12:00:00Z"}"#
        let response = try JSONDecoder().decode(FindMentorMatchesResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.matches.first?.id, profileID)
        XCTAssertEqual(response.matches.first?.id, response.matches.first?.mentorId)
    }

    private var messageJSON: String {
        #"{"id":"44444444-4444-4444-8444-444444444444","match_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","sender_id":"11111111-1111-4111-8111-111111111111","content":"Saved message","created_at":"2026-11-06T12:00:00Z","read_at":null,"flagged":false}"#
    }

    func testNewestMessagePageIsDisplayedChronologicallyAndPollingPreservesHistory() async throws {
        func page(_ range: ClosedRange<Int>) throws -> String {
            let rows: [[String: Any]] = range.reversed().map { index in
                ["id": String(format: "44444444-4444-4444-8444-%012d", index),
                 "match_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", "sender_id": owner.uuidString,
                 "content": "Message \(index)", "created_at": ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: Double(index))),
                 "flagged": false, "read_at": NSNull()]
            }
            return String(decoding: try JSONSerialization.data(withJSONObject: rows), as: UTF8.self)
        }
        MentorshipFixtureURLProtocol.fixture.prepare([(200, try page(51...100)), (200, try page(1...50)), (200, try page(101...150)), (200, try page(101...150))])
        let match = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
        let messaging = MentorshipMessagingService(dataService: service())
        await messaging.loadMessages(matchId: match)
        XCTAssertEqual(messaging.messages.first?.content, "Message 51")
        XCTAssertEqual(messaging.latestMessage?.content, "Message 100")
        await messaging.loadMoreMessages(matchId: match, offset: 50)
        try await messaging.refreshMessages(matchId: match)
        try await messaging.refreshMessages(matchId: match)
        XCTAssertEqual(messaging.messages.count, 150)
        XCTAssertEqual(messaging.oldestMessage?.content, "Message 1")
        XCTAssertEqual(messaging.latestMessage?.content, "Message 150")
        let url = try XCTUnwrap(MentorshipFixtureURLProtocol.fixture.requests.first?.url)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(query.first { $0.name == "order" }?.value, "created_at.desc,id.desc")
        XCTAssertEqual(query.first { $0.name == "limit" }?.value, "50")
    }

    func testMessageSendUsesWritableFieldsAndReturnsDatabaseRow() async throws {
        MentorshipFixtureURLProtocol.fixture.prepare([(201, "[\(messageJSON)]")])
        let saved = try await service().sendMessage(matchId: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!, content: "Original draft")
        XCTAssertEqual(saved.content, "Saved message")
        XCTAssertFalse(saved.isRead ?? true)
        let request = try XCTUnwrap(MentorshipFixtureURLProtocol.fixture.requests.first)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["match_id", "sender_id", "content"])
    }

    func testFailedMessageSendExposesErrorWithoutAddingLocalMessage() async {
        MentorshipFixtureURLProtocol.fixture.prepare([(400, "{\"message\":\"Synthetic failure\"}")])
        let messages = MentorshipMessagingService(dataService: service())
        do { try await messages.sendMessage(matchId: UUID(), content: "Retained draft"); XCTFail("Must fail") }
        catch { }
        XCTAssertNotNil(messages.error)
        XCTAssertFalse(messages.isSending)
        XCTAssertTrue(messages.messages.isEmpty)
    }

    func testReadAndFlagStateDecodeFromPersistedColumns() throws {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let json = messageJSON.replacingOccurrences(of: "\"read_at\":null", with: "\"read_at\":\"2026-11-06T12:01:00Z\"")
            .replacingOccurrences(of: "\"flagged\":false", with: "\"flagged\":true")
        let message = try decoder.decode(MentorshipMessage.self, from: Data(json.utf8))
        XCTAssertEqual(message.isRead, true)
        XCTAssertTrue(message.isSafetyFlagged)
    }

    private var matchJSON: String {
        #"{"id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","mentor_id":"22222222-2222-4222-8222-222222222222","mentee_id":"11111111-1111-4111-8111-111111111111","status":"active","created_at":"2026-11-06T12:00:00Z","updated_at":"2026-11-06T12:00:00Z"}"#
    }

    private var reportJSON: String {
        #"{"id":"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb","match_id":"aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa","reporter_id":"11111111-1111-4111-8111-111111111111","reported_id":"22222222-2222-4222-8222-222222222222","reason":"boundary_violation","status":"pending","description":"Keep this detail","message_ids":[],"created_at":"2026-11-06T12:00:00Z","resolved_at":null,"resolved_by":null}"#
    }

    func testSafetyReportResolvesOtherParticipantAndUsesDatabaseReason() async throws {
        MentorshipFixtureURLProtocol.fixture.prepare([(200, "[\(matchJSON)]"),
            (200, "\"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb\""), (200, "[\(reportJSON)]")])
        let safety = MentorshipSafetyService(dataService: service())
        try await safety.reportMentorship(matchId: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!,
            reason: "Boundary violations", description: "Keep this detail")
        XCTAssertEqual(safety.reports.count, 1)
        XCTAssertEqual(safety.reports.first?.reportedUserId, profileID)
        let requests = MentorshipFixtureURLProtocol.fixture.requests
        XCTAssertEqual(requests.map { $0.url.lastPathComponent }, ["mentorship_matches", "report_mentorship_issue", "mentorship_reports"])
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[1].body) as? [String: String])
        XCTAssertEqual(body["p_reported_id"], profileID.uuidString)
        XCTAssertEqual(body["p_reason"], "boundary_violation")
        XCTAssertEqual(body["p_description"], "Keep this detail")
    }

    func testReportUnderInvestigationDecodesDatabaseResolutionColumns() throws {
        let json = reportJSON.replacingOccurrences(of: "\"status\":\"pending\"", with: "\"status\":\"investigating\"")
            .replacingOccurrences(of: "\"resolved_at\":null", with: "\"resolved_at\":\"2026-11-06T13:00:00Z\"")
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let report = try decoder.decode(MentorshipReport.self, from: Data(json.utf8))
        XCTAssertEqual(report.status, .investigating)
        XCTAssertNotNil(report.reviewedAt)
    }

    func testSafetyReportFailureIsThrownAndNoLocalSuccessIsPublished() async {
        MentorshipFixtureURLProtocol.fixture.prepare([(200, "[\(matchJSON)]"), (400, "{\"message\":\"Synthetic failure\"}")])
        let safety = MentorshipSafetyService(dataService: service())
        do {
            try await safety.reportMentorship(matchId: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!,
                reason: "Boundary violations", description: "Retained detail")
            XCTFail("A failed report must remain in the form")
        } catch { }
        XCTAssertTrue(safety.reports.isEmpty)
        XCTAssertNotNil(safety.error)
        XCTAssertFalse(safety.isLoading)
    }

    func testSafetyReportRejectsUnrelatedReportedUserBeforeWrite() async {
        MentorshipFixtureURLProtocol.fixture.prepare([(200, "[\(matchJSON)]")])
        do {
            _ = try await service().createReport(matchId: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!,
                reportedUserId: UUID(), reason: "other")
            XCTFail("Only the other participant can be reported")
        } catch { }
        XCTAssertEqual(MentorshipFixtureURLProtocol.fixture.requests.count, 1)
    }

    func testEndMentorshipWaitsForConfirmedDatabaseResult() async throws {
        MentorshipFixtureURLProtocol.fixture.prepare([(200, "false"), (200, "true")])
        let data = service(); let match = UUID()
        do { try await data.endMentorship(matchId: match, reason: "Finished"); XCTFail("False is not persistence") }
        catch { }
        try await data.endMentorship(matchId: match, reason: "Finished")
        XCTAssertEqual(MentorshipFixtureURLProtocol.fixture.requests.map { $0.url.lastPathComponent }, ["end_mentorship", "end_mentorship"])
    }

    func testMessageMutationsUseValidatedDatabaseFunctions() async throws {
        MentorshipFixtureURLProtocol.fixture.prepare([(200, "true"), (200, "true"), (200, "true")])
        let data = service(); let match = UUID(); let message = UUID()
        try await data.markMessagesAsRead(matchId: match)
        try await data.flagMessage(messageId: message, reason: "Synthetic concern")
        try await data.deleteMessage(messageId: message)
        XCTAssertEqual(MentorshipFixtureURLProtocol.fixture.requests.map { $0.url.lastPathComponent },
                       ["mark_messages_read", "flag_mentorship_message", "delete_mentorship_message"])
    }

    func testExistingProfileDecodesDatabaseVerificationWithoutCreatingAnother() async throws {
        MentorshipFixtureURLProtocol.fixture.prepare([(200, "[\(profileJSON)]")])
        let profile = try await service().fetchOrCreateProfile()
        XCTAssertEqual(profile.id, profileID)
        XCTAssertTrue(profile.isVerified)
        XCTAssertEqual(MentorshipFixtureURLProtocol.fixture.requests.map(\.method), ["GET"])
    }

    func testProfileReadFailureNeverBecomesCreate() async {
        MentorshipFixtureURLProtocol.fixture.prepare([(400, "{\"message\":\"synthetic read failure\",\"code\":\"fixture\"}")])
        do { _ = try await service().fetchOrCreateProfile(); XCTFail("A failed read must remain a failure") }
        catch { }
        XCTAssertEqual(MentorshipFixtureURLProtocol.fixture.requests.map(\.method), ["GET"])
    }

    func testEmptyProfileReadCreatesOnlyWritableFieldsAndReturnsSavedRow() async throws {
        MentorshipFixtureURLProtocol.fixture.prepare([(200, "[]"), (201, "[\(profileJSON)]")])
        let saved = try await service().fetchOrCreateProfile()
        XCTAssertEqual(saved.id, profileID)
        let requests = MentorshipFixtureURLProtocol.fixture.requests
        XCTAssertEqual(requests.map(\.method), ["GET", "POST"])
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requests[1].body) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["user_id", "timezone"])
        XCTAssertEqual(UUID(uuidString: try XCTUnwrap(body["user_id"] as? String)), owner)
    }

    func testZeroRowProfileUpdateCannotReportSuccess() async {
        MentorshipFixtureURLProtocol.fixture.prepare([(200, "[]")])
        do { _ = try await service().updateProfile(bio: "Synthetic bio"); XCTFail("Zero rows is not a saved profile") }
        catch { }
    }
}

private struct MentorshipFixtureStorage: AuthLocalStorage {
    func store(key: String, value: Data) throws { }
    func retrieve(key: String) throws -> Data? { nil }
    func remove(key: String) throws { }
}

private final class MentorshipFixtureURLProtocol: URLProtocol {
    static let fixture = MentorshipHTTPFixture()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "mentorship-fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, body) = Self.fixture.respond(to: request)
        Self.fixture.waitIfHeld()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status,
            httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

private final class MentorshipHTTPFixture: @unchecked Sendable {
    struct Request {
        let method: String
        let url: URL
        let body: Data
    }
    private let lock = NSLock()
    private var responses: [(Int, String)] = []
    private var recorded: [Request] = []
    private var hold = false
    private var gate = DispatchSemaphore(value: 0)
    private var onRequest: (() -> Void)?
    var requests: [Request] { lock.lock(); defer { lock.unlock() }; return recorded }
    func prepare(_ responses: [(Int, String)], hold: Bool = false, onRequest: (() -> Void)? = nil) {
        lock.lock(); defer { lock.unlock() }
        self.responses = responses; recorded = []; self.hold = hold
        self.onRequest = onRequest; gate = DispatchSemaphore(value: 0)
    }
    func waitIfHeld() {
        lock.lock(); let held = hold; let semaphore = gate; lock.unlock()
        if held { _ = semaphore.wait(timeout: .now() + 3) }
    }
    func release() { lock.lock(); let semaphore = gate; lock.unlock(); semaphore.signal() }
    func respond(to request: URLRequest) -> (Int, String) {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count <= 0 { break }
                body.append(contentsOf: bytes.prefix(count))
            }
        }
        lock.lock(); defer { lock.unlock() }
        recorded.append(Request(method: request.httpMethod ?? "GET", url: request.url!, body: body))
        onRequest?()
        return responses.isEmpty ? (400, "{\"message\":\"Unexpected fixture request\"}") : responses.removeFirst()
    }
}
