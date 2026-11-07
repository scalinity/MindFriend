import Foundation

// MARK: - Support session foundation models (spec §9.2–9.6)
//
// Foundation-only, Codable, Sendable value types. No UI, network or Supabase dependencies.
// Free-text fields are user content: never log them (spec §9.9).

public enum SupportSessionLimits {
    // Text limits count Unicode scalars (code points), matching Postgres char_length and the Edge contract.
    public static let schemaVersion = 1
    public static let titleMaxCharacters = 80
    public static let concernMaxCharacters = 4_000
    public static let draftMaxCharacters = 4_000
    public static let stepActionMaxCharacters = 400
    public static let reflectionNoteMaxCharacters = 1_000
    public static let shareableNoteMaxCharacters = 1_000
    public static let responseMaxCharacters = 4_000
    public static let transcriptTextMaxCharacters = 20_000
    public static let checkpointMaxBytes = 32 * 1_024
    public static let journalMaxBytes = 8 * 1_024 * 1_024
    public static let maxSessions = 200
    public static let maxActivitiesPerSession = 50
    public static let maxEventsPerSession = 1_000
    public static let maxUnsentIntents = 500
    public static let maxPendingTranscriptEvents = 2_000
    public static let maxRetainedSavedTranscriptIDs = 500
    public static let maxFailureRecords = 100
}

// MARK: - Identity

/// Immutable authenticated owner + account epoch. A repository is bound to exactly one of these.
public struct SupportSessionIdentity: Equatable, Hashable, Sendable {
    public let ownerID: UUID
    public let epochID: UUID

    public init(ownerID: UUID, epochID: UUID = UUID()) {
        self.ownerID = ownerID
        self.epochID = epochID
    }
}

// MARK: - Enumerations

public enum SupportSessionStatus: String, Codable, Equatable, Sendable {
    case open, closed, deleted
}

public enum SupportActivityStatus: String, Codable, Equatable, Sendable {
    case ready
    case inProgress = "in_progress"
    case paused, completed, stopped

    public var isTerminal: Bool { self == .completed || self == .stopped }
    public var isUnfinished: Bool { !isTerminal }
}

public enum SupportSyncStatus: String, Codable, Equatable, Sendable {
    case localOnly = "local_only"
    case pending, synced, conflict, failed
}

public enum SupportContextScope: String, Codable, Equatable, Sendable {
    case conversationOnly = "conversation_only"
    case personalized
}

public enum SupportActivityTemplateKey: String, Codable, Equatable, Sendable, CaseIterable {
    case groundPresentV1 = "ground_present_v1"
    case untangleThoughtV1 = "untangle_thought_v1"
    case chooseStepV1 = "choose_step_v1"

    public var kind: SupportActivityKind {
        switch self {
        case .groundPresentV1: return .grounding
        case .untangleThoughtV1: return .untangle
        case .chooseStepV1: return .chooseStep
        }
    }
}

public enum SupportActivityKind: String, Codable, Equatable, Sendable {
    case grounding, untangle
    case chooseStep = "choose_step"
}

public enum SupportReflectionOutcome: String, Codable, Equatable, Sendable {
    case helpful
    case notForMe = "not_for_me"
    case notSure = "not_sure"
    case skip
}

public enum SupportStepState: String, Codable, Equatable, Sendable {
    /// A proposed draft is editable input; it has not been saved or completed.
    case draft
    case saved
    case selfReportedDone = "self_reported_done"
    case dismissed
}

public enum SupportStepChoice: String, Codable, Equatable, Sendable {
    case saveForLater, didIt, notNow
}

public enum SupportCanonicalReferenceKind: String, Codable, Equatable, Sendable {
    case exerciseSession = "exercise_session"
    case journalEntry = "journal_entry"
}

public struct SupportCanonicalReference: Codable, Equatable, Sendable {
    public var kind: SupportCanonicalReferenceKind
    public var id: UUID
    public init(kind: SupportCanonicalReferenceKind, id: UUID) {
        self.kind = kind
        self.id = id
    }
}

// MARK: - Activity payloads

/// Checkpoint payload version 1 (spec §9.3).
public struct SupportCheckpoint: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var payloadVersion: Int
    public var templateVersion: Int
    public var lastPromptID: String?
    public var completedStepIDs: [String]
    public var skippedStepIDs: [String]
    /// Optional typed responses keyed by prompt ID (private content).
    public var responses: [String: String]
    public var activeMilliseconds: Int64
    public var lastDurableWrite: Date?

    public init(
        payloadVersion: Int = SupportCheckpoint.currentVersion,
        templateVersion: Int = 1,
        lastPromptID: String? = nil,
        completedStepIDs: [String] = [],
        skippedStepIDs: [String] = [],
        responses: [String: String] = [:],
        activeMilliseconds: Int64 = 0,
        lastDurableWrite: Date? = nil
    ) {
        self.payloadVersion = payloadVersion
        self.templateVersion = templateVersion
        self.lastPromptID = lastPromptID
        self.completedStepIDs = completedStepIDs
        self.skippedStepIDs = skippedStepIDs
        self.responses = responses
        self.activeMilliseconds = activeMilliseconds
        self.lastDurableWrite = lastDurableWrite
    }

    public static let empty = SupportCheckpoint()
}

/// Device-only state. Account sync never schedules a reminder on another device.
public enum SupportReminderState: String, Codable, Equatable, Sendable {
    case pending, scheduled, failed
}

/// Practical-step payload (spec §9.3). Owned by the activity; not an ActionPlan item.
public struct SupportStepPayload: Codable, Equatable, Sendable {
    public var actionText: String
    public var state: SupportStepState
    public var reminderAt: Date?
    public var reminderTimeZoneIdentifier: String?
    public var reminderState: SupportReminderState?
    public var confirmedAt: Date?

    /// Notification choices belong only to the protected journal on this device.
    public var accountPayload: SupportStepPayload {
        SupportStepPayload(actionText: actionText, state: state, confirmedAt: confirmedAt)
    }

    public init(
        actionText: String,
        state: SupportStepState,
        reminderAt: Date? = nil,
        reminderTimeZoneIdentifier: String? = nil,
        reminderState: SupportReminderState? = nil,
        confirmedAt: Date? = nil
    ) {
        self.actionText = actionText
        self.state = state
        self.reminderAt = reminderAt
        self.reminderTimeZoneIdentifier = reminderTimeZoneIdentifier
        self.reminderState = reminderState
        self.confirmedAt = confirmedAt
    }
}

public struct SupportActivityResult: Codable, Equatable, Sendable {
    public var acknowledgedStepCount: Int
    public var skippedStepCount: Int
    public var activeMilliseconds: Int64
    /// Content-free reason for stopped results, e.g. `skipped_all`, `user_ended`, `discarded`, `session_closed`, `replaced`.
    public var stoppedReason: String?
    /// Exact text the person approved for the conversation (spec §5.5). Off by default.
    public var shareableNote: String?

    public init(
        acknowledgedStepCount: Int = 0,
        skippedStepCount: Int = 0,
        activeMilliseconds: Int64 = 0,
        stoppedReason: String? = nil,
        shareableNote: String? = nil
    ) {
        self.acknowledgedStepCount = acknowledgedStepCount
        self.skippedStepCount = skippedStepCount
        self.activeMilliseconds = activeMilliseconds
        self.stoppedReason = stoppedReason
        self.shareableNote = shareableNote
    }
}

public struct SupportReflection: Codable, Equatable, Sendable {
    public var outcome: SupportReflectionOutcome
    public var note: String?
    public var includeWrittenAnswers: Bool
    public var recordedAt: Date
    public var shareableText: String?

    public init(outcome: SupportReflectionOutcome, note: String? = nil, includeWrittenAnswers: Bool = false, recordedAt: Date, shareableText: String? = nil) {
        self.outcome = outcome
        self.note = note
        self.includeWrittenAnswers = includeWrittenAnswers
        self.recordedAt = recordedAt
        self.shareableText = shareableText
    }
}

// MARK: - Session / activity / events

public struct SupportActivity: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let templateKey: SupportActivityTemplateKey
    public var templateVersion: Int
    public var kind: SupportActivityKind { templateKey.kind }
    public var status: SupportActivityStatus
    public var canonicalReference: SupportCanonicalReference?
    public var checkpoint: SupportCheckpoint
    public var step: SupportStepPayload?
    public var activeMilliseconds: Int64
    public var result: SupportActivityResult?
    public var reflection: SupportReflection?
    public var lastChangedRevision: Int64
    public var syncStatus: SupportSyncStatus
    public let createdAt: Date
    public var updatedAt: Date
    public var finishedAt: Date?
    public var acceptedProposalID: UUID? = nil

    enum CodingKeys: String, CodingKey {
        case id, sessionID, templateKey, templateVersion, status, canonicalReference, checkpoint, step
        case activeMilliseconds, result, reflection, lastChangedRevision, syncStatus, createdAt, updatedAt, finishedAt, acceptedProposalID
    }
}

public struct SupportSession: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    /// Immutable authenticated owner. Must equal the repository identity's owner.
    public let ownerID: UUID
    public var conversationID: UUID?
    public var previousSessionID: UUID?
    public var selectedActivityID: UUID?
    public var title: String
    public var concern: String?
    public var status: SupportSessionStatus
    public var contextScope: SupportContextScope
    /// Local monotonic counter bumped on each accepted local mutation. The server-authoritative
    /// revision is tracked separately in `SupportJournal.serverRevisions`.
    public var localRevision: Int64
    public var syncStatus: SupportSyncStatus
    public let createdAt: Date
    public var updatedAt: Date
    public var closedAt: Date?
}

public enum SupportEventKind: String, Codable, Equatable, Sendable {
    case sessionCreated = "session_created"
    case sessionRenamed = "session_renamed"
    case scopeChanged = "scope_changed"
    case sessionClosed = "session_closed"
    case activityStarted = "activity_started"
    case checkpointSaved = "checkpoint_saved"
    case activityPaused = "activity_paused"
    case activityResumed = "activity_resumed"
    case activityCompleted = "activity_completed"
    case activityStopped = "activity_stopped"
    case activityDiscarded = "activity_discarded"
    case stepSaved = "step_saved"
    case reflected
}

/// Content-free timeline event (spec §9.3 `support_session_events`).
public struct SupportSessionEvent: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let activityID: UUID?
    public let kind: SupportEventKind
    public let occurredAt: Date
    /// Short non-sensitive detail, e.g. a stopped reason code. Never user text.
    public let detail: String?
}

// MARK: - Mutations / outbox

public enum SupportMutationKind: String, Codable, Equatable, Sendable {
    case create
    case updateSession = "update_session"
    case acceptProposal = "accept_proposal"
    case startActivity = "start_activity"
    case checkpointActivity = "checkpoint_activity"
    case finishActivity = "finish_activity"
    case recordReflection = "record_reflection"
    /// Typed, idempotent server scrub (new contract operation): removes checkpoint responses, result/reflection notes and step text.
    case discardActivityAnswers = "discard_activity_answers"
    case deleteSession = "delete_session"
}

/// Discriminated bounded payload. Cases only carry structured activity data — never hidden AI requests.
public enum SupportMutationPayload: Codable, Equatable, Sendable {
    case create(title: String, concern: String?, conversationID: UUID?, previousSessionID: UUID?, contextScope: SupportContextScope)
    case updateSession(title: String?, contextScope: SupportContextScope?, status: SupportSessionStatus?)
    case attachConversation(conversationID: UUID)
    case declineTemplate(SupportActivityTemplateKey)
    case acceptProposal(proposalID: UUID, activityID: UUID)
    case startActivity(activityID: UUID, templateKey: SupportActivityTemplateKey, templateVersion: Int, canonicalReference: SupportCanonicalReference?)
    case checkpointActivity(activityID: UUID, status: SupportActivityStatus, checkpoint: SupportCheckpoint, step: SupportStepPayload?)
    /// `checkpoint` is the exact final checkpoint (answers included) so Finish never depends on a separate checkpoint mutation.
    case finishActivity(activityID: UUID, status: SupportActivityStatus, result: SupportActivityResult, step: SupportStepPayload?, checkpoint: SupportCheckpoint?)
    case recordReflection(activityID: UUID, reflection: SupportReflection)
    case discardActivityAnswers(activityID: UUID)
    case deleteSession

    public var kind: SupportMutationKind {
        switch self {
        case .create: return .create
        case .updateSession, .attachConversation, .declineTemplate: return .updateSession
        case .acceptProposal: return .acceptProposal
        case .startActivity: return .startActivity
        case .checkpointActivity: return .checkpointActivity
        case .finishActivity: return .finishActivity
        case .recordReflection: return .recordReflection
        case .discardActivityAnswers: return .discardActivityAnswers
        case .deleteSession: return .deleteSession
        }
    }

    public var targetActivityID: UUID? {
        switch self {
        case .acceptProposal(_, let id), .startActivity(let id, _, _, _), .checkpointActivity(let id, _, _, _),
             .finishActivity(let id, _, _, _, _), .recordReflection(let id, _), .discardActivityAnswers(let id):
            return id
        default:
            return nil
        }
    }

    /// Same operation with all user-authored content removed. Used only for attempts that must never be replayed
    /// (session deleted / scrubbed) so a content-bearing wire envelope is not kept or re-published.
    var contentRedacted: SupportMutationPayload {
        switch self {
        case .create(_, _, let conversationID, let previousSessionID, let scope):
            return .create(title: "", concern: nil, conversationID: conversationID, previousSessionID: previousSessionID, contextScope: scope)
        case .updateSession(_, let scope, let status):
            return .updateSession(title: nil, contextScope: scope, status: status)
        case .checkpointActivity(let id, let status, let cp, _):
            return .checkpointActivity(activityID: id, status: status, checkpoint: SupportCheckpoint(templateVersion: cp.templateVersion), step: nil)
        case .finishActivity(let id, let status, var result, _, _):
            result.shareableNote = nil
            return .finishActivity(activityID: id, status: status, result: result, step: nil, checkpoint: nil)
        case .recordReflection(let id, var reflection):
            reflection.note = nil
            reflection.shareableText = nil
            reflection.includeWrittenAnswers = false
            return .recordReflection(activityID: id, reflection: reflection)
        case .attachConversation, .declineTemplate, .acceptProposal, .startActivity, .discardActivityAnswers, .deleteSession:
            return self
        }
    }
}

/// An ordered, still-unsent local intent. May be rewritten (coalesced/rebased) because nothing was transmitted.
public struct SupportMutationIntent: Codable, Equatable, Identifiable, Sendable {
    /// Stable across rebases.
    public let id: UUID
    public var operationID: UUID
    public let sessionID: UUID
    public var payload: SupportMutationPayload
    public let createdAt: Date
    public var rebaseCount: Int
}

/// The wire envelope. Fully immutable once created; replays resend exactly this value (spec §9.4).
public struct SupportMutationEnvelope: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let operationID: UUID
    public let sessionID: UUID
    public let expectedRevision: Int64?
    public let kind: SupportMutationKind
    public let payload: SupportMutationPayload
    /// Local normalized payload fingerprint (FNV-1a 64 over canonical JSON); the server computes its own hash.
    public let payloadFingerprint: String
}

public enum SupportAttemptState: Codable, Equatable, Sendable {
    /// Transmission started in this process.
    case inFlight
    /// Outcome unknown (transient failure or relaunch). Replay the same operation ID.
    case ambiguous
    /// Definite 409; waiting for a compatible rebase or abandonment.
    case rejectedConflict(currentRevision: Int64)
}

public struct SupportTransmittedAttempt: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID { envelope.operationID }
    public let intentID: UUID
    /// Immutable while the attempt may be replayed. Replaced by a content-free equivalent (`contentRedacted`)
    /// only when the session was deleted/scrubbed and the attempt must be reconciled, never replayed.
    public internal(set) var envelope: SupportMutationEnvelope
    public var state: SupportAttemptState
    public let firstTransmittedAt: Date
    public var transmissionCount: Int
    public let rebaseCount: Int
    public internal(set) var contentRedacted: Bool = false

    enum CodingKeys: String, CodingKey {
        case intentID, envelope, state, firstTransmittedAt, transmissionCount, rebaseCount, contentRedacted
    }
}

extension SupportTransmittedAttempt {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        intentID = try c.decode(UUID.self, forKey: .intentID)
        envelope = try c.decode(SupportMutationEnvelope.self, forKey: .envelope)
        state = try c.decode(SupportAttemptState.self, forKey: .state)
        firstTransmittedAt = try c.decode(Date.self, forKey: .firstTransmittedAt)
        transmissionCount = try c.decode(Int.self, forKey: .transmissionCount)
        rebaseCount = try c.decode(Int.self, forKey: .rebaseCount)
        contentRedacted = try c.decodeIfPresent(Bool.self, forKey: .contentRedacted) ?? false
    }
}

public enum SupportAttemptOutcome: Equatable, Sendable {
    case confirmed(revision: Int64)
    case revisionConflict(currentRevision: Int64)
    /// Non-retryable (auth/validation/ownership/expired/tombstoned). Content-free code only.
    case rejected(code: String)
    /// Transport / 5xx: keep the same operation ID.
    case transientFailure
}

/// Content-free diagnostic for a non-retryable rejection.
public struct SupportSyncFailure: Codable, Equatable, Sendable {
    public let operationID: UUID
    public let sessionID: UUID
    public let kind: SupportMutationKind
    public let code: String
    public let at: Date
}

// MARK: - Privacy suppression (spec §8.5)

public enum SupportSuppressionKind: String, Codable, Equatable, Sendable {
    case memory
    case memoryFragment = "memory_fragment"
    case sourceMessage = "source_message"
    case sourceConversation = "source_conversation"
    case derivedRecord = "derived_record"
}

/// Identifier-only suppression record. Never stores forgotten plaintext.
public struct SupportPrivacySuppression: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: SupportSuppressionKind
    public let targetID: String
    public let createdAt: Date
    /// Account-wide privacy revision returned by the server; nil until acknowledged.
    public var acknowledgedPrivacyRevision: Int64?
    public var isAcknowledged: Bool { acknowledgedPrivacyRevision != nil }
}

// MARK: - Transcript events (spec §9.8)

public enum SupportTranscriptRole: String, Codable, Equatable, Sendable {
    case user, assistant, system
}

public enum SupportTranscriptSyncState: String, Codable, Equatable, Sendable {
    case pending, saved, rejected
}

public struct SupportTranscriptEvent: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let providerEventID: String?
    public let sessionID: UUID
    public let conversationID: UUID?
    public let role: SupportTranscriptRole
    /// Ordered per session; assigned by the repository.
    public let sequence: Int64
    public let occurredAt: Date
    public let voiceCallID: UUID?
    public let providerOrder: Int64?
    public let providerItemID: String?
    public let voiceCallStartedAt: Date?
    /// Cleared once the server confirms the event is saved.
    public var text: String
    public var syncState: SupportTranscriptSyncState
    /// A definitive account rejection. Text remains protected locally and is never retried automatically.
    public var failureCode: String?

    public init(id: UUID, providerEventID: String?, sessionID: UUID, conversationID: UUID?,
                role: SupportTranscriptRole, sequence: Int64, occurredAt: Date, text: String,
                syncState: SupportTranscriptSyncState, voiceCallID: UUID? = nil, providerOrder: Int64? = nil,
                providerItemID: String? = nil, voiceCallStartedAt: Date? = nil) {
        self.id = id
        self.providerEventID = providerEventID
        self.sessionID = sessionID
        self.conversationID = conversationID
        self.role = role
        self.sequence = sequence
        self.occurredAt = occurredAt
        self.text = text
        self.syncState = syncState
        self.voiceCallID = voiceCallID
        self.providerOrder = providerOrder
        self.providerItemID = providerItemID
        self.voiceCallStartedAt = voiceCallStartedAt
    }
}

// MARK: - Deletion tombstone

/// Content-free owner/session-ID tombstone (spec §9.4). Queued operations targeting it are rejected.
public struct SupportSessionTombstone: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let deletedAt: Date
}

// MARK: - Remote conflicts (spec §9.6: never silently last-write-wins)

public enum SupportConflictKind: String, Codable, Equatable, Sendable {
    case terminalStatus = "terminal_status"
    case stepText = "step_text"
    case selectedActivity = "selected_activity"
}

public enum SupportConflictResolution: Equatable, Sendable {
    case keepLocal, takeRemote
}

/// A retained remote version that disagrees with unsent/unconfirmed local work. While any exist for a session,
/// the session's known server revision does not advance and no new mutation is released.
public struct SupportRemoteConflict: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let activityID: UUID?
    public let kind: SupportConflictKind
    public var remoteRevision: Int64
    public var remoteSession: SupportSession
    public var remoteActivities: [SupportActivity]
    public let detectedAt: Date
}

// MARK: - Template catalog (spec §9.3: never guess a "similar" step)

public struct SupportTemplateCatalog: Equatable, Sendable {
    private let prompts: [String: [String]]

    public init(prompts: [String: [String]]) { self.prompts = prompts }

    private static func key(_ template: SupportActivityTemplateKey, _ version: Int) -> String { "\(template.rawValue)@\(version)" }

    /// Version-1 prompt IDs. The bundled templates must use exactly these identifiers.
    public static let standard = SupportTemplateCatalog(prompts: [
        key(.groundPresentV1, 1): ["see", "feel", "hear", "smell", "taste"],
        key(.untangleThoughtV1, 1): ["on_mind", "certain_unclear", "fairer_way"],
        key(.chooseStepV1, 1): ["action", "smaller"],
    ])

    public func promptIDs(template: SupportActivityTemplateKey, version: Int) -> [String]? {
        prompts[Self.key(template, version)]
    }

    public func supports(template: SupportActivityTemplateKey, version: Int) -> Bool {
        promptIDs(template: template, version: version) != nil
    }
}

/// A deliberate text send whose server outcome is not yet acknowledged. It is never an automatic send queue.
public struct SupportPendingChatRequest: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let conversationID: UUID
    public let content: String
    public let scope: SupportContextScope
    public let privacyRevision: Int64
    public let createdAt: Date
}

/// No payload or execution claim: the earlier request was abandoned after a deliberate erasure.
public struct SupportErasedUnknownRequest: Codable, Equatable, Sendable {
    public let operationID: UUID
    public let sessionID: UUID
    public let kind: SupportMutationKind
    public let observedServerRevision: Int64?
    public let recordedAt: Date
}

// MARK: - Journal

/// The per-account versioned journal: one atomic recoverable unit (spec §9.6).
public struct SupportJournal: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public let ownerID: UUID
    /// Monotonic count of durable commits.
    public var commitSequence: Int64
    public var sessions: [UUID: SupportSession]
    public var activities: [UUID: SupportActivity]
    public var events: [SupportSessionEvent]
    public var drafts: [UUID: String]
    public var serverRevisions: [UUID: Int64]
    public var intents: [SupportMutationIntent]
    public var attempts: [SupportTransmittedAttempt]
    public var suppressions: [SupportPrivacySuppression]
    public var transcriptEvents: [SupportTranscriptEvent]
    public var nextTranscriptSequence: [UUID: Int64]
    public var tombstones: [UUID: SupportSessionTombstone]
    public var failures: [SupportSyncFailure]
    public var conflicts: [SupportRemoteConflict]
    public var discardedActivityIDs: Set<UUID> = []
    public var pendingChatRequests: [UUID: SupportPendingChatRequest] = [:]
    public var reservedConversationIDs: [UUID: UUID] = [:]
    public var memoryRecords: [UUID: SupportMemoryRecord] = [:]
    public var memoryChanges: [SupportMemoryChange] = []
    public var declinedTemplates: [UUID: Set<SupportActivityTemplateKey>] = [:]
    public var accountPrivacyRevision: Int64?
    public var memoryUpdatedAt: Date?
    public var erasedUnknownRequests: [SupportErasedUnknownRequest] = []

    public init(ownerID: UUID) {
        self.schemaVersion = SupportJournal.currentSchemaVersion
        self.ownerID = ownerID
        self.commitSequence = 0
        self.sessions = [:]
        self.activities = [:]
        self.events = []
        self.drafts = [:]
        self.serverRevisions = [:]
        self.intents = []
        self.attempts = []
        self.suppressions = []
        self.transcriptEvents = []
        self.nextTranscriptSequence = [:]
        self.tombstones = [:]
        self.failures = []
        self.conflicts = []
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, ownerID, commitSequence, sessions, activities, events, drafts, serverRevisions, intents
        case attempts, suppressions, transcriptEvents, nextTranscriptSequence, tombstones, failures, conflicts, discardedActivityIDs, pendingChatRequests, reservedConversationIDs, memoryRecords, memoryChanges, declinedTemplates, accountPrivacyRevision, memoryUpdatedAt, erasedUnknownRequests
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        ownerID = try c.decode(UUID.self, forKey: .ownerID)
        commitSequence = try c.decode(Int64.self, forKey: .commitSequence)
        sessions = try c.decode([UUID: SupportSession].self, forKey: .sessions)
        activities = try c.decode([UUID: SupportActivity].self, forKey: .activities)
        events = try c.decode([SupportSessionEvent].self, forKey: .events)
        drafts = try c.decode([UUID: String].self, forKey: .drafts)
        serverRevisions = try c.decode([UUID: Int64].self, forKey: .serverRevisions)
        intents = try c.decode([SupportMutationIntent].self, forKey: .intents)
        attempts = try c.decode([SupportTransmittedAttempt].self, forKey: .attempts)
        suppressions = try c.decode([SupportPrivacySuppression].self, forKey: .suppressions)
        transcriptEvents = try c.decode([SupportTranscriptEvent].self, forKey: .transcriptEvents)
        nextTranscriptSequence = try c.decode([UUID: Int64].self, forKey: .nextTranscriptSequence)
        tombstones = try c.decode([UUID: SupportSessionTombstone].self, forKey: .tombstones)
        failures = try c.decode([SupportSyncFailure].self, forKey: .failures)
        conflicts = try c.decodeIfPresent([SupportRemoteConflict].self, forKey: .conflicts) ?? []
        discardedActivityIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .discardedActivityIDs) ?? []
        pendingChatRequests = try c.decodeIfPresent([UUID: SupportPendingChatRequest].self, forKey: .pendingChatRequests) ?? [:]
        reservedConversationIDs = try c.decodeIfPresent([UUID: UUID].self, forKey: .reservedConversationIDs) ?? [:]
        memoryRecords = try c.decodeIfPresent([UUID: SupportMemoryRecord].self, forKey: .memoryRecords) ?? [:]
        memoryChanges = try c.decodeIfPresent([SupportMemoryChange].self, forKey: .memoryChanges) ?? []
        declinedTemplates = try c.decodeIfPresent([UUID: Set<SupportActivityTemplateKey>].self, forKey: .declinedTemplates) ?? [:]
        accountPrivacyRevision = try c.decodeIfPresent(Int64.self, forKey: .accountPrivacyRevision)
        memoryUpdatedAt = try c.decodeIfPresent(Date.self, forKey: .memoryUpdatedAt)
        erasedUnknownRequests = try c.decodeIfPresent([SupportErasedUnknownRequest].self, forKey: .erasedUnknownRequests) ?? []
    }

    /// While any privacy mutation is unacknowledged, personalized cloud generation must stay paused (spec §8.5).
    public var personalizedCloudPaused: Bool {
        !memoryChanges.isEmpty || suppressions.contains { !$0.isAcknowledged }
    }

    /// The same eligibility used by the outbox and its observer; blocked local choices are not sync work.
    public var nextReplayableAttempt: SupportTransmittedAttempt? {
        let busy = Set(attempts.filter { $0.state == .inFlight }.map { $0.envelope.sessionID })
        return attempts.first { $0.state == .ambiguous && !$0.contentRedacted && !busy.contains($0.envelope.sessionID) }
    }

    public var nextSendableIntent: SupportMutationIntent? {
        let blocked = Set(attempts.map { $0.envelope.sessionID }).union(conflicts.map(\.sessionID))
        return intents.first { !blocked.contains($0.sessionID) && ($0.payload.kind == .create || serverRevisions[$0.sessionID] != nil) }
    }

    public var hasAutomaticNonTranscriptWork: Bool {
        !memoryChanges.isEmpty || nextReplayableAttempt != nil || nextSendableIntent != nil
            || attempts.contains { $0.contentRedacted }
    }

    public func hasOutstandingMutations(sessionID: UUID) -> Bool {
        intents.contains { $0.sessionID == sessionID } || attempts.contains { $0.envelope.sessionID == sessionID }
            || hasUnresolvedConflict(sessionID: sessionID)
    }

    public var hasAutomaticTranscriptWork: Bool {
        transcriptEvents.contains { $0.syncState == .pending && !hasOutstandingMutations(sessionID: $0.sessionID) }
    }

    public var hasAutomaticSyncWork: Bool {
        hasAutomaticNonTranscriptWork || hasAutomaticTranscriptWork
    }

    public func isSuppressed(kind: SupportSuppressionKind, targetID: String) -> Bool {
        suppressions.contains { $0.kind == kind && $0.targetID == targetID }
    }

    public func activities(in sessionID: UUID) -> [SupportActivity] {
        activities.values.filter { $0.sessionID == sessionID }.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
    }

    public func hasUnresolvedConflict(sessionID: UUID) -> Bool {
        conflicts.contains { $0.sessionID == sessionID }
    }

    public func events(for sessionID: UUID) -> [SupportSessionEvent] {
        events.filter { $0.sessionID == sessionID }
    }
}

// MARK: - Errors

public enum SupportSessionError: Error, Equatable, Sendable {
    case invalidated
    case staleEpoch
    case notLoaded
    case ownerMismatch
    case unsupportedJournalVersion(Int)
    case journalCorrupt
    case protectedDataUnavailable
    case journalReadFailed(String)
    case journalWriteFailed(String)
    case journalTooLarge
    case sessionNotFound(UUID)
    case sessionAlreadyExists(UUID)
    case sessionNotOpen(UUID)
    case sessionDeleted(UUID)
    case activityNotFound(UUID)
    case activityAlreadyExists(UUID)
    case invalidTransition(from: SupportActivityStatus, to: SupportActivityStatus)
    case activityTerminal(UUID)
    case anotherActivityUnfinished(UUID)
    case templateKindMismatch
    case valueTooLong(field: String, limit: Int)
    case emptyValue(field: String)
    case checkpointTooLarge
    case capacityExceeded(String)
    case unknownAttempt(UUID)
    case attemptNotRejected(UUID)
    case operationIDReused(UUID)
    case chatRequestNeedsReconciliation(UUID)
    case conversationAlreadyAttached
    case conversationNotAttached
    case chatContextChanged
    case unsupportedTemplateVersion(template: String, version: Int)
    case unsupportedCheckpointVersion(Int)
    case checkpointTemplateMismatch
    case unknownPromptID(String)
    case invalidCheckpoint(String)
    case invalidReminder
    /// The retained activity uses a template/checkpoint schema this build cannot run. It is kept untouched
    /// (never reset); it can only be stopped, closed or deleted until a migration or the old template is available.
    case activityTemplateUnavailable(UUID)
    case unresolvedConflict(UUID)
    case conflictNotFound(UUID)
    case recoveryCopiesNeedDecision
}

// MARK: - Helpers

enum SupportFingerprint {
    /// Canonical (sorted-keys) JSON + FNV-1a 64. Local replay-identity check only; not cryptographic.
    static func fingerprint(_ payload: SupportMutationPayload, sessionID: UUID) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var bytes = Data(sessionID.uuidString.utf8)
        bytes.append(contentsOf: (try? encoder.encode(payload)) ?? Data())
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(format: "%016llx", hash)
    }
}
