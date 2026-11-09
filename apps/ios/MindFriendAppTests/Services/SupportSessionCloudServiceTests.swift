import XCTest
@testable import MindFriendApp

// Synthetic-only tests for SupportSessionCloudService. Every request goes through a REAL `URLSession` whose
// `protocolClasses` is a `URLProtocol` stub bound to a unique `.invalid` host: no network, no service, no account,
// no credential. Tokens and identifiers are fabricated per test.

private func assertCloudThrows<T>(_ expression: @autoclosure () throws -> T, _ message: String = "",
                                  file: StaticString = #filePath, line: UInt = #line,
                                  _ handler: (Error) -> Void = { _ in }) {
    do { _ = try expression(); XCTFail(message.isEmpty ? "Expected an error" : message, file: file, line: line) }
    catch { handler(error) }
}

// MARK: - Stub infrastructure

private struct CloudStubRequest {
    let url: URL?
    let method: String?
    let headers: [String: String]
    let body: Data

    var json: [String: Any] { (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:] }
    var payload: [String: Any] { json["payload"] as? [String: Any] ?? [:] }
    var bodyText: String { String(decoding: body, as: UTF8.self) }
    func header(_ name: String) -> String? { headers.first { $0.key.lowercased() == name.lowercased() }?.value }
}

private struct CloudStubReply {
    var status = 200
    var headers = ["Content-Type": "application/json"]
    var body = Data()
    var error: URLError?

    static func json(_ status: Int = 200, _ object: Any, headers: [String: String] = [:]) -> CloudStubReply {
        var reply = CloudStubReply()
        reply.status = status
        reply.body = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        reply.headers.merge(headers) { $1 }
        return reply
    }

    static func raw(_ status: Int, _ text: String, headers: [String: String] = [:]) -> CloudStubReply {
        var reply = CloudStubReply()
        reply.status = status
        reply.body = Data(text.utf8)
        reply.headers.merge(headers) { $1 }
        return reply
    }

    static func failure(_ code: URLError.Code) -> CloudStubReply {
        var reply = CloudStubReply()
        reply.error = URLError(code)
        return reply
    }
}

private final class CloudStub: @unchecked Sendable {
    let host = "s-\(UUID().uuidString.lowercased()).fixture.invalid"
    var projectURL: URL { URL(string: "https://\(host)")! }
    private let lock = NSLock()
    private var captured: [CloudStubRequest] = []
    private var handler: @Sendable (CloudStubRequest) -> CloudStubReply = { _ in .raw(500, "") }

    init() { CloudStubProtocol.register(self) }

    func respond(_ newHandler: @escaping @Sendable (CloudStubRequest) -> CloudStubReply) {
        lock.lock(); defer { lock.unlock() }
        handler = newHandler
    }

    var requests: [CloudStubRequest] {
        lock.lock(); defer { lock.unlock() }
        return captured
    }

    fileprivate func handle(_ request: CloudStubRequest) -> CloudStubReply {
        lock.lock()
        captured.append(request)
        let current = handler
        lock.unlock()
        return current(request)
    }

    func unregister() { CloudStubProtocol.unregister(host: host) }
}

private final class CloudStubProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var registry: [String: CloudStub] = [:]

    static func register(_ stub: CloudStub) {
        lock.lock(); defer { lock.unlock() }
        registry[stub.host] = stub
    }

    static func unregister(host: String) {
        lock.lock(); defer { lock.unlock() }
        registry[host] = nil
    }

    private static func stub(for url: URL?) -> CloudStub? {
        guard let host = url?.host else { return nil }
        lock.lock(); defer { lock.unlock() }
        return registry[host]
    }

    override class func canInit(with request: URLRequest) -> Bool { stub(for: request.url) != nil }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private static func readBody(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    override func startLoading() {
        guard let url = request.url, let stub = Self.stub(for: url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let reply = stub.handle(CloudStubRequest(
            url: url, method: request.httpMethod, headers: request.allHTTPHeaderFields ?? [:], body: Self.readBody(request)))
        if let error = reply.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class OwnerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: SupportCloudBinding?
    init(_ value: SupportCloudBinding?) { self.value = value }
    var current: SupportCloudBinding? {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); defer { lock.unlock() }; value = newValue }
    }
}

private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

// MARK: - Fixtures

private let ownerA = SupportCloudBinding(ownerID: UUID(uuidString: "AAAAAAAA-0000-4000-8000-00000000000A")!, accountEpoch: 7)
private let ownerB = SupportCloudBinding(ownerID: UUID(uuidString: "BBBBBBBB-0000-4000-8000-00000000000B")!, accountEpoch: 8)
private let tokenA = "synthetic-owner-a.header.sig_1~2"
private let publicKey = "synthetic-public-key"
private let stamp = "2026-11-06T23:00:00.123456+00:00"

private func lower(_ id: UUID) -> String { id.uuidString.lowercased() }

private func sessionJSON(
    id: UUID, revision: Int, status: String = "open", selected: UUID? = nil, scope: String = "conversation_only",
    title: String = "Email supervisor", conversation: UUID? = nil, updatedAt: String = stamp
) -> [String: Any] {
    [
        "id": lower(id), "conversation_id": conversation.map(lower) as Any? ?? NSNull(), "previous_session_id": NSNull(),
        "selected_activity_id": selected.map(lower) as Any? ?? NSNull(), "title": title, "concern": NSNull(),
        "status": status, "context_scope": scope, "revision": revision, "suppressed_templates": [String](),
        "created_at": "2026-11-06T22:00:00+00:00", "updated_at": updatedAt,
        "closed_at": status == "closed" ? stamp as Any : NSNull(), "deleted_at": status == "deleted" ? stamp as Any : NSNull(),
    ]
}

private func activityJSON(
    id: UUID = UUID(), template: String = "ground_present_v1", kind: String = "grounding", status: String = "in_progress",
    stopReason: Any = NSNull(), ref: UUID? = nil, checkpoint: Any = NSNull(), result: Any = NSNull(),
    reflection: Any = NSNull(), activeMs: Int = 0, lastRevision: Int = 1, templateVersion: Int = 1
) -> [String: Any] {
    let terminal = status == "completed" || status == "stopped"
    return [
        "id": lower(id), "template_key": template, "template_version": templateVersion, "kind": kind, "status": status,
        "stop_reason": stopReason, "canonical_ref_type": ref == nil ? NSNull() : "exercise_session" as Any,
        "canonical_ref_id": ref.map(lower) as Any? ?? NSNull(), "checkpoint": checkpoint, "result": result,
        "reflection": reflection, "active_ms": activeMs, "last_changed_revision": lastRevision,
        "created_at": "2026-11-06T22:01:00.5+00:00", "updated_at": "2026-11-06T22:30:00Z",
        "finished_at": terminal ? "2026-11-06T22:30:00Z" as Any : NSNull(),
    ]
}

private func snapshotJSON(
    session: [String: Any], activities: [[String: Any]] = [], privacy: Int = 3
) -> [String: Any] {
    ["session": session, "activities": activities, "proposals": [Any](), "privacy_revision": privacy]
}

private func successJSON(
    operation: String, kind: String, revision: Int, snapshot: [String: Any], activity: UUID? = nil, noOp: Bool = false,
    replayed: Bool = false, extra: [String: Any] = [:]
) -> [String: Any] {
    var body: [String: Any] = [
        "ok": true, "operation_id": operation, "kind": kind, "revision": revision, "no_op": noOp,
        "event_id": noOp ? NSNull() : lower(UUID()) as Any, "activity_id": activity.map(lower) as Any? ?? NSNull(),
        "sync_status": "synced", "replayed": replayed, "server_time": stamp, "snapshot": snapshot,
    ]
    body.merge(extra) { $1 }
    return body
}

/// A server that behaves like `support_apply_mutation` for a first application: echoes operation/kind/session, advances the
/// revision by exactly one, issues an event, and shows the requested effect on the target activity at the new revision.
private func echoSuccess(_ request: CloudStubRequest) -> CloudStubReply {
    let body = request.json
    let payload = request.payload
    let operation = body["operation_id"] as? String ?? ""
    let kind = body["kind"] as? String ?? ""
    let session = UUID(uuidString: body["session_id"] as? String ?? "") ?? UUID()
    let revision = ((body["expected_revision"] as? Int) ?? 0) + 1
    let activityID = UUID(uuidString: payload["activity_id"] as? String ?? "")
    var status = "open", title = "Email supervisor", scope = "conversation_only"
    var conversation: UUID?
    var extra: [String: Any] = [:]
    var activity: [String: Any]?
    switch kind {
    case "delete_session":
        status = "deleted"; extra["deleted"] = true
    case "update_session":
        if let t = payload["title"] as? String { title = t.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let c = payload["context_scope"] as? String { scope = c }
        if let c = payload["conversation_id"] as? String { conversation = UUID(uuidString: c) }
        extra["closed"] = payload["close"] != nil
        if payload["close"] != nil { status = "closed" }
    case "accept_proposal":
        activity = activityJSON(id: activityID!, template: "choose_step_v1", kind: "next_step", status: "ready", lastRevision: revision)
    case "start_activity":
        activity = activityJSON(id: activityID!, status: "in_progress", lastRevision: revision)
    case "checkpoint_activity":
        activity = activityJSON(id: activityID!, status: payload["pause"] as? Bool == true ? "paused" : "in_progress", lastRevision: revision)
    case "finish_activity":
        activity = activityJSON(id: activityID!, status: payload["outcome"] as? String ?? "stopped", lastRevision: revision)
    case "record_reflection":
        activity = activityJSON(id: activityID!, status: "completed", reflection: [
            "outcome": payload["outcome"] as? String ?? "skip", "note": payload["note"] as Any? ?? NSNull(),
            "share_note": payload["share_note"] as? Bool ?? false, "shareable_text": payload["shareable_text"] as Any? ?? NSNull()],
            lastRevision: revision)
    case "discard_activity_answers":
        activity = activityJSON(id: activityID!, status: "stopped", stopReason: "discarded", result: ["discarded": true], lastRevision: revision)
    default: break
    }
    let live = activity.flatMap { ($0["status"] as? String).map { ["ready", "in_progress", "paused"].contains($0) } } ?? false
    let snapshot = snapshotJSON(
        session: sessionJSON(id: session, revision: revision, status: status, selected: live ? activityID : nil, scope: scope, title: title, conversation: conversation),
        activities: activity.map { [$0] } ?? [])
    return .json(200, successJSON(operation: operation, kind: kind, revision: revision, snapshot: snapshot, activity: activityID, extra: extra))
}

private func envelope(
    _ payload: SupportMutationPayload, session: UUID, operation: UUID = UUID(), expected: Int64? = 4
) -> SupportMutationEnvelope {
    SupportMutationEnvelope(
        schemaVersion: 1, operationID: operation, sessionID: session, expectedRevision: payload.kind == .create ? nil : expected,
        kind: payload.kind, payload: payload, payloadFingerprint: SupportFingerprint.fingerprint(payload, sessionID: session))
}

private func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, _ s: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
}

// MARK: - Rig

private struct Rig {
    let stub: CloudStub
    let owner: OwnerBox
    let tokenCalls: CallCounter
    let service: SupportSessionCloudService
}

final class SupportSessionCloudServiceTests: XCTestCase {
    private func makeRig(
        binding: SupportCloudBinding = ownerA,
        proof: SupportCloudBinding? = ownerA,
        token: (@Sendable (OwnerBox) async throws -> SupportCloudCredential?)? = nil,
        configure: ((URLSessionConfiguration) -> Void)? = nil,
        apiKey: String = publicKey,
        projectURL: URL? = nil
    ) -> Rig {
        let stub = CloudStub()
        let owner = OwnerBox(proof)
        let calls = CallCounter()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CloudStubProtocol.self]
        configure?(configuration)
        let session = URLSession(configuration: configuration)
        addTeardownBlock {
            session.invalidateAndCancel()
            stub.unregister()
        }
        let tokenSource: SupportCloudTokenSource = { [token] in
            calls.increment()
            if let token { return try await token(owner) }
            return SupportCloudCredential(binding: binding, accessToken: tokenA)
        }
        let service = SupportSessionCloudService(
            binding: binding, ownerProof: { owner.current }, tokenSource: tokenSource,
            transport: URLSessionSupportCloudTransport(session: session),
            projectURL: projectURL ?? stub.projectURL, apiKey: apiKey)
        return Rig(stub: stub, owner: owner, tokenCalls: calls, service: service)
    }

    private func expectError<T>(
        _ expression: @autoclosure () async throws -> T, file: StaticString = #filePath, line: UInt = #line
    ) async -> SupportCloudError? {
        do {
            _ = try await expression()
            XCTFail("expected a SupportCloudError", file: file, line: line)
            return nil
        } catch let error as SupportCloudError {
            return error
        } catch {
            XCTFail("unexpected error type \(type(of: error))", file: file, line: line)
            return nil
        }
    }

    private func expectError<T>(
        _ expected: SupportCloudError, _ expression: @autoclosure () async throws -> T,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        let error = await expectError(try await expression(), file: file, line: line)
        XCTAssertEqual(error, expected, file: file, line: line)
    }

    // MARK: - Mutation kinds: canonical flat TS keys (never the Swift Codable enum shape)

    func testEveryMutationKindSendsCanonicalFlatKeysThroughRealURLSession() async throws {
        let rig = makeRig()
        rig.stub.respond { echoSuccess($0) }
        let sid = UUID(), aid = UUID(), conversation = UUID(), previous = UUID()
        let reminderStep = SupportStepPayload(
            actionText: "Write the subject line", state: .saved, reminderAt: utc(2026, 11, 7, 9),
            reminderTimeZoneIdentifier: "America/New_York", confirmedAt: utc(2026, 11, 6, 23))
        let doneStep = SupportStepPayload(
            actionText: "Write the subject line", state: .selfReportedDone, reminderAt: utc(2026, 11, 7, 9),
            reminderTimeZoneIdentifier: "America/New_York", confirmedAt: utc(2026, 11, 6, 23))
        let checkpoint = SupportCheckpoint(
            templateVersion: 1, lastPromptID: "hear", completedStepIDs: ["see", "feel"], skippedStepIDs: ["hear"],
            responses: ["see": "the window"], activeMilliseconds: 12_345, lastDurableWrite: utc(2026, 11, 6, 23))
        let cases: [(SupportMutationPayload, String, Set<String>)] = [
            (.create(title: "Email", concern: "Putting it off", conversationID: conversation, previousSessionID: previous, contextScope: .personalized),
             "create", ["title", "concern", "context_scope", "conversation_id", "previous_session_id"]),
            (.create(title: "", concern: nil, conversationID: nil, previousSessionID: nil, contextScope: .conversationOnly),
             "create", ["title", "context_scope"]),
            (.updateSession(title: "Renamed", contextScope: .conversationOnly, status: .closed),
             "update_session", ["title", "context_scope", "close"]),
            (.startActivity(activityID: aid, templateKey: .groundPresentV1, templateVersion: 1,
                            canonicalReference: SupportCanonicalReference(kind: .exerciseSession, id: UUID())),
             "start_activity", ["activity_id", "template_key"]),
            (.checkpointActivity(activityID: aid, status: .inProgress, checkpoint: checkpoint, step: nil),
             "checkpoint_activity", ["activity_id", "checkpoint", "active_ms", "pause"]),
            (.checkpointActivity(activityID: aid, status: .paused, checkpoint: SupportCheckpoint(templateVersion: 1), step: reminderStep),
             "checkpoint_activity", ["activity_id", "checkpoint", "active_ms", "pause"]),
            (.finishActivity(activityID: aid, status: .completed,
                             result: SupportActivityResult(acknowledgedStepCount: 2, skippedStepCount: 1, activeMilliseconds: 12_345, shareableNote: "Done"),
                             step: doneStep, checkpoint: checkpoint),
             "finish_activity", ["activity_id", "outcome", "active_ms", "result", "checkpoint"]),
            (.finishActivity(activityID: aid, status: .stopped,
                             result: SupportActivityResult(activeMilliseconds: 900, stoppedReason: "skipped_all"), step: nil, checkpoint: nil),
             "finish_activity", ["activity_id", "outcome", "active_ms", "result", "reason"]),
            (.recordReflection(activityID: aid, reflection: SupportReflection(outcome: .helpful, note: "ok", includeWrittenAnswers: true, recordedAt: utc(2026, 11, 6))),
             "record_reflection", ["activity_id", "outcome", "note", "share_note", "shareable_text"]),
            (.recordReflection(activityID: aid, reflection: SupportReflection(outcome: .skip, note: nil, includeWrittenAnswers: false, recordedAt: utc(2026, 11, 6))),
             "record_reflection", ["activity_id", "outcome", "share_note"]),
            (.discardActivityAnswers(activityID: aid), "discard_activity_answers", ["activity_id"]),
            (.deleteSession, "delete_session", []),
            // Root-added payload cases through the ENVELOPE path (not only the separate factories).
            (.attachConversation(conversationID: conversation), "update_session", ["conversation_id"]),
            (.acceptProposal(proposalID: UUID(), activityID: aid), "accept_proposal", ["proposal_id", "activity_id"]),
            (.declineTemplate(.chooseStepV1), "update_session", ["decline_template"]),
        ]
        for (payload, wireKind, keys) in cases {
            let sent = envelope(payload, session: sid)
            let result = try await rig.service.mutate(sent)
            guard case .confirmed(let confirmation) = result else { return XCTFail("expected confirmation for \(wireKind)") }
            XCTAssertEqual(confirmation.operationID, sent.operationID)
            let request = try XCTUnwrap(rig.stub.requests.last)
            let body = request.json
            XCTAssertEqual(Set(body.keys), ["op", "schema_version", "operation_id", "session_id", "expected_revision", "kind", "payload"])
            XCTAssertEqual(body["op"] as? String, "mutate")
            XCTAssertEqual(body["schema_version"] as? Int, 1)
            XCTAssertEqual(body["kind"] as? String, wireKind)
            XCTAssertEqual(body["operation_id"] as? String, lower(sent.operationID))
            XCTAssertEqual(body["session_id"] as? String, lower(sid))
            if wireKind == "create" { XCTAssertTrue(body["expected_revision"] is NSNull) } else { XCTAssertEqual(body["expected_revision"] as? Int, 4) }
            XCTAssertEqual(Set(request.payload.keys), keys, "payload keys for \(wireKind)")
            // Never the Swift enum shape, the local FNV fingerprint, or any clock/zone-derived field.
            XCTAssertFalse(request.bodyText.contains(sent.payloadFingerprint))
            // `result.discarded` is the SERVER-owned erasure marker; no client mutation ever emits it.
            for forbidden in ["payloadFingerprint", "payload_fingerprint", "client_occurred_at", "_0", "associatedValues", "discarded"] {
                XCTAssertFalse(request.bodyText.contains(forbidden), "\(forbidden) leaked into \(wireKind)")
            }
        }
        XCTAssertEqual(rig.stub.requests.count, cases.count, "exactly one request per mutation; no retries, no extras")
    }

    func testCheckpointFinishAndReflectionValuesFollowTheSQLWire() async throws {
        let rig = makeRig()
        rig.stub.respond { echoSuccess($0) }
        let sid = UUID(), aid = UUID()
        let checkpoint = SupportCheckpoint(
            templateVersion: 1, lastPromptID: "hear", completedStepIDs: ["see", "feel"], skippedStepIDs: ["hear"],
            responses: ["see": "the window"], activeMilliseconds: 12_345)
        _ = try await rig.service.mutate(envelope(.checkpointActivity(activityID: aid, status: .inProgress, checkpoint: checkpoint, step: nil), session: sid))
        var request = try XCTUnwrap(rig.stub.requests.last)
        XCTAssertEqual(request.payload["active_ms"] as? Int, 12_345, "active_ms is milliseconds, not seconds")
        XCTAssertEqual(request.payload["pause"] as? Bool, false)
        let cp = try XCTUnwrap(request.payload["checkpoint"] as? [String: Any])
        XCTAssertEqual(Set(cp.keys), ["version", "template_version", "current_step", "completed_steps", "skipped_steps", "responses"])
        XCTAssertEqual(cp["version"] as? Int, 1)
        XCTAssertEqual(cp["template_version"] as? Int, 1)
        XCTAssertEqual(cp["current_step"] as? String, "hear")
        XCTAssertEqual(cp["completed_steps"] as? [String], ["see", "feel"])
        XCTAssertEqual(cp["skipped_steps"] as? [String], ["hear"])
        XCTAssertEqual(cp["responses"] as? [String: String], ["see": "the window"])

        // Paused saved step: exactly {action_text, state}; reminder metadata (device-local) never reaches the wire.
        let step = SupportStepPayload(actionText: "Write the subject line", state: .saved, reminderAt: utc(2026, 11, 7, 9),
                                      reminderTimeZoneIdentifier: "America/New_York", confirmedAt: utc(2026, 11, 6, 23))
        _ = try await rig.service.mutate(envelope(.checkpointActivity(activityID: aid, status: .paused, checkpoint: SupportCheckpoint(templateVersion: 1), step: step), session: sid))
        request = try XCTUnwrap(rig.stub.requests.last)
        XCTAssertEqual(request.payload["pause"] as? Bool, true)
        let pausedStep = try XCTUnwrap((request.payload["checkpoint"] as? [String: Any])?["step"] as? [String: Any])
        XCTAssertEqual(pausedStep as? [String: String], ["action_text": "Write the subject line", "state": "saved"])
        for reminderText in ["reminder", "America/New_York", "confirmed", "2026-11-07"] {
            XCTAssertFalse(request.bodyText.contains(reminderText), "\(reminderText) must not be on the wire")
        }
    }

    func testFinishIsAtomicCarriesFinalCheckpointResultAndStepInOneRequest() async throws {
        let rig = makeRig()
        rig.stub.respond { echoSuccess($0) }
        let sid = UUID(), aid = UUID()
        let final = SupportCheckpoint(templateVersion: 1, lastPromptID: "smaller", completedStepIDs: ["action"], activeMilliseconds: 61_000)
        let step = SupportStepPayload(actionText: "Write the subject line", state: .selfReportedDone, reminderAt: utc(2026, 11, 7, 9),
                                      reminderTimeZoneIdentifier: "Europe/Paris", confirmedAt: utc(2026, 11, 6, 23))
        let result = SupportActivityResult(acknowledgedStepCount: 1, skippedStepCount: 0, activeMilliseconds: 61_000, shareableNote: "Subject line drafted")
        _ = try await rig.service.mutate(envelope(.finishActivity(activityID: aid, status: .completed, result: result, step: step, checkpoint: final), session: sid))
        XCTAssertEqual(rig.stub.requests.count, 1, "finish + final checkpoint + result is ONE request")
        let request = try XCTUnwrap(rig.stub.requests.first)
        XCTAssertEqual(request.payload["outcome"] as? String, "completed")
        XCTAssertEqual(request.payload["active_ms"] as? Int, 61_000)
        XCTAssertNil(request.payload["reason"], "a completed activity carries no stop reason")
        XCTAssertEqual((request.payload["checkpoint"] as? [String: Any])?["current_step"] as? String, "smaller")
        let wireResult = try XCTUnwrap(request.payload["result"] as? [String: Any])
        XCTAssertEqual(Set(wireResult.keys), ["acknowledged_count", "skipped_count", "shareable_note", "step"])
        XCTAssertEqual(wireResult["acknowledged_count"] as? Int, 1)
        XCTAssertEqual(wireResult["shareable_note"] as? String, "Subject line drafted")
        XCTAssertEqual(wireResult["step"] as? [String: String], ["action_text": "Write the subject line", "state": "self_reported_done"])
        XCTAssertFalse(request.bodyText.contains("Europe/Paris"))
    }

    func testStoppedFinishCarriesReasonAndOnlyADismissedStepWithoutText() async throws {
        let rig = makeRig()
        rig.stub.respond { echoSuccess($0) }
        let sid = UUID(), aid = UUID()
        let dismissed = SupportStepPayload(actionText: "private plan text", state: .dismissed)
        _ = try await rig.service.mutate(envelope(.finishActivity(
            activityID: aid, status: .stopped, result: SupportActivityResult(stoppedReason: "user_ended"), step: dismissed, checkpoint: nil), session: sid))
        let request = try XCTUnwrap(rig.stub.requests.last)
        XCTAssertEqual(request.payload["reason"] as? String, "user_ended")
        XCTAssertEqual((request.payload["result"] as? [String: Any])?["step"] as? [String: String], ["state": "dismissed"])
        XCTAssertFalse(request.bodyText.contains("private plan text"), "a dismissed step never carries its text")
    }

    func testAcceptProposalAndAttachConversationExtensionPointsEncodeFlatPayloads() async throws {
        let rig = makeRig()
        rig.stub.respond { echoSuccess($0) }
        let sid = UUID(), proposal = UUID(), activity = UUID(), conversation = UUID()
        let accept = try SupportCloudWireMutation.acceptProposal(
            operationID: UUID(), sessionID: sid, expectedRevision: 3, proposalID: proposal, activityID: activity, previousDisposition: .save)
        _ = try await rig.service.mutate(accept)
        var request = try XCTUnwrap(rig.stub.requests.last)
        XCTAssertEqual(request.json["kind"] as? String, "accept_proposal")
        XCTAssertEqual(request.payload as? [String: String],
                       ["proposal_id": lower(proposal), "activity_id": lower(activity), "previous_disposition": "save"])
        let attach = try SupportCloudWireMutation.attachConversation(operationID: UUID(), sessionID: sid, expectedRevision: 3, conversationID: conversation)
        _ = try await rig.service.mutate(attach)
        request = try XCTUnwrap(rig.stub.requests.last)
        XCTAssertEqual(request.json["kind"] as? String, "update_session")
        XCTAssertEqual(request.payload as? [String: String], ["conversation_id": lower(conversation)])
    }

    // MARK: - Replay identity

    func testReplayingTheSameEnvelopeSendsByteIdenticalRequestsIndependentOfClockAndService() async throws {
        let sid = UUID(), aid = UUID()
        let payload = SupportMutationPayload.checkpointActivity(
            activityID: aid, status: .inProgress,
            checkpoint: SupportCheckpoint(templateVersion: 1, lastPromptID: "feel", completedStepIDs: ["see"], responses: ["see": "tree", "feel": "chair"],
                                          activeMilliseconds: 500, lastDurableWrite: Date()),
            step: nil)
        let sent = envelope(payload, session: sid)
        let expected = try SupportCloudWireMutation(envelope: sent).requestData()
        let first = makeRig(), second = makeRig()
        first.stub.respond { echoSuccess($0) }
        second.stub.respond { echoSuccess($0) }
        _ = try await first.service.mutate(sent)
        _ = try await first.service.mutate(sent)
        // A different service instance and a different clock instant produce the same bytes.
        try await Task.sleep(nanoseconds: 20_000_000)
        _ = try await second.service.mutate(sent)
        let bodies = first.stub.requests.map(\.body) + second.stub.requests.map(\.body)
        XCTAssertEqual(bodies.count, 3)
        XCTAssertTrue(bodies.allSatisfy { $0 == expected }, "replay must be byte-identical")
        XCTAssertEqual(try SupportCloudWireMutation(envelope: sent).requestData(), expected)
    }

    // MARK: - Owner / epoch around every await; no dispatch on mismatch

    func testOwnerGoneBeforeTokenFetchNeverFetchesATokenOrDispatches() async throws {
        let rig = makeRig(proof: nil)
        let error = await expectError(try await rig.service.capabilities())
        XCTAssertEqual(error, .ownerChanged)
        XCTAssertEqual(rig.tokenCalls.value, 0)
        XCTAssertTrue(rig.stub.requests.isEmpty)
    }

    func testOwnerChangeDuringTokenFetchNeverDispatches() async throws {
        let rig = makeRig(token: { owner in
            owner.current = ownerB
            return SupportCloudCredential(binding: ownerA, accessToken: tokenA)
        })
        let error = await expectError(try await rig.service.mutate(envelope(.deleteSession, session: UUID())))
        XCTAssertEqual(error, .ownerChanged)
        XCTAssertTrue(rig.stub.requests.isEmpty)
    }

    func testEpochSwitchForTheSameOwnerIsAMismatch() async throws {
        let sameOwnerNewEpoch = SupportCloudBinding(ownerID: ownerA.ownerID, accountEpoch: ownerA.accountEpoch + 1)
        let rig = makeRig(proof: sameOwnerNewEpoch)
        let error = await expectError(try await rig.service.listMemory())
        XCTAssertEqual(error, .ownerChanged)
        XCTAssertTrue(rig.stub.requests.isEmpty)
    }

    func testTokenCapturedForAnotherOwnerOrEpochIsNeverUsed() async throws {
        for foreign in [ownerB, SupportCloudBinding(ownerID: ownerA.ownerID, accountEpoch: 99)] {
            let rig = makeRig(token: { _ in SupportCloudCredential(binding: foreign, accessToken: "foreign.token.value") })
            let error = await expectError(try await rig.service.capabilities())
            XCTAssertEqual(error, .ownerChanged)
            XCTAssertTrue(rig.stub.requests.isEmpty, "a foreign token must never be dispatched")
        }
    }

    func testResponseArrivingAfterOwnerSwitchIsDiscardedAndNeverPublished() async throws {
        let rig = makeRig()
        let sid = UUID(), aid = UUID()
        rig.stub.respond { [owner = rig.owner] request in
            owner.current = ownerB          // the account switches while the response is in flight
            return echoSuccess(request)
        }
        let sent = envelope(.discardActivityAnswers(activityID: aid), session: sid)
        let error = await expectError(try await rig.service.mutate(sent))
        XCTAssertEqual(error, .ownerChanged, "a delayed valid reply under another owner is dropped")
        XCTAssertEqual(error?.attemptOutcome, .transientFailure, "the OLD owner's attempt stays replayable with the same operation ID")
        XCTAssertEqual(rig.stub.requests.count, 1)
    }

    func testOwnerSwitchOutranksATransportFailureOnTheFailurePath() async throws {
        let rig = makeRig()
        rig.stub.respond { [owner = rig.owner] _ in
            owner.current = nil
            return .failure(.timedOut)
        }
        let error = await expectError(try await rig.service.listMemory())
        XCTAssertEqual(error, .ownerChanged)
    }

    func testCancellationBeforeDispatchStopsWithoutARequest() async throws {
        let rig = makeRig(token: { _ in
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return SupportCloudCredential(binding: ownerA, accessToken: tokenA)
        })
        let task = Task { try await rig.service.capabilities() }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("a cancelled call must not succeed")
        } catch let error as SupportCloudError {
            XCTAssertEqual(error, .cancelled)
            XCTAssertEqual(error.attemptOutcome, .transientFailure)
        }
        XCTAssertTrue(rig.stub.requests.isEmpty)
    }

    // MARK: - Captured headers are authoritative

    func testRequestCarriesCapturedTokenAndApiKeyEvenWhenTheSessionHasAmbientHeaders() async throws {
        let rig = makeRig(configure: {
            $0.httpAdditionalHeaders = ["Authorization": "Bearer ambient-other-owner", "apikey": "ambient-other-key"]
        })
        rig.stub.respond { _ in .json(200, ["session_contract": 1, "context_policy": 1, "voice_context": 0, "status": "ok"]) }
        _ = try await rig.service.capabilities()
        let request = try XCTUnwrap(rig.stub.requests.first)
        XCTAssertEqual(request.header("Authorization"), "Bearer \(tokenA)")
        XCTAssertEqual(request.header("apikey"), publicKey)
        XCTAssertEqual(request.header("Content-Type"), "application/json")
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url?.path, "/functions/v1/support-session")
        XCTAssertFalse(request.bodyText.contains(tokenA), "the token is a header, never body content")
    }

    func testTokenIsNeverEchoedInDescriptionsOrErrors() async throws {
        let credential = SupportCloudCredential(binding: ownerA, accessToken: tokenA)
        XCTAssertFalse("\(credential)".contains(tokenA))
        XCTAssertFalse(String(reflecting: credential).contains(tokenA))
        let rig = makeRig()
        rig.stub.respond { _ in .json(401, ["msg": "Invalid JWT \(tokenA)"]) }
        let error = await expectError(try await rig.service.capabilities())
        XCTAssertFalse("\(String(describing: error))".contains(tokenA))
    }

    func testUnsafeEndpointsAndTokensAreRefusedBeforeAnyRequest() async throws {
        let insecure = makeRig(projectURL: URL(string: "http://remote.fixture.invalid")!)
        await expectError(.capabilityUnavailable(.notConfigured), try await insecure.service.capabilities())
        XCTAssertEqual(insecure.tokenCalls.value, 0)
        XCTAssertTrue(SupportSessionCloudService.isAllowedEndpoint(URL(string: "http://127.0.0.1:54321")!))
        XCTAssertTrue(SupportSessionCloudService.isAllowedEndpoint(URL(string: "https://project.supabase.co")!))
        XCTAssertFalse(SupportSessionCloudService.isAllowedEndpoint(URL(string: "http://project.supabase.co")!))
        let missingKey = makeRig(apiKey: "")
        await expectError(.capabilityUnavailable(.notConfigured), try await missingKey.service.capabilities())
        let splitHeader = makeRig(token: { _ in SupportCloudCredential(binding: ownerA, accessToken: "abc\r\nX-Injected: 1") })
        await expectError(.authenticationRequired(.noSession), try await splitHeader.service.capabilities())
        XCTAssertTrue(splitHeader.stub.requests.isEmpty)
        XCTAssertFalse(SupportSessionCloudService.isValidToken(""))
        XCTAssertTrue(SupportSessionCloudService.isValidToken(tokenA))
    }

    // MARK: - Capabilities: three independent versions

    func testCapabilitiesAreIndependentAndNotDeployedIsExplicit() async throws {
        let rig = makeRig()
        rig.stub.respond { _ in .json(200, ["session_contract": 0, "context_policy": 0, "voice_context": 0, "status": "not_deployed"]) }
        var caps = try await rig.service.capabilities()
        XCTAssertTrue(caps.isNotDeployed)
        XCTAssertFalse(caps.sessionContractAvailable || caps.contextPolicyAvailable || caps.voiceContextAvailable || caps.canEnforcePrivacyForChat)
        XCTAssertEqual(rig.stub.requests.last?.json as? [String: String], ["op": "capabilities"])

        rig.stub.respond { _ in .json(200, [
            "session_contract": 1, "context_policy": 0, "voice_context": 0, "privacy_revision": true, "memory_lifecycle": true,
            "chat_confirmation": true, "lazy_attach": true, "schema": "20261106230200", "status": "ok"]) }
        caps = try await rig.service.capabilities()
        XCTAssertTrue(caps.sessionContractAvailable)
        XCTAssertFalse(caps.contextPolicyAvailable)
        XCTAssertFalse(caps.voiceContextAvailable)
        XCTAssertFalse(caps.canEnforcePrivacyForChat, "no context policy: personalized cloud chat must stay paused")
        XCTAssertEqual(caps.schema, "20261106230200")

        rig.stub.respond { _ in .json(200, ["session_contract": 0, "context_policy": 1, "voice_context": 0, "privacy_revision": true, "status": "ok"]) }
        caps = try await rig.service.capabilities()
        XCTAssertFalse(caps.sessionContractAvailable)
        XCTAssertTrue(caps.contextPolicyAvailable)
        XCTAssertTrue(caps.canEnforcePrivacyForChat)
        XCTAssertFalse(caps.voiceContextAvailable)

        rig.stub.respond { _ in .json(200, ["session_contract": 1, "context_policy": 1, "voice_context": 1, "status": "ok"]) }
        caps = try await rig.service.capabilities()
        XCTAssertTrue(caps.voiceContextAvailable)
        XCTAssertFalse(caps.canEnforcePrivacyForChat, "privacy_revision not advertised fails closed")
    }

    func testCapabilityContractViolationsAreMalformedNotSuccess() async throws {
        let rig = makeRig()
        let bodies: [Any] = [
            ["session_contract": 1, "context_policy": 1, "status": "ok"],                                   // voice_context missing
            ["session_contract": 1, "context_policy": 1, "voice_context": 0],                               // status missing
            ["session_contract": 1, "context_policy": 1, "voice_context": 0, "status": "maybe"],
            ["session_contract": 1, "context_policy": 0, "voice_context": 0, "status": "not_deployed"],     // contradictory
            ["session_contract": -1, "context_policy": 0, "voice_context": 0, "status": "ok"],
            ["session_contract": "1", "context_policy": 0, "voice_context": 0, "status": "ok"],
            [Any](),
        ]
        for body in bodies {
            rig.stub.respond { _ in .json(200, body) }
            let error = await expectError(try await rig.service.capabilities())
            guard case .malformedResponse = error else { return XCTFail("expected malformedResponse for \(body)") }
        }
    }

    func testMissingFunctionOrRPCIsReportedAsUnavailableNotAsAnOldPrivacyFallback() async throws {
        let rig = makeRig()
        // Platform 404 (no `ok`): the Edge function is not deployed.
        rig.stub.respond { _ in .json(404, ["code": "NOT_FOUND", "message": "Requested function was not found"]) }
        let caps = try await rig.service.capabilities()
        XCTAssertTrue(caps.isNotDeployed)
        await expectError(.capabilityUnavailable(.functionNotDeployed), try await rig.service.mutate(envelope(.deleteSession, session: UUID())))
        await expectError(.capabilityUnavailable(.functionNotDeployed), try await rig.service.listMemory())
        // Handler 503 with capability: not_deployed (RPC missing).
        rig.stub.respond { _ in .json(503, ["ok": false, "code": "TEMPORARY_FAILURE", "capability": "not_deployed"]) }
        let error = await expectError(try await rig.service.get(sessionID: UUID()))
        XCTAssertEqual(error, .capabilityUnavailable(.rpcNotDeployed))
        XCTAssertEqual(error?.attemptOutcome, .transientFailure, "local work continues; the operation is kept for later")
        // The contract's own NOT_FOUND is a definitive answer, not a missing capability.
        rig.stub.respond { _ in .json(404, ["ok": false, "code": "NOT_FOUND"]) }
        let notFound = await expectError(try await rig.service.get(sessionID: UUID()))
        guard case .rejected(let rejection)? = notFound else { return XCTFail("expected a definitive NOT_FOUND") }
        XCTAssertEqual(rejection.code, .notFound)
    }

    // MARK: - Missing / malformed responses never count as success

    func testMalformedMutationRepliesAreUnknownOutcomesNotSuccessOrRejection() async throws {
        let rig = makeRig()
        let sid = UUID(), aid = UUID(), op = UUID()
        let sent = envelope(.discardActivityAnswers(activityID: aid), session: sid, operation: op, expected: 4)
        @Sendable func good(_ mutate: (inout [String: Any]) -> Void = { _ in }) -> Any {
            let discarded = activityJSON(id: aid, status: "stopped", stopReason: "discarded", result: ["discarded": true], lastRevision: 5)
            let snapshot = snapshotJSON(session: sessionJSON(id: sid, revision: 5), activities: [discarded])
            var body = successJSON(operation: lower(op), kind: "discard_activity_answers", revision: 5, snapshot: snapshot, activity: aid)
            mutate(&body)
            return body
        }
        func withSnapshot(_ edit: @escaping (inout [String: Any]) -> Void) -> Any {
            good { body in
                var snapshot = body["snapshot"] as! [String: Any]
                edit(&snapshot)
                body["snapshot"] = snapshot
            }
        }
        let wrongSessionSnapshot = snapshotJSON(session: sessionJSON(id: UUID(), revision: 5), activities: [])
        let cases: [(String, CloudStubReply)] = [
            ("empty object", .json(200, [String: Any]())),
            ("array body", .json(200, [Any]())),
            ("not json", .raw(200, "<html>ok</html>")),
            ("truncated", .raw(200, "{\"ok\":true,\"operation_id\":\"")),
            ("empty body", .raw(200, "")),
            ("ok false", .json(200, good { $0["ok"] = false })),
            ("missing ok", .json(200, good { $0["ok"] = nil })),
            ("missing snapshot", .json(200, good { $0["snapshot"] = nil })),
            ("null snapshot", .json(200, good { $0["snapshot"] = NSNull() })),
            ("missing revision", .json(200, good { $0["revision"] = nil })),
            ("zero revision", .json(200, good { $0["revision"] = 0 })),
            ("string revision", .json(200, good { $0["revision"] = "5" })),
            ("missing event_id key", .json(200, good { $0["event_id"] = nil })),
            ("sync pending", .json(200, good { $0["sync_status"] = "pending" })),
            ("missing sync_status", .json(200, good { $0["sync_status"] = nil })),
            ("other operation", .json(200, good { $0["operation_id"] = lower(UUID()) })),
            ("other kind", .json(200, good { $0["kind"] = "delete_session" })),
            ("bad server_time", .json(200, good { $0["server_time"] = "yesterday" })),
            ("other session", .json(200, good { $0["snapshot"] = wrongSessionSnapshot })),
            ("snapshot behind revision", .json(200, withSnapshot { $0["session"] = sessionJSON(id: sid, revision: 4, selected: aid) })),
            ("activity missing", .json(200, withSnapshot { $0["activities"] = [Any]() })),
            ("bad activity status", .json(200, withSnapshot { $0["activities"] = [activityJSON(id: aid, status: "exploded")] })),
            ("bad activity uuid", .json(200, withSnapshot { var a = activityJSON(id: aid); a["id"] = "not-a-uuid"; $0["activities"] = [a] })),
            ("kind/template mismatch", .json(200, withSnapshot { $0["activities"] = [activityJSON(id: aid, template: "choose_step_v1", kind: "grounding")] })),
            ("two in progress", .json(200, withSnapshot { $0["activities"] = [activityJSON(id: aid), activityJSON()] })),
            ("completed without finished_at", .json(200, withSnapshot { var a = activityJSON(id: aid, status: "completed"); a["finished_at"] = NSNull(); $0["activities"] = [a] })),
            ("missing privacy_revision", .json(200, withSnapshot { $0["privacy_revision"] = nil })),
            ("unknown scope", .json(200, withSnapshot { var s = sessionJSON(id: sid, revision: 5, selected: aid); s["context_scope"] = "everything"; $0["session"] = s })),
            ("missing nullable key", .json(200, withSnapshot { var s = sessionJSON(id: sid, revision: 5, selected: aid); s["closed_at"] = nil; $0["session"] = s })),
            ("title too long", .json(200, withSnapshot { $0["session"] = sessionJSON(id: sid, revision: 5, selected: aid, title: String(repeating: "x", count: 81)) })),
        ]
        for (name, reply) in cases {
            rig.stub.respond { _ in reply }
            let error = await expectError(try await rig.service.mutate(sent))
            guard case .malformedResponse? = error else { XCTFail("\(name): expected malformedResponse, got \(String(describing: error))"); continue }
            XCTAssertEqual(error?.attemptOutcome, .transientFailure, "\(name): outcome unknown -> replay the same operation ID")
            XCTAssertEqual(error?.isDefinitiveRejection, false)
        }
        XCTAssertEqual(rig.stub.requests.count, cases.count, "one request per attempt; the adapter never retries")
        // The control reply IS accepted, proving the cases above fail for their stated reason only.
        rig.stub.respond { _ in .json(200, good()) }
        let result = try await rig.service.mutate(sent)
        XCTAssertEqual(result.attemptOutcome, .confirmed(revision: 5))
    }

    // MARK: - Conflict, rejection, auth, transient: definitive vs unknown

    func testRevisionConflictIsDefinitiveAndCarriesTheCurrentSnapshot() async throws {
        let rig = makeRig()
        let sid = UUID(), aid = UUID()
        let current = snapshotJSON(session: sessionJSON(id: sid, revision: 9, selected: aid, scope: "personalized"), activities: [activityJSON(id: aid, status: "paused")])
        rig.stub.respond { _ in .json(409, ["ok": false, "code": "REVISION_CONFLICT", "current_revision": 9, "snapshot": current]) }
        let result = try await rig.service.mutate(envelope(.deleteSession, session: sid, expected: 4))
        guard case .conflict(let conflict) = result else { return XCTFail("expected a conflict") }
        XCTAssertEqual(conflict.currentRevision, 9)
        XCTAssertEqual(conflict.snapshot?.session.revision, 9)
        XCTAssertEqual(conflict.snapshot?.session.contextScope, .personalized)
        XCTAssertEqual(result.attemptOutcome, .revisionConflict(currentRevision: 9))
        let remote = try rig.service.remoteSnapshot(from: try XCTUnwrap(conflict.snapshot))
        XCTAssertEqual(remote.revision, 9)
        XCTAssertEqual(remote.activities.first?.status, .paused)

        // A conflict whose body disagrees with itself is not trusted as definitive.
        let bad: [Any] = [
            ["ok": false, "code": "REVISION_CONFLICT", "snapshot": current],
            ["ok": false, "code": "REVISION_CONFLICT", "current_revision": 8, "snapshot": current],
            ["ok": false, "code": "REVISION_CONFLICT", "current_revision": 0],
            ["ok": false, "code": "REVISION_CONFLICT", "current_revision": 9,
             "snapshot": snapshotJSON(session: sessionJSON(id: UUID(), revision: 9))],
        ]
        for body in bad {
            rig.stub.respond { _ in .json(409, body) }
            let error = await expectError(try await rig.service.mutate(envelope(.deleteSession, session: sid, expected: 4)))
            guard case .malformedResponse? = error else { return XCTFail("expected malformedResponse for \(body)") }
        }
    }

    func testOtherConflictCodesAreRejectionsNotRevisionConflicts() async throws {
        let rig = makeRig()
        let sent = envelope(.deleteSession, session: UUID(), expected: 4)
        rig.stub.respond { _ in .json(409, ["ok": false, "code": "OPERATION_ID_REUSED", "message": "operation_id was already used for a different request"]) }
        var error = await expectError(try await rig.service.mutate(sent))
        guard case .rejected(let reused)? = error else { return XCTFail("expected a rejection") }
        XCTAssertEqual(reused.code, .operationIDReused)
        XCTAssertEqual(error?.attemptOutcome, .rejected(code: "OPERATION_ID_REUSED"))
        XCTAssertEqual(error?.isDefinitiveRejection, true)

        rig.stub.respond { _ in .json(409, ["ok": false, "code": "PRIVACY_REVISION_STALE", "current_privacy_revision": 12]) }
        error = await expectError(try await rig.service.mutate(sent))
        guard case .rejected(let stale)? = error else { return XCTFail("expected a rejection") }
        XCTAssertEqual(stale.code, .privacyRevisionStale)
        XCTAssertEqual(stale.currentPrivacyRevision, 12)

        for (status, code) in [(400, "INVALID_PAYLOAD"), (404, "NOT_FOUND"), (409, "PROPOSAL_EXPIRED"), (422, "CONTENT_UNAVAILABLE"),
                               (402, "ENTITLEMENT_REQUIRED"), (409, "MEMORY_LIMIT_REACHED")] {
            rig.stub.respond { _ in .json(status, ["ok": false, "code": code]) }
            error = await expectError(try await rig.service.mutate(sent))
            XCTAssertEqual(error?.attemptOutcome, .rejected(code: code), code)
        }
        // A 409 that is not the contract's body proves nothing.
        rig.stub.respond { _ in .raw(409, "conflict") }
        error = await expectError(try await rig.service.mutate(sent))
        guard case .malformedResponse? = error else { return XCTFail("a non-contract 409 is not a definitive answer") }
    }

    func testAuthFailuresAreRetryableBindingErrorsNotRejectionsAndNeverFallBack() async throws {
        let rig = makeRig()
        let sent = envelope(.deleteSession, session: UUID(), expected: 4)
        let cases: [(CloudStubReply, SupportCloudAuthReason)] = [
            (.json(401, ["code": 401, "message": "Invalid JWT"]), .unauthorized),
            (.json(401, ["msg": "JWT expired"]), .expiredToken),
            (.json(401, ["message": "Token has expired", "error": "invalid_token"]), .expiredToken),
            (.json(403, ["message": "forbidden"]), .forbidden),
            (.json(401, ["ok": false, "code": "AUTH_REQUIRED"]), .unauthorized),
            (.raw(401, ""), .unauthorized),
        ]
        for (reply, reason) in cases {
            rig.stub.respond { _ in reply }
            let error = await expectError(try await rig.service.mutate(sent))
            XCTAssertEqual(error, .authenticationRequired(reason))
            XCTAssertEqual(error?.attemptOutcome, .transientFailure, "auth is retryable with the same operation ID after repair")
            XCTAssertEqual(error?.isDefinitiveRejection, false)
        }
        XCTAssertEqual(rig.stub.requests.count, cases.count, "no automatic re-auth or retry inside the adapter")

        let noSession = makeRig(token: { _ in nil })
        await expectError(.authenticationRequired(.noSession), try await noSession.service.capabilities())
        XCTAssertTrue(noSession.stub.requests.isEmpty)
        struct Boom: Error {}
        let failing = makeRig(token: { _ in throw Boom() })
        await expectError(.authenticationRequired(.tokenUnavailable), try await failing.service.capabilities())
        XCTAssertTrue(failing.stub.requests.isEmpty)
    }

    func testTimeoutsAndServerErrorsAreUnknownOutcomesNeverDefinitiveRejections() async throws {
        let rig = makeRig()
        let sent = envelope(.deleteSession, session: UUID(), expected: 4)
        let cases: [(CloudStubReply, SupportCloudError)] = [
            (.failure(.timedOut), .transport(.timeout)),
            (.failure(.notConnectedToInternet), .transport(.offline)),
            (.failure(.networkConnectionLost), .transport(.connectionLost)),
            (.failure(.secureConnectionFailed), .transport(.secureConnection)),
            (.json(503, ["ok": false, "code": "TEMPORARY_FAILURE"]), .serverTemporary(status: 503, retryAfter: nil)),
            (.raw(502, "<html>bad gateway</html>"), .serverTemporary(status: 502, retryAfter: nil)),
            (.raw(504, ""), .serverTemporary(status: 504, retryAfter: nil)),
            (.json(429, ["ok": false, "code": "RATE_LIMITED", "retry_after_seconds": 12], headers: ["Retry-After": "7"]), .serverTemporary(status: 429, retryAfter: 7)),
            (.json(429, ["ok": false, "code": "RATE_LIMITED", "retry_after_seconds": 12]), .serverTemporary(status: 429, retryAfter: 12)),
        ]
        for (reply, expected) in cases {
            rig.stub.respond { _ in reply }
            let error = await expectError(try await rig.service.mutate(sent))
            XCTAssertEqual(error, expected)
            XCTAssertEqual(error?.attemptOutcome, .transientFailure)
            XCTAssertEqual(error?.isDefinitiveRejection, false, "a timeout/5xx must never mark work as rejected")
        }
        XCTAssertEqual(rig.stub.requests.count, cases.count, "exactly one request per call: no hidden retry")
    }

    // MARK: - get / list / paging

    func testGetReturnsSnapshotAndEventPageWithStableResumePoint() async throws {
        let rig = makeRig()
        let sid = UUID(), aid = UUID()
        @Sendable func event(_ seq: Int, _ kind: String = "activity_checkpointed") -> [String: Any] {
            ["id": lower(UUID()), "activity_id": lower(aid), "operation_id": lower(UUID()), "kind": kind, "seq": seq,
             "client_occurred_at": NSNull(), "accepted_at": stamp, "payload": ["active_ms": seq * 1000]]
        }
        let snapshot = snapshotJSON(session: sessionJSON(id: sid, revision: 7, selected: aid), activities: [activityJSON(id: aid)])
        rig.stub.respond { _ in .json(200, ["ok": true, "snapshot": snapshot, "events": [event(5), event(6), event(7, "activity_paused")], "server_time": stamp]) }
        let detail = try await rig.service.get(sessionID: sid, afterSequence: 4, limit: 3)
        let request = try XCTUnwrap(rig.stub.requests.first)
        XCTAssertEqual(request.json["op"] as? String, "get")
        XCTAssertEqual(request.json["session_id"] as? String, lower(sid))
        XCTAssertEqual(request.json["after_seq"] as? Int, 4)
        XCTAssertEqual(request.json["limit"] as? Int, 3)
        XCTAssertEqual(request.json["schema_version"] as? Int, 1)
        XCTAssertEqual(detail.events.map(\.sequence), [5, 6, 7])
        XCTAssertEqual(detail.events.last?.kind, .activityPaused)
        XCTAssertEqual(detail.nextAfterSequence, 7)
        XCTAssertTrue(detail.mayHaveMoreEvents(limit: 3))
        XCTAssertFalse(detail.mayHaveMoreEvents(limit: 50))
        XCTAssertEqual(detail.snapshot.session.revision, 7)

        let bad: [(String, [Any])] = [
            ("not ascending", [event(6), event(5)]),
            ("not after cursor", [event(4)]),
            ("duplicate sequence", [event(5), event(5)]),
            ("unknown kind", [event(5, "mystery")]),
            ("over limit", [event(5), event(6), event(7), event(8)]),
        ]
        for (name, events) in bad {
            rig.stub.respond { _ in .json(200, ["ok": true, "snapshot": snapshot, "events": events, "server_time": stamp]) }
            let error = await expectError(try await rig.service.get(sessionID: sid, afterSequence: 4, limit: 3))
            guard case .malformedResponse? = error else { XCTFail("\(name): expected malformed, got \(String(describing: error))"); continue }
        }
        rig.stub.respond { _ in .json(200, ["ok": true, "snapshot": snapshotJSON(session: sessionJSON(id: UUID(), revision: 7)), "events": [Any](), "server_time": stamp]) }
        guard case .malformedResponse? = await expectError(try await rig.service.get(sessionID: sid)) else { return XCTFail("session echo mismatch must be malformed") }
        let before = rig.stub.requests.count
        await expectError(.invalidRequest(.numberOutOfRange(field: "after_seq")), try await rig.service.get(sessionID: sid, afterSequence: -1))
        await expectError(.invalidRequest(.numberOutOfRange(field: "limit")), try await rig.service.get(sessionID: sid, limit: 201))
        XCTAssertEqual(rig.stub.requests.count, before, "invalid parameters never reach the wire")
    }

    func testListUsesTheServersExactCursorStringAndFilters() async throws {
        let rig = makeRig()
        let first = UUID(), second = UUID()
        let microseconds = "2026-11-06T23:00:00.123456+00:00"
        @Sendable func summary(_ id: UUID, _ updated: String, status: String = "open") -> [String: Any] {
            ["id": lower(id), "conversation_id": NSNull(), "previous_session_id": NSNull(), "title": "Item", "status": status,
             "context_scope": "conversation_only", "revision": 3, "selected_activity_id": NSNull(), "created_at": stamp, "updated_at": updated,
             "closed_at": NSNull(), "deleted_at": NSNull(), "unfinished_count": 1, "selected_activity": NSNull()]
        }
        let nextCursor: [String: Any] = ["updated_at": microseconds, "id": lower(second)]
        rig.stub.respond { _ in .json(200, ["ok": true, "items": [summary(first, "2026-11-06T23:30:00.9+00:00"), summary(second, microseconds)],
                                          "next_cursor": nextCursor, "privacy_revision": 2, "server_time": stamp]) }
        let page = try await rig.service.list(limit: 2)
        var request = try XCTUnwrap(rig.stub.requests.last)
        XCTAssertEqual(Set(request.json.keys), ["op", "schema_version", "limit", "direction", "include_deleted"], "no cursor on the first page")
        XCTAssertEqual(request.json["direction"] as? String, "desc")
        XCTAssertEqual(request.json["include_deleted"] as? Bool, false)
        XCTAssertEqual(page.items.map(\.id), [first, second])
        XCTAssertEqual(page.nextCursor?.updatedAt, microseconds, "microsecond precision survives")
        XCTAssertEqual(page.nextCursor?.id, second)
        XCTAssertEqual(page.items[1].cursor, page.nextCursor, "an item's own cursor equals the server's cursor")

        rig.stub.respond { _ in .json(200, ["ok": true, "items": [Any](), "next_cursor": NSNull(), "privacy_revision": 2, "server_time": stamp]) }
        let last = try await rig.service.list(limit: 2, cursor: page.nextCursor, status: .open, direction: .ascending, includeDeleted: true)
        request = try XCTUnwrap(rig.stub.requests.last)
        let cursor = try XCTUnwrap(request.json["cursor"] as? [String: String])
        XCTAssertEqual(cursor, ["updated_at": microseconds, "id": lower(second)], "cursor is echoed verbatim, not re-formatted")
        XCTAssertEqual(request.json["status"] as? String, "open")
        XCTAssertEqual(request.json["direction"] as? String, "asc")
        XCTAssertEqual(request.json["include_deleted"] as? Bool, true)
        XCTAssertNil(last.nextCursor)

        let before = rig.stub.requests.count
        await expectError(.invalidRequest(.numberOutOfRange(field: "limit")), try await rig.service.list(limit: 0))
        await expectError(.invalidRequest(.numberOutOfRange(field: "limit")), try await rig.service.list(limit: 101))
        assertCloudThrows(try SupportCloudListCursor(updatedAt: "not a date", id: UUID()))
        XCTAssertEqual(rig.stub.requests.count, before)

        let bad: [[String: Any]] = [
            ["ok": true, "items": [summary(first, stamp), summary(first, stamp)], "next_cursor": NSNull(), "privacy_revision": 2, "server_time": stamp],
            ["ok": true, "items": [Any](), "next_cursor": nextCursor, "privacy_revision": 2, "server_time": stamp],
            ["ok": true, "items": [summary(first, stamp)], "privacy_revision": 2, "server_time": stamp],
            ["ok": true, "items": [summary(first, stamp)], "next_cursor": ["updated_at": "nope", "id": lower(second)], "privacy_revision": 2, "server_time": stamp],
            ["ok": true, "items": [summary(first, stamp)], "next_cursor": ["updated_at": microseconds], "privacy_revision": 2, "server_time": stamp],
            ["ok": true, "items": [summary(first, stamp, status: "weird")], "next_cursor": NSNull(), "privacy_revision": 2, "server_time": stamp],
        ]
        for body in bad {
            rig.stub.respond { _ in .json(200, body) }
            guard case .malformedResponse? = await expectError(try await rig.service.list()) else { return XCTFail("expected malformed for \(body)") }
        }
    }

    // MARK: - Context receipt

    func testReceiptRemovedSourcesShowNoDetailAndMissingReceiptIsAnOlderReply() async throws {
        let rig = makeRig()
        let request = UUID(), memory = UUID(), message = UUID(), conversation = UUID()
        @Sendable func receipt(sources: Any, omitting: String? = nil, requestID: UUID? = nil) -> [String: Any] {
            var inner: [String: Any] = [
                "schema_version": 1, "receipt_id": lower(UUID()), "request_id": lower(requestID ?? request), "support_session_id": NSNull(),
                "conversation_id": lower(conversation), "assistant_message_id": lower(UUID()), "privacy_revision": 4, "scope": "personalized",
                "provider": ["vendor": "openai", "model": "gpt-6-luna", "route_version": "v1"], "sources": sources,
                "exclusions": ["health_data"], "created_at": stamp]
            if let omitting { inner[omitting] = nil }
            return ["ok": true, "receipt": inner]
        }
        let sources: [[String: Any]] = [
            ["kind": "companion_memory", "id": lower(memory), "revision_at_send": 2, "date": stamp, "state": "removed", "label": "boundaries"],
            ["kind": "message", "id": lower(message), "revision_at_send": 0, "date": NSNull(), "state": "available", "label": NSNull()],
            ["kind": "safety_policy", "id": "00000000-0000-0000-0000-000000000001", "revision_at_send": 0, "date": NSNull(), "state": "available", "label": NSNull()],
        ]
        rig.stub.respond { _ in .json(200, receipt(sources: sources)) }
        guard case .available(let result) = try await rig.service.receipt(requestID: request) else { return XCTFail("expected a receipt") }
        XCTAssertEqual(rig.stub.requests.last?.json as? [String: String], ["op": "receipt", "request_id": lower(request)])
        XCTAssertEqual(result.scope, .personalized)
        XCTAssertEqual(result.provider, SupportCloudContextProvider(vendor: "openai", model: "gpt-6-luna", routeVersion: "v1"))
        XCTAssertEqual(result.exclusions, ["health_data"])
        XCTAssertEqual(result.sources.map(\.kind), [.companionMemory, .message, .safetyPolicy])
        XCTAssertEqual(result.sources[0].state, .removed)
        XCTAssertNil(result.sources[0].label, "a removed source carries no resurrected detail")
        XCTAssertEqual(result.sources[0].revisionAtSend, 2)
        XCTAssertNil(result.supportSessionID)

        rig.stub.respond { _ in .json(404, ["ok": false, "code": "NOT_FOUND"]) }
        let older = try await rig.service.receipt(requestID: request)
        XCTAssertEqual(older, .unavailableOlderReply, "missing receipt is 'details unavailable for this older reply', not 'no memory used'")

        for body in [receipt(sources: sources, omitting: "sources"), receipt(sources: sources, omitting: "provider"),
                     receipt(sources: sources, omitting: "privacy_revision"), receipt(sources: sources, omitting: "assistant_message_id"),
                     receipt(sources: sources, requestID: UUID()), receipt(sources: [["kind": "mystery", "id": lower(UUID()), "revision_at_send": 0, "date": NSNull(), "state": "available", "label": NSNull()]]),
                     receipt(sources: [["kind": "message", "id": lower(UUID()), "revision_at_send": 0, "date": NSNull(), "state": "gone", "label": NSNull()]])] {
            rig.stub.respond { _ in .json(200, body) }
            guard case .malformedResponse? = await expectError(try await rig.service.receipt(requestID: request)) else { return XCTFail("a partial receipt must not be accepted") }
        }
        rig.stub.respond { _ in .json(404, ["code": "NOT_FOUND", "message": "Requested function was not found"]) }
        await expectError(.capabilityUnavailable(.functionNotDeployed), try await rig.service.receipt(requestID: request))
    }

    // MARK: - Memory

    func testListMemoryDecodesCanonicalMemoryAndRejectsPartialShapes() async throws {
        let rig = makeRig()
        let memory = UUID(), fragment = UUID(), intent = UUID(), source = UUID()
        @Sendable func page(daily: Any = NSNull(), saved: [[String: Any]]? = nil) -> [String: Any] {
            let savedRows = saved ?? [["id": lower(memory), "category": "avoid_topics", "content": "No breath counting", "origin": "user_authored", "revision": 2,
                                       "state": "stale", "confirmed_at": stamp, "review_due_at": NSNull(), "expires_at": NSNull(), "disabled_at": NSNull(),
                                       "last_used_at": NSNull(), "source_message_id": lower(source)]]
            return ["ok": true, "privacy_revision": 6, "max_confirmed": 20, "saved": savedRows,
                    "candidates": [["id": lower(fragment), "fragment_type": "preference", "value": "Likes walks", "review_state": "legacy_review",
                                    "provenance": "unknown", "source_message_id": NSNull(), "source_conversation_id": NSNull(),
                                    "candidate_expires_at": NSNull(), "extracted_at": stamp]],
                    "daily_intent": daily, "server_time": stamp]
        }
        rig.stub.respond { _ in .json(200, page()) }
        var decoded = try await rig.service.listMemory()
        XCTAssertEqual(rig.stub.requests.last?.json as? [String: String], ["op": "memory_list"])
        XCTAssertEqual(decoded.privacyRevision, 6)
        XCTAssertEqual(decoded.maxConfirmed, 20)
        XCTAssertEqual(decoded.saved.first?.category, .avoidTopics)
        XCTAssertEqual(decoded.saved.first?.state, .stale)
        XCTAssertEqual(decoded.saved.first?.revision, 2)
        XCTAssertEqual(decoded.saved.first?.sourceMessageID, source)
        XCTAssertEqual(decoded.candidates.first?.provenance, .unknown)
        XCTAssertEqual(decoded.candidates.first?.reviewState, .legacyReview)
        XCTAssertNil(decoded.dailyIntent)
        rig.stub.respond { _ in .json(200, page(daily: ["id": lower(intent), "intent": "Rest", "created_at": stamp, "expires_at": "2026-11-07T23:00:00Z"])) }
        decoded = try await rig.service.listMemory()
        XCTAssertEqual(decoded.dailyIntent?.id, intent)

        var broken = page(); broken["privacy_revision"] = nil
        var noIntentKey = page(); noIntentKey["daily_intent"] = nil
        var badCategory = page(saved: [["id": lower(memory), "category": "secrets", "content": "x", "origin": "user_authored", "revision": 1, "state": "confirmed",
                                        "confirmed_at": NSNull(), "review_due_at": NSNull(), "expires_at": NSNull(), "disabled_at": NSNull(),
                                        "last_used_at": NSNull(), "source_message_id": NSNull()]])
        badCategory["ok"] = true
        for body in [broken, noIntentKey, badCategory] {
            rig.stub.respond { _ in .json(200, body) }
            guard case .malformedResponse? = await expectError(try await rig.service.listMemory()) else { return XCTFail("expected malformed") }
        }
    }

    func testMemoryMutationsEncodeImmutablePayloadsAndReturnTheOperationsPrivacyRevision() async throws {
        let rig = makeRig()
        let memory = UUID(), fragment = UUID(), source = UUID()
        @Sendable func reply(_ request: CloudStubRequest, extra: [String: Any] = [:], replayed: Bool = false) -> CloudStubReply {
            var body: [String: Any] = ["ok": true, "operation_id": request.json["operation_id"] as Any, "kind": request.json["kind"] as Any,
                                       "privacy_revision": 11, "replayed": replayed, "server_time": stamp]
            body.merge(extra) { $1 }
            return .json(200, body)
        }
        let cases: [(SupportCloudMemoryOperation, String, [String: Any], [String: Any])] = [
            (.edit(memoryID: memory, content: "Prefers short steps", category: .preferences, expectedRevision: 2), "memory_edit",
             ["memory_id": lower(memory), "content": "Prefers short steps", "category": "preferences", "expected_revision": 2], ["memory_id": lower(memory), "memory_revision": 3]),
            (.stopUsing(memoryID: memory, expectedRevision: nil), "memory_stop_using", ["memory_id": lower(memory)], ["memory_id": lower(memory)]),
            (.resumeUsing(memoryID: memory, expectedRevision: 3), "memory_resume_using", ["memory_id": lower(memory), "expected_revision": 3], ["memory_id": lower(memory)]),
            (.forgetMemory(memoryID: memory), "memory_forget", ["memory_id": lower(memory)], ["memory_id": lower(memory), "suppressed_turns": 2]),
            (.forgetCandidate(fragmentID: fragment), "memory_forget", ["fragment_id": lower(fragment)],
             ["fragment_id": lower(fragment), "memory_id": NSNull(), "suppressed_turns": 0, "conversation_scope_excluded": true]),
            (.approveCandidate(fragmentID: fragment, editedContent: nil), "candidate_approve", ["fragment_id": lower(fragment)], ["fragment_id": lower(fragment), "memory_id": lower(memory)]),
            (.approveCandidate(fragmentID: fragment, editedContent: "Edited"), "candidate_approve", ["fragment_id": lower(fragment), "content": "Edited"], ["fragment_id": lower(fragment), "memory_id": lower(memory)]),
            (.dismissCandidate(fragmentID: fragment), "candidate_dismiss", ["fragment_id": lower(fragment)], ["fragment_id": lower(fragment)]),
            (.suppressSource(kind: .conversation, id: source), "suppress_source", ["source_kind": "conversation", "id": lower(source)], ["source_kind": "conversation", "id": lower(source), "suppressed_turns": 4]),
            (.unsuppressSource(kind: .message, id: source), "unsuppress_source", ["source_kind": "message", "id": lower(source)], ["source_kind": "message", "id": lower(source)]),
        ]
        for (operation, wireKind, payload, extra) in cases {
            let mutation = try SupportCloudMemoryMutation(operationID: UUID(), operation: operation)
            rig.stub.respond { reply($0, extra: extra) }
            let result = try await rig.service.mutateMemory(mutation)
            guard case .confirmed(let receipt) = result else { return XCTFail("expected confirmation for \(wireKind)") }
            XCTAssertEqual(receipt.privacyRevision, 11, "the reply carries the privacy revision recorded with THIS operation")
            XCTAssertFalse(receipt.privacyRevisionIsHistorical, "a first application is not a replayed receipt")
            XCTAssertEqual(receipt.operationID, mutation.operationID)
            XCTAssertEqual(result.attemptOutcome, .confirmed(revision: 11))
            let request = try XCTUnwrap(rig.stub.requests.last)
            XCTAssertEqual(Set(request.json.keys), ["op", "schema_version", "operation_id", "kind", "payload"])
            XCTAssertEqual(request.json["op"] as? String, "memory_mutate")
            XCTAssertEqual(request.json["kind"] as? String, wireKind)
            XCTAssertEqual(NSDictionary(dictionary: request.payload), NSDictionary(dictionary: payload), wireKind)
            XCTAssertEqual(request.body, try mutation.requestData(), "bytes are fixed at construction: replay cannot change the payload")
        }
        let forgot = try SupportCloudMemoryMutation(operationID: UUID(), operation: .forgetCandidate(fragmentID: fragment))
        rig.stub.respond { reply($0, extra: ["fragment_id": lower(fragment), "memory_id": NSNull(), "suppressed_turns": 3, "conversation_scope_excluded": true]) }
        guard case .confirmed(let receipt) = try await rig.service.mutateMemory(forgot) else { return XCTFail() }
        XCTAssertEqual(receipt.suppressedTurns, 3)
        XCTAssertEqual(receipt.conversationScopeExcluded, true)
        XCTAssertNil(receipt.memoryID)
        // A confirmed replay returns the STORED receipt (forget is never a no-op), so it carries the same target fields.
        rig.stub.respond { reply($0, extra: ["fragment_id": lower(fragment), "memory_id": NSNull(), "suppressed_turns": 3, "conversation_scope_excluded": true], replayed: true) }
        guard case .confirmed(let replay) = try await rig.service.mutateMemory(forgot) else { return XCTFail() }
        XCTAssertTrue(replay.replayed)
        XCTAssertFalse(replay.noOp)
        XCTAssertTrue(replay.privacyRevisionIsHistorical)
    }

    func testMemoryConflictAndMalformedAndInvalidMemoryRequests() async throws {
        let rig = makeRig()
        let memory = UUID()
        let edit = try SupportCloudMemoryMutation(operationID: UUID(), operation: .edit(memoryID: memory, content: "New", category: nil, expectedRevision: 2))
        rig.stub.respond { _ in .json(409, ["ok": false, "code": "REVISION_CONFLICT", "current_revision": 5,
                                          "memory": ["id": lower(memory), "category": "preferences", "content": "Current text", "revision": 5]]) }
        let result = try await rig.service.mutateMemory(edit)
        guard case .conflict(let conflict) = result else { return XCTFail("expected conflict") }
        XCTAssertEqual(conflict.currentRevision, 5)
        XCTAssertEqual(conflict.content, "Current text")
        XCTAssertEqual(result.attemptOutcome, .revisionConflict(currentRevision: 5))

        let bad: [CloudStubReply] = [
            .json(200, ["ok": true, "operation_id": lower(UUID()), "kind": "memory_edit", "privacy_revision": 2, "replayed": false, "server_time": stamp]),
            .json(200, ["ok": true, "operation_id": lower(edit.operationID), "kind": "memory_forget", "privacy_revision": 2, "replayed": false, "server_time": stamp]),
            .json(200, ["ok": true, "operation_id": lower(edit.operationID), "kind": "memory_edit", "replayed": false, "server_time": stamp]),
            .json(200, ["ok": true, "operation_id": lower(edit.operationID), "kind": "memory_edit", "privacy_revision": 0, "replayed": false, "server_time": stamp]),
            .json(200, ["ok": true, "operation_id": lower(edit.operationID), "kind": "memory_edit", "privacy_revision": 2, "server_time": stamp]),
            .json(409, ["ok": false, "code": "REVISION_CONFLICT", "current_revision": 5]),
            .json(409, ["ok": false, "code": "REVISION_CONFLICT", "current_revision": 5, "memory": ["id": lower(memory), "category": "preferences", "content": "x", "revision": 4]]),
        ]
        for reply in bad {
            rig.stub.respond { _ in reply }
            guard case .malformedResponse? = await expectError(try await rig.service.mutateMemory(edit)) else { return XCTFail("expected malformed") }
        }
        let before = rig.stub.requests.count
        assertCloudThrows(try SupportCloudMemoryMutation(operationID: UUID(), operation: .edit(memoryID: memory, content: "   ", category: nil, expectedRevision: 1)))
        assertCloudThrows(try SupportCloudMemoryMutation(operationID: UUID(), operation: .edit(memoryID: memory, content: String(repeating: "👍", count: 501), category: nil, expectedRevision: 1)))
        assertCloudThrows(try SupportCloudMemoryMutation(operationID: UUID(), operation: .edit(memoryID: memory, content: "ok", category: nil, expectedRevision: 0)))
        XCTAssertNoThrow(try SupportCloudMemoryMutation(operationID: UUID(), operation: .edit(memoryID: memory, content: String(repeating: "👍", count: 500), category: nil, expectedRevision: 1)))
        XCTAssertEqual(rig.stub.requests.count, before)
    }

    // MARK: - Encoding limits: Unicode scalars, unsupported shapes error instead of inventing a save

    func testUnsupportedOrOversizedLocalShapesFailBeforeAnyRequest() async throws {
        let rig = makeRig()
        let sid = UUID(), aid = UUID()
        let family = "👨‍👩‍👧"            // 5 Unicode scalars, ONE grapheme
        XCTAssertEqual(family.count, 1)
        XCTAssertEqual(family.unicodeScalars.count, 5)
        let step = { (text: String, state: SupportStepState) in SupportStepPayload(actionText: text, state: state) }
        let longResponses = Dictionary(uniqueKeysWithValues: ["see", "feel", "hear", "smell", "taste", "on_mind", "certain_unclear", "fairer_way", "action", "smaller"]
            .map { ($0, String(repeating: "a", count: 4_000)) })
        let cases: [(String, SupportMutationEnvelope, SupportCloudEncodingFailure)] = [
            ("reopen", envelope(.updateSession(title: nil, contextScope: nil, status: .open), session: sid), .unsupportedValue(field: "status")),
            ("deleted via update", envelope(.updateSession(title: nil, contextScope: nil, status: .deleted), session: sid), .unsupportedValue(field: "status")),
            ("title scalars", envelope(.create(title: String(repeating: family, count: 17), concern: nil, conversationID: nil, previousSessionID: nil, contextScope: .conversationOnly), session: sid), .valueTooLong(field: "title", limit: 80)),
            ("concern too long", envelope(.create(title: "t", concern: String(repeating: "c", count: 4_001), conversationID: nil, previousSessionID: nil, contextScope: .conversationOnly), session: sid), .valueTooLong(field: "concern", limit: 4_000)),
            ("template version", envelope(.startActivity(activityID: aid, templateKey: .groundPresentV1, templateVersion: 2, canonicalReference: nil), session: sid), .unsupportedTemplateVersion(2)),
            ("checkpoint status", envelope(.checkpointActivity(activityID: aid, status: .completed, checkpoint: SupportCheckpoint(), step: nil), session: sid), .unsupportedValue(field: "checkpoint.status")),
            ("unknown prompt", envelope(.checkpointActivity(activityID: aid, status: .inProgress, checkpoint: SupportCheckpoint(lastPromptID: "bogus"), step: nil), session: sid), .unknownPromptID("bogus")),
            ("unknown response id", envelope(.checkpointActivity(activityID: aid, status: .inProgress, checkpoint: SupportCheckpoint(responses: ["nope": "x"]), step: nil), session: sid), .unknownPromptID("nope")),
            ("response scalars", envelope(.checkpointActivity(activityID: aid, status: .inProgress, checkpoint: SupportCheckpoint(responses: ["see": String(repeating: "x", count: 4_001)]), step: nil), session: sid), .valueTooLong(field: "checkpoint.responses", limit: 4_000)),
            ("checkpoint 32 KiB", envelope(.checkpointActivity(activityID: aid, status: .inProgress, checkpoint: SupportCheckpoint(responses: longResponses), step: nil), session: sid), .tooLarge(field: "checkpoint", bytes: 0, limit: 32 * 1_024)),
            ("paused step not saved", envelope(.checkpointActivity(activityID: aid, status: .paused, checkpoint: SupportCheckpoint(), step: step("x", .selfReportedDone)), session: sid), .unsupportedValue(field: "checkpoint.step.state")),
            ("empty saved step", envelope(.checkpointActivity(activityID: aid, status: .paused, checkpoint: SupportCheckpoint(), step: step("  ", .saved)), session: sid), .emptyValue(field: "step.action_text")),
            ("step scalars", envelope(.checkpointActivity(activityID: aid, status: .paused, checkpoint: SupportCheckpoint(), step: step(String(repeating: "s", count: 401), .saved)), session: sid), .valueTooLong(field: "step.action_text", limit: 400)),
            ("finish status", envelope(.finishActivity(activityID: aid, status: .paused, result: SupportActivityResult(), step: nil, checkpoint: nil), session: sid), .unsupportedValue(field: "finish.status")),
            ("completed with reason", envelope(.finishActivity(activityID: aid, status: .completed, result: SupportActivityResult(stoppedReason: "skipped_all"), step: nil, checkpoint: nil), session: sid), .unsupportedValue(field: "result.stoppedReason")),
            ("reason too long", envelope(.finishActivity(activityID: aid, status: .stopped, result: SupportActivityResult(stoppedReason: String(repeating: "r", count: 41)), step: nil, checkpoint: nil), session: sid), .valueTooLong(field: "reason", limit: 40)),
            ("completed step not done", envelope(.finishActivity(activityID: aid, status: .completed, result: SupportActivityResult(), step: step("x", .saved), checkpoint: nil), session: sid), .unsupportedValue(field: "result.step.state")),
            ("stopped step not dismissed", envelope(.finishActivity(activityID: aid, status: .stopped, result: SupportActivityResult(), step: step("x", .saved), checkpoint: nil), session: sid), .unsupportedValue(field: "result.step.state")),
            ("negative active ms", envelope(.finishActivity(activityID: aid, status: .stopped, result: SupportActivityResult(activeMilliseconds: -1), step: nil, checkpoint: nil), session: sid), .numberOutOfRange(field: "active_ms")),
            ("note scalars", envelope(.recordReflection(activityID: aid, reflection: SupportReflection(outcome: .helpful, note: String(repeating: "n", count: 1_001), includeWrittenAnswers: false, recordedAt: Date())), session: sid), .valueTooLong(field: "note", limit: 1_000)),
            ("missing expected", SupportMutationEnvelope(schemaVersion: 1, operationID: UUID(), sessionID: sid, expectedRevision: nil, kind: .deleteSession, payload: .deleteSession, payloadFingerprint: "x"), .missingExpectedRevision),
            ("create with expected", SupportMutationEnvelope(schemaVersion: 1, operationID: UUID(), sessionID: sid, expectedRevision: 1, kind: .create, payload: .create(title: "t", concern: nil, conversationID: nil, previousSessionID: nil, contextScope: .conversationOnly), payloadFingerprint: "x"), .unexpectedExpectedRevision),
            ("zero expected", envelope(.deleteSession, session: sid, expected: 0), .invalidExpectedRevision(0)),
            ("schema 2", SupportMutationEnvelope(schemaVersion: 2, operationID: UUID(), sessionID: sid, expectedRevision: 1, kind: .deleteSession, payload: .deleteSession, payloadFingerprint: "x"), .schemaVersion(2)),
            ("kind mismatch", SupportMutationEnvelope(schemaVersion: 1, operationID: UUID(), sessionID: sid, expectedRevision: 1, kind: .create, payload: .deleteSession, payloadFingerprint: "x"), .unsupportedValue(field: "kind")),
        ]
        for (name, sent, expected) in cases {
            let error = await expectError(try await rig.service.mutate(sent))
            guard case .invalidRequest(let failure)? = error else { XCTFail("\(name): expected invalidRequest, got \(String(describing: error))"); continue }
            if case .tooLarge(let field, _, let limit) = expected, case .tooLarge(let gotField, _, let gotLimit) = failure {
                XCTAssertEqual(field, gotField); XCTAssertEqual(limit, gotLimit)
            } else {
                XCTAssertEqual(failure, expected, name)
            }
            XCTAssertEqual(error?.attemptOutcome, .rejected(code: "CLIENT_ENCODING_FAILED"))
        }
        XCTAssertTrue(rig.stub.requests.isEmpty, "nothing unencodable is ever sent")
        XCTAssertEqual(rig.tokenCalls.value, 0, "encoding is validated before any token is fetched")
        // 16 family emoji are exactly 80 scalars (the limit) and are accepted: scalars, not graphemes, are counted.
        rig.stub.respond { echoSuccess($0) }
        _ = try await rig.service.mutate(envelope(.create(title: String(repeating: family, count: 16), concern: nil, conversationID: nil, previousSessionID: nil, contextScope: .conversationOnly), session: sid))
        XCTAssertEqual(rig.stub.requests.count, 1)
    }

    // MARK: - JSON writer / dates

    func testStableJSONSortsKeysEscapesAndMeasuresJsonbBytes() throws {
        let value = SupportCloudJSON.object(["b": .array([.int(1), .int(2)]), "a": .int(1), "é": .string("x\u{07}\"\\\n/")])
        XCTAssertEqual(String(decoding: try value.stableData(), as: UTF8.self), "{\"a\":1,\"b\":[1,2],\"é\":\"x\\u0007\\\"\\\\\\n/\"}")
        XCTAssertEqual(try SupportCloudJSON.object(["a": .int(1), "b": .array([.int(1), .int(2)])]).jsonbByteCount(), "{\"a\": 1, \"b\": [1, 2]}".utf8.count)
        XCTAssertEqual(try value.stableData(), try value.stableData())
        assertCloudThrows(try SupportCloudJSON.double(1.5).stableData())
    }

    func testISODatesParseWithAndWithoutFractionsAndAnyOffset() throws {
        let base = utc(2026, 11, 6, 23, 0, 0).timeIntervalSince1970
        let cases: [(String, Double)] = [
            ("2026-11-06T23:00:00Z", base),
            ("2026-11-06T23:00:00z", base),
            ("2026-11-06T23:00:00.5Z", base + 0.5),
            ("2026-11-06T23:00:00.123Z", base + 0.123),
            ("2026-11-06T23:00:00.123456+00:00", base + 0.123456),
            ("2026-11-06T23:00:00.123456789Z", base + 0.123456789),
            ("2026-11-06T23:00:00.1234567891234Z", base + 0.1234567891),
            ("2026-11-06 23:00:00+00", base),
            ("2026-11-07T04:30:00+05:30", base),
            ("2026-11-06T15:00:00-0800", base),
            ("2026-11-06T18:00:00-05", base),
            ("2028-02-29T00:00:00Z", utc(2028, 2, 29).timeIntervalSince1970),
            ("1999-12-31T23:59:59Z", utc(1999, 12, 31, 23, 59, 59).timeIntervalSince1970),
        ]
        for (text, expected) in cases {
            let parsed = try XCTUnwrap(SupportCloudDate.parse(text), text)
            XCTAssertEqual(parsed.timeIntervalSince1970, expected, accuracy: 0.000_01, text)
        }
        for text in ["", "2026-11-06", "2026-11-06T23:00:00", "2026-11-06T23:00:00.Z", "2026-13-06T23:00:00Z", "2026-11-31T23:00:00Z",
                     "2027-02-29T00:00:00Z", "2026-11-06T24:00:00Z", "2026-11-06T23:60:00Z", "2026-11-06T23:00:00+24:00", "2026-11-06T23:00:00+05:7",
                     "2026-11-06T23:00:00Zjunk", "yesterday", "2026-11-06T23:00:00 +00:00 extra"] {
            XCTAssertNil(SupportCloudDate.parse(text), text)
        }
    }

    // MARK: - Wire → local domain

    func testSnapshotConvertsToTheRepositorySnapshotWithTheCapturedOwner() async throws {
        let rig = makeRig()
        let sid = UUID(), grounding = UUID(), untangle = UUID(), saved = UUID(), done = UUID(), exercise = UUID(), conversation = UUID()
        let groundingCheckpoint: [String: Any] = [
            "version": 1, "template_version": 1, "current_step": "taste", "completed_steps": ["see", "feel", "hear", "smell"], "skipped_steps": ["taste"],
            "responses": ["see": "window"]]
        let activities: [[String: Any]] = [
            activityJSON(id: grounding, status: "completed", ref: exercise, checkpoint: groundingCheckpoint,
                         result: ["acknowledged_count": 4, "skipped_count": 1, "shareable_note": "Grounded"],
                         reflection: ["outcome": "helpful", "note": "calmer", "share_note": false, "shareable_text": NSNull()], activeMs: 90_000, lastRevision: 6),
            activityJSON(id: untangle, template: "untangle_thought_v1", kind: "untangle", status: "paused",
                         checkpoint: ["version": 1, "template_version": 1, "current_step": "certain_unclear", "completed_steps": ["on_mind"],
                                      "responses": ["on_mind": "private words"]], activeMs: 4_000, lastRevision: 5),
            activityJSON(id: saved, template: "choose_step_v1", kind: "next_step", status: "paused",
                         checkpoint: ["version": 1, "template_version": 1, "step": ["action_text": "Write the subject line", "state": "saved"]], activeMs: 1_000, lastRevision: 7),
            activityJSON(id: done, template: "choose_step_v1", kind: "next_step", status: "completed",
                         checkpoint: ["version": 1, "template_version": 1, "step": ["action_text": "stale draft", "state": "saved"]],
                         result: ["step": ["action_text": "Sent the email", "state": "self_reported_done"]], lastRevision: 8),
        ]
        let json = snapshotJSON(session: sessionJSON(id: sid, revision: 12, selected: saved, scope: "personalized", conversation: conversation), activities: activities)
        let data = try JSONSerialization.data(withJSONObject: json)
        let snapshot = try SupportCloudDecoding.decode(SupportCloudSnapshot.self, from: data)
        let remote = try rig.service.remoteSnapshot(from: snapshot)
        XCTAssertEqual(remote.session.ownerID, ownerA.ownerID, "the owner comes from the captured binding; the server record has no user_id")
        XCTAssertEqual(remote.revision, 12)
        XCTAssertFalse(remote.isDeleted)
        XCTAssertEqual(remote.session.contextScope, .personalized)
        XCTAssertEqual(remote.session.conversationID, conversation)
        XCTAssertEqual(remote.session.selectedActivityID, saved)
        XCTAssertEqual(remote.session.syncStatus, .synced)
        XCTAssertEqual(remote.activities.count, 4)
        XCTAssertTrue(remote.discardedActivityIDs.isEmpty, "nothing was erased in this snapshot")

        let g = try XCTUnwrap(remote.activities.first { $0.id == grounding })
        XCTAssertEqual(g.status, .completed)
        XCTAssertEqual(g.canonicalReference, SupportCanonicalReference(kind: .exerciseSession, id: exercise))
        XCTAssertEqual(g.checkpoint.completedStepIDs, ["see", "feel", "hear", "smell"])
        XCTAssertEqual(g.checkpoint.skippedStepIDs, ["taste"])
        XCTAssertEqual(g.checkpoint.lastPromptID, "taste")
        XCTAssertEqual(g.checkpoint.responses, ["see": "window"])
        XCTAssertEqual(g.checkpoint.activeMilliseconds, 90_000)
        XCTAssertEqual(g.checkpoint.templateVersion, 1)
        XCTAssertEqual(g.activeMilliseconds, 90_000)
        XCTAssertEqual(g.result, SupportActivityResult(acknowledgedStepCount: 4, skippedStepCount: 1, activeMilliseconds: 90_000, stoppedReason: nil, shareableNote: "Grounded"))
        XCTAssertEqual(g.reflection?.outcome, .helpful)
        XCTAssertEqual(g.reflection?.includeWrittenAnswers, false)
        XCTAssertEqual(g.lastChangedRevision, 6)
        XCTAssertEqual(g.syncStatus, .synced)
        XCTAssertNotNil(g.finishedAt)

        let u = try XCTUnwrap(remote.activities.first { $0.id == untangle })
        XCTAssertEqual(u.status, .paused)
        XCTAssertEqual(u.checkpoint.responses, ["on_mind": "private words"])
        XCTAssertNil(u.result)
        XCTAssertNil(u.step)

        let s = try XCTUnwrap(remote.activities.first { $0.id == saved })
        XCTAssertEqual(s.step, SupportStepPayload(actionText: "Write the subject line", state: .saved))
        XCTAssertNil(s.step?.reminderAt, "reminders are device-local and never come from the wire")
        XCTAssertNil(s.step?.reminderTimeZoneIdentifier)

        let d = try XCTUnwrap(remote.activities.first { $0.id == done })
        XCTAssertEqual(d.step, SupportStepPayload(actionText: "Sent the email", state: .selfReportedDone), "a finished activity takes its step from result, not a stale checkpoint")

        // Tombstone path.
        let tombstone = snapshotJSON(session: sessionJSON(id: sid, revision: 13, status: "deleted", title: ""), activities: [])
        let deleted = try rig.service.remoteSnapshot(from: try SupportCloudDecoding.decode(SupportCloudSnapshot.self, from: try JSONSerialization.data(withJSONObject: tombstone)))
        XCTAssertTrue(deleted.isDeleted)
        XCTAssertEqual(deleted.revision, 13)
        XCTAssertTrue(deleted.activities.isEmpty)

        // The same wire snapshot under another binding is owned by THAT binding only.
        let other = try snapshot.remoteSnapshot(owner: ownerB)
        XCTAssertEqual(other.session.ownerID, ownerB.ownerID)
        XCTAssertNotEqual(other.session.ownerID, remote.session.ownerID)
    }

    func testUnrepresentableWireShapesThrowInsteadOfBeingSkippedOrInvented() throws {
        let sid = UUID(), aid = UUID()
        func convert(_ activity: [String: Any]) throws -> SupportRemoteSessionSnapshot {
            let json = snapshotJSON(session: sessionJSON(id: sid, revision: 3, selected: aid), activities: [activity])
            let snapshot = try SupportCloudDecoding.decode(SupportCloudSnapshot.self, from: try JSONSerialization.data(withJSONObject: json))
            return try snapshot.remoteSnapshot(owner: ownerA)
        }
        let step = "choose_step_v1", kind = "next_step"
        // A model-suggested draft is its own state: representable locally, never presented as saved or done.
        let draftSnapshot = try convert(activityJSON(id: aid, template: step, kind: kind, status: "ready",
            checkpoint: ["version": 1, "template_version": 1, "step": ["action_text": "Go", "state": "draft"]]))
        XCTAssertEqual(draftSnapshot.activities.first?.step, SupportStepPayload(actionText: "Go", state: .draft))
        XCTAssertNotEqual(draftSnapshot.activities.first?.step?.state, .saved)
        let shapes: [(String, [String: Any])] = [
            ("unknown checkpoint key", activityJSON(id: aid, checkpoint: ["version": 1, "template_version": 1, "step_index": 2])),
            ("checkpoint version", activityJSON(id: aid, checkpoint: ["version": 2, "template_version": 1])),
            ("checkpoint template version", activityJSON(id: aid, checkpoint: ["version": 1, "template_version": 9])),
            ("unknown prompt id", activityJSON(id: aid, checkpoint: ["version": 1, "template_version": 1, "current_step": "on_mind"])),
            ("completed list type", activityJSON(id: aid, checkpoint: ["version": 1, "template_version": 1, "completed_steps": "see"])),
            ("response type", activityJSON(id: aid, checkpoint: ["version": 1, "template_version": 1, "responses": ["see": 5]])),
            ("unknown result key", activityJSON(id: aid, status: "completed", result: ["elapsed_ms": 5])),
            ("negative count", activityJSON(id: aid, status: "completed", result: ["acknowledged_count": -1])),
            ("step extra key", activityJSON(id: aid, template: step, kind: kind, status: "paused",
                                           checkpoint: ["version": 1, "template_version": 1, "step": ["action_text": "x", "state": "saved", "reminder_at": "2026-11-07T09:00:00Z"]])),
            ("step without text", activityJSON(id: aid, template: step, kind: kind, status: "paused", checkpoint: ["version": 1, "template_version": 1, "step": ["state": "saved"]])),
            ("unknown step state", activityJSON(id: aid, template: step, kind: kind, status: "paused", checkpoint: ["version": 1, "template_version": 1, "step": ["action_text": "x", "state": "done"]])),
            ("draft step without text", activityJSON(id: aid, template: step, kind: kind, status: "ready", checkpoint: ["version": 1, "template_version": 1, "step": ["state": "draft"]])),
            ("unsupported template version", activityJSON(id: aid, templateVersion: 2)),
        ]
        for (name, activity) in shapes {
            assertCloudThrows(try convert(activity), name) { XCTAssertTrue($0 is SupportCloudConversionError, "\(name): \($0)") }
        }
        // A dismissed step with no text means "no saved step"; a discarded activity maps to a content-free result.
        let stopped = try convert(activityJSON(id: aid, template: step, kind: kind, status: "stopped", stopReason: "user_ended", result: ["step": ["state": "dismissed"]]))
        XCTAssertNil(stopped.activities.first?.step)
        XCTAssertEqual(stopped.activities.first?.result?.stoppedReason, "user_ended")
        let discarded = try convert(activityJSON(id: aid, status: "stopped", stopReason: "discarded", result: ["discarded": true]))
        XCTAssertEqual(discarded.activities.first?.result?.stoppedReason, "discarded")
        XCTAssertNil(discarded.activities.first?.result?.shareableNote)
        XCTAssertEqual(discarded.activities.first?.checkpoint.responses, [:])
    }

    func testReflectionSharedTextSurfacesOnlyWhenTheNoteWasDeliberatelyShared() throws {
        let sid = UUID(), aid = UUID()
        func convert(share: Bool, text: Any) throws -> SupportActivity {
            let reflection: [String: Any] = ["outcome": "not_sure", "note": "mixed", "share_note": share, "shareable_text": text]
            let json = snapshotJSON(session: sessionJSON(id: sid, revision: 3), activities: [activityJSON(id: aid, status: "completed", result: ["shareable_note": "from result"], reflection: reflection)])
            let snapshot = try SupportCloudDecoding.decode(SupportCloudSnapshot.self, from: try JSONSerialization.data(withJSONObject: json))
            return try XCTUnwrap(try snapshot.remoteSnapshot(owner: ownerA).activities.first)
        }
        let shared = try convert(share: true, text: "Shared summary")
        XCTAssertEqual(shared.result?.shareableNote, "Shared summary")
        XCTAssertEqual(shared.reflection?.includeWrittenAnswers, true)
        XCTAssertEqual(shared.reflection?.outcome, .notSure)
        let notShared = try convert(share: false, text: NSNull())
        XCTAssertEqual(notShared.result?.shareableNote, "from result")
        XCTAssertEqual(notShared.reflection?.includeWrittenAnswers, false)
    }

    // MARK: - No hidden sends

    // MARK: - CS05: an acknowledgment must PROVE the requested effect

    func testForgedOrInconsistentSessionAcknowledgmentsAreNotConfirmations() async throws {
        let rig = makeRig()
        let sid = UUID(), aid = UUID(), op = UUID(), other = UUID()
        let finish = envelope(.finishActivity(activityID: aid, status: .completed, result: SupportActivityResult(), step: nil, checkpoint: nil),
                              session: sid, operation: op, expected: 5)
        @Sendable func reply(
            revision: Int = 6, snapshotRevision: Int? = nil, noOp: Bool = false, extra: [String: Any] = [:], activity: UUID? = nil,
            noTarget: Bool = false, activities: [[String: Any]]? = nil, status: String = "completed", lastChanged: Int? = nil,
            replayed: Bool = false
        ) -> CloudStubReply {
            let target = noTarget ? nil : (activity ?? aid)
            let rows = activities ?? (target.map { [activityJSON(id: $0, status: status, lastRevision: lastChanged ?? revision)] } ?? [])
            let snapshot = snapshotJSON(session: sessionJSON(id: sid, revision: snapshotRevision ?? revision), activities: rows)
            return .json(200, successJSON(operation: lower(op), kind: "finish_activity", revision: revision, snapshot: snapshot, activity: target,
                                          noOp: noOp, replayed: replayed, extra: extra))
        }
        let forged: [(String, CloudStubReply)] = [
            ("unchanged revision, null event, null target, empty snapshot", reply(revision: 5, extra: ["event_id": NSNull()], noTarget: true, activities: [])),
            ("unchanged revision although applied", reply(revision: 5)),
            ("skipped revision", reply(revision: 7)),
            ("applied without an event", reply(extra: ["event_id": NSNull()])),
            ("no-op that names an event", reply(revision: 5, noOp: true, extra: ["event_id": lower(UUID())])),
            ("activity operation without a target", reply(noTarget: true, activities: [])),
            ("different target than requested", reply(activity: other)),
            ("requested activity absent, other old activities present",
             reply(activities: [activityJSON(id: UUID(), status: "completed", lastRevision: 2), activityJSON(id: UUID(), status: "stopped", lastRevision: 3)])),
            ("status not applied", reply(status: "in_progress")),
            ("stopped instead of completed", reply(status: "stopped")),
            ("activity not changed at this revision", reply(lastChanged: 4)),
            ("snapshot behind the receipt", reply(snapshotRevision: 5)),
            ("snapshot ahead of a first application", reply(snapshotRevision: 9)),
        ]
        for (name, response) in forged {
            rig.stub.respond { _ in response }
            let error = await expectError(try await rig.service.mutate(finish))
            guard case .malformedResponse? = error else { XCTFail("\(name): expected malformedResponse, got \(String(describing: error))"); continue }
            XCTAssertEqual(error?.attemptOutcome, .transientFailure, "\(name): the operation stays replayable")
        }

        // Non-activity operations: effect, tombstone, flags and revision-1 creation.
        @Sendable func plain(kind: String, revision: Int, status: String = "open", title: String = "Email supervisor",
                             extra: [String: Any] = [:], noOp: Bool = false, activity: UUID? = nil, replayed: Bool = false) -> CloudStubReply {
            let snapshot = snapshotJSON(session: sessionJSON(id: sid, revision: revision, status: status, title: title))
            return .json(200, successJSON(operation: lower(op), kind: kind, revision: revision, snapshot: snapshot, activity: activity,
                                          noOp: noOp, replayed: replayed, extra: extra))
        }
        let delete = envelope(.deleteSession, session: sid, operation: op, expected: 4)
        let close = envelope(.updateSession(title: nil, contextScope: nil, status: .closed), session: sid, operation: op, expected: 4)
        let rename = envelope(.updateSession(title: "Renamed", contextScope: nil, status: nil), session: sid, operation: op, expected: 4)
        let create = envelope(.create(title: "t", concern: nil, conversationID: nil, previousSessionID: nil, contextScope: .conversationOnly), session: sid, operation: op)
        let plainForged: [(String, SupportMutationEnvelope, CloudStubReply)] = [
            ("deleted flag without a tombstone", delete, plain(kind: "delete_session", revision: 5, extra: ["deleted": true])),
            ("delete not applied", delete, plain(kind: "delete_session", revision: 5)),
            ("delete names an activity", delete, plain(kind: "delete_session", revision: 5, status: "deleted", extra: ["deleted": true], activity: aid)),
            ("close not applied", close, plain(kind: "update_session", revision: 5, extra: ["closed": false])),
            ("closed status without the closed flag", close, plain(kind: "update_session", revision: 5, status: "closed", extra: ["closed": false])),
            ("rename not applied", rename, plain(kind: "update_session", revision: 5, title: "Old")),
            ("create at revision 2", create, plain(kind: "create", revision: 2)),
            ("create as a no-op", create, plain(kind: "create", revision: 1, noOp: true)),
        ]
        for (name, sent, response) in plainForged {
            rig.stub.respond { _ in response }
            let error = await expectError(try await rig.service.mutate(sent))
            guard case .malformedResponse? = error else { XCTFail("\(name): expected malformedResponse, got \(String(describing: error))"); continue }
        }

        // Genuine controls stay confirmed.
        let tombstone = snapshotJSON(session: sessionJSON(id: sid, revision: 10, status: "deleted", title: ""), activities: [])
        let genuine: [(String, SupportMutationEnvelope, CloudStubReply, Int, Bool)] = [
            ("first application", finish, reply(), 6, false),
            ("semantic no-op keeps the expected revision", finish, reply(revision: 5, noOp: true, extra: ["reason": "activity_finished"], status: "completed", lastChanged: 3), 5, true),
            ("replay of a historical receipt while the snapshot advanced", envelope(.finishActivity(activityID: aid, status: .completed, result: SupportActivityResult(), step: nil, checkpoint: nil), session: sid, operation: op, expected: 2),
             reply(revision: 6, snapshotRevision: 9, status: "completed", lastChanged: 6, replayed: true), 6, false),
            ("replay although the activity was later erased", finish, reply(revision: 6, snapshotRevision: 9, status: "stopped", lastChanged: 8, replayed: true), 6, false),
            ("replay after the session was deleted (no old target row)", finish,
             .json(200, successJSON(operation: lower(op), kind: "finish_activity", revision: 6, snapshot: tombstone, activity: aid, replayed: true)), 6, false),
            ("first delete", delete, plain(kind: "delete_session", revision: 5, status: "deleted", extra: ["deleted": true]), 5, false),
            ("replayed delete", delete, plain(kind: "delete_session", revision: 5, status: "deleted", extra: ["deleted": true], replayed: true), 5, false),
            ("close", close, plain(kind: "update_session", revision: 5, status: "closed", extra: ["closed": true]), 5, false),
            ("rename", rename, plain(kind: "update_session", revision: 5, title: "Renamed"), 5, false),
            ("rename that PostgreSQL btrim trims (spaces only)", envelope(.updateSession(title: "  Renamed  ", contextScope: nil, status: nil), session: sid, operation: op, expected: 4),
             plain(kind: "update_session", revision: 5, title: "Renamed"), 5, false),
            ("rename whose trailing newline btrim keeps", envelope(.updateSession(title: "Renamed\n", contextScope: nil, status: nil), session: sid, operation: op, expected: 4),
             plain(kind: "update_session", revision: 5, title: "Renamed\n"), 5, false),
            ("create", create, plain(kind: "create", revision: 1), 1, false),
        ]
        for (name, sent, response, revision, noOp) in genuine {
            rig.stub.respond { _ in response }
            guard case .confirmed(let confirmation) = try await rig.service.mutate(sent) else { XCTFail("\(name): expected confirmation"); continue }
            XCTAssertEqual(confirmation.revision, Int64(revision), name)
            XCTAssertEqual(confirmation.noOp, noOp, name)
        }
    }

    // MARK: - CS04: memory replies and conflicts are bound to the requested target

    func testMemoryRepliesAreBoundToTheRequestedTargetByKind() async throws {
        let rig = makeRig()
        let memory = UUID(), other = UUID(), fragment = UUID(), source = UUID()
        func mutation(_ operation: SupportCloudMemoryOperation) throws -> SupportCloudMemoryMutation {
            try SupportCloudMemoryMutation(operationID: UUID(), operation: operation)
        }
        @Sendable func memoryReply(_ request: CloudStubRequest, kind: String? = nil, extra: [String: Any], replayed: Bool = false) -> CloudStubReply {
            var body: [String: Any] = ["ok": true, "operation_id": request.json["operation_id"] as Any, "kind": kind ?? request.json["kind"] as Any,
                                       "privacy_revision": 9, "replayed": replayed, "server_time": stamp]
            body.merge(extra) { $1 }
            return .json(200, body)
        }
        let edit = SupportCloudMemoryOperation.edit(memoryID: memory, content: "New", category: nil, expectedRevision: 2)
        let approve = SupportCloudMemoryOperation.approveCandidate(fragmentID: fragment, editedContent: nil)
        let m = lower(memory), o = lower(other), f = lower(fragment), src = lower(source)
        let forgedReplies: [(String, SupportCloudMemoryOperation, [String: Any])] = [
            ("edit without a target", edit, ["memory_revision": 3]),
            ("edit of another memory", edit, ["memory_id": o, "memory_revision": 3]),
            ("edit without a revision", edit, ["memory_id": m]),
            ("edit that claims a change but keeps the revision", edit, ["memory_id": m, "memory_revision": 2]),
            ("edit that skips a revision", edit, ["memory_id": m, "memory_revision": 4]),
            ("edit with revision zero", edit, ["memory_id": m, "memory_revision": 0]),
            ("approval with no ids", approve, [:]),
            ("approval without the canonical memory", approve, ["fragment_id": f]),
            ("approval of another fragment", approve, ["fragment_id": o, "memory_id": m]),
            ("approval without the fragment", approve, ["memory_id": m]),
            ("stop with no target", .stopUsing(memoryID: memory, expectedRevision: nil), [:]),
            ("stop of another memory", .stopUsing(memoryID: memory, expectedRevision: nil), ["memory_id": o]),
            ("resume of another memory", .resumeUsing(memoryID: memory, expectedRevision: nil), ["memory_id": o]),
            ("forget with no target", .forgetMemory(memoryID: memory), [:]),
            ("forget of another memory", .forgetMemory(memoryID: memory), ["memory_id": o, "suppressed_turns": 0]),
            ("forget without the suppressed-turn count", .forgetMemory(memoryID: memory), ["memory_id": m]),
            ("forget answered by the fragment path", .forgetMemory(memoryID: memory), ["fragment_id": f, "memory_id": m, "suppressed_turns": 0, "conversation_scope_excluded": false]),
            ("negative suppressed turns", .forgetMemory(memoryID: memory), ["memory_id": m, "suppressed_turns": -1]),
            ("candidate forget with no target", .forgetCandidate(fragmentID: fragment), [:]),
            ("candidate forget of another fragment", .forgetCandidate(fragmentID: fragment), ["fragment_id": o, "memory_id": NSNull(), "suppressed_turns": 0, "conversation_scope_excluded": true]),
            ("candidate forget without the turn count", .forgetCandidate(fragmentID: fragment), ["fragment_id": f, "memory_id": NSNull(), "conversation_scope_excluded": true]),
            ("candidate forget without the scope flag", .forgetCandidate(fragmentID: fragment), ["fragment_id": f, "memory_id": NSNull(), "suppressed_turns": 0]),
            ("dismissal with no target", .dismissCandidate(fragmentID: fragment), [:]),
            ("dismissal of another fragment", .dismissCandidate(fragmentID: fragment), ["fragment_id": o]),
            ("suppression with no target", .suppressSource(kind: .conversation, id: source), [:]),
            ("suppression of the wrong kind", .suppressSource(kind: .conversation, id: source), ["source_kind": "message", "id": src, "suppressed_turns": 0]),
            ("suppression of another source", .suppressSource(kind: .conversation, id: source), ["source_kind": "conversation", "id": o, "suppressed_turns": 0]),
            ("suppression without the turn count", .suppressSource(kind: .conversation, id: source), ["source_kind": "conversation", "id": src]),
            ("restoration with no target", .unsuppressSource(kind: .message, id: source), [:]),
            ("restoration of another source", .unsuppressSource(kind: .message, id: source), ["source_kind": "message", "id": o]),
        ]
        for (name, operation, extra) in forgedReplies {
            let sent = try mutation(operation)
            rig.stub.respond { memoryReply($0, extra: extra) }
            let error = await expectError(try await rig.service.mutateMemory(sent))
            guard case .malformedResponse? = error else { XCTFail("\(name): expected malformedResponse, got \(String(describing: error))"); continue }
            XCTAssertEqual(error?.attemptOutcome, .transientFailure, "\(name): not an acknowledgment, so the operation stays replayable")
        }
        rig.stub.respond { memoryReply($0, kind: "memory_forget", extra: ["memory_id": m, "memory_revision": 3]) }
        guard case .malformedResponse? = await expectError(try await rig.service.mutateMemory(try mutation(edit))) else { return XCTFail("a reply for another kind must not count") }

        // Legitimate shapes are kept: no-ops, a candidate forget with a null promoted memory, and stored replays.
        let legitimate: [(String, SupportCloudMemoryOperation, [String: Any], Bool)] = [
            ("edit", edit, ["memory_id": m, "memory_revision": 3], false),
            ("no-op edit keeps the revision", edit, ["no_op": true, "memory_id": m, "memory_revision": 2], false),
            ("replayed edit returns its stored receipt", edit, ["memory_id": m, "memory_revision": 3], true),
            ("stop", .stopUsing(memoryID: memory, expectedRevision: nil), ["memory_id": m], false),
            ("no-op stop", .stopUsing(memoryID: memory, expectedRevision: 3), ["no_op": true, "memory_id": m], false),
            ("resume", .resumeUsing(memoryID: memory, expectedRevision: 3), ["memory_id": m], false),
            ("forget", .forgetMemory(memoryID: memory), ["memory_id": m, "suppressed_turns": 2], false),
            ("candidate forget with a null promoted memory", .forgetCandidate(fragmentID: fragment), ["fragment_id": f, "memory_id": NSNull(), "suppressed_turns": 0, "conversation_scope_excluded": true], false),
            ("approve", approve, ["fragment_id": f, "memory_id": m], false),
            ("no-op approve of an already promoted fragment", approve, ["no_op": true, "fragment_id": f, "memory_id": m], false),
            ("dismiss", .dismissCandidate(fragmentID: fragment), ["fragment_id": f], false),
            ("no-op dismiss", .dismissCandidate(fragmentID: fragment), ["no_op": true, "fragment_id": f], false),
            ("suppress", .suppressSource(kind: .conversation, id: source), ["source_kind": "conversation", "id": src, "suppressed_turns": 4], false),
            ("unsuppress", .unsuppressSource(kind: .message, id: source), ["source_kind": "message", "id": src], false),
        ]
        for (name, operation, extra, replayed) in legitimate {
            rig.stub.respond { memoryReply($0, extra: extra, replayed: replayed) }
            guard case .confirmed(let receipt) = try await rig.service.mutateMemory(try mutation(operation)) else { XCTFail("\(name): expected confirmation"); continue }
            XCTAssertEqual(receipt.replayed, replayed, name)
        }
    }

    func testMemoryConflictsAreBoundToTheRequestedMemoryAndRevision() async throws {
        let rig = makeRig()
        let memory = UUID(), other = UUID(), fragment = UUID()
        @Sendable func conflict(_ id: UUID, current: Int) -> CloudStubReply {
            .json(409, ["ok": false, "code": "REVISION_CONFLICT", "current_revision": current,
                        "memory": ["id": lower(id), "category": "preferences", "content": "Current text", "revision": current]])
        }
        let edit = SupportCloudMemoryOperation.edit(memoryID: memory, content: "New", category: nil, expectedRevision: 2)
        let rejected: [(String, SupportCloudMemoryOperation, CloudStubReply)] = [
            ("conflict about another memory", edit, conflict(other, current: 5)),
            ("conflict at the revision the caller expected", edit, conflict(memory, current: 2)),
            ("stop without an expected revision cannot conflict", .stopUsing(memoryID: memory, expectedRevision: nil), conflict(memory, current: 5)),
            ("resume of another memory", .resumeUsing(memoryID: memory, expectedRevision: 3), conflict(other, current: 5)),
            ("forget cannot conflict", .forgetMemory(memoryID: memory), conflict(memory, current: 5)),
            ("approval cannot conflict", .approveCandidate(fragmentID: fragment, editedContent: nil), conflict(memory, current: 5)),
        ]
        for (name, operation, response) in rejected {
            rig.stub.respond { _ in response }
            let error = await expectError(try await rig.service.mutateMemory(try SupportCloudMemoryMutation(operationID: UUID(), operation: operation)))
            guard case .malformedResponse? = error else { XCTFail("\(name): expected malformedResponse, got \(String(describing: error))"); continue }
            XCTAssertEqual(error?.attemptOutcome, .transientFailure, "\(name): a foreign conflict is never a rebase basis")
        }
        let accepted: [(String, SupportCloudMemoryOperation, Int)] = [
            ("edit", edit, 5),
            ("stop with an expected revision", .stopUsing(memoryID: memory, expectedRevision: 3), 5),
            ("resume with an expected revision", .resumeUsing(memoryID: memory, expectedRevision: 3), 5),
        ]
        for (name, operation, current) in accepted {
            rig.stub.respond { _ in conflict(memory, current: current) }
            guard case .conflict(let result) = try await rig.service.mutateMemory(try SupportCloudMemoryMutation(operationID: UUID(), operation: operation)) else {
                XCTFail("\(name): expected a conflict"); continue
            }
            XCTAssertEqual(result.memoryID, memory, name)
            XCTAssertEqual(result.currentRevision, Int64(current), name)
        }
    }

    // MARK: - CS07: a replayed receipt's privacy revision is historical

    func testReplayedMemoryReceiptKeepsItsHistoricalPrivacyRevision() async throws {
        let rig = makeRig()
        let memory = UUID()
        let stop = try SupportCloudMemoryMutation(operationID: UUID(), operation: .stopUsing(memoryID: memory, expectedRevision: nil))
        @Sendable func receipt(_ request: CloudStubRequest, privacy: Int, replayed: Bool) -> CloudStubReply {
            .json(200, ["ok": true, "operation_id": request.json["operation_id"] as Any, "kind": "memory_stop_using", "memory_id": lower(memory),
                        "privacy_revision": privacy, "replayed": replayed, "server_time": stamp])
        }
        rig.stub.respond { receipt($0, privacy: 7, replayed: false) }
        guard case .confirmed(let first) = try await rig.service.mutateMemory(stop) else { return XCTFail() }
        XCTAssertFalse(first.privacyRevisionIsHistorical)
        // Another privacy operation advances the account to 11; the delayed replay still returns the STORED revision 7.
        rig.stub.respond { receipt($0, privacy: 7, replayed: true) }
        let replayResult = try await rig.service.mutateMemory(stop)
        guard case .confirmed(let replay) = replayResult else { return XCTFail() }
        XCTAssertTrue(replay.privacyRevisionIsHistorical)
        XCTAssertEqual(replay.privacyRevision, 7, "the stored receipt is preserved verbatim, not rewritten as current")
        XCTAssertEqual(replayResult.attemptOutcome, .confirmed(revision: 7))
        rig.stub.respond { _ in .json(200, ["ok": true, "privacy_revision": 11, "max_confirmed": 20, "saved": [Any](), "candidates": [Any](),
                                          "daily_intent": NSNull(), "server_time": stamp]) }
        let page = try await rig.service.listMemory()
        XCTAssertGreaterThan(page.privacyRevision, replay.privacyRevision, "only a fresh authoritative read establishes the current revision")
    }

    // MARK: - CS03: the actual accept_proposal seed checkpoint

    private func convertSnapshot(_ activities: [[String: Any]], selected: UUID? = nil, status: String = "open") throws -> SupportRemoteSessionSnapshot {
        let json = snapshotJSON(session: sessionJSON(id: UUID(), revision: 5, status: status, selected: selected), activities: activities)
        let snapshot = try SupportCloudDecoding.decode(SupportCloudSnapshot.self, from: try JSONSerialization.data(withJSONObject: json))
        return try snapshot.remoteSnapshot(owner: ownerA)
    }

    func testActualAcceptProposalReplyConvertsToADraftUsingTheRowTemplateVersion() async throws {
        let rig = makeRig()
        let sid = UUID(), aid = UUID(), proposal = UUID()
        // Exactly what `support_do_accept_proposal` writes: NO template_version inside the seed checkpoint.
        let seed: [String: Any] = ["version": 1, "step": ["action_text": "Synthetic next action", "state": "draft"]]
        let accepted = activityJSON(id: aid, template: "choose_step_v1", kind: "next_step", status: "ready", checkpoint: seed, lastRevision: 5)
        rig.stub.respond { request in
            .json(200, successJSON(operation: request.json["operation_id"] as! String, kind: "accept_proposal", revision: 5,
                                   snapshot: snapshotJSON(session: sessionJSON(id: sid, revision: 5, selected: aid), activities: [accepted]), activity: aid))
        }
        let result = try await rig.service.mutate(envelope(.acceptProposal(proposalID: proposal, activityID: aid), session: sid, expected: 4))
        guard case .confirmed(let confirmation) = result else { return XCTFail("expected confirmation") }
        let remote = try rig.service.remoteSnapshot(from: confirmation.snapshot)
        let activity = try XCTUnwrap(remote.activities.first)
        XCTAssertEqual(activity.status, .ready, "acceptance is not a start and never a completion")
        XCTAssertEqual(activity.step, SupportStepPayload(actionText: "Synthetic next action", state: .draft))
        XCTAssertNotEqual(activity.step?.state, .saved)
        XCTAssertNotEqual(activity.step?.state, .selfReportedDone)
        XCTAssertEqual(activity.templateVersion, 1)
        XCTAssertEqual(activity.checkpoint.templateVersion, 1, "the ROW's template version is authoritative")
        XCTAssertTrue(activity.checkpoint.completedStepIDs.isEmpty && activity.checkpoint.skippedStepIDs.isEmpty)
        XCTAssertTrue(activity.checkpoint.responses.isEmpty)
        XCTAssertNil(activity.result, "no invented completion")
        XCTAssertNil(activity.reflection)
        XCTAssertNil(activity.finishedAt)
        XCTAssertTrue(remote.discardedActivityIDs.isEmpty)

        // The same untouched seed also survives `start_activity` (which only flips the status) and a later finish.
        XCTAssertEqual(try convertSnapshot([activityJSON(id: aid, template: "choose_step_v1", kind: "next_step", status: "in_progress", checkpoint: seed)], selected: aid)
            .activities.first?.step?.state, .draft)
        let done = try convertSnapshot([activityJSON(id: aid, template: "choose_step_v1", kind: "next_step", status: "completed", checkpoint: seed,
                                                     result: ["step": ["action_text": "Sent it", "state": "self_reported_done"]])])
        XCTAssertEqual(done.activities.first?.step, SupportStepPayload(actionText: "Sent it", state: .selfReportedDone), "a finished activity takes its step from result")
    }

    func testSeedCheckpointIsOnlyAcceptedInItsExactShape() throws {
        let aid = UUID()
        let draft: [String: Any] = ["action_text": "Go", "state": "draft"]
        let bad: [(String, [String: Any])] = [
            ("grounding seed", activityJSON(id: aid, status: "ready", checkpoint: ["version": 1, "step": draft])),
            ("version only", activityJSON(id: aid, template: "choose_step_v1", kind: "next_step", status: "ready", checkpoint: ["version": 1])),
            ("saved step without template_version", activityJSON(id: aid, template: "choose_step_v1", kind: "next_step", status: "paused",
                                                                  checkpoint: ["version": 1, "step": ["action_text": "Go", "state": "saved"]])),
            ("seed with progress fields", activityJSON(id: aid, template: "choose_step_v1", kind: "next_step", status: "ready",
                                                      checkpoint: ["version": 1, "current_step": "action", "step": draft])),
            ("seed with extra step key", activityJSON(id: aid, template: "choose_step_v1", kind: "next_step", status: "ready",
                                                     checkpoint: ["version": 1, "step": ["action_text": "Go", "state": "draft", "reminder_at": "2026-11-07T09:00:00Z"]])),
            ("seed without text", activityJSON(id: aid, template: "choose_step_v1", kind: "next_step", status: "ready",
                                              checkpoint: ["version": 1, "step": ["state": "draft"]])),
            ("ordinary checkpoint missing template_version", activityJSON(id: aid, checkpoint: ["version": 1, "completed_steps": ["see"]])),
            ("template_version null", activityJSON(id: aid, template: "choose_step_v1", kind: "next_step", status: "ready",
                                                  checkpoint: ["version": 1, "template_version": NSNull(), "step": draft])),
            ("template_version mismatch", activityJSON(id: aid, template: "choose_step_v1", kind: "next_step", status: "ready",
                                                      checkpoint: ["version": 1, "template_version": 9, "step": draft])),
        ]
        for (name, activity) in bad {
            assertCloudThrows(try convertSnapshot([activity]), name) { XCTAssertTrue($0 is SupportCloudConversionError, "\(name): \($0)") }
        }
    }

    // MARK: - CS02 / CS06: server-erased activities

    func testDiscardedCompletedStepWithErasedTextConvertsWithoutAnActionableStep() throws {
        let aid = UUID(), done = UUID(), groundingRef = UUID()
        // Exact `support_do_discard` output for a COMPLETED practical step: the state survives, the text does not.
        let scrubbedReflection: [String: Any] = ["outcome": "helpful", "note": NSNull(), "share_note": false, "shareable_text": NSNull()]
        let discardedStep = activityJSON(id: aid, template: "choose_step_v1", kind: "next_step", status: "completed", checkpoint: NSNull(),
                                         result: ["discarded": true, "step": ["state": "self_reported_done"]], reflection: scrubbedReflection,
                                         activeMs: 7_000, lastRevision: 9)
        let live = activityJSON(id: done, template: "choose_step_v1", kind: "next_step", status: "completed",
                                result: ["step": ["action_text": "Kept step", "state": "self_reported_done"]], lastRevision: 4)
        let remote = try convertSnapshot([discardedStep, live])
        XCTAssertEqual(remote.discardedActivityIDs, [aid], "only the server-erased activity carries the marker")
        let erased = try XCTUnwrap(remote.activities.first { $0.id == aid })
        XCTAssertEqual(erased.status, .completed, "completion history is preserved")
        XCTAssertNil(erased.step, "no actionable step without its text")
        XCTAssertEqual(erased.result, SupportActivityResult(acknowledgedStepCount: 0, skippedStepCount: 0, activeMilliseconds: 7_000, stoppedReason: nil, shareableNote: nil))
        XCTAssertEqual(erased.reflection?.outcome, .helpful)
        XCTAssertNil(erased.reflection?.note)
        XCTAssertEqual(erased.reflection?.includeWrittenAnswers, false)
        XCTAssertTrue(erased.checkpoint.responses.isEmpty)
        XCTAssertEqual(erased.activeMilliseconds, 7_000)
        XCTAssertEqual(erased.lastChangedRevision, 9)
        XCTAssertEqual(try XCTUnwrap(remote.activities.first { $0.id == done }).step, SupportStepPayload(actionText: "Kept step", state: .selfReportedDone))

        // Other server-written shapes: dismissed state, bare marker on a stopped activity, canonical reference retained.
        let dismissed = try convertSnapshot([activityJSON(id: aid, template: "choose_step_v1", kind: "next_step", status: "stopped", stopReason: "discarded",
                                                          result: ["discarded": true, "step": ["state": "dismissed"]])])
        XCTAssertNil(dismissed.activities.first?.step)
        XCTAssertEqual(dismissed.activities.first?.result?.stoppedReason, "discarded")
        let bare = try convertSnapshot([activityJSON(id: aid, status: "stopped", stopReason: "discarded", ref: groundingRef, result: ["discarded": true])])
        XCTAssertEqual(bare.discardedActivityIDs, [aid])
        XCTAssertEqual(bare.activities.first?.canonicalReference, SupportCanonicalReference(kind: .exerciseSession, id: groundingRef))
    }

    func testDiscardMarkerSanitizesLeftoverContentAndRejectsForgedShapes() throws {
        let aid = UUID()
        // A row that still carries content next to the marker is converted content-free and never copied.
        let leaky = activityJSON(
            id: aid, template: "choose_step_v1", kind: "next_step", status: "completed",
            checkpoint: ["version": 1, "template_version": 1, "current_step": "action", "completed_steps": ["action"], "responses": ["action": "private words"],
                         "step": ["action_text": "private plan", "state": "saved"]],
            result: ["discarded": true, "step": ["action_text": "private plan", "state": "self_reported_done"]],
            reflection: ["outcome": "not_sure", "note": "private note", "share_note": true, "shareable_text": "private share"], activeMs: 1_000)
        let remote = try convertSnapshot([leaky])
        let activity = try XCTUnwrap(remote.activities.first)
        XCTAssertEqual(remote.discardedActivityIDs, [aid])
        XCTAssertNil(activity.step)
        XCTAssertTrue(activity.checkpoint.responses.isEmpty)
        XCTAssertTrue(activity.checkpoint.completedStepIDs.isEmpty)
        XCTAssertNil(activity.checkpoint.lastPromptID)
        XCTAssertNil(activity.result?.shareableNote)
        XCTAssertNil(activity.reflection?.note)
        XCTAssertEqual(activity.reflection?.includeWrittenAnswers, false)
        XCTAssertEqual(activity.reflection?.outcome, .notSure)
        let encoded = String(decoding: try JSONEncoder().encode(activity), as: UTF8.self)
        for secret in ["private words", "private plan", "private note", "private share"] {
            XCTAssertFalse(encoded.contains(secret), "\(secret) must not survive the converter")
        }

        // The SQL writes only {discarded, step.state}; a hybrid or a marker on live work is not a server erasure.
        let rejected: [(String, [String: Any])] = [
            ("marker with counters", activityJSON(id: aid, status: "completed", result: ["discarded": true, "acknowledged_count": 3])),
            ("marker with a note", activityJSON(id: aid, status: "completed", result: ["discarded": true, "shareable_note": "x"])),
            ("marker on a live activity", activityJSON(id: aid, status: "paused", result: ["discarded": true])),
            ("marker with an unknown step state", activityJSON(id: aid, status: "completed", result: ["discarded": true, "step": ["state": "vanished"]])),
            ("marker with a step without a state", activityJSON(id: aid, status: "completed", result: ["discarded": true, "step": ["action_text": "x"]])),
        ]
        for (name, row) in rejected {
            assertCloudThrows(try convertSnapshot([row]), name) { XCTAssertTrue($0 is SupportCloudConversionError, "\(name): \($0)") }
        }
        // `discarded: false` is an ordinary row, and a tombstone carries no markers.
        XCTAssertTrue(try convertSnapshot([activityJSON(id: aid, status: "completed", result: ["discarded": false, "acknowledged_count": 2])]).discardedActivityIDs.isEmpty)
        XCTAssertTrue(try convertSnapshot([], status: "deleted").discardedActivityIDs.isEmpty)
    }

    func testDiscardConfirmationConvertsWithItsAuthoritativeErasureMarker() async throws {
        let rig = makeRig()
        rig.stub.respond { echoSuccess($0) }
        let sid = UUID(), aid = UUID()
        guard case .confirmed(let confirmation) = try await rig.service.mutate(envelope(.discardActivityAnswers(activityID: aid), session: sid)) else {
            return XCTFail("expected confirmation")
        }
        let remote = try rig.service.remoteSnapshot(from: confirmation.snapshot)
        XCTAssertEqual(remote.discardedActivityIDs, [aid])
        XCTAssertEqual(remote.session.ownerID, ownerA.ownerID)
    }

    func testEveryOperationIsExactlyOneRequestWithAKnownOpAndNoChatOrProviderTraffic() async throws {
        let rig = makeRig()
        let sid = UUID()
        rig.stub.respond { request in
            switch request.json["op"] as? String {
            case "capabilities": return .json(200, ["session_contract": 1, "context_policy": 1, "voice_context": 0, "status": "ok"])
            case "get": return .json(404, ["ok": false, "code": "NOT_FOUND"])
            case "list": return .json(200, ["ok": true, "items": [Any](), "next_cursor": NSNull(), "privacy_revision": 1, "server_time": stamp])
            case "receipt": return .json(404, ["ok": false, "code": "NOT_FOUND"])
            default: return .raw(500, "")
            }
        }
        _ = try await rig.service.capabilities()
        _ = await expectError(try await rig.service.get(sessionID: sid))
        _ = try await rig.service.list()
        _ = try await rig.service.receipt(requestID: UUID())
        let ops = rig.stub.requests.compactMap { $0.json["op"] as? String }
        XCTAssertEqual(ops, ["capabilities", "get", "list", "receipt"])
        XCTAssertTrue(rig.stub.requests.allSatisfy { $0.url?.path == "/functions/v1/support-session" && $0.method == "POST" })
        XCTAssertTrue(rig.stub.requests.allSatisfy { !$0.bodyText.contains("message") && !$0.bodyText.contains("prompt") })
    }
}
