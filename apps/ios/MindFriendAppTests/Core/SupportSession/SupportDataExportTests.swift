import XCTest
#if canImport(MindFriendApp)
@testable import MindFriendApp
#endif

// Owner data export (AC-20 / E01) — engine tests.
//
// Every test drives the real `SupportDataExporter` through a real `URLSession` whose `protocolClasses` is a `URLProtocol`
// stub bound to a unique `.invalid` host: no network, no service, no account, no provider. The stub speaks the wire shape of
// `public.export_owner_data_page` (supabase/migrations/20261107040000_support_data_export.sql) page for page, including the
// 100-row keyset paging, so the request bytes the SDK-free client builds are the bytes asserted here.
// NOT covered here (and not claimed): the SQL itself (supabase/tests/support_data_export.sql), the SwiftUI view, the share
// sheet, and device data protection (asserted only where the platform exposes it).

// MARK: - Stub server

private struct StubReply {
    var status = 200
    var body = Data()
    var transportError: URLError?

    static func page(_ object: [String: Any], status: Int = 200) -> StubReply {
        StubReply(status: status, body: (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data())
    }
}

private struct RecordedRequest {
    let index: Int
    let request: URLRequest
    let body: [String: Any]
    var dataset: String { body["p_dataset"] as? String ?? "" }
    var after: String? { body["p_after"] as? String }
}

private final class ExportStubServer: @unchecked Sendable {
    typealias Hook = (_ recorded: RecordedRequest, _ reply: StubReply) -> StubReply

    let host = "export-stub-\(UUID().uuidString.lowercased()).invalid"
    let owner: UUID
    private let lock = NSLock()
    private var datasetRows: [String: [[String: Any]]] = [:]
    private var unavailable: Set<String> = []
    private var recordedRequests: [RecordedRequest] = []
    var hook: Hook?
    var pageSize = 100

    var ownerText: String { owner.uuidString.lowercased() }

    init(owner: UUID, rowsPerDataset: Int = 3, overrides: [String: Int] = [:]) {
        self.owner = owner
        for dataset in SupportExportDataset.allCases {
            let count = overrides[dataset.rawValue] ?? rowsPerDataset
            datasetRows[dataset.rawValue] = (0..<count).map { Self.row(dataset: dataset.rawValue, index: $0, owner: owner) }
        }
        ExportStubRegistry.register(host: host, server: self)
    }

    deinit { ExportStubRegistry.unregister(host: host) }

    static func key(_ index: Int) -> String { String(format: "00000000-0000-4000-8000-%012d", index) }

    static func row(dataset: String, index: Int, owner: UUID) -> [String: Any] {
        let key = Self.key(index)
        var row: [String: Any] = [
            "id": key, "export_key": key, "export_owner_id": owner.uuidString.lowercased(),
            "content": "SENTINEL-\(dataset)-\(index)",
        ]
        if dataset != "messages" && dataset != "support_context_receipt_sources" { row["user_id"] = owner.uuidString.lowercased() }
        return row
    }

    func markUnavailable(_ dataset: SupportExportDataset) { lock.withLock { _ = unavailable.insert(dataset.rawValue) } }
    func setRows(_ dataset: SupportExportDataset, _ rows: [[String: Any]]) { lock.withLock { datasetRows[dataset.rawValue] = rows } }
    var requests: [RecordedRequest] { lock.withLock { recordedRequests } }

    fileprivate func handle(_ request: URLRequest, body: Data) -> StubReply {
        let parsed = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        let (recorded, reply): (RecordedRequest, StubReply) = lock.withLock {
            let recorded = RecordedRequest(index: recordedRequests.count + 1, request: request, body: parsed)
            recordedRequests.append(recorded)
            return (recorded, defaultReply(dataset: recorded.dataset, after: recorded.after))
        }
        return hook?(recorded, reply) ?? reply
    }

    private func defaultReply(dataset: String, after: String?) -> StubReply {
        func nullable(_ value: String?) -> Any { if let value { return value }; return NSNull() }
        func envelope(status: String, rows: [[String: Any]], hasMore: Bool, next: String?, reason: String? = nil) -> [String: Any] {
            var page: [String: Any] = [
                "catalog_version": 1, "catalog_size": 25, "owner": ownerText, "dataset": dataset, "status": status,
                "after": nullable(after), "rows": rows, "row_count": rows.count, "has_more": hasMore,
                "next_cursor": nullable(next),
                "limits": ["max_rows": 100, "max_page_bytes": 262_144, "requested_rows": 100],
            ]
            if let reason { page["reason"] = reason }
            return page
        }
        if unavailable.contains(dataset) {
            return .page(envelope(status: "unavailable", rows: [], hasMore: false, next: nil, reason: "table_absent"))
        }
        let all = datasetRows[dataset] ?? []
        let remaining = all.filter { row in
            guard let after else { return true }
            return after.utf8.lexicographicallyPrecedes((row["export_key"] as? String ?? "").utf8)
        }
        let taken = Array(remaining.prefix(min(pageSize, 100)))
        let hasMore = remaining.count > taken.count
        return .page(envelope(status: "available", rows: taken, hasMore: hasMore, next: hasMore ? taken.last?["export_key"] as? String : nil))
    }
}

private enum ExportStubRegistry {
    private static let lock = NSLock()
    private static var servers: [String: ExportStubServer] = [:]
    static func register(host: String, server: ExportStubServer) { lock.withLock { servers[host] = server } }
    static func unregister(host: String) { lock.withLock { servers[host] = nil } }
    static func server(for host: String?) -> ExportStubServer? { lock.withLock { host.flatMap { servers[$0] } } }
}

private final class ExportStubProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { ExportStubRegistry.server(for: request.url?.host) != nil }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let server = ExportStubRegistry.server(for: request.url?.host) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost)); return
        }
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 8192)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                body.append(buffer, count: read)
            }
            stream.close()
        }
        let reply = server.handle(request, body: body)
        if let error = reply.transportError {
            client?.urlProtocol(self, didFailWithError: error); return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

// MARK: - Owner box, local source, harness

private final class BindingBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: SupportExportBinding?
    private var _tokenCalls = 0
    var token = "RAW-CAPTURED-TOKEN_1.abc-xyz"
    var credentialBinding: SupportExportBinding?
    var onToken: (() -> Void)?

    init(_ binding: SupportExportBinding?) { value = binding }
    func get() -> SupportExportBinding? { lock.withLock { value } }
    func set(_ binding: SupportExportBinding?) { lock.withLock { value = binding } }
    var tokenCalls: Int { lock.withLock { _tokenCalls } }
    func noteTokenCall() { lock.withLock { _tokenCalls += 1 } }
}

/// Parks every owner-proof call while closed, so a test can hold a run at a known point and release it later.
private final class AsyncGate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = true
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func close() { lock.withLock { isOpen = false } }
    func release() {
        let parked = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            isOpen = true
            let all = waiters
            waiters = []
            return all
        }
        parked.forEach { $0.resume() }
    }
    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let proceed = lock.withLock { () -> Bool in
                if isOpen { return true }
                waiters.append(continuation)
                return false
            }
            if proceed { continuation.resume() }
        }
    }
    var waitingCount: Int { lock.withLock { waiters.count } }
}

private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [SupportExportProgress] = []
    func add(_ p: SupportExportProgress) { lock.withLock { items.append(p) } }
    var all: [SupportExportProgress] { lock.withLock { items } }
}

private struct Harness {
    let server: ExportStubServer
    let box: BindingBox
    let binding: SupportExportBinding
    let baseDirectory: URL
    let exporter: SupportDataExporter
    let localCalls: LocalCallCounter

    var leftovers: [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: baseDirectory.path)) ?? []
    }
}

private final class LocalCallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func hit() { lock.withLock { n += 1 } }
    var count: Int { lock.withLock { n } }
}

private let testAPIKey = "TEST-ANON-API-KEY"

/// `SUPPORT_EXPORT_TEST_TMP` / `SUPPORT_EXPORT_REPO_ROOT` exist only so an isolated, sandboxed host run can point at writable
/// and readable locations. Under Xcode neither is set and the defaults apply.
private func testTemporaryDirectory() -> URL {
    if let override = ProcessInfo.processInfo.environment["SUPPORT_EXPORT_TEST_TMP"], !override.isEmpty {
        return URL(fileURLWithPath: override, isDirectory: true)
    }
    return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
}

private func repositoryRoot(_ file: String = #filePath) -> URL {
    if let override = ProcessInfo.processInfo.environment["SUPPORT_EXPORT_REPO_ROOT"], !override.isEmpty {
        return URL(fileURLWithPath: override, isDirectory: true)
    }
    var root = URL(fileURLWithPath: file)
    for _ in 0..<6 { root = root.deletingLastPathComponent() }   // …/apps/ios/MindFriendAppTests/Core/SupportSession/<file>
    return root
}

private func makeHarness(
    rowsPerDataset: Int = 3,
    overrides: [String: Int] = [:],
    configuration: SupportExportConfiguration = .standard,
    local: @escaping @Sendable (SupportExportBinding) -> SupportExportLocalOutcome = { .journal(SupportJournal(ownerID: $0.ownerID)) },
    epoch: UInt64 = 7,
    proofGate: AsyncGate? = nil
) -> Harness {
    let owner = UUID()
    let binding = SupportExportBinding(ownerID: owner, accountEpoch: epoch)
    let server = ExportStubServer(owner: owner, rowsPerDataset: rowsPerDataset, overrides: overrides)
    let box = BindingBox(binding)
    let counter = LocalCallCounter()
    let base = testTemporaryDirectory().appendingPathComponent("export-tests-\(UUID().uuidString)", isDirectory: true)

    let sessionConfiguration = URLSessionConfiguration.ephemeral
    sessionConfiguration.protocolClasses = [ExportStubProtocol.self]
    // Ambient session-level identity that a correct request must override.
    sessionConfiguration.httpAdditionalHeaders = ["Authorization": "Bearer AMBIENT-SDK-TOKEN", "apikey": "AMBIENT-KEY", "X-Ambient": "1"]
    let session = URLSession(configuration: sessionConfiguration)

    let exporter = SupportDataExporter(
        binding: binding,
        ownerProof: { await proofGate?.wait(); return box.get() },
        tokenSource: {
            box.noteTokenCall()
            box.onToken?()
            guard let current = box.get() else { return nil }
            return SupportExportCredential(binding: box.credentialBinding ?? current, accessToken: box.token)
        },
        local: { counter.hit(); return local($0) },
        transport: URLSessionSupportExportTransport(session: session, maxResponseBytes: configuration.responseBytesCap),
        files: SupportExportFiles(baseDirectory: base),
        projectURL: URL(string: "https://\(server.host)")!,
        apiKey: testAPIKey,
        appVersion: "9.9 (1)",
        configuration: configuration,
        clock: { Date(timeIntervalSince1970: 1_800_000_000) })
    return Harness(server: server, box: box, binding: binding, baseDirectory: base, exporter: exporter, localCalls: counter)
}

private func parseExport(_ result: SupportExportResult, file: StaticString = #filePath, line: UInt = #line) throws -> [String: Any] {
    let data = try Data(contentsOf: result.fileURL)
    return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any], file: file, line: line)
}

private func datasets(_ doc: [String: Any]) -> [String: [String: Any]] {
    ((doc["cloud"] as? [String: Any])?["datasets"] as? [String: [String: Any]]) ?? [:]
}

// MARK: - Journal fixture

private struct JournalSentinels {
    let session = UUID()
    let conversation = UUID()
    let memory = UUID()
    let request = UUID()
}

private func makeJournal(owner: UUID, _ s: JournalSentinels) -> SupportJournal {
    var j = SupportJournal(ownerID: owner)
    let when = Date(timeIntervalSince1970: 1_800_000_000.25)
    j.commitSequence = 42
    j.sessions[s.session] = SupportSession(
        id: s.session, ownerID: owner, conversationID: s.conversation, previousSessionID: nil, selectedActivityID: nil,
        title: "SESSION-TITLE-SENTINEL", concern: "CONCERN-SENTINEL", status: .open, contextScope: .personalized,
        localRevision: 3, syncStatus: .pending, createdAt: when, updatedAt: when, closedAt: nil)
    j.drafts[s.session] = "DRAFT-SENTINEL"
    j.transcriptEvents = [
        SupportTranscriptEvent(id: UUID(), providerEventID: "evt-1", sessionID: s.session, conversationID: s.conversation, role: .user,
                               sequence: 1, occurredAt: when, text: "TRANSCRIPT-PENDING-SENTINEL", syncState: .pending),
        SupportTranscriptEvent(id: UUID(), providerEventID: "evt-2", sessionID: s.session, conversationID: s.conversation, role: .assistant,
                               sequence: 2, occurredAt: when, text: "", syncState: .saved),
    ]
    j.pendingChatRequests[s.request] = SupportPendingChatRequest(
        id: s.request, sessionID: s.session, conversationID: s.conversation, content: "PENDING-CHAT-SENTINEL",
        scope: .personalized, privacyRevision: 4, createdAt: when)
    j.memoryRecords[s.memory] = SupportMemoryRecord(
        id: s.memory, content: "MEMORY-SENTINEL", category: "preferences", origin: "user_authored", state: "active", revision: 2,
        confirmedAt: when, reviewDueAt: nil, expiresAt: nil, lastUsedAt: nil, sourceMessageID: nil, sourceConversationID: nil, isSuggestion: false)
    j.memoryChanges = [SupportMemoryChange(
        id: UUID(), targetID: s.memory, action: .edit, content: "MEMORY-CHANGE-SENTINEL", category: nil, expectedRevision: 2, createdAt: when)]
    j.declinedTemplates[s.session] = [.untangleThoughtV1, .groundPresentV1]
    j.reservedConversationIDs[UUID()] = UUID()
    j.erasedUnknownRequests = [SupportErasedUnknownRequest(
        operationID: UUID(), sessionID: s.session, kind: .updateSession, observedServerRevision: 3, recordedAt: when)]
    j.intents = [SupportMutationIntent(
        id: UUID(), operationID: UUID(), sessionID: s.session,
        payload: .updateSession(title: "OUTBOX-TITLE-SENTINEL", contextScope: nil, status: nil), createdAt: when, rebaseCount: 0)]
    j.suppressions = [SupportPrivacySuppression(
        id: UUID(), kind: .memory, targetID: s.memory.uuidString, createdAt: when, acknowledgedPrivacyRevision: nil)]
    j.accountPrivacyRevision = 7
    j.memoryUpdatedAt = when
    return j
}

// MARK: - Tests

final class SupportDataExportTests: XCTestCase {
    private var cleanup: [URL] = []

    override func tearDown() {
        for url in cleanup { try? FileManager.default.removeItem(at: url) }
        cleanup = []
        super.tearDown()
    }

    private func harness(
        rowsPerDataset: Int = 3, overrides: [String: Int] = [:], configuration: SupportExportConfiguration = .standard,
        local: @escaping @Sendable (SupportExportBinding) -> SupportExportLocalOutcome = { .journal(SupportJournal(ownerID: $0.ownerID)) }
    ) -> Harness {
        let h = makeHarness(rowsPerDataset: rowsPerDataset, overrides: overrides, configuration: configuration, local: local)
        cleanup.append(h.baseDirectory)
        return h
    }

    private func expectFailure(_ expected: SupportExportError, _ h: Harness, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            _ = try await h.exporter.run()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch let error as SupportExportError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("unexpected \(type(of: error))", file: file, line: line)
        }
        XCTAssertEqual(h.leftovers, [], "a failed export must leave no file behind", file: file, line: line)
    }

    // MARK: Paging

    func testPaginatesPastOneHundredRowsAndFollowsTheServerCursorExactly() async throws {
        let h = harness(overrides: ["moods": 250, "messages": 101])
        let result = try await h.exporter.run()

        let moods = h.server.requests.filter { $0.dataset == "moods" }
        XCTAssertEqual(moods.count, 3, "250 rows at 100 per page is three pages")
        XCTAssertEqual(moods.map(\.after), [nil, ExportStubServer.key(99), ExportStubServer.key(199)], "each cursor is the server's previous next_cursor, verbatim")
        XCTAssertEqual(h.server.requests.filter { $0.dataset == "messages" }.count, 2, "101 rows must not stop at one page")
        XCTAssertTrue(h.server.requests.allSatisfy { ($0.body["p_limit"] as? Int) == 100 })

        let doc = try parseExport(result)
        let moodSection = try XCTUnwrap(datasets(doc)["moods"])
        XCTAssertEqual((moodSection["rows"] as? [[String: Any]])?.count, 250)
        XCTAssertEqual(moodSection["row_count"] as? Int, 250)
        XCTAssertEqual(moodSection["pages"] as? Int, 3)
        XCTAssertEqual(moodSection["complete"] as? Bool, true)
        let keys = (moodSection["rows"] as? [[String: Any]] ?? []).compactMap { $0["export_key"] as? String }
        XCTAssertEqual(keys, keys.sorted(), "rows are written in server key order")
        XCTAssertEqual(Set(keys).count, 250)

        XCTAssertEqual(result.summary.totalRows, 250 + 101 + 23 * 3)
        XCTAssertEqual(h.server.requests.count, 25 + 2 + 1)
        XCTAssertEqual(result.summary.datasets.count, 25)
        XCTAssertTrue(result.summary.isComplete)
        XCTAssertEqual(result.summary.byteCount, (try FileManager.default.attributesOfItem(atPath: result.fileURL.path)[.size] as? NSNumber)?.intValue)
    }

    func testAnEmptyDatasetIsAnAvailableEmptyDatasetNotAnUnavailableOne() async throws {
        let h = harness(overrides: ["crisis_events": 0])
        let result = try await h.exporter.run()
        let section = try XCTUnwrap(datasets(try parseExport(result))["crisis_events"])
        XCTAssertEqual(section["status"] as? String, "available")
        XCTAssertEqual(section["row_count"] as? Int, 0)
        XCTAssertTrue(result.summary.isComplete)
    }

    // MARK: Raw request

    func testRequestsAreRawFixedHostWithCapturedTokenOwnerAndOnlyFixedDatasets() async throws {
        let h = harness()
        h.box.token = "RAW-CAPTURED-TOKEN_2.abc-xyz"
        _ = try await h.exporter.run()

        let requests = h.server.requests
        XCTAssertFalse(requests.isEmpty)
        for recorded in requests {
            let url = try XCTUnwrap(recorded.request.url)
            XCTAssertEqual(url.scheme, "https")
            XCTAssertEqual(url.host, h.server.host, "fixed host, never derived from data")
            XCTAssertEqual(url.path, "/rest/v1/rpc/export_owner_data_page")
            XCTAssertNil(url.query)
            XCTAssertEqual(recorded.request.httpMethod, "POST")
            XCTAssertEqual(recorded.request.value(forHTTPHeaderField: "apikey"), testAPIKey, "request key wins over the session's ambient one")
            XCTAssertEqual(recorded.request.value(forHTTPHeaderField: "Authorization"), "Bearer RAW-CAPTURED-TOKEN_2.abc-xyz",
                           "captured token wins over the session's ambient Authorization")
            XCTAssertEqual(recorded.request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(Set(recorded.body.keys), ["p_expected_owner", "p_dataset", "p_after", "p_limit"], "no generic table/filter/SQL parameter")
            XCTAssertEqual(recorded.body["p_expected_owner"] as? String, h.binding.ownerID.uuidString.lowercased())
        }
        XCTAssertEqual(requests.map(\.dataset), SupportExportDataset.allCases.map(\.rawValue), "exactly the fixed list, in order, once each")
        XCTAssertEqual(h.box.tokenCalls, requests.count, "a token is captured for every request, never cached across an owner check")
    }

    func testUnsafeEndpointsAndTokensAreRefusedBeforeAnyRequest() async {
        XCTAssertFalse(SupportDataExporter.isAllowedEndpoint(URL(string: "http://example.com")!))
        XCTAssertFalse(SupportDataExporter.isAllowedEndpoint(URL(string: "ftp://example.com")!))
        XCTAssertTrue(SupportDataExporter.isAllowedEndpoint(URL(string: "https://example.com")!))
        XCTAssertTrue(SupportDataExporter.isAllowedEndpoint(URL(string: "http://127.0.0.1:54321")!))
        XCTAssertFalse(SupportDataExporter.isValidToken("bad token"))
        XCTAssertFalse(SupportDataExporter.isValidToken("a\r\nX-Injected: 1"))
        XCTAssertFalse(SupportDataExporter.isValidToken(""))
        XCTAssertTrue(SupportDataExporter.isValidToken("eyJhbGciOi.eyJzdWIi.sig-_~+/="))

        let h = harness()
        h.box.token = "bad token with spaces"
        await expectFailure(.authenticationRequired, h)
        XCTAssertEqual(h.server.requests.count, 0, "an unusable token never reaches the wire")
    }

    // MARK: Owner / epoch

    func testOwnerGoneBeforeTheFirstTokenFetchNeverFetchesATokenOrDispatches() async {
        let h = harness()
        h.box.set(nil)
        await expectFailure(.ownerChanged, h)
        XCTAssertEqual(h.box.tokenCalls, 0)
        XCTAssertEqual(h.server.requests.count, 0)
        XCTAssertEqual(h.localCalls.count, 0)
    }

    func testOwnerChangeDuringTheTokenFetchNeverDispatches() async {
        let h = harness()
        let other = SupportExportBinding(ownerID: UUID(), accountEpoch: 8)
        h.box.onToken = { h.box.set(other) }
        await expectFailure(.ownerChanged, h)
        XCTAssertEqual(h.server.requests.count, 0)
    }

    func testEpochSwitchForTheSameOwnerIsAMismatchAtEveryAwait() async {
        for switchAt in [1, 2, 13, 25] {
            let h = harness()
            let next = SupportExportBinding(ownerID: h.binding.ownerID, accountEpoch: h.binding.accountEpoch + 1)
            h.server.hook = { recorded, reply in
                if recorded.index == switchAt { h.box.set(next) }
                return reply
            }
            await expectFailure(.ownerChanged, h)
            XCTAssertEqual(h.server.requests.count, switchAt, "no request is dispatched after the switch (switch at \(switchAt))")
        }
    }

    func testAResponseArrivingAfterTheOwnerSwitchedIsDiscardedUndecoded() async {
        let h = harness()
        let other = SupportExportBinding(ownerID: UUID(), accountEpoch: 99)
        // The reply is garbage; if it were decoded the error would be `malformed`, not `ownerChanged`.
        h.server.hook = { recorded, reply in
            if recorded.index == 4 { h.box.set(other); return StubReply(status: 200, body: Data("not json".utf8)) }
            return reply
        }
        await expectFailure(.ownerChanged, h)
        XCTAssertEqual(h.server.requests.count, 4)
    }

    func testOwnerSwitchOutranksATransportFailureOnTheFailurePath() async {
        let h = harness()
        let other = SupportExportBinding(ownerID: UUID(), accountEpoch: 9)
        h.server.hook = { recorded, reply in
            if recorded.index == 3 { h.box.set(other); return StubReply(transportError: URLError(.networkConnectionLost)) }
            return reply
        }
        await expectFailure(.ownerChanged, h)
    }

    func testTokenCapturedForAnotherOwnerOrEpochIsNeverUsed() async {
        let h = harness()
        h.box.credentialBinding = SupportExportBinding(ownerID: UUID(), accountEpoch: h.binding.accountEpoch)
        await expectFailure(.ownerChanged, h)
        XCTAssertEqual(h.server.requests.count, 0)

        let h2 = harness()
        h2.box.credentialBinding = SupportExportBinding(ownerID: h2.binding.ownerID, accountEpoch: h2.binding.accountEpoch + 1)
        await expectFailure(.ownerChanged, h2)
        XCTAssertEqual(h2.server.requests.count, 0)
    }

    func testCancellationMidExportDiscardsTheTemporaryFile() async {
        let h = harness(overrides: ["moods": 250])
        let holder = TaskHolder()
        h.server.hook = { recorded, reply in
            if recorded.index == 6 { holder.cancel() }
            return reply
        }
        let task = Task { try await h.exporter.run() }
        holder.set(task)
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch let error as SupportExportError {
            XCTAssertEqual(error, .cancelled)
        } catch {
            XCTFail("unexpected error type")
        }
        XCTAssertEqual(h.leftovers, [])
        XCTAssertLessThanOrEqual(h.server.requests.count, 6, "no request is dispatched after cancellation")
    }

    // MARK: Corrupt pages

    func testCorruptPagesAreRejectedAsAWholeAndLeaveNoFile() async {
        typealias Mutation = (name: String, expected: SupportExportError, apply: (inout [String: Any]) -> Void)
        func firstRow(_ page: inout [String: Any], _ body: (inout [String: Any]) -> Void) {
            var rows = page["rows"] as? [[String: Any]] ?? []
            guard !rows.isEmpty else { return }
            body(&rows[0]); page["rows"] = rows
        }
        let other = UUID().uuidString.lowercased()
        let mutations: [Mutation] = [
            ("owner echo", .malformed(dataset: "moods", reason: "owner_echo"), { $0["owner"] = other }),
            ("dataset echo", .malformed(dataset: "moods", reason: "dataset_echo"), { $0["dataset"] = "messages" }),
            ("cursor echo", .malformed(dataset: "moods", reason: "cursor_echo"), { $0["after"] = ExportStubServer.key(5) }),
            ("row count", .malformed(dataset: "moods", reason: "row_count"), { $0["row_count"] = 5 }),
            ("more than 100 rows", .malformed(dataset: "moods", reason: "row_count"), {
                let r = ($0["rows"] as? [[String: Any]] ?? [])
                $0["rows"] = r + r; $0["row_count"] = r.count * 2 }),
            ("foreign row owner", .malformed(dataset: "moods", reason: "row_owner"), { firstRow(&$0) { $0["export_owner_id"] = other } }),
            ("foreign user_id", .malformed(dataset: "moods", reason: "row_user"), { firstRow(&$0) { $0["user_id"] = other } }),
            ("missing row owner", .malformed(dataset: "moods", reason: "row_owner"), { firstRow(&$0) { $0["export_owner_id"] = nil } }),
            ("missing row key", .malformed(dataset: "moods", reason: "row_shape"), { firstRow(&$0) { $0["export_key"] = nil } }),
            ("duplicate key", .malformed(dataset: "moods", reason: "key_order"), {
                var r = $0["rows"] as? [[String: Any]] ?? []
                if r.count > 1 { r[1]["export_key"] = r[0]["export_key"] }; $0["rows"] = r }),
            ("descending keys", .malformed(dataset: "moods", reason: "key_order"), {
                $0["rows"] = Array(($0["rows"] as? [[String: Any]] ?? []).reversed()) }),
            ("key not after cursor", .malformed(dataset: "moods", reason: "key_order"), { firstRow(&$0) { $0["export_key"] = ExportStubServer.key(99) } }),
            ("more without cursor", .malformed(dataset: "moods", reason: "next_cursor"), { $0["next_cursor"] = NSNull() }),
            ("cursor not last key", .malformed(dataset: "moods", reason: "next_cursor"), { $0["next_cursor"] = ExportStubServer.key(98) }),
            ("more with no rows", .malformed(dataset: "moods", reason: "next_cursor"), { $0["rows"] = [[String: Any]](); $0["row_count"] = 0 }),
            ("limits echo", .malformed(dataset: "moods", reason: "limits_echo"), { $0["limits"] = ["max_rows": 200, "max_page_bytes": 262_144, "requested_rows": 100] }),
            ("unknown status", .malformed(dataset: "moods", reason: "status"), { $0["status"] = "partial" }),
            ("unavailable midway", .malformed(dataset: "moods", reason: "unavailable_midway"), {
                $0["status"] = "unavailable"; $0["reason"] = "table_absent"; $0["rows"] = [[String: Any]](); $0["row_count"] = 0
                $0["has_more"] = false; $0["next_cursor"] = NSNull() }),
            ("missing next_cursor key", .malformed(dataset: "moods", reason: "undecodable_page"), { $0["next_cursor"] = nil }),
            ("missing after key", .malformed(dataset: "moods", reason: "undecodable_page"), { $0["after"] = nil }),
            ("missing rows", .malformed(dataset: "moods", reason: "undecodable_page"), { $0["rows"] = nil }),
            ("rows not objects", .malformed(dataset: "moods", reason: "row_shape"), { $0["rows"] = Array(repeating: "x", count: ($0["rows"] as? [Any] ?? []).count) as [Any] }),
            ("catalog version", .catalogMismatch, { $0["catalog_version"] = 2 }),
            ("catalog size", .catalogMismatch, { $0["catalog_size"] = 24 }),
        ]
        for mutation in mutations {
            let h = harness(overrides: ["moods": 250])
            // Corrupt the SECOND moods page: page one validates, proving state is carried across pages.
            h.server.hook = { recorded, reply in
                guard recorded.dataset == "moods", recorded.after != nil else { return reply }
                guard var page = (try? JSONSerialization.jsonObject(with: reply.body)) as? [String: Any] else { return reply }
                mutation.apply(&page)
                return .page(page)
            }
            await expectFailure(mutation.expected, h)
        }
    }

    func testNonJSONAndOversizedAndWrongShapeBodiesAreNotSuccess() async {
        let bodies: [(String, Data)] = [
            ("html", Data("<html>captive portal</html>".utf8)),
            ("empty", Data()),
            ("array", Data("[]".utf8)),
            ("scalar", Data("true".utf8)),
        ]
        for (name, body) in bodies {
            let h = harness()
            h.server.hook = { recorded, reply in recorded.index == 2 ? StubReply(status: 200, body: body) : reply }
            await expectFailure(.malformed(dataset: SupportExportDataset.allCases[1].rawValue, reason: "undecodable_page"), h)
            XCTAssertFalse(name.isEmpty)
        }
        var small = SupportExportConfiguration.standard
        small.responseBytesCap = 2_000
        let h = harness(overrides: ["moods": 250], configuration: small)
        await expectFailure(.limitExceeded("response_bytes"), h)
    }

    // MARK: Partial failure and HTTP mapping

    func testPartialFailureDiscardsEverythingAndNamesNoContent() async {
        let h = harness()
        h.server.hook = { recorded, reply in recorded.index == 14 ? StubReply(status: 500, body: Data(#"{"message":"SENTINEL-server-text","code":"57014"}"#.utf8)) : reply }
        let log = ProgressLog()
        do {
            _ = try await h.exporter.run(progress: { log.add($0) })
            XCTFail("expected failure")
        } catch let error as SupportExportError {
            XCTAssertEqual(error, .temporaryFailure(status: 500))
            XCTAssertFalse(String(describing: error).contains("SENTINEL"))
            XCTAssertFalse(error.userMessage.contains("SENTINEL"))
            XCTAssertFalse(String(reflecting: error).contains("SENTINEL"))
        } catch {
            XCTFail("unexpected error type")
        }
        XCTAssertEqual(h.leftovers, [], "13 datasets were already written; none of that may survive")
        XCTAssertEqual(log.all.last, .readingCloud(dataset: SupportExportDataset.allCases[13], index: 14, total: 25))
        XCTAssertEqual(h.server.requests.count, 14, "the export stops at the first failure")
    }

    func testHTTPFailuresMapToTypedContentFreeErrors() async {
        func body(_ code: String?) -> Data { Data((code.map { #"{"code":"\#($0)","message":"SENTINEL-body"}"# } ?? "SENTINEL-body").utf8) }
        let cases: [(Int, String?, SupportExportError)] = [
            (401, "PGRST301", .authenticationRequired),
            (403, "42501", .ownerChanged),
            (403, "28000", .authenticationRequired),
            (403, nil, .authenticationRequired),
            (404, "PGRST202", .serviceUnavailable),
            (400, "22023", .rejected(status: 400)),
            (408, nil, .temporaryFailure(status: 408)),
            (429, nil, .temporaryFailure(status: 429)),
            (503, nil, .temporaryFailure(status: 503)),
        ]
        for (status, code, expected) in cases {
            let h = harness()
            h.server.hook = { recorded, reply in recorded.index == 1 ? StubReply(status: status, body: body(code)) : reply }
            await expectFailure(expected, h)
            XCTAssertFalse(expected.userMessage.isEmpty)
        }
        let transport: [(URLError.Code, SupportExportError)] = [
            (.notConnectedToInternet, .transport("offline")), (.timedOut, .transport("timeout")),
            (.networkConnectionLost, .transport("connection_lost")), (.secureConnectionFailed, .transport("secure_connection")),
            (.badURL, .transport("other")),
        ]
        for (code, expected) in transport {
            let h = harness()
            h.server.hook = { recorded, reply in recorded.index == 1 ? StubReply(transportError: URLError(code)) : reply }
            await expectFailure(expected, h)
        }
    }

    // MARK: Unavailable

    func testAbsentDatasetIsExplicitlyUnavailableAndTheExportIsNotCalledComplete() async throws {
        let h = harness()
        h.server.markUnavailable(.offlineMutationReceipts)
        let result = try await h.exporter.run()

        let section = try XCTUnwrap(datasets(try parseExport(result))["offline_mutation_receipts"])
        XCTAssertEqual(section["status"] as? String, "unavailable")
        XCTAssertEqual(section["reason"] as? String, "table_absent")
        XCTAssertEqual(section["complete"] as? Bool, false)
        XCTAssertEqual((section["rows"] as? [Any])?.count, 0)

        XCTAssertFalse(result.summary.isComplete)
        XCTAssertEqual(result.summary.omissions.count, 1)
        XCTAssertTrue(result.summary.omissions[0].contains(SupportExportDataset.offlineMutationReceipts.title))
        XCTAssertEqual(result.summary.datasets.last?.status, .unavailable(reason: "table_absent"))
        let completeness = try XCTUnwrap(try parseExport(result)["completeness"] as? [String: Any])
        XCTAssertEqual(completeness["complete"] as? Bool, false)
        XCTAssertEqual((completeness["omissions"] as? [String])?.count, 1)
    }

    // MARK: Local journal

    func testLocalJournalIsEncodedFromTheActualJournalWithExplicitPendingAndLocalStatus() async throws {
        let s = JournalSentinels()
        // The owner is generated by the harness; the journal is built for whichever owner is bound.
        let h = harness(local: { .journal(makeJournal(owner: $0.ownerID, s)) })
        let result = try await h.exporter.run()
        let journal = makeJournal(owner: h.binding.ownerID, s)

        let doc = try parseExport(result)
        let local = try XCTUnwrap(doc["local"] as? [String: Any])
        XCTAssertEqual(local["status"] as? String, "included")
        let exported = try XCTUnwrap(local["journal"] as? [String: Any])

        // Every stored property of the CURRENT journal type is present: nothing is hand-picked.
        let stored = Mirror(reflecting: journal).children.compactMap(\.label)
        XCTAssertGreaterThan(stored.count, 15)
        for name in stored { XCTAssertNotNil(exported[name], "journal field \(name) is missing from the export") }

        // Content from every user-authored local area, including the newer memory/privacy/outbox state.
        let text = String(decoding: try Data(contentsOf: result.fileURL), as: UTF8.self)
        for sentinel in ["DRAFT-SENTINEL", "TRANSCRIPT-PENDING-SENTINEL", "PENDING-CHAT-SENTINEL", "MEMORY-SENTINEL", "MEMORY-CHANGE-SENTINEL",
                         "OUTBOX-TITLE-SENTINEL", "SESSION-TITLE-SENTINEL", "CONCERN-SENTINEL"] {
            XCTAssertTrue(text.contains(sentinel), "\(sentinel) must be exported")
        }
        // UUID-keyed collections are objects keyed by the UUID, not flat alternating arrays.
        let drafts = try XCTUnwrap(exported["drafts"] as? [String: Any])
        XCTAssertEqual(drafts[s.session.uuidString] as? String, "DRAFT-SENTINEL")
        XCTAssertNotNil((exported["memoryRecords"] as? [String: Any])?[s.memory.uuidString])
        XCTAssertNotNil((exported["pendingChatRequests"] as? [String: Any])?[s.request.uuidString])
        XCTAssertEqual((exported["declinedTemplates"] as? [String: Any])?[s.session.uuidString] as? [String], ["ground_present_v1", "untangle_thought_v1"])
        XCTAssertEqual((exported["reservedConversationIDs"] as? [String: Any])?.count, 1)
        XCTAssertEqual((exported["erasedUnknownRequests"] as? [Any])?.count, 1)
        XCTAssertEqual(exported["accountPrivacyRevision"] as? Int, 7)
        XCTAssertEqual(exported["commitSequence"] as? Int, 42)

        // Explicit local/pending status, derived from the same journal.
        let status = try XCTUnwrap(local["status_summary"] as? [String: Any])
        let counts = try XCTUnwrap(status["counts"] as? [String: Int])
        XCTAssertEqual(counts["sessions"], 1)
        XCTAssertEqual(counts["drafts_with_text"], 1)
        XCTAssertEqual(counts["unsent_mutations"], 1)
        XCTAssertEqual(counts["transcript_events_pending"], 1)
        XCTAssertEqual(counts["transcript_events_saved"], 1)
        XCTAssertEqual(counts["pending_chat_requests"], 1)
        XCTAssertEqual(counts["unacknowledged_privacy_suppressions"], 1)
        XCTAssertEqual(counts["unsent_memory_changes"], 1)
        XCTAssertEqual(status["personalized_cloud_paused"] as? Bool, true)
        XCTAssertEqual((status["session_sync_status"] as? [String: Int])?["pending"], 1)
        XCTAssertNotNil((status["meaning"] as? [String: Any])?["unsent_mutations"])

        XCTAssertEqual(result.summary.local.status, .included)
        XCTAssertEqual(result.summary.local.unsentMutations, 1)
        XCTAssertEqual(result.summary.local.pendingTranscriptEvents, 1)
        XCTAssertEqual(h.localCalls.count, 1, "the journal is read once")
    }

    func testLocalUnavailableIsExplicitNotEmptyAndMakesTheExportIncomplete() async throws {
        let h = harness(local: { _ in .unavailable(.accountEpochMismatch) })
        let result = try await h.exporter.run()
        let local = try XCTUnwrap(try parseExport(result)["local"] as? [String: Any])
        XCTAssertEqual(local["status"] as? String, "unavailable")
        XCTAssertEqual(local["reason"] as? String, "account_epoch_mismatch")
        XCTAssertNil(local["journal"], "no empty journal may stand in for an unreadable one")
        XCTAssertFalse(result.summary.isComplete)
        XCTAssertEqual(result.summary.local.status, .unavailable(.accountEpochMismatch))
        XCTAssertTrue(result.summary.omissions.contains { $0.contains("on-device") })

        let wrongOwner = harness(local: { _ in .journal(SupportJournal(ownerID: UUID())) })
        let second = try await wrongOwner.exporter.run()
        XCTAssertEqual(second.summary.local.status, .unavailable(.journalOwnerMismatch))
        XCTAssertNil((try parseExport(second)["local"] as? [String: Any])?["journal"])
    }

    // MARK: Document and file

    func testDocumentStatesOwnerTimeScopeLimitsAndTheVaultBoundary() async throws {
        let h = harness()
        let result = try await h.exporter.run()
        let doc = try parseExport(result)

        let header = try XCTUnwrap(doc["export"] as? [String: Any])
        XCTAssertEqual(header["format"] as? String, "mindfriend.owner-data-export")
        XCTAssertEqual(header["schema_version"] as? Int, 1)
        XCTAssertEqual(header["exported_at"] as? String, SupportExportDates.string(Date(timeIntervalSince1970: 1_800_000_000)))
        XCTAssertEqual(header["app_version"] as? String, "9.9 (1)")
        XCTAssertEqual((doc["owner"] as? [String: Any])?["user_id"] as? String, h.binding.ownerID.uuidString.lowercased())

        let scope = try XCTUnwrap(doc["scope"] as? [String: Any])
        XCTAssertEqual(scope["cloud_datasets"] as? [String], SupportExportDataset.allCases.map(\.rawValue))
        XCTAssertEqual((scope["private_vault"] as? [String: Any])?["included"] as? Bool, false)
        XCTAssertEqual((scope["private_vault"] as? [String: Any])?["reason"] as? String, "device_only")
        XCTAssertEqual(scope["not_included"] as? [String], SupportExportScope.notIncluded)
        XCTAssertFalse((scope["statement"] as? String ?? "").lowercased().contains("all your data"))
        XCTAssertEqual(scope["consistency"] as? String, SupportExportScope.consistencyNote)

        let limits = try XCTUnwrap((doc["limits"] as? [String: Any])?["cloud"] as? [String: Any])
        XCTAssertEqual(limits["page_rows"] as? Int, 100)
        XCTAssertEqual(limits["page_bytes_target"] as? Int, 262_144)
        XCTAssertEqual(limits["response_bytes_cap"] as? Int, 2_097_152)
        XCTAssertEqual(limits["max_pages_per_dataset"] as? Int, 5_000)
        XCTAssertEqual(limits["max_file_bytes"] as? Int, 104_857_600)
        XCTAssertEqual(limits["catalog_version"] as? Int, 1)

        XCTAssertEqual(Set(datasets(doc).keys), Set(SupportExportDataset.allCases.map(\.rawValue)))
        let completeness = try XCTUnwrap(doc["completeness"] as? [String: Any])
        XCTAssertEqual(completeness["complete"] as? Bool, true)
        XCTAssertEqual(completeness["total_cloud_rows"] as? Int, 75)
        XCTAssertEqual((completeness["omissions"] as? [Any])?.count, 0)
        XCTAssertNotNil(completeness["completed_at"] as? String)
    }

    func testFileIsProtectedExcludedFromBackupAndOnlyOurOwnDirectoryCanBeDiscarded() async throws {
        let h = harness()
        let result = try await h.exporter.run()
        let fm = FileManager.default

        XCTAssertTrue(fm.fileExists(atPath: result.fileURL.path))
        XCTAssertEqual(result.fileURL.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL, h.baseDirectory.standardizedFileURL)
        XCTAssertTrue(result.fileURL.lastPathComponent.hasPrefix("MindFriend-Data-Export-"))
        XCTAssertTrue(result.fileURL.lastPathComponent.hasSuffix(".json"))
        XCTAssertFalse(result.fileURL.path.contains(h.binding.ownerID.uuidString), "the owner id is not in the path")
        #if os(iOS)
        XCTAssertEqual(try result.fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        XCTAssertEqual(try result.fileURL.deletingLastPathComponent().resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        #elseif os(macOS)
        // macOS records the exclusion as an xattr that `isExcludedFromBackup` does not report; assert the attribute itself.
        for path in [result.fileURL.path, result.fileURL.deletingLastPathComponent().path] {
            XCTAssertGreaterThanOrEqual(getxattr(path, "com.apple.metadata:com_apple_backup_excludeItem", nil, 0, 0, 0), 0)
        }
        #endif
        #if os(iOS) && !targetEnvironment(simulator)
        let protection = try fm.attributesOfItem(atPath: result.fileURL.path)[.protectionKey] as? FileProtectionType
        XCTAssertTrue(protection == .completeUnlessOpen || protection == .complete)
        #endif

        // A path that is not one of our export directories is never deleted.
        let foreignDir = testTemporaryDirectory().appendingPathComponent("not-ours-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: foreignDir, withIntermediateDirectories: true)
        cleanup.append(foreignDir)
        let foreignFile = foreignDir.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: foreignFile)
        let foreignResult = SupportExportResult(fileURL: foreignFile, binding: h.binding, summary: result.summary)
        h.exporter.discard(foreignResult)
        XCTAssertTrue(fm.fileExists(atPath: foreignFile.path))

        h.exporter.discard(result)
        XCTAssertFalse(fm.fileExists(atPath: result.fileURL.path))
        XCTAssertEqual(h.leftovers, [])
        h.exporter.discard(result)   // idempotent
    }

    func testStaleExportDirectoriesFromAnInterruptedRunArePurged() async throws {
        let h = harness()
        let fm = FileManager.default
        let stale = h.baseDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: stale, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: stale.appendingPathComponent("MindFriend-Data-Export-old.json"))
        try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-7_200)], ofItemAtPath: stale.path)
        let fresh = h.baseDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: fresh, withIntermediateDirectories: true)
        let unrelated = h.baseDirectory.appendingPathComponent("not-a-uuid", isDirectory: true)
        try fm.createDirectory(at: unrelated, withIntermediateDirectories: true)
        try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-7_200)], ofItemAtPath: unrelated.path)

        h.exporter.purgeLeftovers(olderThan: 3_600)
        XCTAssertFalse(fm.fileExists(atPath: stale.path))
        XCTAssertTrue(fm.fileExists(atPath: fresh.path), "a recent directory (possibly another run) is kept")
        XCTAssertTrue(fm.fileExists(atPath: unrelated.path), "only UUID-named export directories are ever removed")
    }

    // MARK: Limits fail closed

    func testPageAndFileLimitsFailClosedInsteadOfTruncatingSilently() async {
        var pages = SupportExportConfiguration.standard
        pages.maxPagesPerDataset = 2
        await expectFailure(.limitExceeded("pages"), harness(overrides: ["moods": 250], configuration: pages))

        var bytes = SupportExportConfiguration.standard
        bytes.maxFileBytes = 2_000
        await expectFailure(.limitExceeded("file_bytes"), harness(configuration: bytes))
    }

    func testAnUnreachableOrNotConfiguredServerNeverProducesAFile() async {
        let owner = UUID()
        let binding = SupportExportBinding(ownerID: owner, accountEpoch: 1)
        let base = testTemporaryDirectory().appendingPathComponent("export-tests-\(UUID().uuidString)", isDirectory: true)
        cleanup.append(base)
        func exporter(url: String, key: String) -> SupportDataExporter {
            SupportDataExporter(
                binding: binding, ownerProof: { binding },
                tokenSource: { SupportExportCredential(binding: binding, accessToken: "tok") },
                local: { .journal(SupportJournal(ownerID: $0.ownerID)) },
                transport: URLSessionSupportExportTransport(session: URLSession(configuration: .ephemeral)),
                files: SupportExportFiles(baseDirectory: base), projectURL: URL(string: url)!, apiKey: key, appVersion: "1")
        }
        for (url, key) in [("http://example.com", "key"), ("https://example.com", "")] {
            do {
                _ = try await exporter(url: url, key: key).run()
                XCTFail("expected notConfigured")
            } catch let error as SupportExportError {
                XCTAssertEqual(error, .notConfigured)
            } catch { XCTFail("unexpected error type") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: base.path), "nothing is created before configuration is validated")
    }

    // MARK: No content in logs / descriptions

    func testCredentialsAndErrorsNeverPrintTheTokenOrAnyContent() {
        let binding = SupportExportBinding(ownerID: UUID(), accountEpoch: 3)
        let credential = SupportExportCredential(binding: binding, accessToken: "SECRET-TOKEN-VALUE")
        for text in [String(describing: credential), String(reflecting: credential), "\(credential)"] {
            XCTAssertFalse(text.contains("SECRET-TOKEN-VALUE"))
            XCTAssertTrue(text.contains("<redacted>"))
        }
        var dumped = ""
        dump(credential, to: &dumped)   // reflection (what a debugger or `dump` shows) must not reveal the token either
        XCTAssertFalse(dumped.contains("SECRET-TOKEN-VALUE"))
        XCTAssertFalse(String(describing: SupportExportError.malformed(dataset: "moods", reason: "row_owner")).contains("SENTINEL"))

        let errors: [SupportExportError] = [
            .ownerChanged, .cancelled, .notConfigured, .authenticationRequired, .serviceUnavailable, .temporaryFailure(status: 500),
            .rejected(status: 400), .transport("offline"), .malformed(dataset: "messages", reason: "row_shape"), .catalogMismatch,
            .limitExceeded("pages"), .fileFailure("no_space"), .fileFailure("protected_data_unavailable"),
        ]
        for error in errors {
            XCTAssertFalse(error.userMessage.isEmpty)
            XCTAssertFalse(error.userMessage.lowercased().contains("sentinel"))
            XCTAssertFalse(String(describing: error).isEmpty)
        }
    }

    func testTheEngineSourceContainsNoLoggingOrPrintingCalls() throws {
        let source = repositoryRoot().appendingPathComponent("apps/ios/MindFriendApp/Core/SupportSession/SupportDataExport.swift")
        guard let data = try? Data(contentsOf: source) else { throw XCTSkip("engine source not readable from this test environment") }
        let text = String(decoding: data, as: UTF8.self)
        for banned in ["Log.", "print(", "debugPrint(", "NSLog(", "os_log", "Logger(", "dump(", "OSLog", "Sentry", "SentrySDK", "breadcrumb"] {
            XCTAssertFalse(text.contains(banned), "the export engine must not contain \(banned)")
        }
        XCTAssertFalse(text.contains("import Supabase"), "no SDK dependency: the export uses fixed-host URLSession")
        XCTAssertFalse(text.contains("supabase.auth"), "no ambient SDK session")
    }

    // MARK: Contract with the SQL

    func testClientCatalogAndLimitsMatchTheMigrationExactly() throws {
        let migration = repositoryRoot().appendingPathComponent("supabase/migrations/20261107040000_support_data_export.sql")
        guard let data = try? Data(contentsOf: migration) else { throw XCTSkip("migration not readable from this test environment") }
        let sql = String(decoding: data, as: UTF8.self)

        func capture(_ pattern: String) throws -> String {
            let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
            let range = NSRange(sql.startIndex..., in: sql)
            let match = try XCTUnwrap(regex.firstMatch(in: sql, range: range), "pattern not found: \(pattern)")
            return String(sql[try XCTUnwrap(Range(match.range(at: 1), in: sql))])
        }
        let names = try capture(#"c_datasets constant text\[\] := ARRAY\[(.*?)\];"#)
            .components(separatedBy: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \n'")) }.filter { !$0.isEmpty }
        XCTAssertEqual(names, SupportExportDataset.allCases.map(\.rawValue), "SQL catalog and client catalog must be identical and identically ordered")
        XCTAssertEqual(Int(try capture(#"c_catalog_version\s+constant integer := (\d+);"#)), SupportExportLimits.catalogVersion)
        XCTAssertEqual(Int(try capture(#"c_max_rows\s+constant integer := (\d+);"#)), SupportExportLimits.pageRows)
        XCTAssertEqual(Int(try capture(#"c_max_bytes\s+constant integer := (\d+);"#)), SupportExportLimits.pageBytesTarget)
        // Every dataset has exactly one query branch.
        for name in names { XCTAssertTrue(sql.contains("p_dataset = '\(name)'"), "no query branch for \(name)") }
        // The only function the migration creates is the one the client calls.
        XCTAssertEqual(sql.components(separatedBy: "CREATE FUNCTION ").count - 1, 1)
        XCTAssertTrue(sql.contains("public.export_owner_data_page"))
        XCTAssertTrue(sql.contains("SECURITY DEFINER"))
        XCTAssertTrue(sql.contains("SET search_path = ''"))
        XCTAssertTrue(sql.contains("FROM PUBLIC, anon, authenticated"))
        XCTAssertFalse(sql.contains("EXECUTE format"), "no dynamic SQL")
        XCTAssertFalse(sql.lowercased().contains("grant select on"), "no table grant is widened for the export")
    }

    // MARK: JSON value

    func testJSONValueKeepsIntegersExactAndEncodesDeterministically() throws {
        let source = #"{"b":9007199254740993,"a":[1,2.5,"x",null,true],"c":{"z":1,"y":2}}"#
        let value = try JSONDecoder().decode(SupportExportJSON.self, from: Data(source.utf8))
        XCTAssertEqual(value.objectValue?["b"], .int(9_007_199_254_740_993), "bigint survives without a double round-trip")
        let encoded = String(decoding: try value.data(), as: UTF8.self)
        XCTAssertEqual(encoded, #"{"a":[1,2.5,"x",null,true],"b":9007199254740993,"c":{"y":2,"z":1}}"#)
        XCTAssertEqual(encoded, String(decoding: try value.data(), as: UTF8.self))
    }
}

private final class TaskHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<SupportExportResult, Error>?
    private var cancelRequested = false
    func set(_ task: Task<SupportExportResult, Error>) {
        let shouldCancel = lock.withLock { () -> Bool in self.task = task; return cancelRequested }
        if shouldCancel { task.cancel() }
    }
    func cancel() {
        let current = lock.withLock { () -> Task<SupportExportResult, Error>? in cancelRequested = true; return task }
        current?.cancel()
    }
}


// MARK: - Generation-bound run / share state (deferred-callback regressions)

private extension SupportExportController.Phase {
    var readyResult: SupportExportResult? { if case .ready(let r) = self { return r }; return nil }
    var isIdle: Bool { if case .idle = self { return true }; return false }
    var failureMessage: String? { if case .failed(let m) = self { return m }; return nil }
    var runningText: String? { if case .running(let t) = self { return t }; return nil }
}

@MainActor
final class SupportExportControllerTests: XCTestCase {
    private func harness(gate: AsyncGate? = nil) -> Harness {
        let h = makeHarness(proofGate: gate)
        let base = h.baseDirectory
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        return h
    }

    private func waitUntil(_ timeout: TimeInterval = 10, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return condition()
    }

    func testALateCancelledRunCannotClearCancelOrOverwriteTheNewerRun() async throws {
        let gateA = AsyncGate(), gateB = AsyncGate()
        let a = harness(gate: gateA), b = harness(gate: gateB)
        a.server.hook = { recorded, reply in if recorded.index == 2 { gateA.close() }; return reply }
        b.server.hook = { recorded, reply in if recorded.index == 2 { gateB.close() }; return reply }
        let controller = SupportExportController()

        controller.start { a.exporter }
        let parkedA = await waitUntil { gateA.waitingCount == 1 }
        XCTAssertTrue(parkedA, "run A is held after two datasets; its file exists")
        XCTAssertEqual(a.leftovers.count, 1)
        let staleGeneration = controller.generation

        controller.reset()                                // account switch / leaving the screen cancels A
        XCTAssertTrue(controller.phase.isIdle)
        XCTAssertGreaterThan(controller.generation, staleGeneration)

        controller.start { b.exporter }                   // a newer export starts while A is still unwinding
        let parkedB = await waitUntil { gateB.waitingCount == 1 }
        XCTAssertTrue(parkedB)
        XCTAssertTrue(controller.isRunning)
        XCTAssertEqual(b.leftovers.count, 1)

        gateA.release()                                   // the OLD cancelled run finally unwinds (old catch/defer path)
        let ignored = await waitUntil { controller.ignoredStaleCompletions == 1 }
        XCTAssertTrue(ignored, "the old run's completion is recognised as stale")
        let aClean = await waitUntil { a.leftovers.isEmpty }
        XCTAssertTrue(aClean, "the old run still removes ITS OWN file")
        XCTAssertEqual(b.leftovers.count, 1, "…and never the newer run's file")
        XCTAssertTrue(controller.isRunning, "the old catch must not overwrite the newer phase")

        controller.cancel()                               // must reach the NEWER task: the old defer must not have cleared its handle
        gateB.release()
        let bIdle = await waitUntil { controller.phase.isIdle }
        XCTAssertTrue(bIdle, "cancelling the newer run works, so its task handle was intact")
        let bClean = await waitUntil { b.leftovers.isEmpty }
        XCTAssertTrue(bClean)
        XCTAssertEqual(controller.ignoredStaleCompletions, 1)
    }

    func testStaleSuccessProgressAndFailureCallbacksNeverTouchTheCurrentRun() async throws {
        let gateB = AsyncGate()
        let a = harness(), b = harness(gate: gateB)
        b.server.hook = { recorded, reply in if recorded.index == 2 { gateB.close() }; return reply }
        let finishedA = try await a.exporter.run()        // an old run that completed successfully after being superseded
        XCTAssertTrue(FileManager.default.fileExists(atPath: finishedA.fileURL.path))

        let controller = SupportExportController()
        let stale = controller.generation
        controller.reset()
        controller.start { b.exporter }
        let parked = await waitUntil { gateB.waitingCount == 1 }
        XCTAssertTrue(parked)
        let before = controller.phase.runningText
        XCTAssertNotNil(before)

        controller.finish(result: finishedA, exporter: a.exporter, generation: stale, stillCurrent: true, cancelled: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: finishedA.fileURL.path), "a stale success deletes its own file")
        controller.fail(SupportExportError.ownerChanged, generation: stale)
        controller.apply(.finishing, generation: stale)

        XCTAssertTrue(controller.isRunning, "stale success/failure/progress cannot publish or change the phase")
        XCTAssertEqual(controller.phase.runningText, before, "stale progress cannot rewrite the status text")
        XCTAssertEqual(b.leftovers.count, 1, "the newer run's file is untouched")
        XCTAssertEqual(controller.ignoredStaleCompletions, 2)

        controller.reset()
        gateB.release()
        let bClean = await waitUntil { b.leftovers.isEmpty }
        XCTAssertTrue(bClean)
    }

    func testCurrentGenerationOutcomesCancelledNotCurrentAndReady() async throws {
        let h = harness()
        let controller = SupportExportController()

        // Cancelled just as the file completed: discarded, back to idle.
        controller.start { h.exporter }
        let ready = await waitUntil { controller.phase.readyResult != nil }
        XCTAssertTrue(ready)
        var result = try XCTUnwrap(controller.phase.readyResult)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.fileURL.path))
        controller.reset()
        XCTAssertFalse(FileManager.default.fileExists(atPath: result.fileURL.path), "reset deletes the finished file")

        let generation = controller.generation
        let again = try await h.exporter.run()
        controller.finish(result: again, exporter: h.exporter, generation: generation, stillCurrent: true, cancelled: true)
        XCTAssertTrue(controller.phase.isIdle)
        XCTAssertFalse(FileManager.default.fileExists(atPath: again.fileURL.path))

        // Account changed while finishing: failed with the plain message, file deleted.
        let third = try await h.exporter.run()
        controller.finish(result: third, exporter: h.exporter, generation: generation, stillCurrent: false, cancelled: false)
        XCTAssertEqual(controller.phase.failureMessage, SupportExportError.ownerChanged.userMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: third.fileURL.path))

        // The normal path publishes exactly this result.
        let fourth = try await h.exporter.run()
        controller.finish(result: fourth, exporter: h.exporter, generation: generation, stillCurrent: true, cancelled: false)
        result = try XCTUnwrap(controller.phase.readyResult)
        XCTAssertEqual(result.fileURL, fourth.fileURL)
        XCTAssertEqual(controller.ignoredStaleCompletions, 0)
        controller.reset()
        XCTAssertTrue(h.leftovers.isEmpty)
    }

    func testDelayedShareSheetCompletionOfAnOldExportCannotTouchTheNewExport() async throws {
        let a = harness(), b = harness()
        let controller = SupportExportController()

        controller.start { a.exporter }
        let readyA = await waitUntil { controller.phase.readyResult != nil }
        XCTAssertTrue(readyA)
        await controller.presentShare()
        XCTAssertTrue(controller.showShareSheet)
        let ticketA = try XCTUnwrap(controller.shareTicket)
        XCTAssertEqual(ticketA.result.fileURL, controller.phase.readyResult?.fileURL)

        controller.reset()                                // account switch while the share sheet is up
        XCTAssertFalse(controller.showShareSheet)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ticketA.result.fileURL.path), "the first export's file is gone")

        controller.start { b.exporter }
        let readyB = await waitUntil { controller.phase.readyResult != nil }
        XCTAssertTrue(readyB)
        let urlB = try XCTUnwrap(controller.phase.readyResult?.fileURL)

        controller.finishSharing(ticketA)                 // the OLD sheet's completion handler fires late
        XCTAssertEqual(controller.phase.readyResult?.fileURL, urlB, "the newer export is still ready")
        XCTAssertTrue(FileManager.default.fileExists(atPath: urlB.path), "and its file is intact")
        XCTAssertEqual(controller.ignoredStaleCompletions, 1)
        XCTAssertNotEqual(urlB, ticketA.result.fileURL)

        // The newer sheet completes normally: it deletes exactly its own file and returns to idle.
        await controller.presentShare()
        let ticketB = try XCTUnwrap(controller.shareTicket)
        XCTAssertEqual(ticketB.result.fileURL, urlB)
        controller.finishSharing(ticketB)
        XCTAssertTrue(controller.phase.isIdle)
        XCTAssertFalse(controller.showShareSheet)
        XCTAssertFalse(FileManager.default.fileExists(atPath: urlB.path))
        XCTAssertTrue(b.leftovers.isEmpty)
    }

    func testAStaleShareTicketStillDeletesExactlyItsOwnFile() async throws {
        let a = harness(), b = harness()
        let orphan = try await a.exporter.run()          // a finished file whose screen state already moved on
        let controller = SupportExportController()
        let ticket = SupportExportController.ShareTicket(generation: controller.generation, result: orphan, exporter: a.exporter)
        controller.start { b.exporter }
        let ready = await waitUntil { controller.phase.readyResult != nil }
        XCTAssertTrue(ready)
        let urlB = try XCTUnwrap(controller.phase.readyResult?.fileURL)

        controller.finishSharing(ticket)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.fileURL.path), "the sheet's own file is deleted")
        XCTAssertTrue(FileManager.default.fileExists(atPath: urlB.path), "the current export's file is not")
        XCTAssertEqual(controller.phase.readyResult?.fileURL, urlB)
        controller.reset()
    }

    func testSharingIsRefusedAndTheFileDiscardedWhenTheOwnerChangedBeforeThePresentation() async throws {
        let h = harness()
        let controller = SupportExportController()
        controller.start { h.exporter }
        let ready = await waitUntil { controller.phase.readyResult != nil }
        XCTAssertTrue(ready)
        let url = try XCTUnwrap(controller.phase.readyResult?.fileURL)

        h.box.set(SupportExportBinding(ownerID: UUID(), accountEpoch: 99))   // a different account is now signed in
        await controller.presentShare()
        XCTAssertFalse(controller.showShareSheet)
        XCTAssertEqual(controller.phase.failureMessage, SupportExportError.ownerChanged.userMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(h.leftovers.isEmpty)
    }

    func testStartWhileRunningIsIgnoredAndWithoutAnExporterItFailsVisibly() async throws {
        let gate = AsyncGate()
        let h = harness(gate: gate)
        h.server.hook = { recorded, reply in if recorded.index == 2 { gate.close() }; return reply }
        let controller = SupportExportController()
        controller.start { h.exporter }
        let parked = await waitUntil { gate.waitingCount == 1 }
        XCTAssertTrue(parked)
        let generation = controller.generation
        var factoryCalls = 0
        controller.start { factoryCalls += 1; return nil }
        XCTAssertEqual(factoryCalls, 0, "a second tap while running does nothing")
        XCTAssertEqual(controller.generation, generation)
        controller.reset()
        gate.release()
        let clean = await waitUntil { h.leftovers.isEmpty }
        XCTAssertTrue(clean)

        controller.start { nil }
        XCTAssertNotNil(controller.phase.failureMessage, "no signed-in owner is a visible failure, not silence")
    }
}
