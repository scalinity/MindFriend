//
//  OfflineMutationService.swift
//  MindFriendApp
//
//  Sends offline-queued mood / quest / exercise items to the owner-scoped
//  idempotent `sync_offline_mutation` RPC. The item's stable `id` is the
//  operation ID, so a replay after a crash or a failed local save returns the
//  stored receipt instead of writing or rewarding twice.
//
//  This service never falls back to the older per-table APIs: those have no
//  idempotency, so using them would reintroduce duplicate writes and XP.
//

import Foundation
import Supabase

/// The account (and sign-in epoch) the app currently considers authenticated.
struct OfflineOwnerProof: Equatable, Sendable {
    let userId: UUID
    let epoch: UInt64
}

enum OfflineMutationError: Error, Equatable, LocalizedError {
    /// The RPC is not deployed on this backend. Items stay queued; nothing is faked.
    case unavailable
    /// The server's answer did not match the request. Treated as a failure, never as success.
    case malformedReceipt

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Offline sync is not available on the server yet."
        case .malformedReceipt: return "The server's confirmation did not match the request."
        }
    }
}

/// Immutable wire request. Contains no queue metadata (synced / attempts / error).
struct OfflineMutationRequest: Encodable, Equatable, Sendable {
    let expectedOwner: String
    let operationId: String
    let kind: String
    let payload: Payload

    enum CodingKeys: String, CodingKey {
        case expectedOwner = "p_expected_owner"
        case operationId = "p_operation_id"
        case kind = "p_kind"
        case payload = "p_payload"
    }

    struct Payload: Encodable, Equatable, Sendable {
        let schemaVersion = 1
        var moodScore: Int?
        var anxietyScore: Int?
        var energyScore: Int?
        var note: String?
        var recordedAtMs: Int64?
        var questId: String?
        var exerciseId: String?
        var durationSeconds: Int?
        var completedAtMs: Int64?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case moodScore = "mood_score"
            case anxietyScore = "anxiety_score"
            case energyScore = "energy_score"
            case note
            case recordedAtMs = "recorded_at_ms"
            case questId = "quest_id"
            case exerciseId = "exercise_id"
            case durationSeconds = "duration_seconds"
            case completedAtMs = "completed_at_ms"
        }

        // Absent fields are omitted (the server treats absent as null).
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(schemaVersion, forKey: .schemaVersion)
            try c.encodeIfPresent(moodScore, forKey: .moodScore)
            try c.encodeIfPresent(anxietyScore, forKey: .anxietyScore)
            try c.encodeIfPresent(energyScore, forKey: .energyScore)
            try c.encodeIfPresent(note, forKey: .note)
            try c.encodeIfPresent(recordedAtMs, forKey: .recordedAtMs)
            try c.encodeIfPresent(questId, forKey: .questId)
            try c.encodeIfPresent(exerciseId, forKey: .exerciseId)
            try c.encodeIfPresent(durationSeconds, forKey: .durationSeconds)
            try c.encodeIfPresent(completedAtMs, forKey: .completedAtMs)
        }
    }
}

/// Subset of the server receipt the client checks. Content-free by design.
struct OfflineMutationReceipt: Decodable, Equatable, Sendable {
    let operationId: UUID
    let kind: String
    let replayed: Bool
    let targetId: UUID?

    enum CodingKeys: String, CodingKey {
        case operationId = "operation_id"
        case kind
        case replayed
        case targetId = "target_id"
    }
}

struct OfflineMutationService: Sendable {
    typealias Transport = @Sendable (OfflineMutationRequest) async throws -> OfflineMutationReceipt

    private let ownerProof: @Sendable () async -> OfflineOwnerProof?
    private let transport: Transport

    /// - Parameters:
    ///   - client: injected Supabase client (the request is authenticated by its session).
    ///   - ownerProof: returns the currently authenticated account and epoch, or nil if signed out.
    init(client: SupabaseClient, ownerProof: @escaping @Sendable () async -> OfflineOwnerProof?) {
        self.ownerProof = ownerProof
        self.transport = { request in
            try await client.rpc("sync_offline_mutation", params: request).execute().value
        }
    }

    /// Test seam.
    init(ownerProof: @escaping @Sendable () async -> OfflineOwnerProof?, transport: @escaping Transport) {
        self.ownerProof = ownerProof
        self.transport = transport
    }

    // MARK: - Handlers

    /// Handler closures for `OfflineContentService.bindOfflineScope`, pinned to one
    /// owner/epoch. Create them with the same userId/epoch passed to the bind call.
    func handlers(userId: String, epoch: UInt64) -> (
        mood: @Sendable (OfflineMoodEntry) async throws -> Void,
        quest: @Sendable (OfflineQuestCompletion) async throws -> Void,
        exercise: @Sendable (OfflineExerciseSession) async throws -> Void
    ) {
        let binding = OfflineOwnerBinding(userId: userId, epoch: epoch)
        return (
            { try await syncMood($0, binding: binding) },
            { try await syncQuest($0, binding: binding) },
            { try await syncExercise($0, binding: binding) }
        )
    }

    // MARK: - Item sync

    func syncMood(_ item: OfflineMoodEntry, binding: OfflineOwnerBinding) async throws {
        // Only persisted semantics are sent; `factors` has no column and is not synced.
        var payload = OfflineMutationRequest.Payload()
        payload.moodScore = item.moodScore
        payload.anxietyScore = item.anxietyLevel
        payload.energyScore = item.energyLevel
        payload.note = (item.notes?.isEmpty == false) ? item.notes : nil
        payload.recordedAtMs = Self.wholeSecondMillis(item.createdAt)
        try await perform(kind: "mood", id: item.id, payload: payload, binding: binding)
    }

    func syncQuest(_ item: OfflineQuestCompletion, binding: OfflineOwnerBinding) async throws {
        var payload = OfflineMutationRequest.Payload()
        payload.questId = item.questId.uuidString.lowercased()
        payload.completedAtMs = Self.wholeSecondMillis(item.completedAt)
        try await perform(kind: "quest", id: item.id, payload: payload, binding: binding)
    }

    func syncExercise(_ item: OfflineExerciseSession, binding: OfflineOwnerBinding) async throws {
        var payload = OfflineMutationRequest.Payload()
        payload.exerciseId = item.exerciseId.uuidString.lowercased()
        payload.durationSeconds = item.durationSeconds
        payload.completedAtMs = Self.wholeSecondMillis(item.completedAt)
        try await perform(kind: "exercise", id: item.id, payload: payload, binding: binding)
    }

    // MARK: - Core

    private func perform(
        kind: String,
        id: UUID,
        payload: OfflineMutationRequest.Payload,
        binding: OfflineOwnerBinding
    ) async throws {
        guard let owner = UUID(uuidString: binding.userId) else {
            throw OfflineSyncHandlerError.nonRetryable("Offline sync rejected an invalid account identifier.")
        }
        // Check the captured owner/epoch before the request (this is a client-side
        // proof, not a pinned token: the SDK attaches whatever session is current).
        // The server compares p_expected_owner with auth.uid() and rejects a mismatch.
        try await requireOwner(binding)
        let request = OfflineMutationRequest(
            expectedOwner: owner.uuidString.lowercased(),
            operationId: id.uuidString.lowercased(),
            kind: kind,
            payload: payload
        )

        let receipt: OfflineMutationReceipt
        do {
            receipt = try await transport(request)
        } catch {
            // If the account changed while the request was in flight, the result
            // belongs to a dead lifecycle: report cancellation, not a failure.
            try await requireOwner(binding)
            throw Self.classify(error)
        }
        try await requireOwner(binding)

        guard receipt.operationId.uuidString.lowercased() == request.operationId, receipt.kind == kind else {
            throw OfflineMutationError.malformedReceipt
        }
    }

    private func requireOwner(_ binding: OfflineOwnerBinding) async throws {
        try Task.checkCancellation()
        guard let proof = await ownerProof(),
              proof.userId.uuidString.lowercased() == binding.userId.lowercased(),
              proof.epoch == binding.epoch else {
            throw CancellationError()
        }
    }

    /// Whole-second precision: the queue persists dates at second precision, so a
    /// retry after relaunch must produce the identical payload.
    static func wholeSecondMillis(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970.rounded(.down)) * 1000
    }

    // MARK: - Error classification

    /// Auth / validation / ownership / changed-payload errors are non-retryable;
    /// transport, timeout and server failures stay retryable; a missing RPC is
    /// reported as unavailable.
    static func classify(_ error: Error) -> Error {
        if error is CancellationError || error is OfflineSyncHandlerError { return error }
        if let url = error as? URLError {
            return url.code == .cancelled ? CancellationError() : url
        }
        if let pg = error as? PostgrestError {
            let code = pg.code ?? ""
            let message = pg.message
            if code == "PGRST202" || code == "42883" || message.contains("Could not find the function") {
                return OfflineMutationError.unavailable
            }
            if message.hasPrefix("IDEMPOTENCY_CONFLICT") || code == "MF409" {
                return OfflineSyncHandlerError.nonRetryable("This offline entry changed after it was first sent and was not applied.")
            }
            if message.hasPrefix("AUTH_REQUIRED") || message.hasPrefix("OWNER_MISMATCH")
                || ["PGRST301", "PGRST302", "PGRST303"].contains(code) {
                return OfflineSyncHandlerError.nonRetryable("Sign in again to finish syncing this offline entry.")
            }
            if message.hasPrefix("NOT_FOUND") {
                return OfflineSyncHandlerError.nonRetryable("This offline entry refers to something that is no longer available.")
            }
            if message.hasPrefix("INVALID_PAYLOAD") || message.hasPrefix("STATE_REJECTED") || code == "22023" {
                return OfflineSyncHandlerError.nonRetryable("This offline entry could not be accepted.")
            }
            if code == "42501" {
                return OfflineSyncHandlerError.nonRetryable("This offline entry does not belong to the signed-in account.")
            }
            return pg   // timeouts (57014), serialization failures (40001), 5xx: retry
        }
        if let http = error as? HTTPError {
            switch http.response.statusCode {
            case 404: return OfflineMutationError.unavailable
            case 401, 403: return OfflineSyncHandlerError.nonRetryable("Sign in again to finish syncing this offline entry.")
            case 408, 429, 500...599: return error
            case 400...499: return OfflineSyncHandlerError.nonRetryable("This offline entry could not be accepted.")
            default: return error
            }
        }
        return error
    }
}

// MARK: - Online atomic save + reward (shared server path with offline sync)

/// Result of the atomic RPCs below. Rewards are paid by the server in the same
/// transaction as the state change: `xpAwarded` is 0 when the work was already
/// counted (for example it had been synced from the offline queue first).
struct AtomicRewardResult: Decodable, Equatable, Sendable {
    /// Mood: created | updated | kept_existing. Quest: completed | already_completed.
    let outcome: String
    let xpAwarded: Int
    let levelUp: Bool
    let newXp: Int?
    let newLevel: Int?
    let newTitle: String?

    enum CodingKeys: String, CodingKey {
        case outcome
        case xpAwarded = "xp_awarded"
        case levelUp = "level_up"
        case newXp = "new_xp"
        case newLevel = "new_level"
        case newTitle = "new_title"
    }
}

/// Online callers must use these instead of "update row, then award_xp" so a
/// quest or day paid through the offline queue is never paid a second time.
enum AtomicCompletionRPC {
    private struct QuestParams: Encodable {
        let pQuestId: String
        let pReflectionNote: String?
        let pRating: Int?
        enum CodingKeys: String, CodingKey {
            case pQuestId = "p_quest_id", pReflectionNote = "p_reflection_note", pRating = "p_rating"
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(pQuestId, forKey: .pQuestId)
            try c.encodeIfPresent(pReflectionNote, forKey: .pReflectionNote)
            try c.encodeIfPresent(pRating, forKey: .pRating)
        }
    }

    private struct MoodParams: Encodable {
        let pLocalDate: String
        let pMoodScore: Int
        let pAnxietyScore: Int?
        let pEnergyScore: Int?
        let pNote: String?
        enum CodingKeys: String, CodingKey {
            case pLocalDate = "p_local_date", pMoodScore = "p_mood_score", pAnxietyScore = "p_anxiety_score"
            case pEnergyScore = "p_energy_score", pNote = "p_note"
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(pLocalDate, forKey: .pLocalDate)
            try c.encode(pMoodScore, forKey: .pMoodScore)
            try c.encodeIfPresent(pAnxietyScore, forKey: .pAnxietyScore)
            try c.encodeIfPresent(pEnergyScore, forKey: .pEnergyScore)
            try c.encodeIfPresent(pNote, forKey: .pNote)
        }
    }

    /// RPC `complete_quest_with_reward(p_quest_id, p_reflection_note, p_rating)`.
    /// Replaces the quest status update plus the separate 50 XP `award_xp` call.
    static func completeQuest(
        client: SupabaseClient, questId: UUID, reflectionNote: String?, rating: Int?
    ) async throws -> AtomicRewardResult {
        try await client.rpc("complete_quest_with_reward", params: QuestParams(
            pQuestId: questId.uuidString.lowercased(), pReflectionNote: reflectionNote, pRating: rating
        )).execute().value
    }

    /// RPC `save_mood_checkin(p_local_date, p_mood_score, ...)` with `localDate` as `yyyy-MM-dd`.
    /// Replaces the mood upsert plus the separate 10 XP call; pays only for a new day.
    static func saveMood(
        client: SupabaseClient, localDate: String, moodScore: Int, anxietyScore: Int?, energyScore: Int?, note: String?
    ) async throws -> AtomicRewardResult {
        try await client.rpc("save_mood_checkin", params: MoodParams(
            pLocalDate: localDate, pMoodScore: moodScore, pAnxietyScore: anxietyScore,
            pEnergyScore: energyScore, pNote: note
        )).execute().value
    }
}
