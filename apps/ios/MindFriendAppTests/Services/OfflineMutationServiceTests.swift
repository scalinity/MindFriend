import XCTest
import Supabase
@testable import MindFriendApp

@MainActor
final class OfflineMutationServiceTests: XCTestCase {
    private let owner = OfflineOwnerProof(userId: UUID(), epoch: 7)

    private func client() -> (SupabaseClient, URLSession) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AtomicFixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = SupabaseClient(supabaseURL: URL(string: "https://atomic-fixture.invalid")!, supabaseKey: "synthetic-anon",
            options: .init(auth: .init(storage: AtomicFixtureStorage(), autoRefreshToken: false), global: .init(session: session)))
        return (client, session)
    }

    func testOnlineMoodCarriesCapturedOwnerAndReturnsCanonicalIdentity() async throws {
        let (client, session) = client(); defer { session.invalidateAndCancel() }
        let moodID = UUID(), expected = owner
        AtomicFixtureProtocol.setHandler { request in
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: Self.body(request)) as? [String: Any])
            XCTAssertEqual((body["p_expected_owner"] as? String)?.lowercased(), expected.userId.uuidString.lowercased())
            XCTAssertEqual(body["p_local_date"] as? String, "2026-11-06")
            XCTAssertEqual(request.url?.lastPathComponent, "save_mood_checkin")
            return try JSONSerialization.data(withJSONObject: ["outcome":"created", "xp_awarded":10, "level_up":false,
                "mood_id":moodID.uuidString, "local_date":"2026-11-06"])
        }
        let result = try await AtomicCompletionRPC.saveMood(client: client, owner: owner, ownerProof: { expected },
            localDate: "2026-11-06", moodScore: 4, anxietyScore: nil, energyScore: nil, note: "Synthetic fixture")
        XCTAssertEqual(result.moodID, moodID)
        XCTAssertEqual(result.xpAwarded, 10)
    }

    func testChangedEpochBeforeDispatchSendsNoOnlineMutation() async throws {
        let (client, session) = client(); defer { session.invalidateAndCancel() }
        AtomicFixtureProtocol.setHandler { _ in XCTFail("No request after lifecycle changed"); return Data() }
        let changed = OfflineOwnerProof(userId: owner.userId, epoch: owner.epoch + 1)
        do {
            _ = try await AtomicCompletionRPC.saveMood(client: client, owner: owner, ownerProof: { changed },
                localDate: "2026-11-06", moodScore: 4, anxietyScore: nil, energyScore: nil, note: nil)
            XCTFail("Changed lifecycle")
        } catch { XCTAssertEqual(error as? SyncQueueError, .lifecycleEnded) }
    }

    func testAccountSwitchDuringOnlineRequestCannotPublishSuccess() async throws {
        let (client, session) = client(); defer { session.invalidateAndCancel() }
        let proof = AtomicOwnerProofBox(owner), changed = OfflineOwnerProof(userId: UUID(), epoch: 8)
        let quest = UUID(), expected = owner
        AtomicFixtureProtocol.setHandler { request in
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: Self.body(request)) as? [String: Any])
            XCTAssertEqual((body["p_expected_owner"] as? String)?.lowercased(), expected.userId.uuidString.lowercased())
            await proof.set(changed)
            return try JSONSerialization.data(withJSONObject: ["outcome":"completed", "xp_awarded":50,
                "level_up":false, "quest_id":quest.uuidString])
        }
        do {
            _ = try await AtomicCompletionRPC.completeQuest(client: client, owner: owner, ownerProof: { await proof.get() },
                questId: quest, reflectionNote: "Synthetic reflection", rating: 4)
            XCTFail("An old account result must not publish")
        } catch { XCTAssertEqual(error as? SyncQueueError, .lifecycleEnded) }
    }

    func testMismatchedCanonicalResponseIsNotAcknowledged() async throws {
        let (client, session) = client(); defer { session.invalidateAndCancel() }
        let expected = owner
        AtomicFixtureProtocol.setHandler { _ in
            try JSONSerialization.data(withJSONObject: ["outcome":"already_completed", "xp_awarded":0,
                "level_up":false, "quest_id":UUID().uuidString])
        }
        do {
            _ = try await AtomicCompletionRPC.completeQuest(client: client, owner: owner, ownerProof: { expected },
                questId: UUID(), reflectionNote: nil, rating: nil)
            XCTFail("Wrong quest identity")
        } catch { XCTAssertEqual(error as? OfflineMutationError, .malformedReceipt) }
    }

    func testOfflineReceiptIsCheckedAfterTheAccountChanges() async throws {
        let proof = AtomicOwnerProofBox(owner), expected = owner
        let service = OfflineMutationService(ownerProof: { await proof.get() }, transport: { request in
            await proof.set(OfflineOwnerProof(userId: expected.userId, epoch: expected.epoch + 1))
            return OfflineMutationReceipt(schemaVersion: 1, operationId: UUID(uuidString: request.operationId)!,
                kind: request.kind, replayed: false, targetId: UUID(), payloadHash: String(repeating: "a", count: 64),
                result: .init(outcome: "created", xpAwarded: 10), createdAt: "2026-11-06T00:00:00Z")
        })
        do {
            try await service.syncMood(OfflineMoodEntry(moodScore: 4), binding: .init(userId: owner.userId.uuidString, epoch: owner.epoch))
            XCTFail("Old receipt cannot confirm a new account epoch")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testUnknownReceiptVersionAndMissingTargetRemainUnconfirmed() async throws {
        for (version, target): (Int, UUID?) in [(2, UUID()), (1, nil)] {
            let expected = owner
            let service = OfflineMutationService(ownerProof: { expected }, transport: { request in
                OfflineMutationReceipt(schemaVersion: version, operationId: UUID(uuidString: request.operationId)!,
                    kind: request.kind, replayed: false, targetId: target, payloadHash: String(repeating: "a", count: 64),
                    result: .init(outcome: "created", xpAwarded: 10), createdAt: "2026-11-06T00:00:00Z")
            })
            do {
                try await service.syncMood(OfflineMoodEntry(moodScore: 4), binding: .init(userId: owner.userId.uuidString, epoch: owner.epoch))
                XCTFail("Incomplete or unsupported receipt")
            } catch { XCTAssertEqual(error as? OfflineMutationError, .malformedReceipt) }
        }
    }

    func testAuthenticationFailuresKeepQueuedItemsRetryable() throws {
        let mismatch = OfflineMutationService.classify(PostgrestError(code: "42501", message: "OWNER_MISMATCH"))
        XCTAssertTrue(mismatch is CancellationError)
        for code in ["PGRST301", "PGRST302", "PGRST303"] {
            XCTAssertTrue(OfflineMutationService.classify(PostgrestError(code: code, message: "JWT expired")) is PostgrestError)
        }
        XCTAssertTrue(OfflineMutationService.classify(PostgrestError(code: "42501", message: "AUTH_REQUIRED")) is PostgrestError)
        for status in [401, 403] {
            let response = try XCTUnwrap(HTTPURLResponse(url: URL(string: "https://atomic-fixture.invalid")!, statusCode: status, httpVersion: nil, headerFields: nil))
            XCTAssertTrue(OfflineMutationService.classify(HTTPError(data: Data(), response: response)) is HTTPError)
        }
        for (code, message) in [("MF409", "IDEMPOTENCY_CONFLICT"), ("22023", "INVALID_PAYLOAD"), ("42501", "NOT_FOUND")] {
            guard case OfflineSyncHandlerError.nonRetryable = OfflineMutationService.classify(PostgrestError(code: code, message: message)) else {
                XCTFail("A definite payload rejection needs a local decision"); continue
            }
        }
    }

    func testRecordedLocalDayUsesGregorianDigitsAndSurvivesQueueRoundTrip() throws {
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-06T23:00:00Z"))
        let tokyo = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        XCTAssertEqual(OfflineLocalDay.string(for: instant, timeZone: tokyo), "2026-11-07")
        XCTAssertEqual(OfflineLocalDay.string(for: instant, timeZone: TimeZone(secondsFromGMT: 0)!), "2026-11-06")
        let item = OfflineMoodEntry(moodScore: 4, createdAt: instant, localDate: "2026-11-07")
        let encoded = try JSONEncoder().encode(item)
        XCTAssertEqual(try JSONDecoder().decode(OfflineMoodEntry.self, from: encoded).localDate, "2026-11-07")
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "localDate")
        XCTAssertNil(try JSONDecoder().decode(OfflineMoodEntry.self, from: JSONSerialization.data(withJSONObject: legacy)).localDate,
                     "Legacy pending attempts must not acquire a new payload under their original operation ID")
    }

    func testEveryMutationUsesOnlyItsCanonicalWireKeys() async throws {
        let expected = owner
        let instant = Date(timeIntervalSince1970: 1_794_003_600)
        let service = OfflineMutationService(ownerProof: { expected }, transport: { request in
            let root = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
            XCTAssertEqual(Set(root.keys), ["p_expected_owner", "p_operation_id", "p_kind", "p_payload"])
            let payload = try XCTUnwrap(root["p_payload"] as? [String: Any])
            let keys: Set<String>
            switch request.kind {
            case "mood": keys = ["schema_version", "mood_score", "recorded_at_ms", "local_date"]
                XCTAssertEqual(payload["local_date"] as? String, "2026-11-07")
            case "quest": keys = ["schema_version", "quest_id", "completed_at_ms"]
            default: keys = ["schema_version", "exercise_id", "duration_seconds", "completed_at_ms"]
            }
            XCTAssertEqual(Set(payload.keys), keys)
            return OfflineMutationReceipt(schemaVersion: 1, operationId: UUID(uuidString: request.operationId)!,
                kind: request.kind, replayed: false, targetId: request.payload.questId.flatMap(UUID.init(uuidString:)) ?? UUID(),
                payloadHash: String(repeating: "a", count: 64),
                result: .init(outcome: request.kind == "mood" ? "created" : "completed", xpAwarded: 0), createdAt: "2026-11-06T00:00:00Z")
        })
        let binding = OfflineOwnerBinding(userId: owner.userId.uuidString, epoch: owner.epoch)
        try await service.syncMood(.init(moodScore: 4, createdAt: instant, localDate: "2026-11-07"), binding: binding)
        try await service.syncQuest(.init(questId: UUID(), completedAt: instant), binding: binding)
        try await service.syncExercise(.init(exerciseId: UUID(), durationSeconds: 60, completedAt: instant), binding: binding)
    }

    nonisolated private static func body(_ request: URLRequest) -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var result = Data(), bytes = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&bytes, maxLength: bytes.count)
            if count <= 0 { break }
            result.append(contentsOf: bytes.prefix(count))
        }
        return result
    }
}

private actor AtomicOwnerProofBox {
    private var value: OfflineOwnerProof?
    init(_ value: OfflineOwnerProof?) { self.value = value }
    func get() -> OfflineOwnerProof? { value }
    func set(_ value: OfflineOwnerProof?) { self.value = value }
}

private struct AtomicFixtureStorage: AuthLocalStorage {
    func store(key: String, value: Data) throws {}
    func retrieve(key: String) throws -> Data? { nil }
    func remove(key: String) throws {}
}

private final class AtomicFixtureProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) async throws -> Data
    private static let gate = NSLock()
    private static var handler: Handler?
    private var workTask: Task<Void, Never>?
    static func setHandler(_ handler: @escaping Handler) { gate.withLock { self.handler = handler } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let handler = Self.gate.withLock { Self.handler }
        workTask = Task {
            do {
                guard let handler else { throw URLError(.resourceUnavailable) }
                let data = try await handler(request)
                try Task.checkCancellation()
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Type":"application/json"])!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch { client?.urlProtocol(self, didFailWithError: error) }
        }
    }
    override func stopLoading() { workTask?.cancel() }
}
