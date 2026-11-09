import Foundation

// MARK: - Support session cloud adapter (spec §9.4, §10.1)
//
// An injected transport + wire adapter for the `support-session` Edge function. It is NOT a second journal,
// coordinator or outbox: it never queues, never retries and never mutates by itself. Every call is one request,
// and the caller (repository/coordinator) decides replay (same operation ID) or rebase (new operation ID) from the
// typed outcome.
//
// Contract sources (authoritative over any prose summary):
//   supabase/functions/_shared/support-contract.ts, support-session-handler.ts,
//   supabase/migrations/2026110623{0000,0100,0200}_*.sql
//
// Safety properties:
//   * Bound to ONE immutable owner + account epoch. The owner proof and the captured credential are re-checked before
//     the token fetch, after the token fetch, immediately before dispatch, after the response await and on the
//     failure path. A response that arrives after the owner changed is discarded, never decoded or published.
//   * The raw `URLRequest` carries `apikey` and `Authorization: Bearer <captured token>` itself. Nothing relies on an
//     SDK client's ambient session.
//   * Only schema/operation/session/expected revision/kind/payload are sent. The server computes its own hash; the
//     local FNV `payloadFingerprint` and any clock or time zone are never part of the wire bytes, so a replay of the
//     same envelope is byte-identical.
//   * Device-local reminder metadata (`SupportStepPayload.reminderAt`, `reminderTimeZoneIdentifier`, `confirmedAt`) is
//     NEVER sent. A practical step on the wire is exactly `{action_text, state}`.
//   * No secrets, response bodies or user text are logged or placed in error values.

// MARK: Identity and injection

/// Narrow immutable authenticated owner + account epoch. Map from `AppState.accountEpoch` / the repository identity.
struct SupportCloudBinding: Hashable, Sendable {
    let ownerID: UUID
    let accountEpoch: UInt64

    init(ownerID: UUID, accountEpoch: UInt64) {
        self.ownerID = ownerID
        self.accountEpoch = accountEpoch
    }
}

/// The owner and access token captured TOGETHER by the token source. The token is never printed.
struct SupportCloudCredential: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let binding: SupportCloudBinding
    fileprivate let accessToken: String

    init(binding: SupportCloudBinding, accessToken: String) {
        self.binding = binding
        self.accessToken = accessToken
    }

    var description: String { "SupportCloudCredential(owner: \(binding.ownerID), epoch: \(binding.accountEpoch), token: <redacted>)" }
    var debugDescription: String { description }
}

/// Returns the CURRENT authenticated binding, or nil when signed out / switching. Called repeatedly around every await.
typealias SupportCloudOwnerProof = @Sendable () async -> SupportCloudBinding?
/// Returns the token captured with its owner, or nil when there is no session. May refresh. Must not return a stale owner.
typealias SupportCloudTokenSource = @Sendable () async throws -> SupportCloudCredential?

// MARK: Errors and outcomes

enum SupportCloudCapabilityGap: Equatable, Sendable {
    /// The platform answered 404 without the contract body: the Edge function is not deployed.
    case functionNotDeployed
    /// The function is deployed but its database RPC is missing (`TEMPORARY_FAILURE` + `capability: not_deployed`).
    case rpcNotDeployed
    /// Local configuration (project URL / public key) is missing.
    case notConfigured
}

enum SupportCloudAuthReason: Equatable, Sendable {
    case noSession, tokenUnavailable, unauthorized, forbidden, expiredToken
}

enum SupportCloudTransportFailure: Equatable, Sendable {
    case timeout, offline, connectionLost, secureConnection, cancelled
    case other(Int)
}

enum SupportCloudErrorCode: String, Equatable, Sendable, CaseIterable {
    case authRequired = "AUTH_REQUIRED"
    case notFound = "NOT_FOUND"
    case revisionConflict = "REVISION_CONFLICT"
    case operationIDReused = "OPERATION_ID_REUSED"
    case invalidPayload = "INVALID_PAYLOAD"
    case privacyRevisionStale = "PRIVACY_REVISION_STALE"
    case proposalExpired = "PROPOSAL_EXPIRED"
    case contentUnavailable = "CONTENT_UNAVAILABLE"
    case entitlementRequired = "ENTITLEMENT_REQUIRED"
    case rateLimited = "RATE_LIMITED"
    case temporaryFailure = "TEMPORARY_FAILURE"
    case memoryLimitReached = "MEMORY_LIMIT_REACHED"
}

/// A definitive, non-automatically-retried server rejection.
struct SupportCloudRejection: Equatable, Sendable {
    let code: SupportCloudErrorCode
    /// Server-supplied content-free hint, bounded. Never user text.
    let message: String?
    let httpStatus: Int
    let currentPrivacyRevision: Int64?
}

enum SupportCloudEncodingFailure: Equatable, Sendable {
    case schemaVersion(Int)
    case missingExpectedRevision
    case unexpectedExpectedRevision
    case invalidExpectedRevision(Int64)
    case valueTooLong(field: String, limit: Int)
    case emptyValue(field: String)
    /// A local value that has no wire representation (never silently invented): e.g. reopen, non-saved paused step.
    case unsupportedValue(field: String)
    case unsupportedTemplateVersion(Int)
    case unknownPromptID(String)
    case numberOutOfRange(field: String)
    case tooLarge(field: String, bytes: Int, limit: Int)
}

enum SupportCloudError: Error, Equatable, Sendable {
    /// The captured owner/epoch is no longer current. Whatever arrived is discarded, never published.
    case ownerChanged
    /// The calling task was cancelled. After dispatch the server outcome is UNKNOWN.
    case cancelled
    /// Nothing was sent: the request could not be encoded.
    case invalidRequest(SupportCloudEncodingFailure)
    /// 401/403/expired JWT/no token. Retryable only after the binding/token is repaired; do not loop.
    case authenticationRequired(SupportCloudAuthReason)
    /// The cloud contract or the function is absent. Local work continues; never fall back to an older privacy path.
    case capabilityUnavailable(SupportCloudCapabilityGap)
    /// URLSession failed after dispatch: the outcome is UNKNOWN (never a definitive rejection).
    case transport(SupportCloudTransportFailure)
    /// 429/5xx/TEMPORARY_FAILURE: the outcome is unknown or the server asked to wait.
    case serverTemporary(status: Int, retryAfter: TimeInterval?)
    /// A reply that violates the contract. For a mutation the outcome is UNKNOWN (replay the same operation ID).
    case malformedResponse(String)
    case rejected(SupportCloudRejection)
}

extension SupportCloudError {
    /// Whether the server definitely does NOT hold this operation, so a fresh operation ID may be considered.
    var isDefinitiveRejection: Bool {
        if case .rejected = self { return true }
        return false
    }

    /// Map to the repository's outcome. Everything that is not a definitive rejection keeps the original operation ID
    /// (`transientFailure` = ambiguous = replay identically). `invalidRequest` never reached the wire and can never
    /// succeed as built, so it is a content-free permanent failure.
    var attemptOutcome: SupportAttemptOutcome {
        switch self {
        case .rejected(let rejection): return .rejected(code: rejection.code.rawValue)
        case .invalidRequest: return .rejected(code: "CLIENT_ENCODING_FAILED")
        case .ownerChanged, .cancelled, .authenticationRequired, .capabilityUnavailable, .transport,
             .serverTemporary, .malformedResponse:
            return .transientFailure
        }
    }
}

/// Wire → local-domain conversion failure. Never a silent skip.
enum SupportCloudConversionError: Error, Equatable, Sendable {
    case unsupportedWireShape(path: String)
    case unsupportedStepState(String)
}

// MARK: - JSON value

/// Minimal JSON value for the opaque parts of the contract (`payload`, `checkpoint`, `result`, event payloads).
indirect enum SupportCloudJSON: Equatable, Sendable, Decodable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([SupportCloudJSON])
    case object([String: SupportCloudJSON])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int64.self) { self = .int(v) }
        else if let v = try? c.decode(Double.self) { self = .double(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([SupportCloudJSON].self) { self = .array(v) }
        else if let v = try? c.decode([String: SupportCloudJSON].self) { self = .object(v) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "unsupported JSON value") }
    }

    var objectValue: [String: SupportCloudJSON]? { if case .object(let v) = self { return v }; return nil }
    var stringValue: String? { if case .string(let v) = self { return v }; return nil }
    var int64Value: Int64? { if case .int(let v) = self { return v }; return nil }
    var boolValue: Bool? { if case .bool(let v) = self { return v }; return nil }
    var arrayValue: [SupportCloudJSON]? { if case .array(let v) = self { return v }; return nil }
    var isNull: Bool { if case .null = self { return true }; return false }

    /// Deterministic compact bytes: keys sorted by UTF-8 bytes, no whitespace, fixed escaping. The same value always
    /// encodes to the same bytes, independent of dictionary order, clock or locale.
    func stableData() throws -> Data {
        var out = [UInt8]()
        out.reserveCapacity(256)
        try write(into: &out, spaced: false)
        return Data(out)
    }

    /// Byte size PostgreSQL measures with `octet_length(jsonb::text)` (", " and ": " separators); mirrors `jsonbBytes`.
    func jsonbByteCount() throws -> Int {
        var out = [UInt8]()
        try write(into: &out, spaced: true)
        return out.count
    }

    private func write(into out: inout [UInt8], spaced: Bool) throws {
        switch self {
        case .null: out.append(contentsOf: Array("null".utf8))
        case .bool(let v): out.append(contentsOf: Array((v ? "true" : "false").utf8))
        case .int(let v): out.append(contentsOf: Array(String(v).utf8))
        case .double: throw SupportCloudError.invalidRequest(.unsupportedValue(field: "number"))
        case .string(let s): Self.writeString(s, into: &out)
        case .array(let items):
            out.append(UInt8(ascii: "["))
            for (i, item) in items.enumerated() {
                if i > 0 { out.append(UInt8(ascii: ",")); if spaced { out.append(UInt8(ascii: " ")) } }
                try item.write(into: &out, spaced: spaced)
            }
            out.append(UInt8(ascii: "]"))
        case .object(let members):
            out.append(UInt8(ascii: "{"))
            let keys = members.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
            for (i, key) in keys.enumerated() {
                if i > 0 { out.append(UInt8(ascii: ",")); if spaced { out.append(UInt8(ascii: " ")) } }
                Self.writeString(key, into: &out)
                out.append(UInt8(ascii: ":"))
                if spaced { out.append(UInt8(ascii: " ")) }
                try members[key]?.write(into: &out, spaced: spaced)
            }
            out.append(UInt8(ascii: "}"))
        }
    }

    private static func writeString(_ s: String, into out: inout [UInt8]) {
        out.append(UInt8(ascii: "\""))
        for scalar in s.unicodeScalars {
            switch scalar.value {
            case 0x22: out.append(contentsOf: Array("\\\"".utf8))
            case 0x5C: out.append(contentsOf: Array("\\\\".utf8))
            case 0x08: out.append(contentsOf: Array("\\b".utf8))
            case 0x0C: out.append(contentsOf: Array("\\f".utf8))
            case 0x0A: out.append(contentsOf: Array("\\n".utf8))
            case 0x0D: out.append(contentsOf: Array("\\r".utf8))
            case 0x09: out.append(contentsOf: Array("\\t".utf8))
            case 0..<0x20:
                let hex = String(scalar.value, radix: 16)
                out.append(contentsOf: Array("\\u\(String(repeating: "0", count: 4 - hex.count))\(hex)".utf8))
            default:
                out.append(contentsOf: Array(String(scalar).utf8))
            }
        }
        out.append(UInt8(ascii: "\""))
    }
}

// MARK: - ISO-8601 dates (with or without fractional seconds, any offset)

enum SupportCloudDate {
    /// Parses `YYYY-MM-DD[T| ]hh:mm:ss[.f{1,9}](Z|±hh[:mm]|±hhmm)`. PostgreSQL emits microseconds and `+00:00`.
    /// A zone designator is mandatory so a server value is never interpreted in the device's current zone.
    static func parse(_ text: String) -> Date? {
        let b = Array(text.utf8)
        var i = 0
        func digits(_ n: Int) -> Int? {
            guard i + n <= b.count else { return nil }
            var v = 0
            for k in 0..<n {
                let c = b[i + k]
                guard c >= 48, c <= 57 else { return nil }
                v = v * 10 + Int(c - 48)
            }
            i += n
            return v
        }
        func eat(_ options: [UInt8]) -> Bool {
            if i < b.count, options.contains(b[i]) { i += 1; return true }
            return false
        }
        guard let year = digits(4), eat([45]), let month = digits(2), eat([45]), let day = digits(2),
              eat([84, 116, 32]), let hour = digits(2), eat([58]), let minute = digits(2), eat([58]),
              let second = digits(2) else { return nil }
        var fraction = 0.0
        if eat([46]) {
            var scale = 0.1
            var count = 0
            while i < b.count, b[i] >= 48, b[i] <= 57 {
                if count < 9 { fraction += Double(b[i] - 48) * scale; scale /= 10 }
                count += 1
                i += 1
            }
            guard count >= 1 else { return nil }
        }
        var offsetSeconds = 0
        if eat([90, 122]) {
            offsetSeconds = 0
        } else if i < b.count, b[i] == 43 || b[i] == 45 {
            let sign = b[i] == 45 ? -1 : 1
            i += 1
            guard let oh = digits(2) else { return nil }
            var om = 0
            if eat([58]) {
                guard let m = digits(2) else { return nil }
                om = m
            } else if i < b.count {
                guard let m = digits(2) else { return nil }
                om = m
            }
            guard oh <= 23, om <= 59 else { return nil }
            offsetSeconds = sign * (oh * 3600 + om * 60)
        } else {
            return nil
        }
        guard i == b.count, (1900...2999).contains(year), (1...12).contains(month), hour <= 23, minute <= 59,
              second <= 59 else { return nil }
        let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        let lengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard day >= 1, day <= lengths[month - 1] else { return nil }
        let days = daysFromCivil(year: year, month: month, day: day)
        let seconds = days * 86_400 + hour * 3600 + minute * 60 + second - offsetSeconds
        return Date(timeIntervalSince1970: Double(seconds) + fraction)
    }

    /// Howard Hinnant's days-from-civil: pure arithmetic, no calendar, locale or time zone.
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (month + 9) % 12
        let doy = (153 * mp + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }
}

// MARK: - Wire limits (mirror support-contract.ts SUPPORT_LIMITS; counts are Unicode scalars, not graphemes)

private enum SupportCloudWireLimits {
    static let title = 80
    static let concern = 4_000
    static let step = 400
    static let note = 1_000
    static let response = 4_000
    static let reason = 40
    static let memoryContent = 500
    static let checkpointBytes = 32 * 1_024
    static let envelopeBytes = 128 * 1_024
    static let requestBodyBytes = 160 * 1_024
    static let memoryEnvelopeBytes = 16 * 1_024
    static let maxActiveMilliseconds: Int64 = 999_999_999_999   // SQL regex ^[0-9]{1,12}$
    static let maxRevision: Int64 = 999_999_999_999_999         // SQL regex ^[0-9]{1,15}$
    static let listMaxLimit = 100
    static let getMaxLimit = 200

    /// Union of the bundled template prompt IDs (TS validates the union; SQL narrows to the activity's template).
    static let knownPromptIDs: Set<String> = Set(SupportActivityTemplateKey.allCases.flatMap {
        SupportTemplateCatalog.standard.promptIDs(template: $0, version: 1) ?? []
    })
}

private func cloudScalarCount(_ s: String) -> Int { s.unicodeScalars.count }

private func cloudCheckText(_ s: String, field: String, max: Int) throws {
    if cloudScalarCount(s) > max { throw SupportCloudError.invalidRequest(.valueTooLong(field: field, limit: max)) }
}

private func cloudUUID(_ id: UUID) -> SupportCloudJSON { .string(id.uuidString.lowercased()) }

// MARK: - Wire mutation (TS flat payload; Swift's Codable associated-value enum is NOT the wire format)

enum SupportCloudWireKind: String, Equatable, Sendable {
    case create
    case updateSession = "update_session"
    case acceptProposal = "accept_proposal"
    case startActivity = "start_activity"
    case checkpointActivity = "checkpoint_activity"
    case finishActivity = "finish_activity"
    case discardActivityAnswers = "discard_activity_answers"
    case recordReflection = "record_reflection"
    case deleteSession = "delete_session"
}

enum SupportCloudPreviousDisposition: String, Equatable, Sendable {
    case save, end
}

/// One immutable, fully validated mutation. `requestData()` is byte-stable: replaying the same value (or the same
/// `SupportMutationEnvelope`) sends exactly the same bytes.
struct SupportCloudWireMutation: Equatable, Sendable {
    let operationID: UUID
    let sessionID: UUID
    let expectedRevision: Int64?
    let kind: SupportCloudWireKind
    let payload: [String: SupportCloudJSON]

    /// Convert the repository's envelope. Only schema/operation/session/expected revision/kind/payload are used;
    /// `payloadFingerprint` (local FNV) is intentionally ignored.
    init(envelope: SupportMutationEnvelope) throws {
        guard envelope.schemaVersion == SupportSessionLimits.schemaVersion else {
            throw SupportCloudError.invalidRequest(.schemaVersion(envelope.schemaVersion))
        }
        guard envelope.kind == envelope.payload.kind else {
            throw SupportCloudError.invalidRequest(.unsupportedValue(field: "kind"))
        }
        let (kind, payload) = try Self.wirePayload(envelope.payload)
        try self.init(operationID: envelope.operationID, sessionID: envelope.sessionID,
                      expectedRevision: envelope.expectedRevision, kind: kind, payload: payload)
    }

    private init(operationID: UUID, sessionID: UUID, expectedRevision: Int64?, kind: SupportCloudWireKind,
                 payload: [String: SupportCloudJSON]) throws {
        if kind == .create {
            guard expectedRevision == nil else { throw SupportCloudError.invalidRequest(.unexpectedExpectedRevision) }
        } else {
            guard let expected = expectedRevision else { throw SupportCloudError.invalidRequest(.missingExpectedRevision) }
            guard expected >= 1, expected <= SupportCloudWireLimits.maxRevision else {
                throw SupportCloudError.invalidRequest(.invalidExpectedRevision(expected))
            }
        }
        self.operationID = operationID
        self.sessionID = sessionID
        self.expectedRevision = expectedRevision
        self.kind = kind
        self.payload = payload
    }

    /// Extension point: `accept_proposal` is not a case of the local `SupportMutationPayload`.
    static func acceptProposal(
        operationID: UUID, sessionID: UUID, expectedRevision: Int64, proposalID: UUID, activityID: UUID,
        previousDisposition: SupportCloudPreviousDisposition? = nil
    ) throws -> SupportCloudWireMutation {
        var payload: [String: SupportCloudJSON] = ["proposal_id": cloudUUID(proposalID), "activity_id": cloudUUID(activityID)]
        if let previousDisposition { payload["previous_disposition"] = .string(previousDisposition.rawValue) }
        return try SupportCloudWireMutation(operationID: operationID, sessionID: sessionID,
                                            expectedRevision: expectedRevision, kind: .acceptProposal, payload: payload)
    }

    /// Extension point: lazy attachment of an owned conversation (`update_session.conversation_id`).
    static func attachConversation(
        operationID: UUID, sessionID: UUID, expectedRevision: Int64, conversationID: UUID
    ) throws -> SupportCloudWireMutation {
        try SupportCloudWireMutation(operationID: operationID, sessionID: sessionID, expectedRevision: expectedRevision,
                                     kind: .updateSession, payload: ["conversation_id": cloudUUID(conversationID)])
    }

    /// Stable request bytes (`op: "mutate"` + flat envelope). Bounded exactly like the Edge parser.
    func requestData() throws -> Data {
        let envelope: [String: SupportCloudJSON] = [
            "schema_version": .int(Int64(SupportSessionLimits.schemaVersion)),
            "operation_id": cloudUUID(operationID),
            "session_id": cloudUUID(sessionID),
            "expected_revision": expectedRevision.map { .int($0) } ?? .null,
            "kind": .string(kind.rawValue),
            "payload": .object(payload),
        ]
        let envelopeBytes = try SupportCloudJSON.object(envelope).jsonbByteCount()
        guard envelopeBytes <= SupportCloudWireLimits.envelopeBytes else {
            throw SupportCloudError.invalidRequest(.tooLarge(field: "envelope", bytes: envelopeBytes,
                                                             limit: SupportCloudWireLimits.envelopeBytes))
        }
        var body = envelope
        body["op"] = .string("mutate")
        let data = try SupportCloudJSON.object(body).stableData()
        guard data.count <= SupportCloudWireLimits.requestBodyBytes else {
            throw SupportCloudError.invalidRequest(.tooLarge(field: "request", bytes: data.count,
                                                             limit: SupportCloudWireLimits.requestBodyBytes))
        }
        return data
    }

    // MARK: Local payload → flat wire payload

    static func wirePayload(_ payload: SupportMutationPayload) throws -> (SupportCloudWireKind, [String: SupportCloudJSON]) {
        switch payload {
        case let .create(title, concern, conversationID, previousSessionID, contextScope):
            try cloudCheckText(title, field: "title", max: SupportCloudWireLimits.title)
            var o: [String: SupportCloudJSON] = ["title": .string(title), "context_scope": .string(contextScope.rawValue)]
            if let concern {
                try cloudCheckText(concern, field: "concern", max: SupportCloudWireLimits.concern)
                o["concern"] = .string(concern)
            }
            if let conversationID { o["conversation_id"] = cloudUUID(conversationID) }
            if let previousSessionID { o["previous_session_id"] = cloudUUID(previousSessionID) }
            return (.create, o)

        case let .declineTemplate(template):
            return (.updateSession, ["decline_template": .string(template.rawValue)])
        case let .attachConversation(conversationID):
            return (.updateSession, ["conversation_id": cloudUUID(conversationID)])
        case let .acceptProposal(proposalID, activityID):
            return (.acceptProposal, ["proposal_id": cloudUUID(proposalID), "activity_id": cloudUUID(activityID)])

        case let .updateSession(title, contextScope, status):
            var o: [String: SupportCloudJSON] = [:]
            if let title {
                try cloudCheckText(title, field: "title", max: SupportCloudWireLimits.title)
                o["title"] = .string(title)
            }
            if let contextScope { o["context_scope"] = .string(contextScope.rawValue) }
            if let status {
                switch status {
                // The repository stops each unfinished activity with its own finish mutation first, so closing the session
                // never completes work and never leaves a pending activity behind.
                case .closed: o["close"] = .string("end_unfinished")
                // Reopen is "continue as a new session" (spec §5.6); deletion is `delete_session`.
                case .open, .deleted: throw SupportCloudError.invalidRequest(.unsupportedValue(field: "status"))
                }
            }
            return (.updateSession, o)

        case let .startActivity(activityID, templateKey, templateVersion, _):
            // Only template version 1 exists on the wire; the server catalog supplies the version. The local canonical
            // reference is an exercise SESSION id and is never sent as `exercise_id` (a catalog id the server resolves).
            guard templateVersion == 1 else { throw SupportCloudError.invalidRequest(.unsupportedTemplateVersion(templateVersion)) }
            return (.startActivity, ["activity_id": cloudUUID(activityID), "template_key": .string(templateKey.rawValue)])

        case let .checkpointActivity(activityID, status, checkpoint, step):
            let pause: Bool
            switch status {
            case .inProgress: pause = false
            case .paused: pause = true
            default: throw SupportCloudError.invalidRequest(.unsupportedValue(field: "checkpoint.status"))
            }
            let wireCheckpoint = try Self.wireCheckpoint(checkpoint, step: step, pause: pause)
            return (.checkpointActivity, [
                "activity_id": cloudUUID(activityID),
                "checkpoint": wireCheckpoint,
                "active_ms": .int(try Self.activeMilliseconds(checkpoint.activeMilliseconds)),
                "pause": .bool(pause),
            ])

        case let .finishActivity(activityID, status, result, step, checkpoint):
            let outcome: String
            switch status {
            case .completed: outcome = "completed"
            case .stopped: outcome = "stopped"
            default: throw SupportCloudError.invalidRequest(.unsupportedValue(field: "finish.status"))
            }
            var o: [String: SupportCloudJSON] = [
                "activity_id": cloudUUID(activityID),
                "outcome": .string(outcome),
                "active_ms": .int(try Self.activeMilliseconds(result.activeMilliseconds)),
            ]
            if status == .stopped {
                if let reason = result.stoppedReason {
                    guard !reason.isEmpty else { throw SupportCloudError.invalidRequest(.emptyValue(field: "reason")) }
                    // Never truncated: a longer reason would change meaning and the server rejects it.
                    try cloudCheckText(reason, field: "reason", max: SupportCloudWireLimits.reason)
                    o["reason"] = .string(reason)
                }
            } else if result.stoppedReason != nil {
                throw SupportCloudError.invalidRequest(.unsupportedValue(field: "result.stoppedReason"))
            }
            guard result.acknowledgedStepCount >= 0, result.skippedStepCount >= 0 else {
                throw SupportCloudError.invalidRequest(.numberOutOfRange(field: "result.count"))
            }
            // Adapter-defined, content-free counters plus the optional approved shareable note. The server treats
            // `result` as an opaque object except `step`/`discarded`.
            var resultObject: [String: SupportCloudJSON] = [
                "acknowledged_count": .int(Int64(result.acknowledgedStepCount)),
                "skipped_count": .int(Int64(result.skippedStepCount)),
            ]
            if let note = result.shareableNote, !note.isEmpty {
                try cloudCheckText(note, field: "shareable_note", max: SupportCloudWireLimits.note)
                resultObject["shareable_note"] = .string(note)
            }
            if let step {
                resultObject["step"] = try Self.wireFinishStep(step, completed: status == .completed)
            }
            o["result"] = .object(resultObject)
            if let checkpoint {
                // Atomic finish: the exact final checkpoint travels WITH the finish; no earlier checkpoint is assumed.
                o["checkpoint"] = try Self.wireCheckpoint(checkpoint, step: nil, pause: nil)
            }
            return (.finishActivity, o)

        case let .recordReflection(activityID, reflection):
            var o: [String: SupportCloudJSON] = [
                "activity_id": cloudUUID(activityID),
                "outcome": .string(reflection.outcome.rawValue),
                "share_note": .bool(reflection.includeWrittenAnswers),
            ]
            if let note = reflection.note, !note.isEmpty {
                try cloudCheckText(note, field: "note", max: SupportCloudWireLimits.note)
                o["note"] = .string(note)
                // The approved note is the only text the person deliberately includes in the conversation.
                if reflection.includeWrittenAnswers { o["shareable_text"] = .string(note) }
            }
            return (.recordReflection, o)

        case let .discardActivityAnswers(activityID):
            return (.discardActivityAnswers, ["activity_id": cloudUUID(activityID)])

        case .deleteSession:
            return (.deleteSession, [:])
        }
    }

    private static func activeMilliseconds(_ value: Int64) throws -> Int64 {
        guard value >= 0, value <= SupportCloudWireLimits.maxActiveMilliseconds else {
            throw SupportCloudError.invalidRequest(.numberOutOfRange(field: "active_ms"))
        }
        return value
    }

    /// Checkpoint v1 exactly as `support_check_prompts` / `support_do_checkpoint` read it:
    /// `version`, `template_version`, `current_step`, `completed_steps`, `skipped_steps`, `responses`, `step`.
    private static func wireCheckpoint(_ cp: SupportCheckpoint, step: SupportStepPayload?, pause: Bool?) throws -> SupportCloudJSON {
        guard cp.payloadVersion == SupportCheckpoint.currentVersion else {
            throw SupportCloudError.invalidRequest(.unsupportedValue(field: "checkpoint.version"))
        }
        guard cp.templateVersion >= 1 else { throw SupportCloudError.invalidRequest(.unsupportedTemplateVersion(cp.templateVersion)) }
        var o: [String: SupportCloudJSON] = [
            "version": .int(Int64(cp.payloadVersion)),
            "template_version": .int(Int64(cp.templateVersion)),
        ]
        if let current = cp.lastPromptID {
            try requireKnownPrompt(current)
            o["current_step"] = .string(current)
        }
        try cp.completedStepIDs.forEach(requireKnownPrompt)
        try cp.skippedStepIDs.forEach(requireKnownPrompt)
        o["completed_steps"] = .array(cp.completedStepIDs.map { .string($0) })
        o["skipped_steps"] = .array(cp.skippedStepIDs.map { .string($0) })
        var responses: [String: SupportCloudJSON] = [:]
        for (id, text) in cp.responses {
            try requireKnownPrompt(id)
            try cloudCheckText(text, field: "checkpoint.responses", max: SupportCloudWireLimits.response)
            responses[id] = .string(text)
        }
        o["responses"] = .object(responses)
        if let step {
            if pause == true {
                // support-contract.ts stepCheck: a paused practical step must be a saved, non-empty step.
                guard step.state == .saved else { throw SupportCloudError.invalidRequest(.unsupportedValue(field: "checkpoint.step.state")) }
            }
            o["step"] = try wireStep(step)
        }
        let json = SupportCloudJSON.object(o)
        let bytes = try json.jsonbByteCount()
        guard bytes <= SupportCloudWireLimits.checkpointBytes else {
            throw SupportCloudError.invalidRequest(.tooLarge(field: "checkpoint", bytes: bytes, limit: SupportCloudWireLimits.checkpointBytes))
        }
        return json
    }

    private static func requireKnownPrompt(_ id: String) throws {
        guard SupportCloudWireLimits.knownPromptIDs.contains(id) else {
            throw SupportCloudError.invalidRequest(.unknownPromptID(String(id.prefix(40))))
        }
    }

    /// Practical step on the wire: exactly `{action_text, state}` (+ nothing else). Reminder metadata is device-local and
    /// is never serialized. A dismissed step carries no text.
    private static func wireStep(_ step: SupportStepPayload) throws -> SupportCloudJSON {
        if step.state == .dismissed { return .object(["state": .string(step.state.rawValue)]) }
        guard !step.actionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SupportCloudError.invalidRequest(.emptyValue(field: "step.action_text"))
        }
        try cloudCheckText(step.actionText, field: "step.action_text", max: SupportCloudWireLimits.step)
        return .object(["action_text": .string(step.actionText), "state": .string(step.state.rawValue)])
    }

    /// `finish_activity.result.step`: completed requires a self-reported, non-empty step (TS stepCheck); a stopped step is
    /// only ever `dismissed` and never carries text.
    private static func wireFinishStep(_ step: SupportStepPayload, completed: Bool) throws -> SupportCloudJSON {
        if completed {
            guard step.state == .selfReportedDone else {
                throw SupportCloudError.invalidRequest(.unsupportedValue(field: "result.step.state"))
            }
        } else {
            guard step.state == .dismissed else {
                throw SupportCloudError.invalidRequest(.unsupportedValue(field: "result.step.state"))
            }
        }
        return try wireStep(step)
    }
}

// MARK: - Strict decoding helpers

struct SupportCloudKey: CodingKey, ExpressibleByStringLiteral {
    let stringValue: String
    var intValue: Int? { nil }
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
    init(stringLiteral value: String) { stringValue = value }
}

/// Every helper throws on a missing key, a wrong type or an out-of-bound value. "Nullable" helpers still REQUIRE the key
/// to be present (the SQL always emits it), so a dropped field can never become a silent success.
private extension KeyedDecodingContainer where K == SupportCloudKey {
    func corrupt(_ key: K, _ why: String) -> DecodingError {
        .dataCorrupted(.init(codingPath: codingPath + [key], debugDescription: why))
    }

    func requirePresent(_ key: K) throws {
        guard contains(key) else {
            throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "missing"))
        }
    }

    func uuid(_ key: K) throws -> UUID { try decode(UUID.self, forKey: key) }

    func uuidOrNull(_ key: K) throws -> UUID? {
        try requirePresent(key)
        return try decodeIfPresent(UUID.self, forKey: key)
    }

    func string(_ key: K, max: Int? = nil) throws -> String {
        let value = try decode(String.self, forKey: key)
        if let max, value.unicodeScalars.count > max { throw corrupt(key, "too long") }
        return value
    }

    func stringOrNull(_ key: K, max: Int? = nil) throws -> String? {
        try requirePresent(key)
        guard let value = try decodeIfPresent(String.self, forKey: key) else { return nil }
        if let max, value.unicodeScalars.count > max { throw corrupt(key, "too long") }
        return value
    }

    func int64(_ key: K, _ range: ClosedRange<Int64>) throws -> Int64 {
        let value = try decode(Int64.self, forKey: key)
        guard range.contains(value) else { throw corrupt(key, "out of range") }
        return value
    }

    func int64OrNull(_ key: K, _ range: ClosedRange<Int64>) throws -> Int64? {
        try requirePresent(key)
        guard let value = try decodeIfPresent(Int64.self, forKey: key) else { return nil }
        guard range.contains(value) else { throw corrupt(key, "out of range") }
        return value
    }

    func bool(_ key: K) throws -> Bool { try decode(Bool.self, forKey: key) }

    /// Optional key that the SQL only emits sometimes (e.g. `no_op`, `closed`). Absent or null -> nil.
    func optionalBool(_ key: K) throws -> Bool? { try decodeIfPresent(Bool.self, forKey: key) }

    func date(_ key: K) throws -> Date {
        guard let date = SupportCloudDate.parse(try decode(String.self, forKey: key)) else { throw corrupt(key, "bad date") }
        return date
    }

    func dateOrNull(_ key: K) throws -> Date? {
        try requirePresent(key)
        guard let text = try decodeIfPresent(String.self, forKey: key) else { return nil }
        guard let date = SupportCloudDate.parse(text) else { throw corrupt(key, "bad date") }
        return date
    }

    func enumValue<E: RawRepresentable>(_ key: K, as type: E.Type) throws -> E where E.RawValue == String {
        guard let value = E(rawValue: try decode(String.self, forKey: key)) else { throw corrupt(key, "unknown value") }
        return value
    }

    func enumOrNull<E: RawRepresentable>(_ key: K, as type: E.Type) throws -> E? where E.RawValue == String {
        try requirePresent(key)
        guard let raw = try decodeIfPresent(String.self, forKey: key) else { return nil }
        guard let value = E(rawValue: raw) else { throw corrupt(key, "unknown value") }
        return value
    }

    func json(_ key: K) throws -> SupportCloudJSON { try decode(SupportCloudJSON.self, forKey: key) }

    /// A required-present JSON object or null (checkpoint/result/reflection columns).
    func objectOrNull(_ key: K) throws -> [String: SupportCloudJSON]? {
        try requirePresent(key)
        switch try json(key) {
        case .null: return nil
        case .object(let o): return o
        default: throw corrupt(key, "expected object")
        }
    }
}

enum SupportCloudDecoding {
    /// Decode a contract body. Every failure is a content-free `malformedResponse` naming only the key path.
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch let error as SupportCloudError {
            throw error
        } catch let error as DecodingError {
            throw SupportCloudError.malformedResponse(describe(error))
        } catch {
            throw SupportCloudError.malformedResponse("decode")
        }
    }

    static func describe(_ error: DecodingError) -> String {
        let (kind, path): (String, [CodingKey])
        switch error {
        case .keyNotFound(let key, let ctx): (kind, path) = ("missing", ctx.codingPath + [key])
        case .typeMismatch(_, let ctx): (kind, path) = ("type", ctx.codingPath)
        case .valueNotFound(_, let ctx): (kind, path) = ("null", ctx.codingPath)
        case .dataCorrupted(let ctx): (kind, path) = ("invalid", ctx.codingPath)
        @unknown default: (kind, path) = ("decode", [])
        }
        let joined = path.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
        return "\(kind):\(joined.prefix(120))"
    }
}

private func malformed(_ what: String) -> SupportCloudError { .malformedResponse(what) }

// MARK: - Capabilities (session_contract / context_policy / voice_context are independent)

struct SupportCloudCapabilities: Equatable, Sendable, Decodable {
    enum Status: String, Equatable, Sendable { case ok, notDeployed = "not_deployed" }

    /// 0 = not deployed. Negotiated separately (spec §10.1).
    let sessionContract: Int
    let contextPolicy: Int
    let voiceContext: Int
    let privacyRevision: Bool
    let memoryLifecycle: Bool
    let chatConfirmation: Bool
    let lazyAttach: Bool
    let schema: String?
    let status: Status

    static let notDeployed = SupportCloudCapabilities(
        sessionContract: 0, contextPolicy: 0, voiceContext: 0, privacyRevision: false, memoryLifecycle: false,
        chatConfirmation: false, lazyAttach: false, schema: nil, status: .notDeployed)

    init(sessionContract: Int, contextPolicy: Int, voiceContext: Int, privacyRevision: Bool, memoryLifecycle: Bool,
         chatConfirmation: Bool, lazyAttach: Bool, schema: String?, status: Status) {
        self.sessionContract = sessionContract
        self.contextPolicy = contextPolicy
        self.voiceContext = voiceContext
        self.privacyRevision = privacyRevision
        self.memoryLifecycle = memoryLifecycle
        self.chatConfirmation = chatConfirmation
        self.lazyAttach = lazyAttach
        self.schema = schema
        self.status = status
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: SupportCloudKey.self)
        sessionContract = Int(try c.int64("session_contract", 0...1_000))
        contextPolicy = Int(try c.int64("context_policy", 0...1_000))
        voiceContext = Int(try c.int64("voice_context", 0...1_000))
        // Optional advertisements: absent means "not advertised", which fails closed.
        privacyRevision = try c.optionalBool("privacy_revision") ?? false
        memoryLifecycle = try c.optionalBool("memory_lifecycle") ?? false
        chatConfirmation = try c.optionalBool("chat_confirmation") ?? false
        lazyAttach = try c.optionalBool("lazy_attach") ?? false
        schema = try c.decodeIfPresent(String.self, forKey: "schema").map { String($0.prefix(40)) }
        status = try c.enumValue("status", as: Status.self)
        if status == .notDeployed, sessionContract != 0 || contextPolicy != 0 || voiceContext != 0 {
            throw c.corrupt("status", "not_deployed with non-zero versions")
        }
    }

    var isNotDeployed: Bool { status == .notDeployed }
    var sessionContractAvailable: Bool { sessionContract >= 1 }
    var contextPolicyAvailable: Bool { contextPolicy >= 1 }
    var voiceContextAvailable: Bool { voiceContext >= 1 }
    /// Cloud chat may use personal context only if the server can enforce scope AND the acknowledged privacy revision
    /// (spec §10.1). Anything less pauses personalized cloud chat; it never falls back to an older privacy path.
    var canEnforcePrivacyForChat: Bool { contextPolicy >= 1 && privacyRevision }
}

// MARK: - Canonical session / activity / proposal records

enum SupportCloudActivityKind: String, Equatable, Sendable {
    case grounding, untangle
    case nextStep = "next_step"

    static func expected(for template: SupportActivityTemplateKey) -> SupportCloudActivityKind {
        switch template {
        case .groundPresentV1: return .grounding
        case .untangleThoughtV1: return .untangle
        case .chooseStepV1: return .nextStep
        }
    }
}

struct SupportCloudSessionRecord: Equatable, Sendable, Decodable {
    let id: UUID
    let conversationID: UUID?
    let previousSessionID: UUID?
    let selectedActivityID: UUID?
    let title: String
    let concern: String?
    let status: SupportSessionStatus
    let contextScope: SupportContextScope
    /// Server-authoritative, session-wide revision.
    let revision: Int64
    let suppressedTemplates: [SupportActivityTemplateKey]
    let createdAt: Date
    let updatedAt: Date
    let closedAt: Date?
    let deletedAt: Date?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: SupportCloudKey.self)
        id = try c.uuid("id")
        conversationID = try c.uuidOrNull("conversation_id")
        previousSessionID = try c.uuidOrNull("previous_session_id")
        selectedActivityID = try c.uuidOrNull("selected_activity_id")
        title = try c.string("title", max: SupportCloudWireLimits.title)
        concern = try c.stringOrNull("concern", max: SupportCloudWireLimits.concern)
        status = try c.enumValue("status", as: SupportSessionStatus.self)
        contextScope = try c.enumValue("context_scope", as: SupportContextScope.self)
        revision = try c.int64("revision", 1...SupportCloudWireLimits.maxRevision)
        let templates = try c.decode([String].self, forKey: "suppressed_templates")
        suppressedTemplates = try templates.map {
            guard let key = SupportActivityTemplateKey(rawValue: $0) else { throw c.corrupt("suppressed_templates", "unknown template") }
            return key
        }
        createdAt = try c.date("created_at")
        updatedAt = try c.date("updated_at")
        closedAt = try c.dateOrNull("closed_at")
        deletedAt = try c.dateOrNull("deleted_at")
    }
}

struct SupportCloudReflectionRecord: Equatable, Sendable {
    let outcome: SupportReflectionOutcome
    let note: String?
    let shareNote: Bool
    let shareableText: String?
}

struct SupportCloudActivityRecord: Equatable, Sendable, Decodable {
    let id: UUID
    let templateKey: SupportActivityTemplateKey
    let templateVersion: Int
    let kind: SupportCloudActivityKind
    let status: SupportActivityStatus
    let stopReason: String?
    let canonicalReference: SupportCanonicalReference?
    /// Raw v1 checkpoint object (mapped explicitly by `localActivity`).
    let checkpoint: [String: SupportCloudJSON]?
    /// Raw adapter result object (mapped explicitly by `localActivity`).
    let result: [String: SupportCloudJSON]?
    let reflection: SupportCloudReflectionRecord?
    let activeMilliseconds: Int64
    let lastChangedRevision: Int64
    let createdAt: Date
    let updatedAt: Date
    let finishedAt: Date?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: SupportCloudKey.self)
        id = try c.uuid("id")
        templateKey = try c.enumValue("template_key", as: SupportActivityTemplateKey.self)
        templateVersion = Int(try c.int64("template_version", 1...1_000))
        kind = try c.enumValue("kind", as: SupportCloudActivityKind.self)
        guard kind == SupportCloudActivityKind.expected(for: templateKey) else { throw c.corrupt("kind", "kind/template mismatch") }
        status = try c.enumValue("status", as: SupportActivityStatus.self)
        stopReason = try c.stringOrNull("stop_reason", max: SupportCloudWireLimits.reason)
        let refType = try c.enumOrNull("canonical_ref_type", as: SupportCanonicalReferenceKind.self)
        let refID = try c.uuidOrNull("canonical_ref_id")
        switch (refType, refID) {
        case let (type?, id?): canonicalReference = SupportCanonicalReference(kind: type, id: id)
        case (nil, nil): canonicalReference = nil
        default: throw c.corrupt("canonical_ref_type", "reference type and id must come together")
        }
        checkpoint = try c.objectOrNull("checkpoint")
        result = try c.objectOrNull("result")
        if let r = try c.objectOrNull("reflection") {
            guard let outcomeText = r["outcome"]?.stringValue, let outcome = SupportReflectionOutcome(rawValue: outcomeText),
                  let share = r["share_note"]?.boolValue else { throw c.corrupt("reflection", "bad reflection") }
            func optionalText(_ key: String) throws -> String? {
                guard let v = r[key] else { throw c.corrupt("reflection", "missing \(key)") }
                if v.isNull { return nil }
                guard let s = v.stringValue, s.unicodeScalars.count <= SupportCloudWireLimits.note else { throw c.corrupt("reflection", "bad \(key)") }
                return s
            }
            reflection = SupportCloudReflectionRecord(outcome: outcome, note: try optionalText("note"), shareNote: share,
                                                     shareableText: try optionalText("shareable_text"))
        } else {
            reflection = nil
        }
        activeMilliseconds = try c.int64("active_ms", 0...SupportCloudWireLimits.maxActiveMilliseconds)
        lastChangedRevision = try c.int64("last_changed_revision", 1...SupportCloudWireLimits.maxRevision)
        createdAt = try c.date("created_at")
        updatedAt = try c.date("updated_at")
        finishedAt = try c.dateOrNull("finished_at")
        // support_activities_finished_shape: finished_at is set exactly for terminal statuses.
        guard status.isTerminal == (finishedAt != nil) else { throw c.corrupt("finished_at", "finished_at/status mismatch") }
    }
}

enum SupportCloudProposalReason: String, Equatable, Sendable {
    case currentRequest = "current_request"
    case approvedPreference = "approved_preference"
    case selectedIntent = "selected_intent"
    case generalOption = "general_option"
}

enum SupportCloudProposalBasisKind: String, Equatable, Sendable {
    case companionMemory = "companion_memory"
    case message
    case activity
}

struct SupportCloudProposalRecord: Equatable, Sendable, Decodable {
    let id: UUID
    let templateKey: SupportActivityTemplateKey
    let reasonCode: SupportCloudProposalReason
    let basisKind: SupportCloudProposalBasisKind?
    let basisRef: UUID?
    let suggestedStep: String?
    let expiresAt: Date

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: SupportCloudKey.self)
        id = try c.uuid("id")
        templateKey = try c.enumValue("template_key", as: SupportActivityTemplateKey.self)
        reasonCode = try c.enumValue("reason_code", as: SupportCloudProposalReason.self)
        basisKind = try c.enumOrNull("basis_kind", as: SupportCloudProposalBasisKind.self)
        basisRef = try c.uuidOrNull("basis_ref")
        guard (basisKind == nil) == (basisRef == nil) else { throw c.corrupt("basis_kind", "basis kind/ref mismatch") }
        suggestedStep = try c.stringOrNull("suggested_step", max: SupportCloudWireLimits.step)
        if suggestedStep != nil, templateKey != .chooseStepV1 { throw c.corrupt("suggested_step", "step only for choose_step") }
        guard try c.string("status") == "offered" else { throw c.corrupt("status", "only offered proposals are actionable") }
        expiresAt = try c.date("expires_at")
    }
}

struct SupportCloudSnapshot: Equatable, Sendable, Decodable {
    let session: SupportCloudSessionRecord
    let activities: [SupportCloudActivityRecord]
    /// Only currently actionable proposals (server filters offered/unexpired/current privacy revision).
    let proposals: [SupportCloudProposalRecord]
    let privacyRevision: Int64

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: SupportCloudKey.self)
        session = try c.decode(SupportCloudSessionRecord.self, forKey: "session")
        activities = try c.decode([SupportCloudActivityRecord].self, forKey: "activities")
        proposals = try c.decode([SupportCloudProposalRecord].self, forKey: "proposals")
        privacyRevision = try c.int64("privacy_revision", 1...SupportCloudWireLimits.maxRevision)
        guard activities.count <= SupportSessionLimits.maxActivitiesPerSession, proposals.count <= 100 else {
            throw c.corrupt("activities", "too many records")
        }
        guard Set(activities.map(\.id)).count == activities.count, Set(proposals.map(\.id)).count == proposals.count else {
            throw c.corrupt("activities", "duplicate ids")
        }
        guard activities.filter({ $0.status == .inProgress }).count <= 1 else {
            throw c.corrupt("activities", "more than one in-progress activity")
        }
        if session.status != .deleted, let selected = session.selectedActivityID,
           !activities.contains(where: { $0.id == selected }) {
            throw c.corrupt("session", "selected activity is not part of the snapshot")
        }
    }
}

// MARK: - Mutation replies

struct SupportCloudXP: Equatable, Sendable, Decodable {
    let amount: Int64
    let newXP: Int64
    let newLevel: Int64
    let levelUp: Bool

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: SupportCloudKey.self)
        amount = try c.int64("amount", 0...Int64(Int32.max))
        newXP = try c.int64("new_xp", 0...Int64(Int32.max))
        newLevel = try c.int64("new_level", 0...Int64(Int32.max))
        levelUp = try c.bool("level_up")
    }
}

/// Confirmed (200, `ok: true`) reply to `mutate`, including confirmed replays and semantic no-ops.
struct SupportCloudMutationConfirmation: Equatable, Sendable, Decodable {
    let operationID: UUID
    let kind: SupportCloudWireKind
    /// Resulting revision of THIS operation (a replay may find the session already past it).
    let revision: Int64
    let noOp: Bool
    let replayed: Bool
    let eventID: UUID?
    let activityID: UUID?
    let serverTime: Date
    let snapshot: SupportCloudSnapshot
    let xp: SupportCloudXP?
    let closed: Bool?
    let deleted: Bool?
    /// Present on a no-op refused for a reason (`activity_finished`, `activity_discarded`).
    let reason: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: SupportCloudKey.self)
        guard try c.bool("ok") else { throw c.corrupt("ok", "ok must be true") }
        operationID = try c.uuid("operation_id")
        kind = try c.enumValue("kind", as: SupportCloudWireKind.self)
        revision = try c.int64("revision", 1...SupportCloudWireLimits.maxRevision)
        noOp = try c.bool("no_op")
        replayed = try c.bool("replayed")
        eventID = try c.uuidOrNull("event_id")
        activityID = try c.uuidOrNull("activity_id")
        guard try c.string("sync_status") == "synced" else { throw c.corrupt("sync_status", "not synced") }
        serverTime = try c.date("server_time")
        snapshot = try c.decode(SupportCloudSnapshot.self, forKey: "snapshot")
        xp = try c.decodeIfPresent(SupportCloudXP.self, forKey: "xp")
        closed = try c.optionalBool("closed")
        deleted = try c.optionalBool("deleted")
        reason = try c.decodeIfPresent(String.self, forKey: "reason").map { String($0.prefix(40)) }
    }

    /// Cross-checks the reply against the request it answers. A reply only settles an operation if it PROVES the
    /// requested effect (mirrors `support_apply_mutation`, 20261106230100 RPC SQL):
    ///
    /// * always: operation/kind/session echo; `no_op` ⇔ no event; an activity operation echoes the REQUESTED activity;
    ///   a non-activity operation names none; a live (non-tombstone) snapshot contains the target activity.
    /// * first application (`replayed == false`): the snapshot IS the receipt's revision; `create` is revision 1; a
    ///   changed session is `expectedRevision + 1` with an event; a semantic no-op keeps `expectedRevision`; and the
    ///   snapshot shows the requested status/effect with `last_changed_revision` equal to the new revision.
    /// * replay (`replayed == true`): the receipt is HISTORICAL. The latest snapshot may be ahead of it, may no longer
    ///   show the original effect, and may be a deleted tombstone without the old target row. None of that is checked.
    ///
    /// Extra unrelated activities in a snapshot are never proof of the requested effect.
    func validated(against request: SupportCloudWireMutation) throws -> SupportCloudMutationConfirmation {
        guard operationID == request.operationID, kind == request.kind else { throw malformed("operation echo mismatch") }
        guard snapshot.session.id == request.sessionID else { throw malformed("snapshot session mismatch") }
        guard noOp == (eventID == nil) else { throw malformed("event/no-op mismatch") }
        if kind == .create, revision != 1 { throw malformed("create revision") }
        let tombstone = snapshot.session.status == .deleted
        if deleted == true, !tombstone { throw malformed("deleted flag without tombstone") }

        if request.kind.targetsActivity {
            guard let requested = request.targetActivityID, activityID == requested else { throw malformed("activity target mismatch") }
        } else {
            guard activityID == nil else { throw malformed("unexpected activity target") }
        }
        let target = activityID.flatMap { id in snapshot.activities.first { $0.id == id } }
        if activityID != nil, !tombstone, target == nil { throw malformed("activity missing from snapshot") }

        if replayed {
            guard snapshot.session.revision >= revision else { throw malformed("snapshot behind receipt") }
            return self
        }
        guard snapshot.session.revision == revision else { throw malformed("snapshot revision mismatch") }
        if request.kind == .create {
            guard !noOp else { throw malformed("create cannot be a no-op") }
        } else {
            guard let expected = request.expectedRevision else { throw malformed("request without expected revision") }
            guard revision == (noOp ? expected : expected + 1) else { throw malformed("revision relation") }
        }
        if !noOp { try requireEffect(of: request, target: target, tombstone: tombstone) }
        return self
    }

    /// The snapshot must show what a newly applied (non-no-op) mutation just did.
    private func requireEffect(of request: SupportCloudWireMutation, target: SupportCloudActivityRecord?, tombstone: Bool) throws {
        let session = snapshot.session
        if request.kind.targetsActivity {
            guard let target, target.lastChangedRevision == revision else { throw malformed("activity not changed at revision") }
        }
        let payload = request.payload
        switch request.kind {
        case .create:
            guard session.status == .open else { throw malformed("created session not open") }
        case .updateSession:
            guard !tombstone else { throw malformed("update produced a tombstone") }
            if let scope = payload["context_scope"]?.stringValue, session.contextScope.rawValue != scope { throw malformed("scope not applied") }
            // PostgreSQL `btrim(text)` removes SPACES only (not tabs or newlines), exactly as `support_do_update_session` applies it.
            if let title = payload["title"]?.stringValue,
               session.title != title.trimmingCharacters(in: CharacterSet(charactersIn: " ")) { throw malformed("title not applied") }
            if let conversation = payload["conversation_id"]?.stringValue,
               session.conversationID != UUID(uuidString: conversation) { throw malformed("conversation not attached") }
            if payload["close"] != nil {
                guard session.status == .closed, closed == true else { throw malformed("close not applied") }
            }
        case .acceptProposal:
            guard target?.status == .ready else { throw malformed("accepted activity not ready") }
        case .startActivity:
            guard target?.status == .inProgress else { throw malformed("started activity not in progress") }
        case .checkpointActivity:
            let expected: SupportActivityStatus = payload["pause"]?.boolValue == true ? .paused : .inProgress
            guard target?.status == expected else { throw malformed("checkpoint status not applied") }
        case .finishActivity:
            let expected: SupportActivityStatus = payload["outcome"]?.stringValue == "completed" ? .completed : .stopped
            guard target?.status == expected else { throw malformed("finish status not applied") }
        case .recordReflection:
            guard target?.reflection?.outcome.rawValue == payload["outcome"]?.stringValue else { throw malformed("reflection not applied") }
        case .discardActivityAnswers:
            guard target?.result?["discarded"]?.boolValue == true else { throw malformed("discard not applied") }
        case .deleteSession:
            guard tombstone, deleted == true else { throw malformed("delete not applied") }
        }
    }
}

extension SupportCloudWireKind {
    /// Kinds whose payload names an `activity_id` the reply must echo.
    var targetsActivity: Bool {
        switch self {
        case .acceptProposal, .startActivity, .checkpointActivity, .finishActivity, .recordReflection, .discardActivityAnswers:
            return true
        case .create, .updateSession, .deleteSession:
            return false
        }
    }
}

extension SupportCloudWireMutation {
    /// The activity the payload targets, when it has one.
    var targetActivityID: UUID? { payload["activity_id"]?.stringValue.flatMap { UUID(uuidString: $0) } }
}

struct SupportCloudRevisionConflict: Equatable, Sendable {
    let currentRevision: Int64
    /// The server's current snapshot, when supplied; its revision always equals `currentRevision`.
    let snapshot: SupportCloudSnapshot?
}

enum SupportCloudMutationResult: Equatable, Sendable {
    case confirmed(SupportCloudMutationConfirmation)
    /// Definitive 409 `REVISION_CONFLICT`: the operation was NOT applied. Rebase against the snapshot with a NEW operation ID.
    case conflict(SupportCloudRevisionConflict)

    var attemptOutcome: SupportAttemptOutcome {
        switch self {
        case .confirmed(let confirmation): return .confirmed(revision: confirmation.revision)
        case .conflict(let conflict): return .revisionConflict(currentRevision: conflict.currentRevision)
        }
    }
}

// MARK: - get / list

enum SupportCloudEventKind: String, Equatable, Sendable {
    case sessionCreated = "session_created"
    case sessionUpdated = "session_updated"
    case sessionClosed = "session_closed"
    case proposalAccepted = "proposal_accepted"
    case activityStarted = "activity_started"
    case activityCheckpointed = "activity_checkpointed"
    case activityPaused = "activity_paused"
    case activityCompleted = "activity_completed"
    case activityStopped = "activity_stopped"
    case activityDiscarded = "activity_discarded"
    case reflectionRecorded = "reflection_recorded"
    case sessionDeleted = "session_deleted"
}

struct SupportCloudSessionEvent: Equatable, Sendable, Decodable {
    let id: UUID
    let activityID: UUID?
    let operationID: UUID
    let kind: SupportCloudEventKind
    let sequence: Int64
    let clientOccurredAt: Date?
    let acceptedAt: Date
    /// Minimal, content-free (≤ 2 KiB) payload; not interpreted here.
    let payload: [String: SupportCloudJSON]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: SupportCloudKey.self)
        id = try c.uuid("id")
        activityID = try c.uuidOrNull("activity_id")
        operationID = try c.uuid("operation_id")
        kind = try c.enumValue("kind", as: SupportCloudEventKind.self)
        sequence = try c.int64("seq", 1...SupportCloudWireLimits.maxRevision)
        clientOccurredAt = try c.dateOrNull("client_occurred_at")
        acceptedAt = try c.date("accepted_at")
        guard let object = try c.objectOrNull("payload") else { throw c.corrupt("payload", "payload must be an object") }
        payload = object
    }
}

/// `get`: the current snapshot plus one page of events ordered by `seq`.
struct SupportCloudSessionDetail: Equatable, Sendable, Decodable {
    let snapshot: SupportCloudSnapshot
    let events: [SupportCloudSessionEvent]
    let serverTime: Date

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: SupportCloudKey.self)
        guard try c.bool("ok") else { throw c.corrupt("ok", "ok must be true") }
        snapshot = try c.decode(SupportCloudSnapshot.self, forKey: "snapshot")
        events = try c.decode([SupportCloudSessionEvent].self, forKey: "events")
        serverTime = try c.date("server_time")
        guard events.count <= SupportCloudWireLimits.getMaxLimit else { throw c.corrupt("events", "too many events") }
    }

    /// Resume point for the next page; nil when no events were returned.
    var nextAfterSequence: Int64? { events.last?.sequence }

    func validated(sessionID: UUID, afterSequence: Int64, limit: Int) throws -> SupportCloudSessionDetail {
        guard snapshot.session.id == sessionID else { throw malformed("snapshot session mismatch") }
        guard events.count <= limit else { throw malformed("events exceed limit") }
        var previous = afterSequence
        for event in events {
            guard event.sequence > previous else { throw malformed("event sequence order") }
            previous = event.sequence
        }
        return self
    }

    /// True when the page was full, so another page may exist.
    func mayHaveMoreEvents(limit: Int) -> Bool { events.count >= limit }
}

/// Opaque, stable `(updated_at, id)` cursor. `updatedAt` is the server's EXACT string (microsecond precision) and is
/// sent back verbatim: re-formatting through `Date` would lose precision and duplicate or skip rows.
struct SupportCloudListCursor: Equatable, Sendable, Decodable {
    let updatedAt: String
    let id: UUID

    init(updatedAt: String, id: UUID) throws {
        guard SupportCloudDate.parse(updatedAt) != nil else {
            throw SupportCloudError.invalidRequest(.unsupportedValue(field: "cursor.updated_at"))
        }
        self.updatedAt = updatedAt
        self.id = id
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: SupportCloudKey.self)
        let text = try c.string("updated_at")
        guard SupportCloudDate.parse(text) != nil else { throw c.corrupt("updated_at", "bad date") }
        updatedAt = text
        id = try c.uuid("id")
    }
}

struct SupportCloudSelectedActivitySummary: Equatable, Sendable {
    let id: UUID
    let templateKey: SupportActivityTemplateKey
    let status: SupportActivityStatus
}

struct SupportCloudSessionSummary: Equatable, Sendable, Decodable {
    let id: UUID
    let conversationID: UUID?
    let previousSessionID: UUID?
    let title: String
    let status: SupportSessionStatus
    let contextScope: SupportContextScope
    let revision: Int64
    let selectedActivityID: UUID?
    let createdAt: Date
    let updatedAt: Date
    /// Exact server string for `updated_at`; use `cursor` to resume after this row.
    let updatedAtWire: String
    let closedAt: Date?
    let deletedAt: Date?
    let unfinishedCount: Int
    let selectedActivity: SupportCloudSelectedActivitySummary?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: SupportCloudKey.self)
        id = try c.uuid("id")
        conversationID = try c.uuidOrNull("conversation_id")
        previousSessionID = try c.uuidOrNull("previous_session_id")
        title = try c.string("title", max: SupportCloudWireLimits.title)
        status = try c.enumValue("status", as: SupportSessionStatus.self)
        contextScope = try c.enumValue("context_scope", as: SupportContextScope.self)
        revision = try c.int64("revision", 1...SupportCloudWireLimits.maxRevision)
        selectedActivityID = try c.uuidOrNull("selected_activity_id")
        createdAt = try c.date("created_at")
        updatedAtWire = try c.string("updated_at")
        guard let parsed = SupportCloudDate.parse(updatedAtWire) else { throw c.corrupt("updated_at", "bad date") }
        updatedAt = parsed
        closedAt = try c.dateOrNull("closed_at")
        deletedAt = try c.dateOrNull("deleted_at")
        unfinishedCount = Int(try c.int64("unfinished_count", 0...1_000))
        try c.requirePresent("selected_activity")
        if let s = try c.decodeIfPresent([String: SupportCloudJSON].self, forKey: "selected_activity") {
            guard let idText = s["id"]?.stringValue, let sid = UUID(uuidString: idText),
                  let keyText = s["template_key"]?.stringValue, let key = SupportActivityTemplateKey(rawValue: keyText),
                  let statusText = s["status"]?.stringValue, let st = SupportActivityStatus(rawValue: statusText) else {
                throw c.corrupt("selected_activity", "bad selected activity")
            }
            selectedActivity = SupportCloudSelectedActivitySummary(id: sid, templateKey: key, status: st)
        } else {
            selectedActivity = nil
        }
    }

    /// Cursor positioned AFTER this row (for resuming an ascending incremental sync from a short page).
    var cursor: SupportCloudListCursor? { try? SupportCloudListCursor(updatedAt: updatedAtWire, id: id) }
}

struct SupportCloudSessionPage: Equatable, Sendable, Decodable {
    let items: [SupportCloudSessionSummary]
    /// nil when the page was not full (the listing is exhausted at this point in time).
    let nextCursor: SupportCloudListCursor?
    let privacyRevision: Int64
    let serverTime: Date

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: SupportCloudKey.self)
        guard try c.bool("ok") else { throw c.corrupt("ok", "ok must be true") }
        items = try c.decode([SupportCloudSessionSummary].self, forKey: "items")
        try c.requirePresent("next_cursor")
        nextCursor = try c.decodeIfPresent(SupportCloudListCursor.self, forKey: "next_cursor")
        privacyRevision = try c.int64("privacy_revision", 1...SupportCloudWireLimits.maxRevision)
        serverTime = try c.date("server_time")
        guard items.count <= SupportCloudWireLimits.listMaxLimit else { throw c.corrupt("items", "too many items") }
        guard Set(items.map(\.id)).count == items.count else { throw c.corrupt("items", "duplicate ids") }
        if nextCursor != nil, items.isEmpty { throw c.corrupt("next_cursor", "cursor without items") }
    }
}

enum SupportCloudListDirection: String, Equatable, Sendable {
    case ascending = "asc"
    case descending = "desc"
}

// MARK: - Context receipt (spec §8.3)

enum SupportCloudContextSourceKind: String, Equatable, Sendable {
    case message
    case companionMemory = "companion_memory"
    case dailyIntent = "daily_intent"
    case session
    case activityResult = "activity_result"
    case safetyPolicy = "safety_policy"
}

enum SupportCloudContextSourceState: String, Equatable, Sendable {
    case available
    /// Forgotten, suppressed or deleted since it was sent. Show "Context removed"; never resurrect detail.
    case removed
}

struct SupportCloudContextSource: Equatable, Sendable, Decodable {
    let kind: SupportCloudContextSourceKind
    let id: UUID
    let revisionAtSend: Int64
    let date: Date?
    let state: SupportCloudContextSourceState
    /// Minimal explanatory label (memory category). Always nil for a removed source.
    let label: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: SupportCloudKey.self)
        kind = try c.enumValue("kind", as: SupportCloudContextSourceKind.self)
        id = try c.uuid("id")
        revisionAtSend = try c.int64("revision_at_send", 0...SupportCloudWireLimits.maxRevision)
        date = try c.dateOrNull("date")
        state = try c.enumValue("state", as: SupportCloudContextSourceState.self)
        let decodedLabel = try c.stringOrNull("label", max: 64)
        label = state == .removed ? nil : decodedLabel
    }
}

struct SupportCloudContextProvider: Equatable, Sendable {
    let vendor: String
    let model: String
    let routeVersion: String
}

struct SupportCloudContextReceipt: Equatable, Sendable, Decodable {
    let schemaVersion: Int
    let receiptID: UUID
    let requestID: UUID
    let supportSessionID: UUID?
    let conversationID: UUID
    let assistantMessageID: UUID?
    let privacyRevision: Int64
    let scope: SupportContextScope
    let provider: SupportCloudContextProvider
    let sources: [SupportCloudContextSource]
    /// Category names of context that was NOT included.
    let exclusions: [String]
    let createdAt: Date

    init(from decoder: Decoder) throws {
        let outer = try decoder.container(keyedBy: SupportCloudKey.self)
        guard try outer.bool("ok") else { throw outer.corrupt("ok", "ok must be true") }
        let c = try outer.nestedContainer(keyedBy: SupportCloudKey.self, forKey: "receipt")
        schemaVersion = Int(try c.int64("schema_version", 1...1_000))
        receiptID = try c.uuid("receipt_id")
        requestID = try c.uuid("request_id")
        supportSessionID = try c.uuidOrNull("support_session_id")
        conversationID = try c.uuid("conversation_id")
        assistantMessageID = try c.uuidOrNull("assistant_message_id")
        privacyRevision = try c.int64("privacy_revision", 1...SupportCloudWireLimits.maxRevision)
        scope = try c.enumValue("scope", as: SupportContextScope.self)
        let p = try c.nestedContainer(keyedBy: SupportCloudKey.self, forKey: "provider")
        provider = SupportCloudContextProvider(vendor: try p.string("vendor", max: 32), model: try p.string("model", max: 64),
                                               routeVersion: try p.string("route_version", max: 32))
        sources = try c.decode([SupportCloudContextSource].self, forKey: "sources")
        exclusions = try c.decode([String].self, forKey: "exclusions")
        createdAt = try c.date("created_at")
        guard sources.count <= 200, exclusions.count <= 50, exclusions.allSatisfy({ $0.unicodeScalars.count <= 64 }) else {
            throw c.corrupt("sources", "receipt out of bounds")
        }
    }
}

enum SupportCloudReceiptResult: Equatable, Sendable {
    case available(SupportCloudContextReceipt)
    /// No receipt was recorded for this request (an older reply, or pre-contract). The UI must say
    /// "Context details are unavailable for this older reply", never "No memory was used".
    case unavailableOlderReply
}

// MARK: - Memory (support_list_memory / support_memory_mutate)

enum SupportCloudMemoryCategory: String, Equatable, Sendable, CaseIterable {
    case boundaries, preferences, triggers
    case avoidTopics = "avoid_topics"
    case positiveReinforcement = "positive_reinforcement"
    case lifeContext = "life_context"
}

enum SupportCloudMemoryOrigin: String, Equatable, Sendable {
    case userAuthored = "user_authored"
    case approvedCandidate = "approved_candidate"
}

enum SupportCloudMemoryState: String, Equatable, Sendable {
    case confirmed, disabled, expired, stale, excluded
}

struct SupportCloudSavedMemory: Equatable, Sendable, Decodable {
    let id: UUID
    let category: SupportCloudMemoryCategory
    let content: String
    let origin: SupportCloudMemoryOrigin
    let revision: Int64
    let state: SupportCloudMemoryState
    let confirmedAt: Date?
    let reviewDueAt: Date?
    let expiresAt: Date?
    let disabledAt: Date?
    let lastUsedAt: Date?
    let sourceMessageID: UUID?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: SupportCloudKey.self)
        id = try c.uuid("id")
        category = try c.enumValue("category", as: SupportCloudMemoryCategory.self)
        content = try c.string("content")
        origin = try c.enumValue("origin", as: SupportCloudMemoryOrigin.self)
        revision = try c.int64("revision", 1...Int64(Int32.max))
        state = try c.enumValue("state", as: SupportCloudMemoryState.self)
        confirmedAt = try c.dateOrNull("confirmed_at")
        reviewDueAt = try c.dateOrNull("review_due_at")
        expiresAt = try c.dateOrNull("expires_at")
        disabledAt = try c.dateOrNull("disabled_at")
        lastUsedAt = try c.dateOrNull("last_used_at")
        sourceMessageID = try c.uuidOrNull("source_message_id")
    }
}

enum SupportCloudFragmentType: String, Equatable, Sendable { case person, event, preference, fact }
enum SupportCloudCandidateReviewState: String, Equatable, Sendable {
    case legacyReview = "legacy_review"
    case pending
}
enum SupportCloudCandidateProvenance: String, Equatable, Sendable { case message, conversation, unknown }

struct SupportCloudMemoryCandidate: Equatable, Sendable, Decodable {
    let id: UUID
    let fragmentType: SupportCloudFragmentType
    let value: String
    let reviewState: SupportCloudCandidateReviewState
    let provenance: SupportCloudCandidateProvenance
    let sourceMessageID: UUID?
    let sourceConversationID: UUID?
    let candidateExpiresAt: Date?
    let extractedAt: Date?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: SupportCloudKey.self)
        id = try c.uuid("id")
        fragmentType = try c.enumValue("fragment_type", as: SupportCloudFragmentType.self)
        value = try c.string("value")
        reviewState = try c.enumValue("review_state", as: SupportCloudCandidateReviewState.self)
        provenance = try c.enumValue("provenance", as: SupportCloudCandidateProvenance.self)
        sourceMessageID = try c.uuidOrNull("source_message_id")
        sourceConversationID = try c.uuidOrNull("source_conversation_id")
        candidateExpiresAt = try c.dateOrNull("candidate_expires_at")
        extractedAt = try c.dateOrNull("extracted_at")
    }
}

struct SupportCloudDailyIntent: Equatable, Sendable {
    let id: UUID
    let intent: String
    let createdAt: Date
    let expiresAt: Date
}

struct SupportCloudMemoryPage: Equatable, Sendable, Decodable {
    let privacyRevision: Int64
    let maxConfirmed: Int
    let saved: [SupportCloudSavedMemory]
    let candidates: [SupportCloudMemoryCandidate]
    let dailyIntent: SupportCloudDailyIntent?
    let serverTime: Date

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: SupportCloudKey.self)
        guard try c.bool("ok") else { throw c.corrupt("ok", "ok must be true") }
        privacyRevision = try c.int64("privacy_revision", 1...SupportCloudWireLimits.maxRevision)
        maxConfirmed = Int(try c.int64("max_confirmed", 1...1_000))
        saved = try c.decode([SupportCloudSavedMemory].self, forKey: "saved")
        candidates = try c.decode([SupportCloudMemoryCandidate].self, forKey: "candidates")
        try c.requirePresent("daily_intent")
        if let d = try c.decodeIfPresent([String: SupportCloudJSON].self, forKey: "daily_intent") {
            guard let idText = d["id"]?.stringValue, let id = UUID(uuidString: idText), let intent = d["intent"]?.stringValue,
                  let created = d["created_at"]?.stringValue.flatMap(SupportCloudDate.parse),
                  let expires = d["expires_at"]?.stringValue.flatMap(SupportCloudDate.parse) else {
                throw c.corrupt("daily_intent", "bad daily intent")
            }
            dailyIntent = SupportCloudDailyIntent(id: id, intent: intent, createdAt: created, expiresAt: expires)
        } else {
            dailyIntent = nil
        }
        serverTime = try c.date("server_time")
        guard saved.count <= 500, candidates.count <= 500 else { throw c.corrupt("saved", "too many records") }
        guard Set(saved.map(\.id)).count == saved.count, Set(candidates.map(\.id)).count == candidates.count else {
            throw c.corrupt("saved", "duplicate ids")
        }
    }
}

enum SupportCloudSourceKind: String, Equatable, Sendable { case conversation, message }

/// The eight `memory_mutate` kinds. Associated values are validated by `SupportCloudMemoryMutation.init`.
enum SupportCloudMemoryOperation: Equatable, Sendable {
    case edit(memoryID: UUID, content: String, category: SupportCloudMemoryCategory?, expectedRevision: Int)
    case stopUsing(memoryID: UUID, expectedRevision: Int?)
    case resumeUsing(memoryID: UUID, expectedRevision: Int?)
    /// Hard removal of a saved memory; the server also suppresses dependent turns.
    case forgetMemory(memoryID: UUID)
    case forgetCandidate(fragmentID: UUID)
    case approveCandidate(fragmentID: UUID, editedContent: String?)
    case dismissCandidate(fragmentID: UUID)
    case suppressSource(kind: SupportCloudSourceKind, id: UUID)
    case unsuppressSource(kind: SupportCloudSourceKind, id: UUID)

    var wireKind: String {
        switch self {
        case .edit: return "memory_edit"
        case .stopUsing: return "memory_stop_using"
        case .resumeUsing: return "memory_resume_using"
        case .forgetMemory, .forgetCandidate: return "memory_forget"
        case .approveCandidate: return "candidate_approve"
        case .dismissCandidate: return "candidate_dismiss"
        case .suppressSource: return "suppress_source"
        case .unsuppressSource: return "unsuppress_source"
        }
    }
}

/// Immutable memory/privacy operation. Its bytes are fixed at construction, so a replay (same `operationID`) can never
/// carry a different payload (the server rejects that as `OPERATION_ID_REUSED`).
struct SupportCloudMemoryMutation: Equatable, Sendable {
    let operationID: UUID
    let operation: SupportCloudMemoryOperation
    private let payload: [String: SupportCloudJSON]

    init(operationID: UUID, operation: SupportCloudMemoryOperation) throws {
        var p: [String: SupportCloudJSON] = [:]
        func revision(_ value: Int) throws -> SupportCloudJSON {
            guard value >= 1, value <= Int(Int32.max) else { throw SupportCloudError.invalidRequest(.numberOutOfRange(field: "expected_revision")) }
            return .int(Int64(value))
        }
        func content(_ text: String) throws -> SupportCloudJSON {
            try cloudCheckText(text, field: "content", max: SupportCloudWireLimits.memoryContent)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SupportCloudError.invalidRequest(.emptyValue(field: "content"))
            }
            return .string(text)
        }
        switch operation {
        case let .edit(memoryID, text, category, expected):
            p = ["memory_id": cloudUUID(memoryID), "content": try content(text), "expected_revision": try revision(expected)]
            if let category { p["category"] = .string(category.rawValue) }
        case let .stopUsing(memoryID, expected), let .resumeUsing(memoryID, expected):
            p = ["memory_id": cloudUUID(memoryID)]
            if let expected { p["expected_revision"] = try revision(expected) }
        case let .forgetMemory(memoryID):
            p = ["memory_id": cloudUUID(memoryID)]
        case let .forgetCandidate(fragmentID), let .dismissCandidate(fragmentID):
            p = ["fragment_id": cloudUUID(fragmentID)]
        case let .approveCandidate(fragmentID, edited):
            p = ["fragment_id": cloudUUID(fragmentID)]
            if let edited { p["content"] = try content(edited) }
        case let .suppressSource(kind, id), let .unsuppressSource(kind, id):
            p = ["source_kind": .string(kind.rawValue), "id": cloudUUID(id)]
        }
        self.operationID = operationID
        self.operation = operation
        self.payload = p
    }

    /// Stable request bytes (`op: "memory_mutate"`).
    func requestData() throws -> Data {
        let envelope: [String: SupportCloudJSON] = [
            "schema_version": .int(Int64(SupportSessionLimits.schemaVersion)),
            "operation_id": cloudUUID(operationID),
            "kind": .string(operation.wireKind),
            "payload": .object(payload),
        ]
        let bytes = try SupportCloudJSON.object(envelope).jsonbByteCount()
        guard bytes <= SupportCloudWireLimits.memoryEnvelopeBytes else {
            throw SupportCloudError.invalidRequest(.tooLarge(field: "memory envelope", bytes: bytes, limit: SupportCloudWireLimits.memoryEnvelopeBytes))
        }
        var body = envelope
        body["op"] = .string("memory_mutate")
        return try SupportCloudJSON.object(body).stableData()
    }
}

/// Confirmed (200) reply to `memory_mutate`.
///
/// `privacyRevision` is the account privacy revision RECORDED WITH THIS OPERATION'S IMMUTABLE RECEIPT. On first
/// application it is the revision that operation produced; on a replay (`replayed == true`) the server returns the stored
/// receipt, so it is HISTORICAL and may be older than the account's current revision (another privacy operation may have
/// advanced it since). Use it to acknowledge this operation, never to lower a newer known revision, and take the current
/// account revision from a fresh authoritative response (`listMemory()`), which this one-request adapter never issues itself.
struct SupportCloudMemoryMutationReceipt: Equatable, Sendable, Decodable {
    let operationID: UUID
    let kind: String
    let noOp: Bool
    let replayed: Bool
    /// The operation's acknowledgment revision (historical on a replay). See the type documentation.
    let privacyRevision: Int64
    /// True when `privacyRevision` comes from a stored receipt and may be older than the account's current revision.
    var privacyRevisionIsHistorical: Bool { replayed }
    let memoryID: UUID?
    let memoryRevision: Int64?
    let fragmentID: UUID?
    let suppressedTurns: Int?
    let conversationScopeExcluded: Bool?
    let sourceKind: SupportCloudSourceKind?
    let sourceID: UUID?
    let serverTime: Date

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: SupportCloudKey.self)
        guard try c.bool("ok") else { throw c.corrupt("ok", "ok must be true") }
        operationID = try c.uuid("operation_id")
        kind = try c.string("kind", max: 40)
        noOp = try c.optionalBool("no_op") ?? false
        replayed = try c.bool("replayed")
        privacyRevision = try c.int64("privacy_revision", 1...SupportCloudWireLimits.maxRevision)
        memoryID = try c.decodeIfPresent(UUID.self, forKey: "memory_id")
        memoryRevision = try c.decodeIfPresent(Int64.self, forKey: "memory_revision")
        fragmentID = try c.decodeIfPresent(UUID.self, forKey: "fragment_id")
        suppressedTurns = try c.decodeIfPresent(Int.self, forKey: "suppressed_turns")
        conversationScopeExcluded = try c.optionalBool("conversation_scope_excluded")
        if let sk = try c.decodeIfPresent(String.self, forKey: "source_kind") {
            guard let parsed = SupportCloudSourceKind(rawValue: sk) else { throw c.corrupt("source_kind", "unknown value") }
            sourceKind = parsed
            sourceID = try c.decodeIfPresent(UUID.self, forKey: "id")
        } else {
            sourceKind = nil
            sourceID = nil
        }
        serverTime = try c.date("server_time")
    }

    /// Binds the reply to the operation that was requested (mirrors `support_memory_mutate`, 20261106230200 memory SQL).
    /// A reply that omits, or names a different, target is never an acknowledgment, so the operation stays replayable.
    /// Legitimate shapes are kept: a no-op edit/stop/resume/approve/dismiss, an approval whose canonical `memory_id` is
    /// the promoted memory, a candidate forget whose `memory_id` may be null, and a replay of any stored receipt.
    func validated(against mutation: SupportCloudMemoryMutation) throws -> SupportCloudMemoryMutationReceipt {
        guard operationID == mutation.operationID, kind == mutation.operation.wireKind else { throw malformed("operation echo mismatch") }
        if let memoryRevision, !(1...Int64(Int32.max)).contains(memoryRevision) { throw malformed("memory revision out of range") }
        if let suppressedTurns, !(0...1_000_000).contains(suppressedTurns) { throw malformed("suppressed turns out of range") }
        switch mutation.operation {
        case let .edit(memoryID, _, _, expectedRevision):
            guard self.memoryID == memoryID, let revision = memoryRevision else { throw malformed("edit target missing") }
            // The guard trigger assigns OLD.revision + 1; a no-op keeps the revision. A replay returns the stored receipt.
            if !replayed { guard revision == Int64(expectedRevision) + (noOp ? 0 : 1) else { throw malformed("edit revision relation") } }
        case let .stopUsing(memoryID, _), let .resumeUsing(memoryID, _):
            guard self.memoryID == memoryID else { throw malformed("memory target missing") }
        case let .forgetMemory(memoryID):
            guard self.memoryID == memoryID, fragmentID == nil, suppressedTurns != nil else { throw malformed("forget target missing") }
        case let .forgetCandidate(fragmentID):
            // `memory_id` is the PROMOTED memory and may legitimately be null.
            guard self.fragmentID == fragmentID, suppressedTurns != nil, conversationScopeExcluded != nil else {
                throw malformed("candidate forget target missing")
            }
        case let .approveCandidate(fragmentID, _):
            guard self.fragmentID == fragmentID, memoryID != nil else { throw malformed("approval target missing") }
        case let .dismissCandidate(fragmentID):
            guard self.fragmentID == fragmentID else { throw malformed("dismiss target missing") }
        case let .suppressSource(kind, id):
            guard sourceKind == kind, sourceID == id, suppressedTurns != nil else { throw malformed("source target missing") }
        case let .unsuppressSource(kind, id):
            guard sourceKind == kind, sourceID == id else { throw malformed("source target missing") }
        }
        return self
    }
}

extension SupportCloudMemoryOperation {
    /// Operations the server can answer with `REVISION_CONFLICT`: the target memory and the revision the caller expected.
    var conflictTarget: (memoryID: UUID, expectedRevision: Int)? {
        switch self {
        case let .edit(memoryID, _, _, expected): return (memoryID, expected)
        case let .stopUsing(memoryID, expected?), let .resumeUsing(memoryID, expected?): return (memoryID, expected)
        default: return nil
        }
    }
}

struct SupportCloudMemoryConflict: Equatable, Sendable {
    let currentRevision: Int64
    let memoryID: UUID
    let category: SupportCloudMemoryCategory
    let content: String
    let revision: Int64
}

enum SupportCloudMemoryMutationResult: Equatable, Sendable {
    case confirmed(SupportCloudMemoryMutationReceipt)
    /// Definitive `REVISION_CONFLICT`: nothing changed. Show the current text and ask again with a NEW operation ID.
    case conflict(SupportCloudMemoryConflict)

    var attemptOutcome: SupportAttemptOutcome {
        switch self {
        case .confirmed(let receipt): return .confirmed(revision: receipt.privacyRevision)
        case .conflict(let conflict): return .revisionConflict(currentRevision: conflict.currentRevision)
        }
    }
}

// MARK: - Transport

/// One request, one response. Injectable so tests drive a real `URLSession` through a `URLProtocol` stub.
protocol SupportCloudTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// Production transport: a plain `URLSession` data task on a request that already carries its own headers.
struct URLSessionSupportCloudTransport: SupportCloudTransport {
    static let maxResponseBytes = 1_048_576

    let session: URLSession

    init(session: URLSession) { self.session = session }

    /// Ephemeral: no cache, no cookies, no ambient headers. Injected sessions may differ; the request is authoritative.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        return URLSession(configuration: configuration)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard data.count <= Self.maxResponseBytes else { throw URLError(.dataLengthExceedsMaximum) }
        return (data, http)
    }
}

fileprivate struct SupportCloudRawResponse {
    let status: Int
    let data: Data
    let retryAfter: TimeInterval?
}

// MARK: - Service

/// Typed client for the `support-session` Edge function.
///
/// Every call is exactly one HTTP request. There is no queue, no retry, no backoff and no fallback: the caller owns
/// those decisions and learns the outcome from the typed result/error (`attemptOutcome` maps to the repository).
final class SupportSessionCloudService: Sendable {
    static let functionPath = "functions/v1/support-session"

    /// The owner + epoch this instance is bound to for its whole life.
    let binding: SupportCloudBinding

    private let ownerProof: SupportCloudOwnerProof
    private let tokenSource: SupportCloudTokenSource
    private let transport: any SupportCloudTransport
    private let endpoint: URL
    private let apiKey: String

    init(
        binding: SupportCloudBinding,
        ownerProof: @escaping SupportCloudOwnerProof,
        tokenSource: @escaping SupportCloudTokenSource,
        transport: any SupportCloudTransport,
        projectURL: URL,
        apiKey: String
    ) {
        self.binding = binding
        self.ownerProof = ownerProof
        self.tokenSource = tokenSource
        self.transport = transport
        self.endpoint = projectURL.appendingPathComponent(Self.functionPath)
        self.apiKey = apiKey
    }

    /// Production wiring: `SupabaseConfig.projectURL`/`anonKey` and an ephemeral `URLSession`.
    static func live(
        binding: SupportCloudBinding,
        ownerProof: @escaping SupportCloudOwnerProof,
        tokenSource: @escaping SupportCloudTokenSource,
        session: URLSession? = nil
    ) -> SupportSessionCloudService {
        SupportSessionCloudService(
            binding: binding, ownerProof: ownerProof, tokenSource: tokenSource,
            transport: URLSessionSupportCloudTransport(session: session ?? URLSessionSupportCloudTransport.makeSession()),
            projectURL: SupabaseConfig.projectURL, apiKey: SupabaseConfig.anonKey)
    }

    // MARK: Operations

    /// Independent versions for `session_contract`, `context_policy` and `voice_context`. A missing function or RPC is
    /// reported as `SupportCloudCapabilities.notDeployed` (explicitly unavailable), not as an error.
    func capabilities() async throws -> SupportCloudCapabilities {
        do {
            let raw = try await perform(try SupportCloudJSON.object(["op": .string("capabilities")]).stableData())
            guard (200..<300).contains(raw.status) else { throw Self.failure(for: raw) }
            return try SupportCloudDecoding.decode(SupportCloudCapabilities.self, from: raw.data)
        } catch SupportCloudError.capabilityUnavailable(let gap) where gap != .notConfigured {
            return .notDeployed
        }
    }

    /// Apply one mutation. Returns `.conflict` only for a definitive 409 `REVISION_CONFLICT` (not applied).
    /// Any thrown error other than `.rejected`/`.invalidRequest` leaves the outcome UNKNOWN: replay the same operation ID.
    func mutate(_ envelope: SupportMutationEnvelope) async throws -> SupportCloudMutationResult {
        try await mutate(try SupportCloudWireMutation(envelope: envelope))
    }

    func mutate(_ mutation: SupportCloudWireMutation) async throws -> SupportCloudMutationResult {
        let raw = try await perform(try mutation.requestData())
        if (200..<300).contains(raw.status) {
            let confirmation = try SupportCloudDecoding.decode(SupportCloudMutationConfirmation.self, from: raw.data)
            return .confirmed(try confirmation.validated(against: mutation))
        }
        if raw.status == 409, Self.contractError(in: raw.data)?.code == .revisionConflict {
            let body = try SupportCloudDecoding.decode(ConflictBody.self, from: raw.data)
            if let snapshot = body.snapshot {
                guard snapshot.session.id == mutation.sessionID, snapshot.session.revision == body.currentRevision else {
                    throw malformed("conflict snapshot mismatch")
                }
            }
            return .conflict(SupportCloudRevisionConflict(currentRevision: body.currentRevision, snapshot: body.snapshot))
        }
        throw Self.failure(for: raw)
    }

    /// Snapshot plus one page of events (`seq > afterSequence`, at most `limit`).
    func get(sessionID: UUID, afterSequence: Int64 = 0, limit: Int = 100) async throws -> SupportCloudSessionDetail {
        guard afterSequence >= 0, afterSequence <= SupportCloudWireLimits.maxRevision else {
            throw SupportCloudError.invalidRequest(.numberOutOfRange(field: "after_seq"))
        }
        guard (1...SupportCloudWireLimits.getMaxLimit).contains(limit) else {
            throw SupportCloudError.invalidRequest(.numberOutOfRange(field: "limit"))
        }
        let body: [String: SupportCloudJSON] = [
            "op": .string("get"), "schema_version": .int(Int64(SupportSessionLimits.schemaVersion)),
            "session_id": cloudUUID(sessionID), "after_seq": .int(afterSequence), "limit": .int(Int64(limit)),
        ]
        let raw = try await perform(try SupportCloudJSON.object(body).stableData())
        guard (200..<300).contains(raw.status) else { throw Self.failure(for: raw) }
        return try SupportCloudDecoding.decode(SupportCloudSessionDetail.self, from: raw.data)
            .validated(sessionID: sessionID, afterSequence: afterSequence, limit: limit)
    }

    /// History/incremental sync page with the server's stable `(updated_at, id)` cursor.
    func list(
        limit: Int = 50,
        cursor: SupportCloudListCursor? = nil,
        status: SupportSessionStatus? = nil,
        direction: SupportCloudListDirection = .descending,
        includeDeleted: Bool = false
    ) async throws -> SupportCloudSessionPage {
        guard (1...SupportCloudWireLimits.listMaxLimit).contains(limit) else {
            throw SupportCloudError.invalidRequest(.numberOutOfRange(field: "limit"))
        }
        var body: [String: SupportCloudJSON] = [
            "op": .string("list"), "schema_version": .int(Int64(SupportSessionLimits.schemaVersion)),
            "limit": .int(Int64(limit)), "direction": .string(direction.rawValue), "include_deleted": .bool(includeDeleted),
        ]
        if let cursor {
            guard SupportCloudDate.parse(cursor.updatedAt) != nil else {
                throw SupportCloudError.invalidRequest(.unsupportedValue(field: "cursor.updated_at"))
            }
            // Verbatim: never re-formatted through `Date`, which would drop microseconds.
            body["cursor"] = .object(["updated_at": .string(cursor.updatedAt), "id": cloudUUID(cursor.id)])
        }
        if let status { body["status"] = .string(status.rawValue) }
        let raw = try await perform(try SupportCloudJSON.object(body).stableData())
        guard (200..<300).contains(raw.status) else { throw Self.failure(for: raw) }
        return try SupportCloudDecoding.decode(SupportCloudSessionPage.self, from: raw.data)
    }

    func listMemory() async throws -> SupportCloudMemoryPage {
        let raw = try await perform(try SupportCloudJSON.object(["op": .string("memory_list")]).stableData())
        guard (200..<300).contains(raw.status) else { throw Self.failure(for: raw) }
        return try SupportCloudDecoding.decode(SupportCloudMemoryPage.self, from: raw.data)
    }

    /// Apply one memory/privacy operation. Immutable: replay the SAME `SupportCloudMemoryMutation` after an unknown outcome.
    func mutateMemory(_ mutation: SupportCloudMemoryMutation) async throws -> SupportCloudMemoryMutationResult {
        let raw = try await perform(try mutation.requestData())
        if (200..<300).contains(raw.status) {
            let receipt = try SupportCloudDecoding.decode(SupportCloudMemoryMutationReceipt.self, from: raw.data)
            return .confirmed(try receipt.validated(against: mutation))
        }
        if raw.status == 409, Self.contractError(in: raw.data)?.code == .revisionConflict {
            let conflict = try SupportCloudDecoding.decode(MemoryConflictBody.self, from: raw.data).conflict
            // A conflict only counts for the memory the caller asked about, at a revision that really differs from the
            // one it expected. Anything else must not hand unrelated text to a correction/rebase.
            guard let target = mutation.operation.conflictTarget, conflict.memoryID == target.memoryID,
                  conflict.currentRevision != Int64(target.expectedRevision) else {
                throw malformed("conflict target mismatch")
            }
            return .conflict(conflict)
        }
        throw Self.failure(for: raw)
    }

    /// The immutable context receipt for a request. `NOT_FOUND` means no receipt exists (an older reply).
    func receipt(requestID: UUID) async throws -> SupportCloudReceiptResult {
        let body: [String: SupportCloudJSON] = ["op": .string("receipt"), "request_id": cloudUUID(requestID)]
        let raw = try await perform(try SupportCloudJSON.object(body).stableData())
        if (200..<300).contains(raw.status) {
            let receipt = try SupportCloudDecoding.decode(SupportCloudContextReceipt.self, from: raw.data)
            guard receipt.requestID == requestID else { throw malformed("receipt request mismatch") }
            return .available(receipt)
        }
        let error = Self.failure(for: raw)
        if case .rejected(let rejection) = error, rejection.code == .notFound { return .unavailableOlderReply }
        throw error
    }

    /// Wire snapshot → repository snapshot, with the owner taken from THIS service's captured binding (the server
    /// record carries no `user_id`). A shape the local domain cannot represent throws; nothing is skipped or invented.
    func remoteSnapshot(from snapshot: SupportCloudSnapshot) throws -> SupportRemoteSessionSnapshot {
        try snapshot.remoteSnapshot(owner: binding)
    }

    // MARK: Request pipeline

    /// Owner/epoch/cancellation are verified before the token fetch, after it, immediately before dispatch, after the
    /// response await and on the failure path. A response observed after the owner changed is dropped undecoded.
    private func perform(_ body: Data) async throws -> SupportCloudRawResponse {
        guard Self.isAllowedEndpoint(endpoint), !apiKey.isEmpty else {
            throw SupportCloudError.capabilityUnavailable(.notConfigured)
        }
        try await requireCurrent()                                   // 1. before token fetch
        let credential: SupportCloudCredential?
        do {
            credential = try await tokenSource()
        } catch is CancellationError {
            throw SupportCloudError.cancelled
        } catch let error as SupportCloudError {
            throw error
        } catch {
            try await requireCurrent()
            throw SupportCloudError.authenticationRequired(.tokenUnavailable)
        }
        try await requireCurrent()                                   // 2. after token fetch
        guard let credential else { throw SupportCloudError.authenticationRequired(.noSession) }
        // A token captured for another owner/epoch is never used, whatever the proof says.
        guard credential.binding == binding else { throw SupportCloudError.ownerChanged }
        guard Self.isValidToken(credential.accessToken) else { throw SupportCloudError.authenticationRequired(.noSession) }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        request.httpShouldHandleCookies = false
        // Set on the request itself so no session-level or SDK-level header can replace the captured owner's token.
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        try await requireCurrent()                                   // 3. immediately before dispatch
        let response: (Data, HTTPURLResponse)
        do {
            response = try await transport.send(request)
        } catch {
            try await requireCurrent()                               // 5. on failure: owner change wins over transport error
            throw Self.classify(transportError: error)
        }
        try await requireCurrent()                                   // 4. after the await, before anything is decoded
        let retryAfter = response.1.value(forHTTPHeaderField: "Retry-After").flatMap(Self.parseRetryAfter)
        return SupportCloudRawResponse(status: response.1.statusCode, data: response.0, retryAfter: retryAfter)
    }

    private func requireCurrent() async throws {
        if Task.isCancelled { throw SupportCloudError.cancelled }
        guard await ownerProof() == binding else { throw SupportCloudError.ownerChanged }
        if Task.isCancelled { throw SupportCloudError.cancelled }
    }

    // MARK: Classification (pure, unit-tested)

    /// https only; plain http is allowed solely for a loopback development stack.
    static func isAllowedEndpoint(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased(), !host.isEmpty else { return false }
        if scheme == "https" { return true }
        return scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)
    }

    /// Conservative bearer-token charset: refuses anything that could split a header.
    static func isValidToken(_ token: String) -> Bool {
        guard !token.isEmpty, token.utf8.count <= 8_192 else { return false }
        return token.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) || $0 == 45 || $0 == 46
                || $0 == 95 || $0 == 126 || $0 == 43 || $0 == 47 || $0 == 61
        }
    }

    static func parseRetryAfter(_ text: String) -> TimeInterval? {
        guard let seconds = Double(text.trimmingCharacters(in: .whitespaces)), seconds.isFinite, seconds >= 0 else { return nil }
        return min(seconds, 3_600)
    }

    static func classify(transportError error: Error) -> SupportCloudError {
        if error is CancellationError { return .cancelled }
        guard let urlError = error as? URLError else { return .transport(.other(0)) }
        switch urlError.code {
        case .timedOut: return .transport(.timeout)
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff: return .transport(.offline)
        case .networkConnectionLost: return .transport(.connectionLost)
        case .cancelled: return .transport(.cancelled)
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected,
             .appTransportSecurityRequiresSecureConnection:
            return .transport(.secureConnection)
        default: return .transport(.other(urlError.code.rawValue))
        }
    }

    /// The contract's error body: `{ ok: false, code: <known code>, ... }`. A platform error body is NOT one.
    fileprivate static func contractError(in data: Data) -> (code: SupportCloudErrorCode, object: [String: SupportCloudJSON])? {
        guard let object = (try? JSONDecoder().decode(SupportCloudJSON.self, from: data))?.objectValue,
              object["ok"]?.boolValue == false, let text = object["code"]?.stringValue,
              let code = SupportCloudErrorCode(rawValue: text) else { return nil }
        return (code, object)
    }

    /// Non-2xx → typed error. Only a definitive contract rejection is `.rejected`; auth, capability and transient
    /// failures keep their own cases so the repository can choose replay vs new ID.
    fileprivate static func failure(for raw: SupportCloudRawResponse) -> SupportCloudError {
        classifyFailure(status: raw.status, data: raw.data, retryAfter: raw.retryAfter)
    }

    static func classifyFailure(status: Int, data: Data, retryAfter: TimeInterval?) -> SupportCloudError {
        let parsed = (try? JSONDecoder().decode(SupportCloudJSON.self, from: data))?.objectValue
        let expired = ["message", "msg", "error_description", "error"].contains {
            parsed?[$0]?.stringValue?.lowercased().contains("expired") == true
        }
        if let (code, object) = contractError(in: data) {
            let bodyRetry = object["retry_after_seconds"]?.int64Value.map { min(max(TimeInterval($0), 0), 3_600) }
            switch code {
            case .authRequired:
                return .authenticationRequired(expired ? .expiredToken : .unauthorized)
            case .rateLimited:
                return .serverTemporary(status: status, retryAfter: retryAfter ?? bodyRetry)
            case .temporaryFailure:
                if object["capability"]?.stringValue == "not_deployed" { return .capabilityUnavailable(.rpcNotDeployed) }
                return .serverTemporary(status: status, retryAfter: retryAfter ?? bodyRetry)
            case .revisionConflict:
                // Only `mutate`/`mutateMemory` understand a conflict; anywhere else it is a contract violation.
                return .malformedResponse("unexpected conflict")
            default:
                return .rejected(SupportCloudRejection(
                    code: code, message: object["message"]?.stringValue.map { String($0.prefix(200)) }, httpStatus: status,
                    currentPrivacyRevision: object["current_privacy_revision"]?.int64Value))
            }
        }
        switch status {
        case 401: return .authenticationRequired(expired ? .expiredToken : .unauthorized)
        case 403: return .authenticationRequired(expired ? .expiredToken : .forbidden)
        case 404: return .capabilityUnavailable(.functionNotDeployed)
        case 408, 425, 429, 500...599: return .serverTemporary(status: status, retryAfter: retryAfter)
        default: return .malformedResponse("status \(status)")
        }
    }

    private struct ConflictBody: Decodable {
        let currentRevision: Int64
        let snapshot: SupportCloudSnapshot?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: SupportCloudKey.self)
            guard try c.bool("ok") == false, try c.string("code") == SupportCloudErrorCode.revisionConflict.rawValue else {
                throw c.corrupt("code", "not a conflict")
            }
            currentRevision = try c.int64("current_revision", 1...SupportCloudWireLimits.maxRevision)
            snapshot = try c.decodeIfPresent(SupportCloudSnapshot.self, forKey: "snapshot")
        }
    }

    private struct MemoryConflictBody: Decodable {
        let conflict: SupportCloudMemoryConflict

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: SupportCloudKey.self)
            guard try c.bool("ok") == false, try c.string("code") == SupportCloudErrorCode.revisionConflict.rawValue else {
                throw c.corrupt("code", "not a conflict")
            }
            let current = try c.int64("current_revision", 1...Int64(Int32.max))
            let m = try c.nestedContainer(keyedBy: SupportCloudKey.self, forKey: "memory")
            let revision = try m.int64("revision", 1...Int64(Int32.max))
            guard revision == current else { throw c.corrupt("memory", "revision mismatch") }
            conflict = SupportCloudMemoryConflict(
                currentRevision: current, memoryID: try m.uuid("id"),
                category: try m.enumValue("category", as: SupportCloudMemoryCategory.self),
                content: try m.string("content"), revision: revision)
        }
    }
}

// MARK: - Wire → local domain (explicit mapping; an unrepresentable shape throws, nothing is skipped or invented)

extension SupportCloudSnapshot {
    /// The owner comes from the CAPTURED binding because the server record carries no `user_id`.
    /// Server revision, template version, checkpoint, step, reflection, status, canonical reference and context scope
    /// are preserved; a deleted tombstone yields `isDeleted: true` with no activities.
    func remoteSnapshot(owner: SupportCloudBinding) throws -> SupportRemoteSessionSnapshot {
        let record = session
        let local = SupportSession(
            id: record.id, ownerID: owner.ownerID, conversationID: record.conversationID,
            previousSessionID: record.previousSessionID, selectedActivityID: record.selectedActivityID,
            title: record.title, concern: record.concern, status: record.status, contextScope: record.contextScope,
            // The repository tracks the authoritative revision separately; keep the counters comparable.
            localRevision: record.revision, syncStatus: .synced, createdAt: record.createdAt,
            updatedAt: record.updatedAt, closedAt: record.closedAt)
        let isDeleted = record.status == .deleted
        let activities = isDeleted ? [] : try self.activities.map { try $0.localActivity(sessionID: record.id) }
        // The server-owned erasure marker (`result.discarded`) is carried explicitly so the repository can apply the privacy
        // scrub BEFORE it merges any pending local content. Each such activity has already been converted to its
        // content-free form above.
        let discarded = isDeleted ? [] : Set(self.activities.filter(\.isAuthoritativelyDiscarded).map(\.id))
        return SupportRemoteSessionSnapshot(session: local, activities: activities, revision: record.revision,
                                            isDeleted: isDeleted, discardedActivityIDs: discarded)
    }
}

extension SupportCloudActivityRecord {
    private static let checkpointKeys: Set<String> = [
        "version", "template_version", "current_step", "completed_steps", "skipped_steps", "responses", "step",
    ]
    private static let resultKeys: Set<String> = ["step", "discarded", "acknowledged_count", "skipped_count", "shareable_note"]
    private static let stepKeys: Set<String> = ["action_text", "state"]

    /// `result.discarded == true` is written only by `support_do_discard` / the suppression closure, which also null the
    /// checkpoint and scrub the reflection. It means the person's answers, step text and notes were ERASED on the server.
    var isAuthoritativelyDiscarded: Bool { result?["discarded"]?.boolValue == true }

    func localActivity(sessionID: UUID) throws -> SupportActivity {
        // A template version this build cannot run is never mapped onto a "similar" one, with or without a checkpoint.
        _ = try promptIDs()
        if isAuthoritativelyDiscarded { return try scrubbedLocalActivity(sessionID: sessionID) }
        let mappedCheckpoint = try mapCheckpoint()
        let mappedResult = try mapResult()

        // A terminal activity's step lives in `result.step`; a live one in `checkpoint.step`. A stale checkpoint step is
        // never resurrected onto a finished activity.
        let step = status.isTerminal ? mappedResult.step : mappedCheckpoint.step

        var result: SupportActivityResult?
        if status.isTerminal || mappedResult.present {
            let reflectionText = (reflection?.shareNote == true) ? reflection?.shareableText : nil
            result = SupportActivityResult(
                acknowledgedStepCount: mappedResult.acknowledged ?? mappedCheckpoint.checkpoint.completedStepIDs.count,
                skippedStepCount: mappedResult.skipped ?? mappedCheckpoint.checkpoint.skippedStepIDs.count,
                activeMilliseconds: activeMilliseconds,
                stoppedReason: stopReason,
                shareableNote: mappedResult.discarded ? nil : (reflectionText ?? mappedResult.shareableNote))
        }
        // The server stores no reflection timestamp; the activity's last update is the closest honest value.
        let localReflection = reflection.map {
            SupportReflection(outcome: $0.outcome, note: $0.note, includeWrittenAnswers: $0.shareNote, recordedAt: updatedAt)
        }
        return SupportActivity(
            id: id, sessionID: sessionID, templateKey: templateKey, templateVersion: templateVersion, status: status,
            canonicalReference: canonicalReference, checkpoint: mappedCheckpoint.checkpoint, step: step,
            activeMilliseconds: activeMilliseconds, result: result, reflection: localReflection,
            lastChangedRevision: lastChangedRevision, syncStatus: .synced, createdAt: createdAt, updatedAt: updatedAt,
            finishedAt: finishedAt)
    }

    private func unsupported(_ path: String) -> SupportCloudConversionError { .unsupportedWireShape(path: path) }

    /// A server-erased activity: history (status, counts, timing, canonical reference, reflection OUTCOME) survives, content
    /// does not. The marker row is exactly `{discarded: true}` optionally with a content-free `step.state` (the SQL keeps the
    /// completed/dismissed state after erasing the text); no text is demanded. Whatever checkpoint, step or reflection text
    /// a wire row might still carry is dropped here, never copied into the local domain.
    private func scrubbedLocalActivity(sessionID: UUID) throws -> SupportActivity {
        // Only terminal activities carry a result, so a marker on a live one is not a server-authored erasure.
        guard status.isTerminal, let wire = result, wire.keys.allSatisfy({ $0 == "discarded" || $0 == "step" }) else {
            throw unsupported("result.discarded")
        }
        if let value = wire["step"], !value.isNull {
            guard let object = value.objectValue, let state = object["state"]?.stringValue else { throw unsupported("result.step.state") }
            guard SupportStepState(rawValue: state) != nil else {
                throw SupportCloudConversionError.unsupportedStepState(String(state.prefix(40)))
            }
        }
        let scrubbedReflection = reflection.map {
            SupportReflection(outcome: $0.outcome, note: nil, includeWrittenAnswers: false, recordedAt: updatedAt)
        }
        return SupportActivity(
            id: id, sessionID: sessionID, templateKey: templateKey, templateVersion: templateVersion, status: status,
            canonicalReference: canonicalReference,
            checkpoint: SupportCheckpoint(templateVersion: templateVersion, activeMilliseconds: activeMilliseconds),
            step: nil, activeMilliseconds: activeMilliseconds,
            result: SupportActivityResult(acknowledgedStepCount: 0, skippedStepCount: 0, activeMilliseconds: activeMilliseconds,
                                          stoppedReason: stopReason, shareableNote: nil),
            reflection: scrubbedReflection, lastChangedRevision: lastChangedRevision, syncStatus: .synced,
            createdAt: createdAt, updatedAt: updatedAt, finishedAt: finishedAt)
    }

    private func promptIDs() throws -> Set<String> {
        guard let ids = SupportTemplateCatalog.standard.promptIDs(template: templateKey, version: templateVersion) else {
            // Never guess a "similar" template after an update (spec §9.3).
            throw unsupported("template_version")
        }
        return Set(ids)
    }

    private func mapCheckpoint() throws -> (checkpoint: SupportCheckpoint, step: SupportStepPayload?) {
        guard let wire = checkpoint else {
            return (SupportCheckpoint(templateVersion: templateVersion, activeMilliseconds: activeMilliseconds), nil)
        }
        if let key = wire.keys.sorted().first(where: { !Self.checkpointKeys.contains($0) }) { throw unsupported("checkpoint.\(key)") }
        guard wire["version"]?.int64Value == Int64(SupportCheckpoint.currentVersion) else { throw unsupported("checkpoint.version") }
        // `support_do_accept_proposal` seeds `{version:1, step:{action_text, state:"draft"}}` WITHOUT `template_version`; the
        // activity row's version is authoritative. Only that exact shape is accepted without it; no version is defaulted
        // for an ordinary checkpoint.
        if wire["template_version"] == nil { return try mapAcceptedProposalSeed(wire) }
        guard wire["template_version"]?.int64Value == Int64(templateVersion) else { throw unsupported("checkpoint.template_version") }
        let valid = try promptIDs()

        func promptList(_ key: String) throws -> [String] {
            guard let value = wire[key], !value.isNull else { return [] }
            guard let items = value.arrayValue else { throw unsupported("checkpoint.\(key)") }
            return try items.map {
                guard let id = $0.stringValue, valid.contains(id) else { throw unsupported("checkpoint.\(key)") }
                return id
            }
        }
        var current: String?
        if let value = wire["current_step"], !value.isNull {
            guard let id = value.stringValue, valid.contains(id) else { throw unsupported("checkpoint.current_step") }
            current = id
        }
        var responses: [String: String] = [:]
        if let value = wire["responses"], !value.isNull {
            guard let object = value.objectValue else { throw unsupported("checkpoint.responses") }
            for (id, text) in object {
                guard valid.contains(id), let string = text.stringValue,
                      string.unicodeScalars.count <= SupportCloudWireLimits.response else { throw unsupported("checkpoint.responses") }
                responses[id] = string
            }
        }
        var step: SupportStepPayload?
        if let value = wire["step"], !value.isNull {
            guard let object = value.objectValue else { throw unsupported("checkpoint.step") }
            step = try mapStep(object, path: "checkpoint.step")
        }
        let mapped = SupportCheckpoint(
            payloadVersion: SupportCheckpoint.currentVersion, templateVersion: templateVersion, lastPromptID: current,
            completedStepIDs: try promptList("completed_steps"), skippedStepIDs: try promptList("skipped_steps"),
            responses: responses, activeMilliseconds: activeMilliseconds, lastDurableWrite: nil)
        return (mapped, step)
    }

    /// The seed checkpoint of an accepted-but-not-yet-worked proposal: a model-suggested step the person may still edit.
    /// It is a `draft`: not saved work, not completed, and not progress. Any other shape without `template_version` throws.
    private func mapAcceptedProposalSeed(_ wire: [String: SupportCloudJSON]) throws -> (checkpoint: SupportCheckpoint, step: SupportStepPayload?) {
        guard templateKey == .chooseStepV1, Set(wire.keys) == ["version", "step"], let object = wire["step"]?.objectValue,
              object["state"]?.stringValue == SupportStepState.draft.rawValue else {
            throw unsupported("checkpoint.template_version")
        }
        let draft = try mapStep(object, path: "checkpoint.step")
        return (SupportCheckpoint(templateVersion: templateVersion, activeMilliseconds: activeMilliseconds), draft)
    }

    private func mapResult() throws -> (present: Bool, acknowledged: Int?, skipped: Int?, shareableNote: String?, discarded: Bool, step: SupportStepPayload?) {
        guard let wire = result else { return (false, nil, nil, nil, false, nil) }
        if let key = wire.keys.sorted().first(where: { !Self.resultKeys.contains($0) }) { throw unsupported("result.\(key)") }
        func count(_ key: String) throws -> Int? {
            guard let value = wire[key], !value.isNull else { return nil }
            guard let n = value.int64Value, (0...100_000).contains(n) else { throw unsupported("result.\(key)") }
            return Int(n)
        }
        var discarded = false
        if let value = wire["discarded"], !value.isNull {
            guard let flag = value.boolValue else { throw unsupported("result.discarded") }
            discarded = flag
        }
        var note: String?
        if let value = wire["shareable_note"], !value.isNull {
            guard let text = value.stringValue, text.unicodeScalars.count <= SupportCloudWireLimits.note else {
                throw unsupported("result.shareable_note")
            }
            note = text
        }
        var step: SupportStepPayload?
        if let value = wire["step"], !value.isNull {
            guard let object = value.objectValue else { throw unsupported("result.step") }
            step = try mapStep(object, path: "result.step")
        }
        return (true, try count("acknowledged_count"), try count("skipped_count"), note, discarded, step)
    }

    /// `{action_text, state}` only. `draft` is a model-suggested step the person has not chosen: it maps to
    /// `SupportStepState.draft`, never to saved or done. A dismissed step without text is "no saved step".
    private func mapStep(_ object: [String: SupportCloudJSON], path: String) throws -> SupportStepPayload? {
        if let key = object.keys.sorted().first(where: { !Self.stepKeys.contains($0) }) { throw unsupported("\(path).\(key)") }
        guard let stateText = object["state"]?.stringValue else { throw unsupported("\(path).state") }
        let state: SupportStepState
        switch stateText {
        case "saved": state = .saved
        case "self_reported_done": state = .selfReportedDone
        case "dismissed": state = .dismissed
        case "draft": state = .draft
        default: throw SupportCloudConversionError.unsupportedStepState(String(stateText.prefix(40)))
        }
        var text: String?
        if let value = object["action_text"], !value.isNull {
            guard let string = value.stringValue, string.unicodeScalars.count <= SupportCloudWireLimits.step else {
                throw unsupported("\(path).action_text")
            }
            text = string
        }
        if state == .dismissed {
            guard let text, !text.isEmpty else { return nil }
            return SupportStepPayload(actionText: text, state: .dismissed)
        }
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw unsupported("\(path).action_text") }
        // Reminder metadata is device-local and absent from the wire; it is never fabricated here.
        return SupportStepPayload(actionText: text, state: state)
    }
}
