// AIConsentService.swift
// Loads, mutates, and observes the user's AI consent state.

import Foundation
import Supabase

protocol AIConsentStore {
    func currentUserId() async throws -> UUID
    func fetchAll() async throws -> [AIConsentRecord]
    func upsert(_ records: [AIConsentRecord]) async throws
    func deleteAIHistory() async throws
}

@MainActor
final class AIConsentService: ObservableObject {
    @Published private(set) var consents: [AIFeature: AIConsentRecord] = [:]
    @Published private(set) var isLoaded: Bool = false

    private let store: AIConsentStore

    init(store: AIConsentStore) {
        self.store = store
    }

    func loadFromServer() async throws {
        let records = try await store.fetchAll()
        consents = Dictionary(uniqueKeysWithValues: records.map { ($0.feature, $0) })
        isLoaded = true
    }

    /// Clears all in-memory consent state. Call on sign-out so the next user
    /// gets a fresh gate check instead of inheriting the previous user's grants.
    func reset() {
        consents = [:]
        isLoaded = false
    }

    func isGranted(_ feature: AIFeature) -> Bool {
        guard let r = consents[feature] else { return false }
        return r.state == .granted && r.policyVersion >= AIConsent.currentPolicyVersion
    }

    /// True if any feature has unknown state OR a stale policy version.
    /// Used by the onboarding/migration consent gate to decide whether to show.
    func needsConsentGate() -> Bool {
        for feature in AIFeature.allCases {
            guard let r = consents[feature] else { return true }
            if r.state == .unknown { return true }
            if r.policyVersion < AIConsent.currentPolicyVersion { return true }
        }
        return false
    }

    /// Set explicit consent for the provided features. Other features:
    /// - if `denyOthers` is true, are written as `denied`
    /// - if `denyOthers` is false, are left untouched
    func setConsent(grant: Set<AIFeature>, denyOthers: Bool) async throws {
        let userId = try await store.currentUserId()
        let now = Date()
        var batch: [AIConsentRecord] = []
        for f in AIFeature.allCases {
            let isGranting = grant.contains(f)
            if !isGranting && !denyOthers { continue }
            batch.append(AIConsentRecord(
                userId: userId,
                feature: f,
                state: isGranting ? .granted : .denied,
                grantedAt: isGranting ? now : nil,
                revokedAt: isGranting ? nil : now,
                policyVersion: AIConsent.currentPolicyVersion,
                updatedAt: now
            ))
        }
        try await store.upsert(batch)
        for r in batch { consents[r.feature] = r }
    }

    func grant(_ features: Set<AIFeature>) async throws {
        try await setConsent(grant: features, denyOthers: false)
    }

    func revoke(_ feature: AIFeature) async throws {
        let userId = try await store.currentUserId()
        let now = Date()
        let record = AIConsentRecord(
            userId: userId,
            feature: feature,
            state: .denied,
            grantedAt: nil,
            revokedAt: now,
            policyVersion: AIConsent.currentPolicyVersion,
            updatedAt: now
        )
        try await store.upsert([record])
        consents[feature] = record
    }

    /// Master-switch off and "delete history" entry point.
    func revokeAll(features: [AIFeature] = AIFeature.allCases, deleteAIHistory: Bool) async throws {
        let userId = try await store.currentUserId()
        let now = Date()
        let batch = features.map { f in
            AIConsentRecord(
                userId: userId,
                feature: f,
                state: .denied,
                grantedAt: nil,
                revokedAt: now,
                policyVersion: AIConsent.currentPolicyVersion,
                updatedAt: now
            )
        }
        try await store.upsert(batch)
        for r in batch { consents[r.feature] = r }
        if deleteAIHistory {
            try await store.deleteAIHistory()
        }
    }

    /// Called by the network layer when an Edge Function returns 403 ai_consent_required —
    /// flip the in-memory state so dependent UI re-renders the empty state.
    func markUnknown(_ feature: AIFeature) {
        guard let r = consents[feature] else { return }
        consents[feature] = AIConsentRecord(
            userId: r.userId,
            feature: feature,
            state: .unknown,
            grantedAt: r.grantedAt,
            revokedAt: r.revokedAt,
            policyVersion: r.policyVersion,
            updatedAt: Date()
        )
    }
}

// MARK: - Production store backed by Supabase

final class SupabaseAIConsentStore: AIConsentStore {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func currentUserId() async throws -> UUID {
        try await client.auth.session.user.id
    }

    func fetchAll() async throws -> [AIConsentRecord] {
        let userId = try await currentUserId()
        let rows: [AIConsentRecord] = try await client
            .from("ai_consents")
            .select()
            .eq("user_id", value: userId)
            .execute()
            .value
        return rows
    }

    func upsert(_ records: [AIConsentRecord]) async throws {
        try await client
            .from("ai_consents")
            .upsert(records, onConflict: "user_id,feature")
            .execute()
    }

    func deleteAIHistory() async throws {
        try await client.functions.invoke(
            "delete-ai-history",
            options: FunctionInvokeOptions(method: .post)
        )
    }
}
