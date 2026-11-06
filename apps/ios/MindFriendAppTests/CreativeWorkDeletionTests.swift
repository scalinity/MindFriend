import XCTest
import Supabase
@testable import MindFriendApp

@MainActor
final class CreativeWorkDeletionTests: XCTestCase {
    private let owner = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
    private let workID = UUID(uuidString: "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC")!

    private func service(_ mode: CreativeDeleteHTTP.Mode = .success) async throws -> CreativeExpressionService {
        CreativeDeleteURLProtocol.fixture.prepare(owner: owner, workID: workID, mode: mode)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CreativeDeleteURLProtocol.self]
        let client = SupabaseClient(
            supabaseURL: URL(string: "https://creative-delete.invalid")!, supabaseKey: "synthetic-anon",
            options: .init(auth: .init(storage: CreativeDeleteAuthStorage(), autoRefreshToken: false),
                           global: .init(session: URLSession(configuration: configuration)))
        )
        let payload = Data("{\"exp\":4102444800}".utf8).base64EncodedString()
            .replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        _ = try await client.auth.setSession(accessToken: "eyJhbGciOiJIUzI1NiJ9.\(payload).synthetic", refreshToken: "synthetic-refresh")
        return CreativeExpressionService(deletionClient: client)
    }

    private func cachedWork(path: String = "stale-cache.png") -> CreativeWork {
        CreativeWork(id: workID.uuidString, userId: owner.uuidString, workType: .voiceJournal,
                     title: nil, description: nil, storagePath: path, generationPrompt: nil, artStyle: nil,
                     durationSeconds: nil, transcription: nil, transcriptionStatus: nil, moodScore: nil,
                     moodTags: nil, isFavorite: false, isSharedToCircle: false, createdAt: Date(), updatedAt: Date())
    }

    func testUncachedWorkUsesAuthoritativeOwnedPathBeforeDeletingRow() async throws {
        let service = try await service()
        XCTAssertTrue(service.creativeWorks.isEmpty)
        try await service.deleteWork(id: workID.uuidString)
        XCTAssertEqual(CreativeDeleteURLProtocol.fixture.events, ["read-row", "remove-media", "check-media", "delete-row"])
        XCTAssertTrue(CreativeDeleteURLProtocol.fixture.validOwnershipFilters)
        XCTAssertEqual(CreativeDeleteURLProtocol.fixture.removedPaths, ["\(owner.uuidString)/voice-journals/recording.m4a"])
    }

    func testStaleCacheCannotChooseTheObjectToDelete() async throws {
        let service = try await service()
        service.creativeWorks = [cachedWork()]
        try await service.deleteWork(id: workID.uuidString)
        XCTAssertEqual(CreativeDeleteURLProtocol.fixture.removedPaths, ["\(owner.uuidString)/voice-journals/recording.m4a"])
        XCTAssertTrue(service.creativeWorks.isEmpty)
    }

    func testStorageFailureRetainsDatabaseAndCachedWork() async throws {
        let service = try await service(.storageFailure)
        service.creativeWorks = [cachedWork()]
        do { try await service.deleteWork(id: workID.uuidString); XCTFail("Storage failure must fail deletion") }
        catch { XCTAssertEqual(service.creativeWorks.count, 1) }
        XCTAssertFalse(CreativeDeleteURLProtocol.fixture.events.contains("delete-row"))
    }

    func testSuccessfulStorageResponseWithRemainingObjectCannotDeleteRow() async throws {
        let service = try await service(.storageNoOp)
        do { try await service.deleteWork(id: workID.uuidString); XCTFail("Remaining media must fail deletion") }
        catch { XCTAssertFalse(CreativeDeleteURLProtocol.fixture.events.contains("delete-row")) }
    }

    func testReadFailureCannotDeleteMedia() async throws {
        let service = try await service(.readFailure)
        do { try await service.deleteWork(id: workID.uuidString); XCTFail("Missing authoritative row must fail") }
        catch { XCTAssertEqual(CreativeDeleteURLProtocol.fixture.events, ["read-row"]) }
    }

    func testDatabaseFailureCanRetryAlreadyRemovedMedia() async throws {
        let service = try await service(.databaseFailureOnce)
        service.creativeWorks = [cachedWork()]
        do { try await service.deleteWork(id: workID.uuidString); XCTFail("Database failure must fail deletion") }
        catch { XCTAssertEqual(service.creativeWorks.count, 1) }
        try await service.deleteWork(id: workID.uuidString)
        XCTAssertTrue(service.creativeWorks.isEmpty)
        XCTAssertEqual(CreativeDeleteURLProtocol.fixture.events.filter { $0 == "delete-row" }.count, 2)
    }

    func testWorkWithoutMediaDeletesOnlyOwnedRow() async throws {
        let service = try await service(.noMedia)
        try await service.deleteWork(id: workID.uuidString)
        XCTAssertEqual(CreativeDeleteURLProtocol.fixture.events, ["read-row", "delete-row"])
        XCTAssertTrue(CreativeDeleteURLProtocol.fixture.validOwnershipFilters)
    }
}

private final class CreativeDeleteAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func store(key: String, value: Data) { lock.lock(); defer { lock.unlock() }; values[key] = value }
    func retrieve(key: String) -> Data? { lock.lock(); defer { lock.unlock() }; return values[key] }
    func remove(key: String) { lock.lock(); defer { lock.unlock() }; values[key] = nil }
}

private final class CreativeDeleteURLProtocol: URLProtocol {
    static let fixture = CreativeDeleteHTTP()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, body) = Self.fixture.respond(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class CreativeDeleteHTTP: @unchecked Sendable {
    enum Mode { case success, storageFailure, storageNoOp, readFailure, databaseFailureOnce, noMedia }
    private let lock = NSLock()
    private var owner = UUID(), workID = UUID()
    private var mode: Mode = .success
    private var recorded: [String] = [], paths: [String] = []
    private var validFilters = true, objectExists = true
    var events: [String] { lock.lock(); defer { lock.unlock() }; return recorded }
    var removedPaths: [String] { lock.lock(); defer { lock.unlock() }; return paths }
    var validOwnershipFilters: Bool { lock.lock(); defer { lock.unlock() }; return validFilters }

    func prepare(owner: UUID, workID: UUID, mode: Mode) {
        lock.lock(); defer { lock.unlock() }
        self.owner = owner; self.workID = workID; self.mode = mode
        recorded = []; paths = []; validFilters = true; objectExists = true
    }

    func respond(_ request: URLRequest) -> (Int, Data) {
        lock.lock(); defer { lock.unlock() }
        guard request.url?.host == "creative-delete.invalid" else { return (500, Data()) }
        let url = request.url!, method = request.httpMethod ?? "GET"
        var status = 200
        var body: Any = [:]
        if url.path == "/auth/v1/user" {
            body = ["id": owner.uuidString, "aud": "authenticated", "app_metadata": [:], "user_metadata": [:],
                    "created_at": "2026-01-01T00:00:00Z"] as [String: Any]
        } else if url.path == "/rest/v1/creative_works" {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            validFilters = validFilters && query.contains { $0.name == "id" && $0.value?.lowercased() == "eq.\(workID.uuidString.lowercased())" }
                && query.contains { $0.name == "user_id" && $0.value?.lowercased() == "eq.\(owner.uuidString.lowercased())" }
            if method == "GET" {
                recorded.append("read-row")
                if mode == .readFailure { status = 500 }
                let path: Any = mode == .noMedia ? NSNull() : "\(owner.uuidString)/voice-journals/recording.m4a"
                body = ["storage_path": path]
            } else if method == "DELETE" {
                recorded.append("delete-row")
                if mode == .databaseFailureOnce { status = 500; mode = .success }
                body = []
            } else { status = 500 }
            if status != 200 { body = ["code": "synthetic", "message": "Synthetic database failure", "details": "", "hint": ""] }
        } else if method == "DELETE" && url.path == "/storage/v1/object/creative-works" {
            recorded.append("remove-media")
            var data = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    data.append(contentsOf: buffer.prefix(count))
                }
            }
            paths = ((try? JSONSerialization.jsonObject(with: data)) as? [String: [String]])?["prefixes"] ?? []
            if mode == .storageFailure { status = 403; body = ["statusCode": "403", "error": "Denied", "message": "Synthetic denial"] }
            else { if mode != .storageNoOp { objectExists = false }; body = [] }
        } else if method == "HEAD" && url.path.hasPrefix("/storage/v1/object/creative-works/") {
            recorded.append("check-media"); status = objectExists ? 200 : 404
            body = ["statusCode": "\(status)", "error": "NotFound", "message": "Synthetic object state"]
        } else { status = 500 }
        return (status, (try? JSONSerialization.data(withJSONObject: body)) ?? Data())
    }
}
