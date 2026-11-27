import XCTest
import Supabase
@testable import MindFriendApp

/// The PATCH bodies must name real `therapist_assignments` columns: PostgREST rejects an
/// unknown key (PGRST204), and clients may only update status, completed_at and client_notes.
@MainActor
final class TherapyIntegrationServiceTests: XCTestCase {
    private let assignmentId = UUID(uuidString: "66666666-6666-4666-8666-666666666666")!

    private func service() -> TherapyIntegrationService {
        TherapyURLProtocol.requests = []
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TherapyURLProtocol.self]
        let client = SupabaseClient(supabaseURL: URL(string: "https://therapy-fixture.invalid")!, supabaseKey: "synthetic-anon",
            options: .init(auth: .init(storage: TherapyFixtureStorage(), autoRefreshToken: false),
                           global: .init(session: URLSession(configuration: config))))
        return TherapyIntegrationService(supabase: client)
    }

    private func patchBody() throws -> [String: Any] {
        let patch = try XCTUnwrap(TherapyURLProtocol.requests.last)
        XCTAssertEqual(patch.httpMethod, "PATCH")
        XCTAssertEqual(patch.url?.lastPathComponent, "therapist_assignments")
        let query = URLComponents(url: try XCTUnwrap(patch.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(query.first { $0.name == "id" }?.value?.lowercased(), "eq.\(assignmentId.uuidString.lowercased())")
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(patch.httpBody)) as? [String: Any])
    }

    func testCompleteAssignmentSendsSnakeCaseColumns() async throws {
        let service = service()

        try await service.completeAssignment(id: assignmentId, notes: "Felt calmer")
        var body = try patchBody()
        XCTAssertEqual(Set(body.keys), ["status", "completed_at", "client_notes"])
        XCTAssertEqual(body["status"] as? String, "completed")
        XCTAssertEqual(body["client_notes"] as? String, "Felt calmer")
        XCTAssertNotNil(ISO8601DateFormatter().date(from: try XCTUnwrap(body["completed_at"] as? String)))

        try await service.completeAssignment(id: assignmentId, notes: nil)
        body = try patchBody()
        XCTAssertEqual(Set(body.keys), ["status", "completed_at"])
    }

    func testSkipAssignmentSendsStatusOnly() async throws {
        try await service().skipAssignment(id: assignmentId)
        XCTAssertEqual(try patchBody() as? [String: String], ["status": "skipped"])
    }
}

private struct TherapyFixtureStorage: AuthLocalStorage {
    func store(key: String, value: Data) throws {}
    func retrieve(key: String) throws -> Data? { nil }
    func remove(key: String) throws {}
}
private final class TherapyURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var recorded: [URLRequest] = []
    static var requests: [URLRequest] {
        get { lock.lock(); defer { lock.unlock() }; return recorded }
        set { lock.lock(); defer { lock.unlock() }; recorded = newValue }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var captured = request
        if captured.httpBody == nil, let stream = captured.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            captured.httpBody = data
        }
        Self.lock.lock(); Self.recorded.append(captured); Self.lock.unlock()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("[]".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
