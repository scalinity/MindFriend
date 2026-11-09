import Foundation

// MARK: - Voice ↔ support-session integration seam (spec §5.8, §9.8)
//
// This file is the *narrow* interface between the voice lifecycle and the support-session
// authority (coordinator / repository / cloud service). Voice never owns session state:
//
//   • `VoiceSupportAccess` is implemented by the caller (root integration) over the real
//     repository. Voice code only asks it to prepare a binding, confirm the binding is still
//     current, durably append FINAL transcript events, and reconcile.
//   • `VoiceSupportBinding` is the immutable identity captured at an explicit "Start voice".
//   • Transcript events are typed, identity-stable, ordered, and carry the binding.
//
// Foundation-only and free of free-text logging: transcript text is user content (spec §9.9).

// MARK: - Binding

/// Immutable identity of one voice session, captured when the person explicitly starts voice.
/// Every admission, session-end, socket and transcript append is bound to exactly this value.
struct VoiceSupportBinding: Equatable, Hashable, Sendable {
    /// Authenticated owner the binding belongs to.
    let ownerUUID: UUID
    /// Local account epoch (`AppState.accountEpoch`) at the time of binding.
    let accountEpoch: UInt64
    let supportSessionUUID: UUID
    let conversationUUID: UUID
    let scope: SupportContextScope
    /// Account privacy revision the caller acknowledged when preparing, when known.
    let privacyRevision: Int64?
}

/// What the person sees *before* voice starts. Reading it must not create or attach anything.
struct VoiceSupportPreview: Equatable, Sendable {
    /// User-visible session title; `nil` falls back to "Conversation".
    var title: String?
    var scope: SupportContextScope
    /// True when the conversation will only be attached/created once the person taps Start voice.
    var conversationWillBeAttached: Bool

    init(title: String? = nil, scope: SupportContextScope, conversationWillBeAttached: Bool = false) {
        self.title = title
        self.scope = scope
        self.conversationWillBeAttached = conversationWillBeAttached
    }

    var displayTitle: String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Conversation" : trimmed
    }

    var scopeSummary: String {
        switch scope {
        case .conversationOnly:
            return "Conversation only. Saved memory is not shared."
        case .personalized:
            return "Personalized. Context you approved may be shared."
        }
    }

    var attachmentNote: String? {
        conversationWillBeAttached ? "This conversation is attached when you start voice." : nil
    }
}

// MARK: - Errors

/// Narrow, user-safe reasons voice cannot start or continue. No provider or server text.
enum VoiceSupportAccessError: Error, Equatable, LocalizedError {
    /// No support-session access was supplied, or the session is unavailable.
    case unavailable
    /// The binding no longer matches the current account, epoch, or privacy state.
    case bindingNotCurrent
    /// The ambient signed-in account is not the binding's owner. Nothing was dispatched.
    case ownerMismatch
    /// The server reported a newer privacy revision than the binding acknowledged.
    case privacyRevisionChanged

    // Voice-context contract (server codes in parentheses). All of these fail closed: nothing is
    // connected, no microphone is started, and there is no fallback to a less-protective path.

    /// The admission carried no nested `voice_context` (VOICE_CONTEXT_REQUIRED): a legacy relay.
    case contextRequired
    /// The nested context was malformed or violated the contract (INVALID_VOICE_CONTEXT).
    case contextInvalid
    /// The nested context declares a version this app cannot use (VOICE_CONTEXT_VERSION_UNSUPPORTED).
    case contextVersionUnsupported
    /// The server could not assemble the voice context (VOICE_CONTEXT_UNAVAILABLE).
    case contextUnavailable
    /// The answer was for another session or conversation (SESSION_CONVERSATION_MISMATCH).
    case sessionMismatch
    /// The answer used another context scope (SCOPE_MISMATCH).
    case scopeMismatch
    /// The context changed after it was bound (VOICE_CONTEXT_CHANGED).
    case contextChanged
    /// The privacy lease expired before it could be refreshed (PRIVACY_LEASE_EXPIRED).
    case privacyLeaseExpired

    /// True when the failure means a previously valid binding or lease is no longer valid, as opposed
    /// to voice never having been available. Drives the stop reason shown to the person.
    var isContextInvalidation: Bool {
        switch self {
        case .bindingNotCurrent, .ownerMismatch, .privacyRevisionChanged, .contextChanged, .privacyLeaseExpired:
            return true
        case .unavailable, .contextRequired, .contextInvalid, .contextVersionUnsupported,
             .contextUnavailable, .sessionMismatch, .scopeMismatch:
            return false
        }
    }

    /// Maps a server error `code` from an admission failure to a narrow error. Unknown codes map to nil.
    static func fromServerCode(_ code: String?) -> VoiceSupportAccessError? {
        switch code {
        case "INVALID_VOICE_CONTEXT": return .contextInvalid
        case "VOICE_CONTEXT_VERSION_UNSUPPORTED": return .contextVersionUnsupported
        case "VOICE_CONTEXT_UNAVAILABLE": return .contextUnavailable
        case "SESSION_CONVERSATION_MISMATCH": return .sessionMismatch
        case "SCOPE_MISMATCH": return .scopeMismatch
        case "VOICE_CONTEXT_REQUIRED": return .contextRequired
        case "VOICE_CONTEXT_CHANGED": return .contextChanged
        case "PRIVACY_LEASE_EXPIRED": return .privacyLeaseExpired
        case "PRIVACY_REVISION_STALE", "PRIVACY_REVISION_CHANGED": return .privacyRevisionChanged
        default: return nil
        }
    }

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Voice isn't available for this conversation right now. You can continue by text."
        case .bindingNotCurrent, .ownerMismatch:
            return "Voice stopped because the account or session changed. Continue by text or start voice again."
        case .privacyRevisionChanged:
            return "Voice stopped because privacy settings changed. Continue by text or start voice again."
        case .contextRequired:
            return "Voice isn't available because the voice service doesn't support conversation context yet. You can continue by text."
        case .contextInvalid:
            return "Voice didn't start because the conversation context couldn't be verified. You can continue by text."
        case .contextVersionUnsupported:
            return "This version of MindFriend can't start voice for this conversation. Update the app or continue by text."
        case .contextUnavailable:
            return "Voice can't use this conversation's context right now. You can continue by text."
        case .sessionMismatch:
            return "Voice didn't start because the voice service answered for a different conversation. You can continue by text."
        case .scopeMismatch:
            return "Voice didn't start because the context selection didn't match. You can continue by text."
        case .contextChanged:
            return "Voice stopped because the conversation context changed. Continue by text or start voice again."
        case .privacyLeaseExpired:
            return "Voice stopped because privacy settings couldn't be confirmed in time. Continue by text or start voice again."
        }
    }
}

// MARK: - Voice context claim (nested admission contract)

/// The nested `voice_context` object a new-contract admission MUST return. Only this nested,
/// versioned object admits a session: top-level echo fields are ignored, because an older Edge
/// function that ignores the new request fields could echo them without enforcing anything.
struct VoiceContextClaim: Equatable, Sendable {
    static let supportedVersion = 1
    /// The privacy lease the relay holds, in milliseconds (spec §9.8: at most five seconds).
    static let requiredPrivacyLeaseMS = 5_000
    /// Voice packet cap in UTF-8 bytes (spec §9.8).
    static let maxPacketBytes = 8_000

    struct Provider: Equatable, Sendable {
        let vendor: String
        let model: String
        let routeVersion: String
    }

    let version: Int
    let supportSessionID: UUID
    let conversationID: UUID
    let scope: SupportContextScope
    let privacyRevision: Int64
    let contextReceiptID: UUID
    /// Lowercase hex SHA-256 of the packet the server assembled. The packet itself never reaches the client.
    let packetSHA256: String
    let packetBytes: Int
    let provider: Provider
    let privacyLeaseMS: Int

    /// Parses the nested object out of an admission response body, strictly. A missing object is a
    /// legacy relay (`contextRequired`); a malformed one is `contextInvalid`; another version is
    /// `contextVersionUnsupported`.
    static func parse(responseData: Data) -> Result<VoiceContextClaim, VoiceSupportAccessError> {
        guard let root = (try? JSONSerialization.jsonObject(with: responseData)) as? [String: Any] else {
            return .failure(.contextRequired)
        }
        return parse(object: root["voice_context"])
    }

    static func parse(object: Any?) -> Result<VoiceContextClaim, VoiceSupportAccessError> {
        guard let object, !(object is NSNull) else { return .failure(.contextRequired) }
        guard let dict = object as? [String: Any] else { return .failure(.contextInvalid) }
        guard let version = integer(dict["version"]) else { return .failure(.contextInvalid) }
        guard version == Int64(supportedVersion) else { return .failure(.contextVersionUnsupported) }

        guard let sessionString = dict["support_session_id"] as? String, let session = UUID(uuidString: sessionString),
              let conversationString = dict["conversation_id"] as? String, let conversation = UUID(uuidString: conversationString),
              let scopeString = dict["context_scope"] as? String, let scope = SupportContextScope(rawValue: scopeString),
              let revision = integer(dict["privacy_revision"]), revision >= 0,
              let receiptString = dict["context_receipt_id"] as? String, let receipt = UUID(uuidString: receiptString),
              receipt != UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)),
              let sha = dict["packet_sha256"] as? String, isSHA256Hex(sha),
              let bytes = integer(dict["packet_bytes"]), bytes >= 1, bytes <= Int64(maxPacketBytes),
              let providerDict = dict["provider"] as? [String: Any],
              let vendor = boundedText(providerDict["vendor"]),
              let model = boundedText(providerDict["model"]),
              let routeVersion = routeVersionText(providerDict["route_version"]),
              let lease = integer(dict["privacy_lease_ms"]) else {
            return .failure(.contextInvalid)
        }

        return .success(VoiceContextClaim(
            version: Int(version),
            supportSessionID: session,
            conversationID: conversation,
            scope: scope,
            privacyRevision: revision,
            contextReceiptID: receipt,
            packetSHA256: sha.lowercased(),
            packetBytes: Int(bytes),
            provider: Provider(vendor: vendor, model: model, routeVersion: routeVersion),
            privacyLeaseMS: Int(clamping: lease)
        ))
    }

    /// Requires the claim to match the immutable binding exactly. Throws before any socket is opened.
    func validate(against binding: VoiceSupportBinding) throws {
        guard version == Self.supportedVersion else { throw VoiceSupportAccessError.contextVersionUnsupported }
        guard supportSessionID == binding.supportSessionUUID, conversationID == binding.conversationUUID else {
            throw VoiceSupportAccessError.sessionMismatch
        }
        guard scope == binding.scope else { throw VoiceSupportAccessError.scopeMismatch }
        if let expected = binding.privacyRevision, privacyRevision != expected {
            throw VoiceSupportAccessError.privacyRevisionChanged
        }
        guard privacyLeaseMS == Self.requiredPrivacyLeaseMS else { throw VoiceSupportAccessError.contextInvalid }
    }

    // MARK: Strict JSON helpers

    /// An exact JSON integer. Booleans and non-integral numbers are rejected.
    private static func integer(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let candidate = number.int64Value
        return number.doubleValue == Double(candidate) ? candidate : nil
    }

    private static func isSHA256Hex(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 70) || ($0 >= 97 && $0 <= 102) }
    }

    private static func boundedText(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.utf8.count <= 128 ? trimmed : nil
    }

    private static func routeVersionText(_ value: Any?) -> String? {
        if let text = boundedText(value) { return text }
        if let number = integer(value) { return String(number) }
        return nil
    }
}

/// Outcome categories an access implementation may throw from `appendFinalEvent`.
/// Any other thrown error is treated as retryable.
enum VoiceSupportAppendError: Error, Equatable {
    /// Transient. The event stays pending and can be retried.
    case retryable
    /// Permanent for this event (for example invalid payload). It is not retried automatically.
    case rejected
    /// The binding is no longer current. Nothing is appended into another account or epoch.
    case bindingNotCurrent
}

// MARK: - Access (provided by the caller)

/// Caller-provided access to the support-session authority. The root constructs one over the real
/// repository/cloud service and injects it into the voice views. Voice never defines a second
/// session authority.
@MainActor
protocol VoiceSupportAccess: AnyObject {
    /// Non-mutating description of the selected session and context scope.
    func preview() -> VoiceSupportPreview

    /// Called ONLY after an explicit "Start voice". May create/attach the conversation. Returns the
    /// immutable binding for this voice session.
    func prepare() async throws -> VoiceSupportBinding

    /// Synchronous validity check (owner, account epoch, session/conversation, privacy revision).
    func isCurrent(_ binding: VoiceSupportBinding) -> Bool

    /// Durably append one FINAL transcript event (idempotent by `event.localUUID`). Returning
    /// normally IS the confirmation; voice never reports "saved" before this returns.
    func appendFinalEvent(_ binding: VoiceSupportBinding, _ event: VoiceTranscriptEvent) async throws

    /// Idempotent server reconcile of the acknowledged events. Called after voice stops.
    func reconcile(_ binding: VoiceSupportBinding) async

    /// Optional push signal for account/epoch/privacy/context invalidation. Each element asks the
    /// voice service to re-check `isCurrent`. Voice also re-checks at every event and on a timer, so
    /// this only makes invalidation faster. It may be called more than once (the service per session,
    /// each voice screen for its lifetime), so every call must return an independent stream.
    func invalidations() -> AsyncStream<Void>?
}

extension VoiceSupportAccess {
    func invalidations() -> AsyncStream<Void>? { nil }
}

// MARK: - Typed transcript events

enum VoiceTranscriptRole: String, Equatable, Hashable, Sendable {
    case user
    case assistant
}

enum VoiceTranscriptFinality: String, Equatable, Hashable, Sendable {
    /// Provisional: may be displayed, never persisted as a turn.
    case partial
    /// Provider-confirmed complete text: the only kind that is appended durably.
    case final
    /// The turn will never complete (cancelled, failed, incomplete, empty). Carries no text.
    case abandoned
}

enum VoiceTranscriptAbandonReason: String, Equatable, Hashable, Sendable {
    case emptyTranscript
    case transcriptionFailed
    case responseCancelled
    case responseIncomplete
    case responseFailed
    case sessionStopped
}

/// One transcript observation. `localUUID` is stable across a turn's partial updates and its final.
struct VoiceTranscriptEvent: Equatable, Identifiable, Sendable {
    let localUUID: UUID
    var id: UUID { localUUID }
    let binding: VoiceSupportBinding
    let role: VoiceTranscriptRole
    let providerItemID: String?
    let providerEventID: String?
    let providerResponseID: String?
    /// Conversation order assigned when the turn is first observed. Roles are never interleaved by
    /// array index; readers order by this value.
    let order: Int64
    /// Number of updates observed for this turn, starting at 1.
    let revision: Int
    let occurredAt: Date
    let finality: VoiceTranscriptFinality
    let abandonReason: VoiceTranscriptAbandonReason?
    /// Empty for `.abandoned`.
    let text: String
}

// MARK: - Assembler (pure, deterministic)

/// Turns provider realtime events into typed transcript events. Pure value type: no audio, no
/// network, no logging. Identity is the provider item/response when present; text is never used to
/// deduplicate, so two legitimate identical utterances stay distinct.
struct VoiceTranscriptAssembler {
    private struct Part {
        var itemID: String?
        var text: String
        var providerFinal: Bool
        /// Provider output position when reported; used to keep multi-item replies in output order.
        var outputIndex: Int?
    }

    private struct Slot {
        let localUUID: UUID
        let order: Int64
        var itemID: String?
        var responseID: String?
        var firstEventID: String?
        var revision: Int = 0
        /// User turns opened by speech_started stay anonymous until the commit names the item.
        var awaitingCommit = false
        // User turns use a single part; assistant turns may have several output items.
        var parts: [Part] = []

        /// Parts in provider output order when every part reports its position, else arrival order.
        var orderedParts: [Part] {
            guard parts.count > 1, parts.allSatisfy({ $0.outputIndex != nil }) else { return parts }
            return parts.enumerated()
                .sorted { ($0.element.outputIndex!, $0.offset) < ($1.element.outputIndex!, $1.offset) }
                .map(\.element)
        }
        var text: String { orderedParts.map(\.text).joined() }
        /// True only when there is at least one part and EVERY part is provider-final. One final part
        /// never vouches for another that is still streaming.
        var allPartsProviderFinal: Bool { !parts.isEmpty && parts.allSatisfy { $0.providerFinal } }
    }

    private struct BoundedKeySet {
        private var keys: Set<String> = []
        private var fifo: [String] = []
        private let capacity: Int
        init(capacity: Int) { self.capacity = capacity }
        func contains(_ key: String) -> Bool { keys.contains(key) }
        mutating func insert(_ key: String) {
            guard keys.insert(key).inserted else { return }
            fifo.append(key)
            if fifo.count > capacity { keys.remove(fifo.removeFirst()) }
        }
    }

    private static let maxOpenSlots = 32

    let binding: VoiceSupportBinding
    private let now: () -> Date
    private let makeID: () -> UUID
    private var nextOrder: Int64 = 1
    private var userSlots: [Slot] = []
    private var assistantSlots: [Slot] = []
    private var finalizedKeys = BoundedKeySet(capacity: 512)
    private var seenEventIDs = BoundedKeySet(capacity: 1_024)

    init(binding: VoiceSupportBinding, now: @escaping () -> Date = Date.init, makeID: @escaping () -> UUID = UUID.init) {
        self.binding = binding
        self.now = now
        self.makeID = makeID
    }

    /// Number of turns observed but not yet finished.
    var openTurnCount: Int { userSlots.count + assistantSlots.count }

    // MARK: Ingest

    mutating func ingest(type: String, json: [String: Any]) -> [VoiceTranscriptEvent] {
        let eventID = Self.string(json["event_id"])
        switch type {
        case "input_audio_buffer.speech_started":
            userSpeechStarted(itemID: Self.string(json["item_id"]))
            return []

        case "input_audio_buffer.committed":
            userCommitted(itemID: Self.string(json["item_id"]))
            return []

        case "conversation.item.created", "conversation.item.added":
            if let item = json["item"] as? [String: Any],
               Self.string(item["role"]) == "user",
               let itemID = Self.string(item["id"]) {
                _ = userSlotIndex(itemID: itemID, create: true)
            }
            return []

        case "conversation.item.input_audio_transcription.delta":
            guard let delta = json["delta"] as? String, !delta.isEmpty else { return [] }
            return userPartial(itemID: Self.string(json["item_id"]), eventID: eventID) { $0 + delta }

        case "conversation.item.input_audio_transcription.updated":
            guard let transcript = json["transcript"] as? String else { return [] }
            return userPartial(itemID: Self.string(json["item_id"]), eventID: eventID) { _ in transcript }

        case "conversation.item.input_audio_transcription.completed":
            guard let transcript = json["transcript"] as? String else { return [] }
            return userFinal(itemID: Self.string(json["item_id"]), eventID: eventID, text: transcript)

        case "conversation.item.input_audio_transcription.failed":
            return userAbandon(itemID: Self.string(json["item_id"]), reason: .transcriptionFailed)

        case "response.created":
            let response = json["response"] as? [String: Any]
            _ = assistantSlotIndex(responseID: Self.string(response?["id"]) ?? Self.string(json["response_id"]),
                                   itemID: nil, create: true)
            return []

        case "response.output_item.added":
            let item = json["item"] as? [String: Any]
            if Self.string(item?["role"]) == "user" { return [] }
            let index = assistantSlotIndex(responseID: Self.string(json["response_id"]),
                                           itemID: Self.string(item?["id"]), create: true)
            if let index, let itemID = Self.string(item?["id"]) {
                Self.ensurePart(in: &assistantSlots[index], itemID: itemID)
                if let outputIndex = json["output_index"] as? Int,
                   let partIndex = assistantSlots[index].parts.firstIndex(where: { $0.itemID == itemID }) {
                    assistantSlots[index].parts[partIndex].outputIndex = outputIndex
                }
            }
            return []

        case "response.audio_transcript.delta", "response.output_audio_transcript.delta",
             "response.text.delta", "response.output_text.delta":
            guard let delta = json["delta"] as? String, !delta.isEmpty else { return [] }
            return assistantPartial(json: json, eventID: eventID) { part in part.text += delta }

        case "response.audio_transcript.done", "response.output_audio_transcript.done":
            guard let transcript = json["transcript"] as? String else { return [] }
            return assistantPartial(json: json, eventID: eventID) { part in
                part.text = transcript
                part.providerFinal = true
            }

        case "response.text.done", "response.output_text.done":
            guard let text = (json["text"] as? String) ?? (json["transcript"] as? String) else { return [] }
            return assistantPartial(json: json, eventID: eventID) { part in
                part.text = text
                part.providerFinal = true
            }

        case "response.done":
            return responseDone(json: json, eventID: eventID)

        default:
            return []
        }
    }

    /// Ends every open turn without inventing completion. Used when the session stops.
    mutating func abandonOpenTurns(reason: VoiceTranscriptAbandonReason = .sessionStopped) -> [VoiceTranscriptEvent] {
        var events: [VoiceTranscriptEvent] = []
        for slot in userSlots where !slot.text.isEmpty {
            events.append(event(for: slot, role: .user, finality: .abandoned, reason: reason, text: "", eventID: nil))
        }
        for slot in assistantSlots where !slot.text.isEmpty {
            events.append(event(for: slot, role: .assistant, finality: .abandoned, reason: reason, text: "", eventID: nil))
        }
        userSlots.removeAll()
        assistantSlots.removeAll()
        return events.sorted { $0.order < $1.order }
    }

    // MARK: User turns

    private mutating func appendUserSlot(itemID: String?, awaitingCommit: Bool) {
        if userSlots.count >= Self.maxOpenSlots { userSlots.removeFirst() }
        var slot = Slot(localUUID: makeID(), order: takeOrder(), itemID: itemID)
        slot.awaitingCommit = awaitingCommit
        userSlots.append(slot)
    }

    private mutating func userSpeechStarted(itemID: String?) {
        if let itemID {
            if let index = userSlots.firstIndex(where: { $0.itemID == itemID }) {
                userSlots[index].awaitingCommit = true
            } else if let index = userSlots.firstIndex(where: { $0.itemID == nil && $0.awaitingCommit }) {
                userSlots[index].itemID = itemID
            } else {
                appendUserSlot(itemID: itemID, awaitingCommit: true)
            }
            return
        }
        // A start without an id while the newest anonymous turn is still uncommitted is the same turn.
        if let last = userSlots.last, last.itemID == nil, last.awaitingCommit { return }
        appendUserSlot(itemID: nil, awaitingCommit: true)
    }

    private mutating func userCommitted(itemID: String?) {
        if let itemID {
            if let index = userSlots.firstIndex(where: { $0.itemID == itemID }) {
                userSlots[index].awaitingCommit = false
            } else if let index = userSlots.firstIndex(where: { $0.itemID == nil && $0.awaitingCommit }) {
                userSlots[index].itemID = itemID
                userSlots[index].awaitingCommit = false
            } else if !finalizedKeys.contains("user:\(itemID)") {
                appendUserSlot(itemID: itemID, awaitingCommit: false)
            }
            return
        }
        if let index = userSlots.firstIndex(where: { $0.awaitingCommit }) {
            userSlots[index].awaitingCommit = false
        } else {
            appendUserSlot(itemID: nil, awaitingCommit: false)
        }
    }

    private mutating func userSlotIndex(itemID: String?, create: Bool) -> Int? {
        if let itemID {
            if let index = userSlots.firstIndex(where: { $0.itemID == itemID }) { return index }
            // Bind the oldest anonymous slot (opened by speech_started without an id).
            if let index = userSlots.firstIndex(where: { $0.itemID == nil }) {
                userSlots[index].itemID = itemID
                return index
            }
        } else if !userSlots.isEmpty {
            return 0
        }
        guard create else { return nil }
        appendUserSlot(itemID: itemID, awaitingCommit: false)
        return userSlots.count - 1
    }

    private mutating func userPartial(itemID: String?, eventID: String?, edit: (String) -> String) -> [VoiceTranscriptEvent] {
        if let itemID, finalizedKeys.contains("user:\(itemID)") { return [] }
        if let eventID, seenEventIDs.contains(eventID) { return [] }
        guard let index = userSlotIndex(itemID: itemID, create: true) else { return [] }
        if userSlots[index].parts.isEmpty { userSlots[index].parts = [Part(itemID: itemID, text: "", providerFinal: false, outputIndex: nil)] }
        let updated = edit(userSlots[index].parts[0].text)
        guard updated != userSlots[index].parts[0].text else { return [] }
        userSlots[index].parts[0].text = updated
        userSlots[index].revision += 1
        if let eventID { seenEventIDs.insert(eventID) }
        guard !updated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return [event(for: userSlots[index], role: .user, finality: .partial, reason: nil,
                      text: updated.trimmingCharacters(in: .whitespacesAndNewlines), eventID: eventID)]
    }

    private mutating func userFinal(itemID: String?, eventID: String?, text: String) -> [VoiceTranscriptEvent] {
        if let itemID, finalizedKeys.contains("user:\(itemID)") { return [] }
        if let eventID, seenEventIDs.contains(eventID) { return [] }
        guard let index = userSlotIndex(itemID: itemID, create: true) else { return [] }
        if let eventID { seenEventIDs.insert(eventID) }
        var slot = userSlots.remove(at: index)
        slot.revision += 1
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let key = slot.itemID ?? itemID { finalizedKeys.insert("user:\(key)") }
        guard !trimmed.isEmpty else {
            return [event(for: slot, role: .user, finality: .abandoned, reason: .emptyTranscript, text: "", eventID: eventID)]
        }
        return [event(for: slot, role: .user, finality: .final, reason: nil, text: trimmed, eventID: eventID)]
    }

    private mutating func userAbandon(itemID: String?, reason: VoiceTranscriptAbandonReason) -> [VoiceTranscriptEvent] {
        if let itemID, finalizedKeys.contains("user:\(itemID)") { return [] }
        guard let index = userSlotIndex(itemID: itemID, create: false) else { return [] }
        var slot = userSlots.remove(at: index)
        slot.revision += 1
        if let key = slot.itemID ?? itemID { finalizedKeys.insert("user:\(key)") }
        return [event(for: slot, role: .user, finality: .abandoned, reason: reason, text: "", eventID: nil)]
    }

    // MARK: Assistant turns

    private mutating func assistantSlotIndex(responseID: String?, itemID: String?, create: Bool) -> Int? {
        if let responseID {
            if let index = assistantSlots.firstIndex(where: { $0.responseID == responseID }) { return index }
            if let index = assistantSlots.lastIndex(where: { $0.responseID == nil }) {
                assistantSlots[index].responseID = responseID
                return index
            }
        } else if let itemID, let index = assistantSlots.firstIndex(where: { slot in
            slot.parts.contains { $0.itemID == itemID }
        }) {
            return index
        } else if !assistantSlots.isEmpty {
            return assistantSlots.count - 1
        }
        guard create else { return nil }
        if assistantSlots.count >= Self.maxOpenSlots { assistantSlots.removeFirst() }
        assistantSlots.append(Slot(localUUID: makeID(), order: takeOrder(), itemID: itemID, responseID: responseID))
        return assistantSlots.count - 1
    }

    private static func ensurePart(in slot: inout Slot, itemID: String?) {
        if let itemID {
            if slot.parts.contains(where: { $0.itemID == itemID }) { return }
            // Adopt an unidentified part that was opened before its item id was known.
            if let index = slot.parts.firstIndex(where: { $0.itemID == nil }) {
                slot.parts[index].itemID = itemID
                return
            }
        } else if !slot.parts.isEmpty {
            return
        }
        slot.parts.append(Part(itemID: itemID, text: "", providerFinal: false, outputIndex: nil))
        if slot.itemID == nil { slot.itemID = itemID }
    }

    private mutating func assistantPartial(json: [String: Any], eventID: String?, edit: (inout Part) -> Void) -> [VoiceTranscriptEvent] {
        let responseID = Self.string(json["response_id"])
        let itemID = Self.string(json["item_id"])
        if let responseID, finalizedKeys.contains("assistant:\(responseID)") { return [] }
        if let eventID, seenEventIDs.contains(eventID) { return [] }
        guard let index = assistantSlotIndex(responseID: responseID, itemID: itemID, create: true) else { return [] }
        Self.ensurePart(in: &assistantSlots[index], itemID: itemID)
        let partIndex = itemID.flatMap { id in assistantSlots[index].parts.firstIndex { $0.itemID == id } }
            ?? assistantSlots[index].parts.count - 1
        let before = assistantSlots[index].text
        edit(&assistantSlots[index].parts[partIndex])
        if let outputIndex = json["output_index"] as? Int {
            assistantSlots[index].parts[partIndex].outputIndex = outputIndex
        }
        if let eventID { seenEventIDs.insert(eventID) }
        guard assistantSlots[index].text != before else { return [] }
        assistantSlots[index].revision += 1
        let shown = assistantSlots[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !shown.isEmpty else { return [] }
        return [event(for: assistantSlots[index], role: .assistant, finality: .partial, reason: nil, text: shown, eventID: eventID)]
    }

    private mutating func responseDone(json: [String: Any], eventID: String?) -> [VoiceTranscriptEvent] {
        let response = json["response"] as? [String: Any]
        let responseID = Self.string(response?["id"]) ?? Self.string(json["response_id"])
        if let responseID, finalizedKeys.contains("assistant:\(responseID)") { return [] }
        if let eventID, seenEventIDs.contains(eventID) { return [] }
        let status = Self.string(response?["status"])?.lowercased()

        // The provider's own output list, in provider order. Each item carries its own terminal status.
        let outputItems = Self.outputItems(response?["output"])
        let textItems = outputItems.filter { !$0.text.isEmpty }

        var index = assistantSlotIndex(responseID: responseID, itemID: nil, create: false)
        if index == nil, !textItems.isEmpty, status == nil || status == "completed" {
            index = assistantSlotIndex(responseID: responseID, itemID: nil, create: true)
        }
        guard let index else { return [] }
        if let eventID { seenEventIDs.insert(eventID) }
        var slot = assistantSlots.remove(at: index)
        slot.revision += 1
        if slot.responseID == nil { slot.responseID = responseID }
        if let key = slot.responseID { finalizedKeys.insert("assistant:\(key)") }

        func abandoned(_ reason: VoiceTranscriptAbandonReason) -> [VoiceTranscriptEvent] {
            [event(for: slot, role: .assistant, finality: .abandoned, reason: reason, text: "", eventID: eventID)]
        }

        switch status {
        case "completed":
            // Even a response reported completed is refused if one of its own items says otherwise.
            if let reason = Self.unfinishedReason(outputItems) { return abandoned(reason) }
        case nil:
            // No response status: nothing is trusted merely because it is present. An explicitly
            // unfinished item abandons the turn; otherwise every item that carries text needs positive
            // evidence (its own "completed" status, or a provider-final transcript for that item).
            if let reason = Self.unfinishedReason(outputItems) { return abandoned(reason) }
            if textItems.isEmpty {
                // Nothing in the output list: every streamed part must be final, because one final part
                // must not promote another that is still unfinished.
                guard slot.allPartsProviderFinal else { return abandoned(.responseIncomplete) }
            } else {
                let allEvidenced = textItems.allSatisfy { item in
                    item.status == "completed"
                        || (item.itemID != nil && slot.parts.contains { $0.itemID == item.itemID && $0.providerFinal })
                }
                guard allEvidenced else { return abandoned(.responseIncomplete) }
            }
        case "cancelled", "canceled":
            return abandoned(.responseCancelled)
        case "failed":
            return abandoned(.responseFailed)
        default:
            return abandoned(.responseIncomplete)
        }

        // The provider's list is authoritative and keeps provider order; a streamed part that is not in
        // it (still unfinished) is never added.
        let providerText = textItems.map { $0.text }.joined()
        let chosen = (providerText.isEmpty ? slot.text : providerText).trimmingCharacters(in: .whitespacesAndNewlines)
        if slot.itemID == nil { slot.itemID = textItems.first?.itemID ?? slot.orderedParts.first?.itemID }
        guard !chosen.isEmpty else { return abandoned(.emptyTranscript) }
        return [event(for: slot, role: .assistant, finality: .final, reason: nil, text: chosen, eventID: eventID)]
    }

    // MARK: Helpers

    private mutating func takeOrder() -> Int64 {
        defer { nextOrder += 1 }
        return nextOrder
    }

    private func event(for slot: Slot, role: VoiceTranscriptRole, finality: VoiceTranscriptFinality,
                       reason: VoiceTranscriptAbandonReason?, text: String, eventID: String?) -> VoiceTranscriptEvent {
        VoiceTranscriptEvent(
            localUUID: slot.localUUID,
            binding: binding,
            role: role,
            providerItemID: slot.itemID ?? slot.parts.first?.itemID,
            providerEventID: eventID ?? slot.firstEventID,
            providerResponseID: slot.responseID,
            order: slot.order,
            revision: max(1, slot.revision),
            occurredAt: now(),
            finality: finality,
            abandonReason: reason,
            text: text
        )
    }

    private static func string(_ value: Any?) -> String? {
        guard let value = value as? String, !value.isEmpty else { return nil }
        return value
    }

    /// One item of a `response.done` output list. `text` is empty for items without a transcript.
    private struct OutputItem {
        let itemID: String?
        /// Lowercased terminal status when the provider reports one.
        let status: String?
        let text: String
    }

    private static func outputItems(_ value: Any?) -> [OutputItem] {
        guard let output = value as? [[String: Any]] else { return [] }
        return output.map { item in
            let parts = (item["content"] as? [[String: Any]]) ?? []
            let text = parts.compactMap { ($0["transcript"] as? String) ?? ($0["text"] as? String) }
                .filter { !$0.isEmpty }
                .joined()
            return OutputItem(itemID: string(item["id"]), status: string(item["status"])?.lowercased(), text: text)
        }
    }

    /// Why a turn is refused, if ANY output item explicitly reports a status other than completed.
    private static func unfinishedReason(_ items: [OutputItem]) -> VoiceTranscriptAbandonReason? {
        let unfinished = items.compactMap { $0.status }.filter { $0 != "completed" }
        guard !unfinished.isEmpty else { return nil }
        if unfinished.contains("failed") { return .responseFailed }
        if unfinished.contains("cancelled") || unfinished.contains("canceled") { return .responseCancelled }
        return .responseIncomplete
    }
}

// MARK: - Captions (what the person sees, with its finality)

/// The caption currently on screen. Carries the typed finality so the UI can label a provisional
/// caption as live and only mark it complete on the corresponding final event.
struct VoiceCaption: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        /// Provisional text that may still change or never complete.
        case live
        /// The provider confirmed this turn complete.
        case complete
        /// The turn ended without completing; the text shown was never confirmed and is not saved.
        case interrupted
    }

    let localUUID: UUID
    let role: VoiceTranscriptRole
    let text: String
    let phase: Phase

    var speakerLabel: String { role == .user ? "You" : "Assistant" }

    var phaseLabel: String {
        switch phase {
        case .live: return "Live"
        case .complete: return "Complete"
        case .interrupted: return "Interrupted"
        }
    }

    var accessibilityLabel: String {
        switch phase {
        case .live: return "\(speakerLabel) caption, live, not final"
        case .complete: return "\(speakerLabel) caption, complete"
        case .interrupted: return "\(speakerLabel) caption, interrupted, not saved"
        }
    }
}

/// Derives the displayed caption from typed events only (never from a transient string).
struct VoiceCaptionTracker {
    private(set) var current: VoiceCaption?

    mutating func apply(_ event: VoiceTranscriptEvent) {
        switch event.finality {
        case .partial:
            // A late partial never regresses a turn that already completed or was interrupted.
            if let current, current.localUUID == event.localUUID, current.phase != .live { return }
            current = VoiceCaption(localUUID: event.localUUID, role: event.role, text: event.text, phase: .live)
        case .final:
            current = VoiceCaption(localUUID: event.localUUID, role: event.role, text: event.text, phase: .complete)
        case .abandoned:
            // Only the turn on screen is affected; its provisional text stays visible but is labeled.
            guard let current, current.localUUID == event.localUUID, current.phase == .live else { return }
            self.current = VoiceCaption(localUUID: current.localUUID, role: current.role, text: current.text, phase: .interrupted)
        }
    }

    mutating func clear() { current = nil }

    /// Drops a finished caption after it has been on screen; a provisional one stays.
    mutating func clearIfComplete() {
        if current?.phase == .complete { current = nil }
    }
}

// MARK: - Leaving a voice screen

/// The single decision both voice views use before navigating away after an explicit End or text
/// switch. Rejected finals count exactly like pending ones: leaving with either is an explicit
/// "leave without saving" choice, never an automatic dismissal.
enum VoiceLeaveGate {
    enum Decision: Equatable {
        case leave
        case holdForTranscript
    }

    static func decide(unsaved: Int, rejected: Int) -> Decision {
        unsaved > 0 || rejected > 0 ? .holdForTranscript : .leave
    }

    /// Whether a screen that is holding for the transcript may now leave by itself. This is
    /// evaluated whenever the counts change, so a pending final turning into a rejected one during
    /// End does not release the hold.
    static func shouldAutoLeave(leaveRequested: Bool, unsaved: Int, rejected: Int) -> Bool {
        leaveRequested && decide(unsaved: unsaved, rejected: rejected) == .leave
    }
}

/// Binds a pending leave (End / text switch) to the generation in which it was issued, so a decision
/// that is still waiting on remote work can never act on a session that started after it. A new
/// explicit Start, an owner or account change, or a context change invalidates every older decision.
struct VoiceExitGate {
    private(set) var generation: UInt64 = 0

    /// A new explicit leave supersedes every older one.
    mutating func begin() -> UInt64 {
        generation &+= 1
        return generation
    }

    /// Start, owner / account change or context change: every pending leave becomes obsolete.
    mutating func invalidate() {
        generation &+= 1
    }

    func isCurrent(_ ticket: UInt64) -> Bool { ticket == generation }
}

// MARK: - Durability journal

/// Holds FINAL events until the access confirms each append. "Saved" is set strictly after
/// `appendFinalEvent` returns. Failures stay pending and retryable; nothing is deduplicated by text.
///
/// Memory contract: an event's text is retained while it is pending, in flight, or rejected, and is
/// released only when the access acknowledges it or the person explicitly discards it.
@MainActor
final class VoiceTranscriptJournal {
    enum EntryState: Equatable {
        case pending
        case inFlight
        case saved
        /// Permanent for this event; surfaced to the person, never retried automatically.
        case rejected
    }

    struct Entry: Equatable {
        let event: VoiceTranscriptEvent
        var state: EntryState
        var attempts: Int
    }

    enum FailureCategory: String, Equatable {
        case retryable
        case rejected
        case bindingNotCurrent
        case unknown
    }

    let binding: VoiceSupportBinding
    let access: any VoiceSupportAccess
    /// Unresolved entries only (pending, in flight, rejected). Acknowledged events are released.
    private(set) var entries: [UUID: Entry] = [:]
    /// Identities the access has acknowledged. Text is no longer held for these.
    private(set) var savedIDs: Set<UUID> = []
    private(set) var lastFailure: FailureCategory?
    /// Set when the access reported the binding is no longer current: no further appends happen.
    private(set) var isBindingStale = false
    private var drainTask: Task<Void, Never>?

    /// Called after any state change (the service republishes counts from here).
    var onChange: (() -> Void)?

    init(binding: VoiceSupportBinding, access: any VoiceSupportAccess) {
        self.binding = binding
        self.access = access
    }

    // MARK: Observation

    var unsavedCount: Int { entries.values.filter { $0.state == .pending || $0.state == .inFlight }.count }
    var rejectedCount: Int { entries.values.filter { $0.state == .rejected }.count }
    var savedCount: Int { savedIDs.count }
    /// Anything the person could still lose: pending, in flight, or rejected.
    var unresolvedCount: Int { entries.count }
    func state(of id: UUID) -> EntryState? { savedIDs.contains(id) ? .saved : entries[id]?.state }

    /// Unresolved entries in conversation order (the order carried by the events).
    var orderedEntries: [Entry] {
        entries.values.sorted { ($0.event.order, $0.event.localUUID.uuidString) < ($1.event.order, $1.event.localUUID.uuidString) }
    }

    // MARK: Submit / retry / flush / discard

    /// Idempotent by `localUUID`. Only `.final` events are accepted, and only for this binding.
    func submitFinal(_ event: VoiceTranscriptEvent) {
        guard event.finality == .final, event.binding == binding,
              entries[event.localUUID] == nil, !savedIDs.contains(event.localUUID) else { return }
        entries[event.localUUID] = Entry(event: event, state: .pending, attempts: 0)
        onChange?()
        startDrainIfNeeded()
    }

    /// Waits for any pass in progress, then makes one more pass over events still pending.
    /// Permanently rejected events are retried only when the person asks (`includeRejected`).
    func retry(includeRejected: Bool = false) async {
        await drainTask?.value
        if includeRejected { requeueRejected() }
        guard !isBindingStale, unsavedCount > 0 else { return }
        startDrainIfNeeded()
        await drainTask?.value
    }

    /// Waits for in-flight work, then makes one more pass over anything still pending.
    func flush() async {
        await retry()
    }

    /// Explicit recovery: rejected events become pending again so the next pass retries them.
    func requeueRejected() {
        var changed = false
        for (id, entry) in entries where entry.state == .rejected {
            entries[id]?.state = .pending
            changed = true
        }
        if changed {
            lastFailure = nil
            onChange?()
        }
    }

    /// Explicit discard of everything not acknowledged. This never marks anything saved and cannot
    /// recall an append that is already in flight; it only stops this journal from holding the text.
    @discardableResult
    func discardUnresolved() -> Int {
        let count = entries.count
        entries.removeAll()
        lastFailure = nil
        if count > 0 { onChange?() }
        return count
    }

    private func startDrainIfNeeded() {
        guard drainTask == nil, !isBindingStale else { return }
        guard entries.values.contains(where: { $0.state == .pending }) else { return }
        drainTask = Task { @MainActor [weak self] in
            let completedPass = await self?.drain() ?? false
            self?.drainTask = nil
            // Events submitted while the pass was finishing must not be stranded. A pass that stopped
            // on a retryable failure waits for an explicit retry or the next final instead.
            if completedPass, let self, !self.isBindingStale,
               self.entries.values.contains(where: { $0.state == .pending }) {
                self.startDrainIfNeeded()
            }
        }
    }

    /// Sequential, in conversation order. A retryable failure stops the pass (head-of-line) so a
    /// later retry keeps the original order; a rejected event does not block the others.
    private func drain() async -> Bool {
        lastFailure = nil
        while let next = orderedEntries.first(where: { $0.state == .pending }) {
            let id = next.event.localUUID
            entries[id]?.state = .inFlight
            entries[id]?.attempts += 1
            onChange?()
            do {
                try await access.appendFinalEvent(binding, next.event)
                // Confirmed by the access: only now is the event saved, and its text is released.
                // (If the person discarded it meanwhile, the acknowledged write is still real.)
                entries[id] = nil
                savedIDs.insert(id)
                onChange?()
            } catch let error as VoiceSupportAppendError {
                switch error {
                case .rejected:
                    entries[id]?.state = .rejected
                    lastFailure = .rejected
                    onChange?()
                case .retryable:
                    entries[id]?.state = .pending
                    lastFailure = .retryable
                    onChange?()
                    return false
                case .bindingNotCurrent:
                    entries[id]?.state = .pending
                    lastFailure = .bindingNotCurrent
                    isBindingStale = true
                    onChange?()
                    return false
                }
            } catch {
                entries[id]?.state = .pending
                lastFailure = .unknown
                onChange?()
                return false
            }
        }
        return true
    }
}
